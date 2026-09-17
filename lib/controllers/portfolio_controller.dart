import 'package:flutter/foundation.dart';

import '../models/fixed_income.dart';
import '../models/history_models.dart';
import '../models/investment_asset.dart';
import '../services/cdi_service.dart';
import '../services/database_service.dart';
import '../services/quote_service.dart';
import '../services/settings_service.dart';
import '../services/sync_service.dart';
import '../services/turso_service.dart';

class PortfolioController extends ChangeNotifier {
  PortfolioController({
    DatabaseService? database,
    QuoteService? quotes,
    CdiService? cdi,
    SettingsService? settings,
    TursoService? turso,
  })  : _database = database ?? DatabaseService.instance,
        _quotes = quotes ?? QuoteService(),
        _cdi = cdi ?? CdiService(),
        _settings = settings ?? const SettingsService(),
        _turso = turso ?? TursoService();

  final DatabaseService _database;
  final QuoteService _quotes;
  final CdiService _cdi;
  final SettingsService _settings;
  final TursoService _turso;

  List<InvestmentAsset> assets = [];
  List<PricePoint> portfolioHistory = [];
  List<PortfolioSnapshot> portfolioSnapshots = [];
  List<CdiRate> cdiRates = [];
  List<PricePoint> cdiHistory = [];
  bool cdiLoading = false;
  String? cdiError;
  final Map<String, List<PricePoint>> assetHistories = {};
  final Set<String> historyLoading = {};
  final Map<String, String> historyErrors = {};
  MarketQuote? dollarQuote;
  bool loading = true;
  bool refreshing = false;
  String? message;
  DateTime? lastRefresh;
  bool finnhubConfigured = false;
  bool finnhubValidated = false;
  String? finnhubConnectionMessage;
  String? _finnhubKey;

  bool tursoConfigured = false;
  bool syncing = false;
  DateTime? lastSync;
  String? syncMessage;
  bool _historyDirtyForSync = false;
  bool _syncRequested = false;

  bool get hasForeignAssets =>
      assets.any((asset) => asset.currency == AssetCurrency.usd);

  bool isHistoryLoading(String assetKey) =>
      historyLoading.any((entry) => entry.startsWith('$assetKey:'));

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
    final price =
        asset.previousClose ?? asset.currentPrice ?? asset.averagePrice;
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
  double get dayPercent =>
      previousTotal == 0 ? 0 : dayResult / previousTotal * 100;
  double get totalResult => totalValue - totalCost;
  double get totalPercent => totalCost == 0 ? 0 : totalResult / totalCost * 100;

  /// Carteira contra o CDI na janela carregada na tela de comparação.
  ///
  /// A rentabilidade da carteira é medida sem os aportes, então o número é
  /// comparável ao CDI acumulado entre as mesmas datas.
  CdiComparison? get cdiComparison =>
      compareToCdi(snapshots: portfolioSnapshots, rates: cdiRates);

  double assetDayResult(InvestmentAsset asset) =>
      currentValue(asset) - previousValue(asset);
  double assetDayPercent(InvestmentAsset asset) {
    final previous = previousValue(asset);
    return previous == 0 ? 0 : assetDayResult(asset) / previous * 100;
  }

  /// Ativos que subiram no dia, da maior para a menor alta percentual.
  ///
  /// O impacto em reais continua disponível em [assetDayResult], mas o ranking
  /// percentual evita que apenas as maiores posições dominem a lista.
  List<InvestmentAsset> get dayGainers {
    final gainers = assets
        .where((asset) => assetDayPercent(asset) > 0)
        .toList(growable: false);
    return [...gainers]
      ..sort(
        (a, b) => assetDayPercent(b).compareTo(assetDayPercent(a)),
      );
  }

  /// Ativos que caíram no dia, da maior para a menor baixa percentual.
  List<InvestmentAsset> get dayLosers {
    final losers = assets
        .where((asset) => assetDayPercent(asset) < 0)
        .toList(growable: false);
    return [...losers]
      ..sort(
        (a, b) => assetDayPercent(a).compareTo(assetDayPercent(b)),
      );
  }

