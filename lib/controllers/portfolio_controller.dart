import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/investment_asset.dart';
import '../services/database_service.dart';
import '../services/quote_service.dart';
import '../services/settings_service.dart';

class PortfolioController extends ChangeNotifier {
  PortfolioController({
    DatabaseService? database,
    QuoteService? quotes,
    SettingsService? settings,
  })
      : _database = database ?? DatabaseService.instance,
        _quotes = quotes ?? QuoteService(),
        _settings = settings ?? const SettingsService();

  final DatabaseService _database;
  final QuoteService _quotes;
  final SettingsService _settings;

  List<InvestmentAsset> assets = [];
  List<PricePoint> portfolioHistory = [];
  MarketQuote? dollarQuote;
  bool loading = true;
  bool refreshing = false;
  String? message;
  DateTime? lastRefresh;
  bool finnhubConfigured = false;

  final Map<int, MarketQuote> _marketQuotes = {};

  bool get hasForeignAssets =>
      assets.any((asset) => asset.currency == AssetCurrency.usd);

  double get usdBrl => dollarQuote?.current ?? 0;
  double get previousUsdBrl => dollarQuote?.previousClose ?? usdBrl;

  double currentValue(InvestmentAsset asset) {
    final price = asset.currentPrice ?? asset.averagePrice;
    final fx = asset.currency == AssetCurrency.usd
        ? (usdBrl > 0 ? usdBrl : asset.averageExchangeRate)
        : 1.0;
    return price * asset.quantity * fx;
  }

  double previousValue(InvestmentAsset asset) {
    final price = asset.previousClose ?? asset.currentPrice ?? asset.averagePrice;
    final fx = asset.currency == AssetCurrency.usd
        ? (previousUsdBrl > 0 ? previousUsdBrl : asset.averageExchangeRate)
        : 1.0;
    return price * asset.quantity * fx;
  }

  double costValue(InvestmentAsset asset) =>
      asset.averagePrice *
      asset.quantity *
      (asset.currency == AssetCurrency.usd ? asset.averageExchangeRate : 1);

  double get totalValue => assets.fold(0, (sum, a) => sum + currentValue(a));
  double get previousTotal =>
      assets.fold(0, (sum, a) => sum + previousValue(a));
  double get totalCost => assets.fold(0, (sum, a) => sum + costValue(a));
  double get dayResult => totalValue - previousTotal;
  double get dayPercent => previousTotal == 0 ? 0 : dayResult / previousTotal * 100;
  double get totalResult => totalValue - totalCost;
  double get totalPercent => totalCost == 0 ? 0 : totalResult / totalCost * 100;

  double assetDayResult(InvestmentAsset asset) =>
      currentValue(asset) - previousValue(asset);
  double assetDayPercent(InvestmentAsset asset) {
    final previous = previousValue(asset);
    return previous == 0 ? 0 : assetDayResult(asset) / previous * 100;
  }

  double assetTotalResult(InvestmentAsset asset) =>
      currentValue(asset) - costValue(asset);

