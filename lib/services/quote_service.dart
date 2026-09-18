import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/investment_asset.dart';
import '../models/history_models.dart';

class QuoteException implements Exception {
  const QuoteException(this.message, {this.status});
  final String message;

  /// Código HTTP, quando a falha veio de uma resposta do provedor.
  ///
  /// Serve para separar "a chave não vale" de "a rede oscilou": só o primeiro
  /// caso justifica parar de consultar o provedor.
  final int? status;

  @override
  String toString() => message;
}

class QuoteService {
  QuoteService({http.Client? client}) : _client = client ?? http.Client();

  /// Uma consulta lenta atrasa a atualização inteira. O limite antigo de 15s
  /// era somado a cada provedor e a cada ativo.
  static const _timeout = Duration(seconds: 10);

  /// A brapi sem token responde 401 para qualquer símbolo fora da lista de
  /// demonstração. Insistir custava uma ida de rede por ativo, em toda
  /// atualização, sempre para o mesmo erro.
  static const _brapiPausa = Duration(minutes: 15);

  final http.Client _client;
  String? _finnhubToken;
  String? _brapiToken;
  DateTime? _brapiIndisponivelAte;

  bool get _brapiDisponivel {
    final ate = _brapiIndisponivelAte;
    return ate == null || DateTime.now().isAfter(ate);
  }

  /// A brapi respondeu negando o acesso, e não apenas falhando.
  static bool _brapiRecusou(Object error) {
    if (error is! QuoteException) return false;
    final status = error.status;
    return status == 401 || status == 403 || status == 429;
  }

  void configureFinnhub(String? token) {
    final clean = token?.trim() ?? '';
    _finnhubToken = clean.isEmpty ? null : clean;
  }

  void configureBrapi(String? token) {
    final clean = token?.trim() ?? '';
    _brapiToken = clean.isEmpty ? null : clean;
    // Uma chave nova merece uma tentativa imediata, mesmo que a anterior tenha
    // sido recusada há pouco.
    _brapiIndisponivelAte = null;
  }

  /// Confere se a chave responde por um papel comum da B3.
  Future<bool> validateBrapiToken(String token) async {
    final quote = await _fetchBrapi('PETR4', token: token.trim());
    return quote.current > 0;
  }

  Future<MarketQuote> fetch(InvestmentAsset asset) {
    return switch (asset.market) {
      AssetMarket.b3 => _fetchBrazilian(asset.symbol),
      AssetMarket.usa => _fetchInternational(asset.symbol),
      AssetMarket.manual => Future.value(MarketQuote(
          current: asset.currentPrice ?? asset.averagePrice,
          previousClose:
              asset.previousClose ?? asset.currentPrice ?? asset.averagePrice,
          history: const [],
          historySource: 'manual',
          priceDate: DateTime.now(),
        )),
      // Renda fixa não tem cotação: o valor vem do CDI publicado, calculado
      // no controlador. Aqui só devolvemos o último valor já apurado.
      AssetMarket.fixedIncome => Future.value(MarketQuote(
          current: asset.currentPrice ?? asset.principal,
          previousClose:
              asset.previousClose ?? asset.currentPrice ?? asset.principal,
          history: const [],
          historySource: 'cdi',
          priceDate: DateTime.now(),
        )),
    };
  }

  /// Obtém somente fechamentos reais publicados pelo provedor.
  /// Não interpola fins de semana, feriados ou valores ausentes.
  Future<List<PricePoint>> fetchHistory(
    InvestmentAsset asset,
    HistoryPeriod period, {
    DateTime? start,
  }) async {
    if (asset.market == AssetMarket.manual) return const [];
    final symbol = asset.market == AssetMarket.b3
        ? '${asset.symbol.trim().toUpperCase().replaceAll('.SA', '')}.SA'
        : asset.symbol.trim().toUpperCase();
    final quote = await _fetchYahoo(
      symbol,
      range: period.providerRange,
      start: start,
      end: DateTime.now().toUtc().add(const Duration(days: 1)),
    );
    return quote.history;
  }

  Future<MarketQuote> fetchDollar() => _fetchYahoo('BRL=X');