  double assetTotalResult(InvestmentAsset asset) =>
      currentValue(asset) - costValue(asset);
  double assetTotalPercent(InvestmentAsset asset) {
    final cost = costValue(asset);
    return cost == 0 ? 0 : assetTotalResult(asset) / cost * 100;
  }

  Future<void> initialize() async {
    loading = true;
    notifyListeners();
    try {
      final finnhubKey = await _settings.loadFinnhubKey();
      _finnhubKey = finnhubKey;
      finnhubConfigured = finnhubKey != null && finnhubKey.isNotEmpty;
      _quotes.configureFinnhub(finnhubKey);
      final tursoCredentials = await _settings.loadTursoCredentials();
      if (tursoCredentials != null) {
        _turso.configure(tursoCredentials.url, tursoCredentials.token);
        tursoConfigured = true;
        await synchronize(silent: true);
      }
      await _reloadLocalData();
      if (assets.isNotEmpty) await refresh();
    } catch (error) {
      message = 'Não foi possível abrir todos os dados: $error';
      await _reloadLocalData();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> _reloadLocalData() async {
    assets = await _database.loadAssets();
    dollarQuote = await _database.loadDollarQuote();
    await _reloadSnapshots();
  }

  Future<void> _reloadSnapshots({DateTime? from}) async {
    portfolioSnapshots = await _database.loadPortfolioSnapshots(from: from);
    portfolioHistory =
        portfolioSnapshots.map((snapshot) => snapshot.toPoint()).toList();
  }

  Future<String?> saveFinnhubKey(String key) async {
    final clean = key.trim();
    if (clean.isEmpty) {
      await _settings.saveFinnhubKey('');
      _quotes.configureFinnhub(null);
      _finnhubKey = null;
      finnhubConfigured = false;
      finnhubValidated = false;
      finnhubConnectionMessage = null;
      notifyListeners();
      return null;
    }
    try {
      await _settings.saveFinnhubKey(clean);
      _finnhubKey = clean;
      _quotes.configureFinnhub(clean);
      finnhubConfigured = true;
    } catch (_) {
      return 'Não foi possível guardar a chave no Android.';
    }
    await testFinnhub();
    await refresh();
    return null;
  }

  Future<String> testFinnhub() async {
    final key = _finnhubKey;
    if (key == null || key.isEmpty) return 'Nenhuma chave foi configurada.';
    try {
      final valid = await _quotes.validateFinnhubToken(key);
      finnhubValidated = valid;
      finnhubConnectionMessage = valid
          ? 'Conexão validada com a Finnhub.'
          : 'A Finnhub não confirmou essa chave.';
    } catch (error) {
      finnhubValidated = false;
      finnhubConnectionMessage = error.toString();
    }
    notifyListeners();
    return finnhubConnectionMessage!;
  }

  Future<String?> configureTurso(String url, String token) async {
    try {
      _turso.configure(url, token);
      await _turso.testConnection();
      tursoConfigured = true;
      syncMessage = 'Conexão com o Turso validada.';
      notifyListeners();
      final synchronized = await synchronize();
      if (!synchronized) {
        tursoConfigured = false;
        _turso.clear();
        return syncMessage ??
            'O Turso não permitiu criar ou sincronizar as tabelas.';
      }
      await _settings.saveTursoCredentials(url, token);
      if (assets.isNotEmpty) await refresh();
      return null;
    } catch (error) {
      syncMessage = error.toString();
      notifyListeners();
      return 'Não foi possível conectar: $error';
    }
  }

  Future<void> removeTurso() async {
    await _settings.clearTursoCredentials();
    _turso.clear();
    tursoConfigured = false;
    syncMessage = null;
    notifyListeners();
  }

  Future<bool> synchronize({bool silent = false}) async {
    if (!tursoConfigured) return false;
    if (syncing) {
      _syncRequested = true;
      return false;
    }
    var succeeded = false;
    syncing = true;
    if (!silent) syncMessage = null;
    notifyListeners();
    try {
      final report = await SyncService(_database, _turso).synchronize();
      _historyDirtyForSync = false;
      lastSync = DateTime.now();
      syncMessage = 'Sincronizado: ${report.uploaded} enviados, '
          '${report.downloaded} recebidos.';
      await _reloadLocalData();
      succeeded = true;
    } catch (error) {
      syncMessage =
          'Sem sincronização: $error. Os dados locais continuam ativos.';
    } finally {
      syncing = false;
      notifyListeners();
      if (_syncRequested) {
        _syncRequested = false;
        await synchronize(silent: true);
      }
    }
    return succeeded;
  }

  Future<void> refresh({bool syncAfter = true}) async {
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
        if (dollarQuote == null) errors.add('dólar');
      }
    }

    for (var i = 0; i < assets.length; i++) {
      final asset = assets[i];
      if (asset.market == AssetMarket.manual || asset.isFixedIncome) continue;
      try {
        final quote = await _quotes.fetch(asset);
        if (asset.id != null) await _database.saveQuote(asset.id!, quote);
        await _database.upsertHistory(
          asset,
          quote.history,
          source: quote.historySource,
        );
        assets[i] = asset.copyWith(
          currentPrice: quote.current,
          previousClose: quote.previousClose,
        );
      } catch (_) {
        errors.add(asset.symbol);
      }
    }

    await refreshFixedIncome();
    if (cdiError != null) errors.add('CDI');

    if (totalValue > 0) {
      await _database.saveSnapshot(totalValue, totalCost);
      await _reloadSnapshots();
    }
    lastRefresh = DateTime.now();
    if (errors.isNotEmpty) {
      message = 'Sem atualização para: ${errors.join(', ')}. '
          'Os demais ativos foram atualizados e o último valor foi mantido.';
    }
    refreshing = false;
    notifyListeners();
    if (syncAfter && tursoConfigured) await synchronize(silent: true);
  }