  Future<void> initialize() async {
    loading = true;
    notifyListeners();
    try {
      final finnhubKey = await _settings.loadFinnhubKey();
      finnhubConfigured = finnhubKey != null && finnhubKey.isNotEmpty;
      _quotes.configureFinnhub(finnhubKey);
      assets = await _database.loadAssets();
      dollarQuote = await _database.loadDollarQuote();
      portfolioHistory = await _database.loadSnapshots();
      if (assets.isNotEmpty) await refresh();
    } catch (error) {
      message = 'Não foi possível abrir os dados: $error';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<String?> saveFinnhubKey(String key) async {
    final clean = key.trim();
    if (clean.isEmpty) {
      await _settings.saveFinnhubKey('');
      _quotes.configureFinnhub(null);
      finnhubConfigured = false;
      notifyListeners();
      return null;
    }
    try {
      final valid = await _quotes.validateFinnhubToken(clean);
      if (!valid) return 'A Finnhub não aceitou essa chave.';
      await _settings.saveFinnhubKey(clean);
      _quotes.configureFinnhub(clean);
      finnhubConfigured = true;
      notifyListeners();
      await refresh();
      return null;
    } catch (_) {
      return 'Não foi possível validar a chave Finnhub.';
    }
  }

  Future<void> refresh() async {
    if (refreshing || assets.isEmpty) return;
    refreshing = true;
    message = null;
    notifyListeners();
    final errors = <String>[];

    if (hasForeignAssets) {
      try {
        dollarQuote = await _quotes.fetchDollar();
        await _database.saveDollarQuote(dollarQuote!);
      } catch (_) {
        if (dollarQuote == null) errors.add('Não foi possível consultar o dólar');
      }
    }

    for (var i = 0; i < assets.length; i++) {
      final asset = assets[i];
      if (asset.market == AssetMarket.manual) continue;
      try {
        final quote = await _quotes.fetch(asset);
        if (asset.id != null) {
          _marketQuotes[asset.id!] = quote;
          await _database.saveQuote(asset.id!, quote);
        }
        assets[i] = asset.copyWith(
          currentPrice: quote.current,
          previousClose: quote.previousClose,
          updatedAt: DateTime.now(),
        );
      } catch (_) {
        errors.add(asset.symbol);
      }
    }

    _buildMarketHistory();
    if (totalValue > 0) {
      await _database.saveSnapshot(totalValue, totalCost);
      if (portfolioHistory.length < 2) {
        portfolioHistory = await _database.loadSnapshots();
      }
    }
    lastRefresh = DateTime.now();
    if (errors.isNotEmpty) {
      message = 'Sem atualização para: ${errors.join(', ')}. Mantive o último valor.';
    }
    refreshing = false;
    notifyListeners();
  }

  Future<String?> saveAsset(InvestmentAsset asset) async {
    try {
      final normalized = asset.copyWith(
        symbol: asset.symbol.trim().toUpperCase(),
        name: asset.name.trim().isEmpty
            ? asset.symbol.trim().toUpperCase()
            : asset.name.trim(),
        previousClose: asset.market == AssetMarket.manual && asset.id != null
            ? assets.firstWhere((a) => a.id == asset.id).currentPrice
            : asset.previousClose,
      );
      final saved = await _database.saveAsset(normalized);
      final index = assets.indexWhere((item) => item.id == saved.id);
      if (index < 0) {
        assets = [...assets, saved]..sort((a, b) => a.symbol.compareTo(b.symbol));
      } else {
        assets[index] = saved;
      }
      notifyListeners();
      await refresh();
      return null;
    } catch (error) {
      if (error.toString().contains('UNIQUE constraint')) {
        return 'Esse ativo já está na carteira.';
      }
      return 'Não foi possível salvar o ativo.';
    }
  }

  Future<void> deleteAsset(InvestmentAsset asset) async {
    if (asset.id == null) return;
    await _database.deleteAsset(asset.id!);
    _marketQuotes.remove(asset.id);
    assets.removeWhere((item) => item.id == asset.id);
    _buildMarketHistory();
    notifyListeners();
  }

  void _buildMarketHistory() {
    final datedQuotes = _marketQuotes.values
        .expand((quote) => quote.history)
        .map((point) => _day(point.date))
        .toSet()
        .toList()
      ..sort();
    if (datedQuotes.length < 2) return;

    final result = <PricePoint>[];
    for (final date in datedQuotes.skip(math.max(0, datedQuotes.length - 30))) {
      var total = 0.0;
      final fx = _valueOn(dollarQuote?.history ?? const [], date) ??
          dollarQuote?.current ??
          1;
      for (final asset in assets) {
        final history = asset.id == null
            ? const <PricePoint>[]
            : (_marketQuotes[asset.id!]?.history ?? const <PricePoint>[]);
        final price = _valueOn(history, date) ??
            asset.currentPrice ??
            asset.averagePrice;
        total += price *
            asset.quantity *
            (asset.currency == AssetCurrency.usd ? fx : 1);
      }
      if (total > 0) result.add(PricePoint(date, total));
    }
    if (result.length >= 2) portfolioHistory = result;
  }

  double? _valueOn(List<PricePoint> points, DateTime date) {
    double? value;
    for (final point in points) {
      if (!_day(point.date).isAfter(date)) value = point.value;
    }
    return value;
  }

  DateTime _day(DateTime date) => DateTime(date.year, date.month, date.day);
}
