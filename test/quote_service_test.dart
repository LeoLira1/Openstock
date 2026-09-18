import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openstock/models/history_models.dart';
import 'package:openstock/models/investment_asset.dart';
import 'package:openstock/services/quote_service.dart';

void main() {
  group('resolvePreviousClose', () {
    test('ignora a cotação parcial de hoje', () {
      final result = resolvePreviousClose(
        history: [
          PricePoint(DateTime(2026, 9, 14, 17), 64.19),
          PricePoint(DateTime(2026, 9, 15, 14), 65.40),
        ],
        current: 65.40,
        providerPrevious: 58.63,
        now: DateTime(2026, 9, 15, 16),
      );

      expect(result, 64.19);
    });

    test('usa o último pregão quando a série termina ontem', () {
      final result = resolvePreviousClose(
        history: [
          PricePoint(DateTime(2026, 9, 11, 17), 63.80),
          PricePoint(DateTime(2026, 9, 14, 17), 64.19),
        ],
        current: 65.40,
        providerPrevious: 58.63,
        now: DateTime(2026, 9, 15, 16),
      );

      expect(result, 64.19);
    });

    test('não confunde candle de hoje em UTC com fechamento de ontem', () {
      final result = resolvePreviousClose(
        history: [
          PricePoint(DateTime.utc(2026, 9, 17), 63.29),
          PricePoint(DateTime.utc(2026, 9, 18), 62.57),
        ],
        current: 62.78,
        providerPrevious: 63.29,
        currentPriceDate: DateTime.utc(2026, 9, 18, 15, 14),
        // O mesmo instante em um aparelho configurado para o Brasil.
        now: DateTime.parse('2026-09-18T12:14:00-03:00'),
      );

      expect(result, 63.29);
    });

    test('recorre ao metadado quando não há histórico', () {
      final result = resolvePreviousClose(
        history: const [],
        current: 65.40,
        providerPrevious: 64.19,
      );

      expect(result, 64.19);
    });
  });

  test('histórico B3 respeita período e usa símbolo SA', () async {
    late Uri requested;
    final service = QuoteService(client: MockClient((request) async {
      requested = request.url;
      return http.Response(
        jsonEncode({
          'chart': {
            'error': null,
            'result': [
              {
                'meta': {
                  'regularMarketPrice': 44.0,
                  'regularMarketTime': 1789344000,
                },
                'timestamp': [1789344000],
                'indicators': {
                  'quote': [
                    {
                      'close': [44.0]
                    }
                  ]
                }
              }
            ]
          }
        }),
        200,
      );
    }));
    const asset = InvestmentAsset(
      symbol: 'PRIO3',
      name: 'PRIO',
      market: AssetMarket.b3,
      currency: AssetCurrency.brl,
      quantity: 10,
      averagePrice: 40,
    );

    final history = await service.fetchHistory(asset, HistoryPeriod.fiveYears);

    expect(requested.path, '/v8/finance/chart/PRIO3.SA');
    expect(requested.queryParameters['range'], '5y');
    expect(requested.queryParameters['interval'], '1d');
    expect(history.single.value, 44);
  });

  test('cotação guarda a data real do preço atual', () async {
    const marketEpoch = 1789661400;
    final service = QuoteService(client: MockClient((request) async {
      return http.Response(
        jsonEncode({
          'chart': {
            'error': null,
            'result': [
              {
                'meta': {
                  'regularMarketPrice': 100.0,
                  'chartPreviousClose': 99.0,
                  'regularMarketTime': marketEpoch,
                },
                'timestamp': [marketEpoch],
                'indicators': {
                  'quote': [
                    {
                      'close': [100.0]
                    }
                  ]
                }
              }
            ]
          }
        }),
        200,
      );
    }));
    const asset = InvestmentAsset(
      symbol: 'AMD',
      name: 'AMD',
      market: AssetMarket.usa,
      currency: AssetCurrency.usd,
      quantity: 1,
      averagePrice: 90,
    );

    final quote = await service.fetch(asset);

    expect(
      quote.priceDate,
      DateTime.fromMillisecondsSinceEpoch(marketEpoch * 1000),
    );
  });

  test('preço ao vivo da Finnhub não substitui o fechamento da série', () async {
    // Caso real de PRIO3 em 18/09/2026: a Finnhub devolveu o preço do momento
    // como `pc`, o que fazia a tela mostrar alta no dia enquanto o pregão
    // acumulava queda contra o fechamento de 17/09.
    final service = QuoteService(client: MockClient((request) async {
      final host = request.url.host;
      if (host == 'brapi.dev') {
        return http.Response('{"error":"token"}', 401);
      }
      if (host == 'finnhub.io') {
        return http.Response(
          jsonEncode({'c': 62.74, 'pc': 62.58, 't': 1789748820}),
          200,
        );
      }
      return http.Response(
        jsonEncode({
          'chart': {
            'error': null,
            'result': [
              {
                'meta': {
                  'regularMarketPrice': 62.78,
                  'chartPreviousClose': 63.29,
                  'regularMarketTime': 1789748820,
                },
                'timestamp': [1789603200, 1789689600],
                'indicators': {
                  'quote': [
                    {
                      'close': [63.29, 62.57]
                    }
                  ]
                }
              }
            ]
          }
        }),
        200,
      );
    }));
    service.configureFinnhub('chave-de-teste');
    const asset = InvestmentAsset(
      symbol: 'PRIO3',
      name: 'PRIO',
      market: AssetMarket.b3,
      currency: AssetCurrency.brl,
      quantity: 267,
      averagePrice: 42.38,
    );

    final quote = await service.fetch(asset);

    expect(quote.current, 62.74);
    expect(quote.previousClose, 63.29);
    final variacao =
        (quote.current - quote.previousClose) / quote.previousClose * 100;
    expect(variacao, lessThan(0));
    expect(variacao, closeTo(-0.87, 0.01));
  });

  test('fechamento zerado da Finnhub não vira variação de 100%', () async {
    final service = QuoteService(client: MockClient((request) async {
      if (request.url.host == 'finnhub.io') {
        return http.Response(jsonEncode({'c': 101.0, 'pc': 0}), 200);
      }
      return http.Response('{"chart":{"error":"nao encontrado"}}', 404);
    }));
    service.configureFinnhub('chave-de-teste');
    const asset = InvestmentAsset(
      symbol: 'AMD',
      name: 'AMD',
      market: AssetMarket.usa,
      currency: AssetCurrency.usd,
      quantity: 1,
      averagePrice: 90,
    );

    final quote = await service.fetch(asset);

    expect(quote.previousClose, 101.0);
  });

  test('consulta Yahoo e Finnhub ao mesmo tempo', () async {
    final finnhubChegou = Completer<void>();
    final service = QuoteService(client: MockClient((request) async {
      final host = request.url.host;
      if (host == 'brapi.dev') return http.Response('{"error":"token"}', 401);
      if (host == 'finnhub.io') {
        finnhubChegou.complete();
        return http.Response(
          jsonEncode({'c': 62.74, 'pc': 62.58, 't': 1789748820}),
          200,
        );
      }
      // O Yahoo só responde depois que a Finnhub for chamada. Enquanto as duas
      // consultas eram sequenciais, esta espera nunca terminava.
      await finnhubChegou.future;
      return http.Response(_chartYahoo(), 200);
    }));
    service.configureFinnhub('chave-de-teste');

    final quote = await service
        .fetch(_prio3)
        .timeout(const Duration(seconds: 5), onTimeout: () {
      fail('as consultas continuam sequenciais');
    });

    expect(quote.current, 62.74);
    expect(quote.previousClose, 63.29);
  });

  test('não repete a brapi em cada ativo depois de uma recusa', () async {
    var idasABrapi = 0;
    final service = QuoteService(client: MockClient((request) async {
      if (request.url.host == 'brapi.dev') {
        idasABrapi++;
        return http.Response('{"error":"token"}', 401);
      }
      return http.Response(_chartYahoo(), 200);
    }));

    await service.fetch(_prio3);
    await service.fetch(_prio3);
    await service.fetch(_prio3);

    // Uma carteira inteira gastava uma ida de rede por ativo para receber
    // sempre o mesmo 401.
    expect(idasABrapi, 1);
  });
  test('com chave, a brapi resolve o ativo em uma única consulta', () async {
    final hosts = <String>[];
    http.BaseRequest? consultaBrapi;
    final service = QuoteService(client: MockClient((request) async {
      hosts.add(request.url.host);
      if (request.url.host == 'brapi.dev') {
        consultaBrapi = request;
        return http.Response(_quoteBrapi(), 200);
      }
      return http.Response(_chartYahoo(), 200);
    }));
    service.configureBrapi('chave-brapi');
    service.configureFinnhub('chave-finnhub');

    final quote = await service.fetch(_prio3);

    expect(consultaBrapi?.headers['Authorization'], 'Bearer chave-brapi');
    // A chave não pode vazar na URL, que acaba em log de proxy e de erro.
    expect(consultaBrapi?.url.query, isNot(contains('chave-brapi')));
    expect(consultaBrapi?.url.path, '/api/quote/PRIO3');
    // Sem chave seriam duas fontes públicas para montar o mesmo dado.
    expect(hosts, ['brapi.dev']);
    expect(quote.current, 62.74);
    expect(quote.previousClose, 63.29);
    expect(quote.historySource, 'brapi');
  });

  test('chave recusada não derruba a cotação', () async {
    final service = QuoteService(client: MockClient((request) async {
      if (request.url.host == 'brapi.dev') {
        return http.Response('{"error":"chave inválida"}', 401);
      }
      return http.Response(_chartYahoo(), 200);
    }));
    service.configureBrapi('chave-vencida');

    final quote = await service.fetch(_prio3);

    expect(quote.current, 62.78);
    expect(quote.previousClose, 63.29);
    expect(quote.historySource, 'yahoo');
  });

  test('falha de rede na brapi não pausa a fonte', () async {
    var idasABrapi = 0;
    final service = QuoteService(client: MockClient((request) async {
      if (request.url.host == 'brapi.dev') {
        idasABrapi++;
        if (idasABrapi == 1) throw const SocketException('sem rede');
        return http.Response(_quoteBrapi(), 200);
      }
      return http.Response(_chartYahoo(), 200);
    }));
    service.configureBrapi('chave-brapi');

    await service.fetch(_prio3);
    final quote = await service.fetch(_prio3);

    // Uma oscilação momentânea não pode custar quinze minutos da melhor fonte.
    expect(idasABrapi, 2);
    expect(quote.historySource, 'brapi');
  });

  test('validação da chave brapi consulta um papel que exige chave', () async {
    http.BaseRequest? consulta;
    final service = QuoteService(client: MockClient((request) async {
      consulta = request;
      return http.Response(_quoteBrapi(), 200);
    }));

    final valido = await service.validateBrapiToken('  chave-brapi  ');

    expect(valido, isTrue);
    // PETR4 responde sem token, então não diria nada sobre a chave.
    expect(consulta?.url.path, '/api/quote/BBAS3');
    expect(consulta?.headers['Authorization'], 'Bearer chave-brapi');
  });
  test('a carteira brasileira cabe em uma requisição', () async {
    final consultas = <http.BaseRequest>[];
    final service = QuoteService(client: MockClient((request) async {
      consultas.add(request);
      return http.Response(_loteBrapi(['PRIO3', 'PETR4', 'VALE3']), 200);
    }));
    service.configureBrapi('chave-brapi');

    final cotacoes = await service.fetchBrazilianBatch(
      ['prio3', 'PETR4.SA', ' vale3 '],
    );

    expect(consultas.length, 1);
    expect(consultas.single.url.path, '/api/quote/PRIO3,PETR4,VALE3');
    expect(consultas.single.headers['Authorization'], 'Bearer chave-brapi');
    expect(cotacoes.keys, {'PRIO3', 'PETR4', 'VALE3'});
    expect(cotacoes['PRIO3']!.current, 62.74);
    // A série vem junto: é ela que define o fechamento anterior.
    expect(cotacoes['PRIO3']!.previousClose, 63.29);
    expect(cotacoes['PRIO3']!.history, hasLength(2));
  });

  test('sem chave o lote nem é tentado', () async {
    var idas = 0;
    final service = QuoteService(client: MockClient((request) async {
      idas++;
      return http.Response(_loteBrapi(['PRIO3']), 200);
    }));

    final cotacoes = await service.fetchBrazilianBatch(['PRIO3', 'PETR4']);

    // Só quatro papéis respondem sem token, e misturar qualquer outro faz a
    // chamada inteira exigir chave.
    expect(idas, 0);
    expect(cotacoes, isEmpty);
  });

  test('carteira grande é dividida em lotes', () async {
    final pedidos = <String>[];
    final service = QuoteService(client: MockClient((request) async {
      final tickers = request.url.path.replaceFirst('/api/quote/', '');
      pedidos.add(tickers);
      return http.Response(_loteBrapi(tickers.split(',')), 200);
    }));
    service.configureBrapi('chave-brapi');

    final simbolos = List.generate(23, (i) => 'ATIVO$i');
    final cotacoes = await service.fetchBrazilianBatch(simbolos);

    expect(pedidos.length, 3);
    expect(pedidos.map((p) => p.split(',').length), [10, 10, 3]);
    expect(cotacoes, hasLength(23));
  });

  test('lote recusado devolve vazio sem derrubar a atualização', () async {
    final service = QuoteService(client: MockClient((request) async {
      return http.Response('{"error":"token"}', 401);
    }));
    service.configureBrapi('chave-vencida');

    final cotacoes = await service.fetchBrazilianBatch(['PRIO3', 'PETR4']);

    // Cada ativo ainda será buscado pelo caminho individual.
    expect(cotacoes, isEmpty);
  });

  test('papel ausente na resposta não entra no resultado', () async {
    final service = QuoteService(client: MockClient((request) async {
      return http.Response(_loteBrapi(['PRIO3']), 200);
    }));
    service.configureBrapi('chave-brapi');

    final cotacoes = await service.fetchBrazilianBatch(['PRIO3', 'XPTO9']);

    expect(cotacoes.keys, {'PRIO3'});
  });
  test('pregão sem fechamento não vira o fechamento de ontem', () async {
    // Série real de PRIO3 em 18/09/2026: o Yahoo publicou o dia 17 sem
    // fechamento, e o dia 16 ficou a um passo de ser lido como a véspera.
    final service = QuoteService(client: MockClient((request) async {
      return http.Response(
        jsonEncode({
          'chart': {
            'error': null,
            'result': [
              {
                'meta': {
                  'regularMarketPrice': 63.24,
                  'chartPreviousClose': 61.50,
                  'regularMarketTime': 1789761949,
                },
                'timestamp': [1789470000, 1789556400, 1789642800, 1789729200],
                'indicators': {
                  'quote': [
                    {
                      'close': [65.68, 62.58, null, 63.24]
                    }
                  ]
                }
              }
            ]
          }
        }),
        200,
      );
    }));
    const asset = InvestmentAsset(
      symbol: 'AMD',
      name: 'AMD',
      market: AssetMarket.usa,
      currency: AssetCurrency.usd,
      quantity: 1,
      averagePrice: 50,
    );

    final quote = await service.fetch(asset);

    expect(quote.current, 63.24);
    // 62,58 é de dois dias antes: assumi-lo faria o papel subir 1% na tela
    // enquanto caía no pregão.
    expect(quote.previousClose, isNot(62.58));
    expect(quote.previousClose, 63.24);
  });

  test('fechamento anterior não vem do início do gráfico', () async {
    // `chartPreviousClose` muda conforme o período pedido — 64,19 em cinco
    // dias, 61,50 em um mês — então não descreve o pregão anterior.
    final service = QuoteService(client: MockClient((request) async {
      return http.Response(
        jsonEncode({
          'chart': {
            'error': null,
            'result': [
              {
                'meta': {
                  'regularMarketPrice': 63.24,
                  'chartPreviousClose': 61.50,
                  'regularMarketTime': 1789761949,
                },
                'timestamp': [1789642800, 1789729200],
                'indicators': {
                  'quote': [
                    {
                      'close': [63.29, 63.24]
                    }
                  ]
                }
              }
            ]
          }
        }),
        200,
      );
    }));
    const asset = InvestmentAsset(
      symbol: 'AMD',
      name: 'AMD',
      market: AssetMarket.usa,
      currency: AssetCurrency.usd,
      quantity: 1,
      averagePrice: 50,
    );

    final quote = await service.fetch(asset);

    expect(quote.previousClose, 63.29);
  });
  test('lote recusado pelo plano não derruba a consulta individual', () async {
    final caminhos = <String>[];
    final service = QuoteService(client: MockClient((request) async {
      if (request.url.host != 'brapi.dev') {
        caminhos.add('yahoo');
        return http.Response(_chartYahoo(), 200);
      }
      final tickers = request.url.path.replaceFirst('/api/quote/', '');
      if (tickers.contains(',')) {
        caminhos.add('lote');
        // 403 é a resposta para um recurso fora do plano.
        return http.Response('{"error":"recurso não incluído"}', 403);
      }
      caminhos.add('individual');
      return http.Response(_quoteBrapi(), 200);
    }));
    service.configureBrapi('chave-brapi');

    final lote = await service.fetchBrazilianBatch(['PRIO3', 'PETR4']);
    expect(lote, isEmpty);

    // A carteira inteira ia para a fonte pública, onde a série pode vir sem o
    // fechamento da véspera.
    final quote = await service.fetch(_prio3);
    expect(quote.historySource, 'brapi');
    expect(quote.previousClose, 63.29);
    expect(caminhos, ['lote', 'individual']);
  });

  test('qualquer recusa do lote preserva a consulta individual', () async {
    for (final status in [401, 403, 429]) {
      final caminhos = <String>[];
      final service = QuoteService(client: MockClient((request) async {
        if (request.url.host != 'brapi.dev') {
          caminhos.add('yahoo');
          return http.Response(_chartYahoo(), 200);
        }
        final tickers = request.url.path.replaceFirst('/api/quote/', '');
        if (tickers.contains(',')) {
          caminhos.add('lote');
          return http.Response('{"error":"recusado"}', status);
        }
        caminhos.add('individual');
        return http.Response(_quoteBrapi(), 200);
      }));
      service.configureBrapi('chave-brapi');

      final lote = await service.fetchBrazilianBatch(['PRIO3', 'PETR4']);
      final quote = await service.fetch(_prio3);

      // Adivinhar o motivo da recusa foi o que manteve a carteira na consulta
      // pública mesmo com a chave válida.
      expect(lote, isEmpty, reason: 'status $status');
      expect(quote.historySource, 'brapi', reason: 'status $status');
      expect(quote.previousClose, 63.29, reason: 'status $status');
      expect(caminhos, ['lote', 'individual'], reason: 'status $status');
    }
  });

  test('o motivo da recusa do lote fica disponível para a tela', () async {
    final service = QuoteService(client: MockClient((request) async {
      return http.Response('{"error":"fora do plano"}', 403);
    }));
    service.configureBrapi('chave-brapi');

    expect(
      await service.motivoLoteIndisponivel(['PRIO3', 'PETR4']),
      'HTTP 403',
    );
  });

  test('lote aceito não produz motivo algum', () async {
    final service = QuoteService(client: MockClient((request) async {
      return http.Response(_loteBrapi(['PRIO3', 'PETR4']), 200);
    }));
    service.configureBrapi('chave-brapi');

    expect(await service.motivoLoteIndisponivel(['PRIO3', 'PETR4']), isNull);
  });
  test('a chave é validada contra um papel que exige autenticação', () async {
    final consultados = <String>[];
    final service = QuoteService(client: MockClient((request) async {
      final papel = request.url.path.replaceFirst('/api/quote/', '');
      consultados.add(papel);
      // PETR4 responde sem token nenhum; um papel comum responde 401.
      if (papel == 'PETR4') return http.Response(_quoteBrapi(), 200);
      return http.Response(
        '{"error":true,"message":"Token inválido","code":"INVALID_TOKEN"}',
        401,
      );
    }));

    // Validar contra PETR4 aprovava qualquer chave, inclusive uma recusada.
    await expectLater(
      service.validateBrapiToken('chave-recusada', symbol: 'PRIO3'),
      throwsA(isA<QuoteException>()),
    );
    expect(consultados, ['PRIO3']);
  });

  test('um papel de demonstração não serve para validar', () async {
    final consultados = <String>[];
    final service = QuoteService(client: MockClient((request) async {
      consultados.add(request.url.path.replaceFirst('/api/quote/', ''));
      return http.Response(_quoteBrapi(), 200);
    }));

    await service.validateBrapiToken('chave', symbol: 'PETR4');

    // A carteira pode começar por um dos quatro papéis abertos: nesse caso a
    // validação troca por outro que exija a chave.
    expect(consultados, ['BBAS3']);
  });

  test('a recusa carrega o código devolvido pela brapi', () async {
    final service = QuoteService(client: MockClient((request) async {
      return http.Response(
        '{"error":true,"message":"Token não fornecido","code":"MISSING_TOKEN"}',
        401,
      );
    }));

    // Sem esse código não dá para saber se a chave foi recusada ou se nem
    // chegou a ser enviada.
    expect(
      await service.motivoLoteIndisponivel(['PRIO3', 'SLCE3']),
      'HTTP 401',
    );
    try {
      await service.validateBrapiToken('chave', symbol: 'PRIO3');
      fail('deveria ter lançado');
    } catch (error) {
      expect(error.toString(), contains('MISSING_TOKEN'));
      expect(error.toString(), contains('401'));
    }
  });
}