  Future<void> ensureHistory(
    InvestmentAsset asset,
    HistoryPeriod period, {
    bool force = false,
    bool syncAfter = true,
  }) async {
    final key = asset.syncKey;
    final taskKey = '$key:${period.name}';
    if (historyLoading.contains(taskKey)) return;
    historyLoading.add(taskKey);
    historyErrors.remove(key);
    notifyListeners();
    final from = period.startFrom(DateTime.now());
    try {
      if (asset.isFixedIncome) {
        // A série da renda fixa é calculada, não baixada: ela vem do principal
        // corrigido pelas taxas do Banco Central que já estão em cache.
        final fresh = await _database.historyFetchIsFresh(
          cdiSeriesKey,
          HistoryPeriod.maximum,
        );
        await refreshFixedIncome(fetch: force || !fresh);
        if ((assetHistories[key] ?? const []).isEmpty) {
          historyErrors[key] =
              'Informe indexador, taxa e data de aplicação do título.';
        }
        return;
      }
      var cached = await _database.loadAssetHistory(key, from: from);
      assetHistories[key] = await _database.loadAssetHistory(key);
      notifyListeners();
      final fresh = await _database.historyFetchIsFresh(key, period);
      if (!force && fresh) return;
      if (asset.market == AssetMarket.manual) {
        if (cached.isEmpty) historyErrors[key] = 'Ativo manual sem histórico.';
        return;
      }

      DateTime? incrementalStart;
      final requestedStart = period.startFrom(DateTime.now());
      final coversStart = requestedStart != null &&
          cached.isNotEmpty &&
          !cached.first.date
              .isAfter(requestedStart.add(const Duration(days: 7)));
      if (coversStart && cached.isNotEmpty) {
        incrementalStart = cached.last.date;
      }
      final fetched = await _quotes.fetchHistory(
        asset,
        period,
        start: incrementalStart,
      );
      await _database.upsertHistory(asset, fetched, source: 'yahoo');
      if (fetched.isNotEmpty) _historyDirtyForSync = true;
      await _database.markHistoryFetched(key, period);
      cached = await _database.loadAssetHistory(key, from: from);
      assetHistories[key] = await _database.loadAssetHistory(key);
      if (cached.isEmpty) historyErrors[key] = 'Nenhum fechamento disponível.';
      if (syncAfter && tursoConfigured && _historyDirtyForSync) {
        await synchronize(silent: true);
      }
    } catch (error) {
      historyErrors[key] = 'Histórico indisponível: $error';
    } finally {
      historyLoading.remove(taskKey);
      notifyListeners();
    }
  }

