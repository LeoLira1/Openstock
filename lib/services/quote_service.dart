import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/investment_asset.dart';
import '../models/history_models.dart';

class QuoteException implements Exception {
  const QuoteException(this.message);
  final String message;
  @override
  String toString() => message;
}

class QuoteService {
  QuoteService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  String? _finnhubToken;

  void configureFinnhub(String? token) {
    final clean = token?.trim() ?? '';
    _finnhubToken = clean.isEmpty ? null : clean;
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

  Future<MarketQuote> _fetchBrazilian(String rawSymbol) async {
    final symbol = rawSymbol.trim().toUpperCase().replaceAll('.SA', '');
    try {
      return await _fetchBrapi(symbol);
    } catch (_) {
      // A consulta sem token da brapi é limitada a símbolos de demonstração.
    }

    MarketQuote? history;
    try {
      history = await _fetchYahoo('$symbol.SA');
    } catch (_) {
      // A Finnhub ainda pode fornecer o preço atual quando configurada.
    }

    if (_finnhubToken != null) {
      try {
        final live = await _fetchFinnhub('$symbol.SA', _finnhubToken!);
        return MarketQuote(
          current: live.current,
          previousClose: live.previousClose,
          history: history?.history ?? const [],
          historySource: history?.historySource ?? live.historySource,
        );
      } catch (_) {
        // Mantém a cotação histórica pública quando a chave não tem acesso à B3.
      }
    }

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
    MarketQuote? history;
    try {
      history = await _fetchYahoo(symbol);
    } catch (_) {
      if (_finnhubToken == null) rethrow;
    }
    if (_finnhubToken == null) return history!;
    try {
      final live = await _fetchFinnhub(symbol, _finnhubToken!);
      return MarketQuote(
        current: live.current,
        previousClose: live.previousClose,
        history: history?.history ?? const [],
        historySource: history?.historySource ?? live.historySource,
      );
    } catch (_) {
      if (history != null) return history;
      rethrow;
    }
  }

  Future<MarketQuote> _fetchFinnhub(String symbol, String token) async {
    final uri = Uri.https('finnhub.io', '/api/v1/quote', {
      'symbol': symbol.trim().toUpperCase(),
      'token': token,
    });
    late final http.Response response;
    try {
      response = await _client.get(uri).timeout(const Duration(seconds: 15));
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
      previousClose: previous ?? current,
      history: const [],
      historySource: 'finnhub',
    );
  }

  Future<MarketQuote> _fetchBrapi(String rawSymbol) async {
    final symbol = rawSymbol.trim().toUpperCase().replaceAll('.SA', '');
    final uri = Uri.https(
      'brapi.dev',
      '/api/quote/$symbol',
      {'range': '1mo', 'interval': '1d', 'fundamental': 'false'},
    );
    final response =
        await _client.get(uri).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw QuoteException('B3: resposta ${response.statusCode} para $symbol');
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
    return MarketQuote(
      current: current,
      previousClose: resolvePreviousClose(
        history: history,
        current: current,
        providerPrevious: previous,
      ),
      history: history,
      historySource: 'brapi',
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
    ).timeout(const Duration(seconds: 15));
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
    final previous = resolvePreviousClose(
      history: history,
      current: current,
      providerPrevious: _number(meta['chartPreviousClose']) ??
          _number(meta['regularMarketPreviousClose']),
    );
    return MarketQuote(
      current: current,
      previousClose: previous,
      history: history,
      historySource: 'yahoo',
    );
  }

  double? _number(Object? value) => value is num ? value.toDouble() : null;
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
  DateTime? now,
}) {
  if (history.isNotEmpty) {
    final ordered = [...history]..sort((a, b) => a.date.compareTo(b.date));
    final localNow = now ?? DateTime.now();
    final startOfToday = DateTime(localNow.year, localNow.month, localNow.day);
    final completed =
        ordered.where((point) => point.date.isBefore(startOfToday));
    if (completed.isNotEmpty) return completed.last.value;
    if (ordered.length > 1) return ordered[ordered.length - 2].value;
  }
  return providerPrevious ?? current;
}