const _prio3 = InvestmentAsset(
  symbol: 'PRIO3',
  name: 'PRIO',
  market: AssetMarket.b3,
  currency: AssetCurrency.brl,
  quantity: 267,
  averagePrice: 42.38,
);

/// Série diária com o fechamento de 17/09/2026 e a parcial de 18/09/2026.
String _chartYahoo() => jsonEncode({
      'chart': {
        'error': null,
        'result': [
          {
            'meta': {
              'regularMarketPrice': 62.78,
              'chartPreviousClose': 63.29,
              'regularMarketTime': 1789748820,
            },
            'timestamp': [1789603200, 1789689600],
            'indicators': {
              'quote': [
                {
                  'close': [63.29, 62.57]
                }
              ]
            }
          }
        ]
      }
    });

/// Resposta da brapi com preço e série diária na mesma consulta.
String _quoteBrapi() => jsonEncode({
      'results': [
        {
          'regularMarketPrice': 62.74,
          'regularMarketPreviousClose': 63.29,
          'regularMarketTime': 1789748820,
          'historicalDataPrice': [
            {'date': 1789603200, 'close': 63.29},
            {'date': 1789689600, 'close': 62.57},
          ],
        }
      ]
    });

/// Resposta da brapi com vários papéis, cada um com a sua série diária.
String _loteBrapi(List<String> symbols) => jsonEncode({
      'results': [
        for (final symbol in symbols)
          {
            'symbol': symbol,
            'regularMarketPrice': 62.74,
            'regularMarketPreviousClose': 63.29,
            'regularMarketTime': 1789748820,
            'historicalDataPrice': [
              {'date': 1789603200, 'close': 63.29},
              {'date': 1789689600, 'close': 62.57},
            ],
          }
      ]
    });