  Future<List<PricePoint>> fetchDollarHistory(DateTime start) async {
    final quote = await _fetchYahoo(
      'BRL=X',
      start: start,
      end: DateTime.now().toUtc().add(const Duration(days: 1)),
    );
    return quote.history;
  }

  Future<MarketQuote> _fetchBrazilian(String rawSymbol) async {
    final symbol = rawSymbol.trim().toUpperCase().replaceAll('.SA', '');
    if (_brapiDisponivel) {
      try {
        final quote = await _fetchBrapi(symbol);
        _brapiIndisponivelAte = null;
        return quote;
      } catch (error) {
        // Chave ausente, recusada ou no limite vale para a carteira inteira: a
        // pausa evita gastar uma ida de rede por ativo para o mesmo erro. Uma
        // falha de rede, por outro lado, pode não se repetir no próximo ativo.
        if (_brapiRecusou(error)) {
          _brapiIndisponivelAte = DateTime.now().add(_brapiPausa);
        }
      }
    }

    // As duas fontes são independentes: pedir uma depois da outra dobrava a
    // latência de cada ativo sem melhorar o resultado.
    final token = _finnhubToken;
    final historyFuture = _opcional(_fetchYahoo('$symbol.SA'));
    final liveFuture =
        token == null ? null : _opcional(_fetchFinnhub('$symbol.SA', token));

    final history = await historyFuture;
    final live = liveFuture == null ? null : await liveFuture;

    // Mantém a cotação histórica pública quando a chave não tem acesso à B3.
    if (live != null) return _mergeLiveWithHistory(live, history);
    if (history != null) return history;
    throw QuoteException(
      'Cotação de $symbol indisponível na brapi, Finnhub e fonte alternativa',
    );
  }

  Future<bool> validateFinnhubToken(String token) async {
    final quote = await _fetchFinnhub('AAPL', token.trim());
    return quote.current > 0;
  }

  Future<MarketQuote> _fetchInternational(String symbol) async {
    final token = _finnhubToken;
    if (token == null) return _fetchYahoo(symbol);

    Object? liveError;
    final historyFuture = _opcional(_fetchYahoo(symbol));
    final liveFuture = _opcional(
      _fetchFinnhub(symbol, token),
      onError: (error) => liveError = error,
    );

    final history = await historyFuture;
    final live = await liveFuture;

    if (live != null) return _mergeLiveWithHistory(live, history);
    if (history != null) return history;
    throw liveError ?? QuoteException('Cotação indisponível para $symbol');
  }

  /// Aguarda uma consulta sem deixar a falha derrubar as outras em andamento.
  ///
  /// O `try` começa a rodar já na chamada, então o erro nunca escapa como
  /// exceção não tratada enquanto o outro provedor ainda responde.
  Future<MarketQuote?> _opcional(
    Future<MarketQuote> consulta, {
    void Function(Object error)? onError,
  }) async {
    try {
      return await consulta;
    } catch (error) {
      onError?.call(error);
      return null;
    }
  }

  /// Combina o preço ao vivo da Finnhub com a série diária já obtida.
  ///
  /// O `pc` da Finnhub é um metadado solto e, para a B3, costuma chegar
  /// defasado: no meio do pregão ele já trouxe um preço do próprio dia, o que
  /// fazia a variação diária ser medida contra a parcial de hoje em vez do
  /// fechamento anterior. A série diária continua sendo a referência primária;
  /// o metadado só entra quando não há nenhum pregão concluído para comparar.
  MarketQuote _mergeLiveWithHistory(MarketQuote live, MarketQuote? history) {
    final series = history?.history ?? const <PricePoint>[];
    final livePrevious = live.previousClose > 0 ? live.previousClose : null;
    return MarketQuote(
      current: live.current,
      previousClose: resolvePreviousClose(
        history: series,
        current: live.current,
        providerPrevious: history?.previousClose ?? livePrevious,
        currentPriceDate: live.priceDate ?? history?.priceDate,
      ),
      history: series,
      historySource: history?.historySource ?? live.historySource,
      priceDate: live.priceDate ?? history?.priceDate,
    );
  }