  /// Taxas diárias do CDI para a janela pedida, do cache e do Banco Central.
  ///
  /// Só as taxas realmente publicadas entram na série; nenhum dia sem
  /// divulgação é preenchido para emendar o gráfico.
  Future<void> ensureCdi(HistoryPeriod period, {bool force = false}) async {
    if (cdiLoading) return;
    cdiLoading = true;
    cdiError = null;
    notifyListeners();
    final from = period.startFrom(DateTime.now()) ?? _earliestKnownDate();
    try {
      await _reloadCdi(from);
      final fresh = await _database.historyFetchIsFresh(cdiSeriesKey, period);
      if (!force && fresh && cdiRates.isNotEmpty) return;

      final coverage = await _database.cdiCoverage();
      // Só busca desde o começo da janela quando o cache não a cobre.
      final covered = coverage != null &&
          !coverage.oldest.isAfter(from.add(const Duration(days: 7)));
      final start = covered ? coverage.newest : from;
      final fetched = await _cdi.fetchDailyRates(start: start);
      await _database.upsertCdiRates(fetched);
      await _database.markHistoryFetched(cdiSeriesKey, period);
      await _reloadCdi(from);
      if (cdiRates.isEmpty) {
        cdiError = 'O Banco Central não publicou CDI para esse período.';
      }
    } catch (error) {
      cdiError = 'CDI indisponível: $error';
    } finally {
      cdiLoading = false;
      notifyListeners();
    }
  }

  /// Recalcula o valor dos títulos de renda fixa com o CDI publicado.
  ///
  /// Nada é cotado: o Banco Central fornece só a taxa do dia, e o valor de cada
  /// título vem do principal corrigido dia útil a dia útil.
  Future<void> refreshFixedIncome({bool fetch = true, bool force = false}) async {
    final titles = assets.where((asset) => asset.isFixedIncome).toList();
    if (titles.isEmpty) return;
    final earliest = titles
        .map((asset) => asset.applicationDate ?? DateTime.now())
        .reduce((a, b) => a.isBefore(b) ? a : b);
    if (fetch) {
      try {
        await _fetchCdiFrom(earliest, force: force);
        cdiError = null;
      } catch (error) {
        cdiError = 'CDI indisponível: $error';
      }
    }
    final rates = await _database.loadCdiRates(from: earliest);
    for (var i = 0; i < assets.length; i++) {
      final asset = assets[i];
      if (!asset.isFixedIncome) continue;
      final accrued = accrueFixedIncome(asset: asset, rates: rates);
      final position =
          fixedIncomePosition(asset: asset, accrued: accrued);
      if (position == null) continue;
      assetHistories[asset.syncKey] = accrued;
      assets[i] = asset.copyWith(
        currentPrice: position.grossValue,
        previousClose: position.previousGrossValue,
      );
      if (asset.id != null) {
        // O valor fica gravado para a abertura seguinte já mostrar o título
        // corrigido, mesmo antes de o CDI do dia ser buscado.
        await _database.saveQuote(
          asset.id!,
          MarketQuote(
            current: position.grossValue,
            previousClose: position.previousGrossValue,
            history: const [],
            historySource: 'cdi',
          ),
        );
      }
    }
    notifyListeners();
  }

