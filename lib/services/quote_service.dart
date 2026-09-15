import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/investment_asset.dart';

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
        )),
    };
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
      throw const QuoteException('Chave Finnhub inválida ou cotação indisponível');
    }
    return MarketQuote(
      current: current,
      previousClose: previous ?? current,
      history: const [],
    );
  }

  Future<MarketQuote> _fetchBrapi(String rawSymbol) async {
    final symbol = rawSymbol.trim().toUpperCase().replaceAll('.SA', '');
    final uri = Uri.https(
      'brapi.dev',
      '/api/quote/$symbol',
      {'range': '1mo', 'interval': '1d', 'fundamental': 'false'},
    );
    final response = await _client.get(uri).timeout(const Duration(seconds: 15));
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
    if (current == null) throw QuoteException('Cotação indisponível para $symbol');
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
    return MarketQuote(
      current: current,
      previousClose: previous ?? (history.isEmpty ? current : history.last.value),
      history: history,
    );
  }

  Future<MarketQuote> _fetchYahoo(String rawSymbol) async {
    final symbol = rawSymbol.trim().toUpperCase();
    final uri = Uri.https(
      'query1.finance.yahoo.com',
      '/v8/finance/chart/$symbol',
      {'range': '1mo', 'interval': '1d', 'events': 'history'},
    );
    final response = await _client.get(
      uri,
      headers: {'User-Agent': 'Mozilla/5.0 OpenStock/1.0'},
    ).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw QuoteException('Mercado internacional: resposta ${response.statusCode}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final chart = body['chart'] as Map<String, dynamic>?;
    if (chart?['error'] != null) throw QuoteException('Símbolo $symbol inválido');
    final results = chart?['result'] as List<dynamic>?;
    if (results == null || results.isEmpty) {
      throw QuoteException('Cotação indisponível para $symbol');
    }
    final data = results.first as Map<String, dynamic>;
    final meta = data['meta'] as Map<String, dynamic>;
    final current = _number(meta['regularMarketPrice']);
    if (current == null) throw QuoteException('Cotação indisponível para $symbol');
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
          DateTime.fromMillisecondsSinceEpoch((timestamps[i] as num).toInt() * 1000),
          close,
        ));
      }
    }
    final previous = _number(meta['regularMarketPreviousClose']) ??
        _number(meta['chartPreviousClose']) ??
        (history.length > 1 ? history[history.length - 2].value : current);
    return MarketQuote(current: current, previousClose: previous, history: history);
  }

  double? _number(Object? value) => value is num ? value.toDouble() : null;
}