  Future<MarketQuote> _fetchFinnhub(String symbol, String token) async {
    final uri = Uri.https('finnhub.io', '/api/v1/quote', {
      'symbol': symbol.trim().toUpperCase(),
      'token': token,
    });
    late final http.Response response;
    try {
      response = await _client.get(uri).timeout(_timeout);
    } catch (error) {
      throw QuoteException(
        'Falha de rede ao acessar finnhub.io (${error.runtimeType})',
      );
    }
    Map<String, dynamic>? data;
    try {
      data = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      data = null;
    }
    if (response.statusCode != 200) {
      final apiError = data?['error']?.toString().trim();
      throw QuoteException(
        'Finnhub respondeu ${response.statusCode}'
        '${apiError == null || apiError.isEmpty ? '' : ': $apiError'}',
      );
    }
    final apiError = data?['error']?.toString().trim();
    if (apiError != null && apiError.isNotEmpty) {
      throw QuoteException('Finnhub: $apiError');
    }
    final current = _number(data?['c']);
    final previous = _number(data?['pc']);
    if (current == null || current <= 0) {
      throw const QuoteException(
          'Chave Finnhub inválida ou cotação indisponível');
    }
    return MarketQuote(
      current: current,
      previousClose: previous != null && previous > 0 ? previous : current,
      history: const [],
      historySource: 'finnhub',
      priceDate: _epochDate(data?['t']),
    );
  }