  /// Garante o CDI em cache desde [from], buscando apenas o trecho que falta.
  Future<void> _fetchCdiFrom(DateTime from, {bool force = false}) async {
    final coverage = await _database.cdiCoverage();
    // Tolerância de uma semana: uma aplicação em sexta, sábado ou véspera de
    // feriado tem como primeiro dia útil um dia bem depois da própria data.
    final covered = coverage != null &&
        !coverage.oldest.isAfter(from.add(const Duration(days: 7)));
    final fresh = await _database.historyFetchIsFresh(
      cdiSeriesKey,
      HistoryPeriod.maximum,
    );
    if (!force && fresh && covered) return;
    final fetched = await _cdi.fetchDailyRates(
      start: covered ? coverage.newest : from,
    );
    await _database.upsertCdiRates(fetched);
    await _database.markHistoryFetched(cdiSeriesKey, HistoryPeriod.maximum);
  }

  Future<void> _reloadCdi(DateTime from) async {
    cdiRates = await _database.loadCdiRates(from: from);
    cdiHistory = accumulateCdi(cdiRates);
  }

  DateTime _earliestKnownDate() {
    final candidates = <DateTime>[
      if (portfolioHistory.isNotEmpty) portfolioHistory.first.date,
      for (final points in assetHistories.values)
        if (points.isNotEmpty) points.first.date,
    ];
    if (candidates.isEmpty) {
      final now = DateTime.now();
      return DateTime(now.year - 5, now.month, now.day);
    }
    return candidates.reduce((a, b) => a.isBefore(b) ? a : b);
  }

  Future<void> loadComparison(
    Iterable<InvestmentAsset> selected,
    HistoryPeriod period,
  ) async {
    // Os snapshots vêm primeiro: no período máximo eles definem desde quando o
    // CDI precisa ser buscado.
    await _reloadSnapshots(from: period.startFrom(DateTime.now()));
    await Future.wait([
      ...selected.map(
        (asset) => ensureHistory(asset, period, syncAfter: false),
      ),
      ensureCdi(period),
    ]);
    notifyListeners();
    if (tursoConfigured && _historyDirtyForSync) {
      await synchronize(silent: true);
    }
  }

  Future<String?> saveAsset(InvestmentAsset asset) async {
    try {
      final symbol = asset.symbol.trim().toUpperCase();
      final now = DateTime.now().toUtc();
      final normalized = asset.copyWith(
        stableKey: buildAssetKey(asset.market, symbol),
        symbol: symbol,
        name: asset.name.trim().isEmpty ? symbol : asset.name.trim(),
        createdAt: asset.createdAt ?? now,
        previousClose: asset.market == AssetMarket.manual && asset.id != null
            ? assets.firstWhere((a) => a.id == asset.id).currentPrice
            : asset.previousClose,
      );
      var assetToSave = normalized;
      var index = assets.indexWhere((item) => item.id == asset.id);
      if (index >= 0 && assets[index].syncKey != normalized.syncKey) {
        // Mantém um tombstone da identidade antiga para os outros aparelhos.
        await _database.deleteAsset(assets[index].id!);
        assetToSave = InvestmentAsset(
          stableKey: normalized.syncKey,
          symbol: normalized.symbol,
          name: normalized.name,
          market: normalized.market,
          currency: normalized.currency,
          quantity: normalized.quantity,
          averagePrice: normalized.averagePrice,
          averageExchangeRate: normalized.averageExchangeRate,
          currentPrice: normalized.currentPrice,
          previousClose: normalized.previousClose,
          createdAt: now,
        );
      }
      final saved = await _database.saveAsset(assetToSave);
      index = assets.indexWhere((item) => item.id == asset.id);
      if (index < 0) {
        assets = [...assets, saved]
          ..sort((a, b) => a.symbol.compareTo(b.symbol));
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
    assets.removeWhere((item) => item.id == asset.id);
    assetHistories.remove(asset.syncKey);
    notifyListeners();
    if (tursoConfigured) await synchronize(silent: true);
  }
}