  Future<MarketQuote> _fetchBrapi(String rawSymbol, {String? token}) async {
    final symbol = rawSymbol.trim().toUpperCase().replaceAll('.SA', '');
    final chave = token ?? _brapiToken;
    final uri = Uri.https(
      'brapi.dev',
      '/api/quote/$symbol',
      {
        'range': '1mo',
        'interval': '1d',
        'fundamental': 'false',
        if (chave != null) 'token': chave,
      },
    );
    final response =
        await _client.get(uri).timeout(_timeout);
    if (response.statusCode != 200) {
      throw QuoteException(
        'B3: resposta ${response.statusCode} para $symbol',
        status: response.statusCode,
      );
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final results = body['results'] as List<dynamic>?;
    if (results == null || results.isEmpty) {
      throw QuoteException('Ativo $symbol não encontrado na B3');
    }
    final data = results.first as Map<String, dynamic>;
    final current = _number(data['regularMarketPrice']);
    final previous = _number(data['regularMarketPreviousClose']);
    if (current == null) {
      throw QuoteException('Cotação indisponível para $symbol');
    }
    final history = <PricePoint>[];
    for (final item in (data['historicalDataPrice'] as List<dynamic>? ?? [])) {
      final row = item as Map<String, dynamic>;
      final close = _number(row['close']);
      final epoch = (row['date'] as num?)?.toInt();
      if (close != null && epoch != null) {
        history.add(PricePoint(
          DateTime.fromMillisecondsSinceEpoch(epoch * 1000),
          close,
        ));
      }
    }
    history.sort((a, b) => a.date.compareTo(b.date));
    final marketDate = _marketDate(data['regularMarketTime']);
    return MarketQuote(
      current: current,
      previousClose: resolvePreviousClose(
        history: history,
        current: current,
        providerPrevious: previous,
        currentPriceDate: marketDate,
      ),
      history: history,
      historySource: 'brapi',
      priceDate:
          marketDate ?? (history.isEmpty ? null : history.last.date),
    );
  }

  Future<MarketQuote> _fetchYahoo(
    String rawSymbol, {
    String range = '1mo',
    DateTime? start,
    DateTime? end,
  }) async {
    final symbol = rawSymbol.trim().toUpperCase();
    final query = <String, String>{
      'interval': '1d',
      'events': 'history',
      if (start == null) 'range': range,
      if (start != null)
        'period1': (start.toUtc().millisecondsSinceEpoch ~/ 1000).toString(),
      if (start != null)
        'period2':
            ((end ?? DateTime.now().toUtc()).toUtc().millisecondsSinceEpoch ~/
                    1000)
                .toString(),
    };
    final uri = Uri.https(
      'query1.finance.yahoo.com',
      '/v8/finance/chart/$symbol',
      query,
    );
    final response = await _client.get(
      uri,
      headers: {'User-Agent': 'Mozilla/5.0 OpenStock/1.0'},
    ).timeout(_timeout);
    if (response.statusCode != 200) {
      throw QuoteException(
          'Mercado internacional: resposta ${response.statusCode}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final chart = body['chart'] as Map<String, dynamic>?;
    if (chart?['error'] != null) {
      throw QuoteException('Símbolo $symbol inválido');
    }
    final results = chart?['result'] as List<dynamic>?;
    if (results == null || results.isEmpty) {
      throw QuoteException('Cotação indisponível para $symbol');
    }
    final data = results.first as Map<String, dynamic>;
    final meta = data['meta'] as Map<String, dynamic>;
    final current = _number(meta['regularMarketPrice']);
    if (current == null) {
      throw QuoteException('Cotação indisponível para $symbol');
    }
    final timestamps = (data['timestamp'] as List<dynamic>? ?? const []);
    final indicators = data['indicators'] as Map<String, dynamic>?;
    final quoteList = indicators?['quote'] as List<dynamic>?;
    final quote = quoteList == null || quoteList.isEmpty
        ? null
        : quoteList.first as Map<String, dynamic>;
    final closes = quote?['close'] as List<dynamic>? ?? const [];
    final history = <PricePoint>[];
    for (var i = 0; i < timestamps.length && i < closes.length; i++) {
      final close = _number(closes[i]);
      if (close != null) {
        history.add(PricePoint(
          DateTime.fromMillisecondsSinceEpoch(
              (timestamps[i] as num).toInt() * 1000),
          close,
        ));
      }
    }
    history.sort((a, b) => a.date.compareTo(b.date));
    final marketDate = _epochDate(meta['regularMarketTime']);
    final previous = resolvePreviousClose(
      history: history,
      current: current,
      providerPrevious: _number(meta['chartPreviousClose']) ??
          _number(meta['regularMarketPreviousClose']),
      currentPriceDate: marketDate,
    );
    return MarketQuote(
      current: current,
      previousClose: previous,
      history: history,
      historySource: 'yahoo',
      priceDate:
          marketDate ?? (history.isEmpty ? null : history.last.date),
    );
  }

  double? _number(Object? value) => value is num ? value.toDouble() : null;

  DateTime? _epochDate(Object? value) {
    if (value is! num || value.toInt() <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(value.toInt() * 1000);
  }

  DateTime? _marketDate(Object? value) {
    if (value is num) return _epochDate(value);
    if (value is String) return DateTime.tryParse(value)?.toLocal();
    return null;
  }
}

/// Obtém o fechamento do pregão anterior a partir da série diária.
///
/// Alguns provedores mantêm `regularMarketPreviousClose` desatualizado. A série
/// histórica é a referência primária; o metadado só é usado quando ela não
/// contém nenhum pregão concluído.
double resolvePreviousClose({
  required List<PricePoint> history,
  required double current,
  double? providerPrevious,
  DateTime? currentPriceDate,
  DateTime? now,
}) {
  if (history.isNotEmpty) {
    final ordered = [...history]..sort((a, b) => a.date.compareTo(b.date));
    // Candles diarios podem chegar como meia-noite UTC. No horario brasileiro,
    // isso vira 21h do dia anterior se comparado como horario local e faz a
    // parcial de hoje parecer o fechamento de ontem. Comparamos o dia UTC do
    // candle com o dia informado pelo proprio preco atual.
    final reference = (currentPriceDate ?? now ?? DateTime.now()).toUtc();
    final referenceDay = DateTime.utc(
      reference.year,
      reference.month,
      reference.day,
    );
    final completed = ordered.where((point) {
      final utc = point.date.toUtc();
      final pointDay = DateTime.utc(utc.year, utc.month, utc.day);
      return pointDay.isBefore(referenceDay);
    });
    if (completed.isNotEmpty) return completed.last.value;
    if (ordered.length > 1) return ordered[ordered.length - 2].value;
  }
  return providerPrevious ?? current;
}
