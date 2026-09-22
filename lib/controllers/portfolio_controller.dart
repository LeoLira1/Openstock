import 'package:flutter/foundation.dart';

import '../models/fixed_income.dart';
import '../models/history_models.dart';
import '../models/investment_asset.dart';
import '../models/investment_transaction.dart';
import '../models/tracking_analytics.dart';
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

  /// Todos os registros diários da carteira, para o gráfico da tela inicial.
  /// [portfolioSnapshots] pode estar recortado pela janela da comparação.
  List<PortfolioSnapshot> portfolioTimeline = [];

  /// Dia e valor em que cada ativo entrou no rastreamento.
  List<PricePoint> trackingEntryPoints = [];
  List<CdiRate> cdiRates = [];
  List<PricePoint> cdiHistory = [];
  bool cdiLoading = false;
  String? cdiError;
  final Map<String, List<PricePoint>> assetHistories = {};
  final Map<String, List<InvestmentTransaction>> transactionsByAsset = {};
  final Map<String, DateTime> quoteDates = {};
  final Map<String, AssetTrackingSummary> assetTrackingSummaries = {};
  TrackingReport? trackingReport;
  bool intelligenceLoading = false;
  String? intelligenceError;
  final Set<String> historyLoading = {};
  final Map<String, String> historyErrors = {};

  /// Dia em que o rastreamento foi reconstruído pela última vez.
  ///
  /// Baixar históricos e refazer os registros diários é caro; trocar o mês ou o
  /// ano do relatório só precisa recalcular a partir do banco. A preparação é
  /// refeita em um novo dia ou quando operações, ativos ou a sincronização
  /// mudam os dados de base.
  DateTime? _trackingPreparedOn;
  MarketQuote? dollarQuote;
  bool loading = true;
  bool refreshing = false;
  String? message;
  DateTime? lastRefresh;
  bool finnhubConfigured = false;
  bool finnhubValidated = false;
  String? finnhubConnectionMessage;
  String? _finnhubKey;
  bool brapiConfigured = false;
  bool brapiValidated = false;
  String? brapiConnectionMessage;
  String? _brapiKey;

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

  bool _isToday(DateTime? value) {
    if (value == null) return false;
    final local = value.toLocal();
    final now = DateTime.now();
    return local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
  }

  bool quoteIsFromToday(InvestmentAsset asset) =>
      _isToday(quoteDates[asset.syncKey]);

  bool get hasMarketQuoteToday => assets.any(
        (asset) =>
            (asset.market == AssetMarket.b3 ||
                asset.market == AssetMarket.usa) &&
            quoteIsFromToday(asset),
      );

  String get dayChangeLabel =>
      hasMarketQuoteToday ? 'hoje' : 'mercados fechados';

  double currentValue(InvestmentAsset asset) {
    final price = asset.currentPrice ?? asset.averagePrice;
    final fx = asset.currency == AssetCurrency.usd
        ? (usdBrl > 0 ? usdBrl : asset.averageExchangeRate)
        : 1.0;
    return price * asset.quantity * fx;
  }

  double previousValue(InvestmentAsset asset) {
    if ((asset.market == AssetMarket.b3 || asset.market == AssetMarket.usa) &&
        !quoteIsFromToday(asset)) {
      return currentValue(asset);
    }
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

  /// Ativos que subiram no dia, do maior para o menor impacto em reais.
  List<InvestmentAsset> get dayGainersByValue {
    final gainers = assets
        .where((asset) => assetDayResult(asset) > 0)
        .toList(growable: false);
    return [...gainers]
      ..sort(
        (a, b) => assetDayResult(b).compareTo(assetDayResult(a)),
      );
  }

  /// Ativos que caíram no dia, da maior para a menor perda em reais.
  List<InvestmentAsset> get dayLosersByValue {
    final losers = assets
        .where((asset) => assetDayResult(asset) < 0)
        .toList(growable: false);
    return [...losers]
      ..sort(
        (a, b) => assetDayResult(a).compareTo(assetDayResult(b)),
      );
  }

  double assetTotalResult(InvestmentAsset asset) =>
      currentValue(asset) - costValue(asset);
  double assetTotalPercent(InvestmentAsset asset) {
    final cost = costValue(asset);
    return cost == 0 ? 0 : assetTotalResult(asset) / cost * 100;
  }

  /// Todas as operações da carteira em uma lista estável entre recargas.
  List<InvestmentTransaction> allTransactions = const [];

  List<InvestmentTransaction> transactionsFor(InvestmentAsset asset) =>
      transactionsByAsset[asset.syncKey] ?? const [];

  DateTime? trackingStartFor(InvestmentAsset asset) {
    final transactions = transactionsFor(asset);
    if (transactions.isEmpty) return null;
    return transactions
        .map((item) => item.transactionDate)
        .reduce((a, b) => a.isBefore(b) ? a : b);
  }

  double incomeFor(InvestmentAsset asset) =>
      calculateTrackedPosition(transactionsFor(asset)).incomeBrl;

  double realizedResultFor(InvestmentAsset asset) =>
      calculateTrackedPosition(transactionsFor(asset)).realizedResultBrl;

  AssetTrackingSummary? trackingSummaryFor(InvestmentAsset asset) =>
      assetTrackingSummaries[asset.syncKey];

  Future<void> initialize() async {
    loading = true;
    notifyListeners();
    try {
      final finnhubKey = await _settings.loadFinnhubKey();
      _finnhubKey = finnhubKey;
      finnhubConfigured = finnhubKey != null && finnhubKey.isNotEmpty;
      _quotes.configureFinnhub(finnhubKey);
      final brapiKey = await _settings.loadBrapiKey();
      _brapiKey = brapiKey;
      brapiConfigured = brapiKey != null && brapiKey.isNotEmpty;
      _quotes.configureBrapi(brapiKey);
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
    await _database.ensureOpeningTransactions(assets);
    await _reloadTransactions();
    dollarQuote = await _database.loadDollarQuote();
    await _reloadSnapshots();
    await _reloadLocalTrackingSummaries();
  }

  Future<void> _reloadTransactions() async {
    final transactions = await _database.loadTransactions();
    allTransactions = List.unmodifiable(transactions);
    transactionsByAsset
      ..clear()
      ..addEntries(
        transactions.fold<Map<String, List<InvestmentTransaction>>>(
          {},
          (grouped, item) {
            grouped.putIfAbsent(item.assetKey, () => []).add(item);
            return grouped;
          },
        ).entries,
      );
  }

  Future<void> _reloadSnapshots({DateTime? from}) async {
    portfolioSnapshots = await _database.loadPortfolioSnapshots(from: from);
    if (from == null) portfolioTimeline = portfolioSnapshots;
    portfolioHistory =
        portfolioSnapshots.map((snapshot) => snapshot.toPoint()).toList();
  }

  Future<void> _reloadLocalTrackingSummaries() async {
    final results = await Future.wait([
      _database.loadCdiRates(),
      ...assets.map((asset) => _database.loadAssetDailySnapshots(asset.syncKey)),
    ]);
    final rates = results.first as List<CdiRate>;
    trackingEntryPoints = trackingEntries([
      for (var i = 0; i < assets.length; i++)
        (
          snapshots: results[i + 1] as List<AssetDailySnapshot>,
          transactions: transactionsFor(assets[i]),
        ),
    ]);
    assetTrackingSummaries.clear();
    for (var i = 0; i < assets.length; i++) {
      final asset = assets[i];
      final summary = calculateAssetTrackingSummary(
        snapshots: results[i + 1] as List<AssetDailySnapshot>,
        transactions: transactionsFor(asset),
        cdiRates: rates,
      );
      if (summary != null) assetTrackingSummaries[asset.syncKey] = summary;
    }
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

  Future<String?> saveBrapiKey(String key) async {
    final clean = key.trim();
    if (clean.isEmpty) {
      await _settings.saveBrapiKey('');
      _quotes.configureBrapi(null);
      _brapiKey = null;
      brapiConfigured = false;
      brapiValidated = false;
      brapiConnectionMessage = null;
      notifyListeners();
      return null;
    }
    try {
      await _settings.saveBrapiKey(clean);
      _brapiKey = clean;
      _quotes.configureBrapi(clean);
      brapiConfigured = true;
    } catch (_) {
      return 'Não foi possível guardar a chave no Android.';
    }
    await testBrapi();
    await refresh();
    return null;
  }

  Future<String> testBrapi() async {
    final key = _brapiKey;
    if (key == null || key.isEmpty) return 'Nenhuma chave foi configurada.';
    try {
      final brasileiros = assets
          .where((asset) => asset.market == AssetMarket.b3)
          .toList(growable: false);
      final valid = await _quotes.validateBrapiToken(
        key,
        symbol: brasileiros.isEmpty ? null : brasileiros.first.symbol,
      );
      brapiValidated = valid;
      if (!valid) {
        brapiConnectionMessage = 'A brapi não confirmou essa chave.';
      } else {
        // A validação usa uma consulta individual. O lote é outro recurso e
        // pode ser recusado sozinho, então vale dizer qual dos dois responde.
        final motivo = await _quotes.motivoLoteIndisponivel(
          assets
              .where((asset) => asset.market == AssetMarket.b3)
              .map((asset) => asset.symbol)
              .toList(growable: false),
        );
        brapiConnectionMessage = motivo == null
            ? 'Conexão validada com a brapi.'
            : 'Conexão validada. A consulta de vários papéis de uma vez não '
                'foi aceita ($motivo), então cada ativo é pedido '
                'separadamente.';
      }
    } catch (error) {
      brapiValidated = false;
      brapiConnectionMessage = 'A brapi não aceitou a chave: $error. '
          'Os ativos brasileiros seguem pela consulta pública.';
    }
    notifyListeners();
    return brapiConnectionMessage!;
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
      if (report.downloaded > 0) _trackingPreparedOn = null;
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

  /// Cotações simultâneas por vez durante a atualização.
  ///
  /// Alto o bastante para diluir a latência de rede, baixo o bastante para não
  /// estourar conexões nem esbarrar no limite dos provedores.
  static const _janelaDeCotacoes = 6;

  Future<void> refresh({bool syncAfter = true}) async {
    if (refreshing || assets.isEmpty) return;
    refreshing = true;
    message = null;
    notifyListeners();
    final errors = <String>[];

    // O dólar não depende de nenhuma cotação: buscá-lo antes do laço deixava a
    // carteira inteira esperando por ele.
    final dolarPendente = hasForeignAssets
        ? () async {
            try {
              dollarQuote = await _quotes.fetchDollar();
            } catch (_) {
              if (dollarQuote == null) errors.add('dólar');
            }
          }()
        : null;

    final indices = <int>[
      for (var i = 0; i < assets.length; i++)
        if (assets[i].market != AssetMarket.manual && !assets[i].isFixedIncome)
          i,
    ];

    // A brapi resolve a carteira brasileira inteira em uma requisição, com a
    // série diária de cada papel. O que ela não atender continua pelo caminho
    // individual logo abaixo.
    final quotes = await _cotacoesEmLote(indices);
    final restantes = indices
        .where((indice) => !quotes.containsKey(indice))
        .toList(growable: false);

    // O restante é independente entre si. Um de cada vez fazia a atualização
    // custar a soma de todas as latências de rede; em uma carteira de quinze
    // ativos isso são quinze idas completas enfileiradas. A janela limitada
    // aproveita a espera sem abrir dezenas de conexões no celular.
    final falhas = <int>{};
    for (var inicio = 0; inicio < restantes.length; inicio += _janelaDeCotacoes) {
      final lote = restantes.skip(inicio).take(_janelaDeCotacoes);
      await Future.wait(lote.map((indice) async {
        try {
          quotes[indice] = await _quotes.fetch(assets[indice]);
        } catch (_) {
          falhas.add(indice);
        }
      }));
    }

    await dolarPendente;
    if (dollarQuote != null && hasForeignAssets) {
      try {
        await _database.saveDollarQuote(dollarQuote!);
      } catch (_) {
        // O valor em memória já vale para a tela; a gravação tenta de novo na
        // próxima atualização.
      }
    }

    // As gravações ficam fora do trecho concorrente: o banco é sequencial de
    // qualquer forma e a ordem dos ativos é preservada nas mensagens de erro.
    for (final indice in indices) {
      if (falhas.contains(indice)) {
        errors.add(assets[indice].symbol);
        continue;
      }
      final quote = quotes[indice];
      if (quote == null) continue;
      final asset = assets[indice];
      final pregaoConhecido = quoteDates[asset.syncKey];
      if (quote.priceDate != null) {
        quoteDates[asset.syncKey] = quote.priceDate!;
      }
      if (asset.id != null) await _database.saveQuote(asset.id!, quote);
      await _database.upsertHistory(
        asset,
        quote.history,
        source: quote.historySource,
      );
      assets[indice] = asset.copyWith(
        currentPrice: quote.current,
        previousClose: fechamentoAnterior(asset, quote, pregaoConhecido),
      );
    }

    await refreshFixedIncome();
    if (cdiError != null) errors.add('CDI');

    if (totalValue > 0) {
      final snapshotDates = <DateTime>{};
      for (final asset in assets) {
        final snapshotDate = _snapshotDateFor(asset);
        if (snapshotDate == null) continue;
        final exchangeRate = asset.currency == AssetCurrency.usd
            ? _exchangeRateForDate(snapshotDate, asset.averageExchangeRate)
            : 1.0;
        final currentPrice = asset.currentPrice ?? asset.averagePrice;
        await _database.saveAssetDailySnapshotAt(
          assetKey: asset.syncKey,
          date: snapshotDate,
          quantity: asset.quantity,
          averagePrice: asset.averagePrice,
          exchangeRate: exchangeRate,
          currentPrice: currentPrice,
          valueBrl: currentPrice * asset.quantity * exchangeRate,
          costBrl: costValue(asset),
        );
        snapshotDates.add(DateTime(
          snapshotDate.year,
          snapshotDate.month,
          snapshotDate.day,
        ));

        // A versão 1.5 podia criar o registro do novo dia antes da abertura.
        // Se essa linha já existe, ela é neutralizada com a última cotação real
        // e depois será naturalmente sobrescrita quando o pregão de hoje abrir.
        final today = DateTime.now();
        if ((asset.market == AssetMarket.b3 ||
                asset.market == AssetMarket.usa) &&
            !_sameDay(snapshotDate, today) &&
            await _database.hasAssetDailySnapshotAt(asset.syncKey, today)) {
          await _database.saveAssetDailySnapshotAt(
            assetKey: asset.syncKey,
            date: today,
            quantity: asset.quantity,
            averagePrice: asset.averagePrice,
            exchangeRate: exchangeRate,
            currentPrice: currentPrice,
            valueBrl: currentPrice * asset.quantity * exchangeRate,
            costBrl: costValue(asset),
          );
          snapshotDates.add(DateTime(today.year, today.month, today.day));
        }
      }
      for (final date in snapshotDates) {
        await _database.buildPortfolioSnapshotAt(date);
      }
      await _reloadSnapshots();
      await _reloadLocalTrackingSummaries();
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

  /// O fechamento da véspera é um fato do pregão: uma vez apurado, não se perde.
  ///
  /// Quando a fonte não sabe informá-lo — a consulta pública às vezes publica o
  /// pregão anterior sem o fechamento dele —, ela devolve o próprio preço e a
  /// variação do dia vira zero. Como as fontes se alternam entre uma
  /// atualização e outra, conforme a chave, o limite de requisições ou a
  /// disponibilidade de cada uma, o resultado do dia mudava a cada toque no
  /// botão sem que preço nenhum tivesse mudado.
  ///
  /// O valor guardado só vale dentro do mesmo pregão: em um dia novo a véspera
  /// é outra, e insistir no valor antigo mediria a variação contra o dia
  /// errado — o erro que este aplicativo já cometeu por outro caminho.
  @visibleForTesting
  double? fechamentoAnterior(
    InvestmentAsset asset,
    MarketQuote quote,
    DateTime? pregaoConhecido,
  ) {
    if (quote.previousClose != quote.current) return quote.previousClose;
    final guardado = asset.previousClose;
    if (guardado == null) return quote.previousClose;
    final mesmoPregao = quote.priceDate != null &&
        _sameDay(pregaoConhecido, quote.priceDate!);
    return mesmoPregao ? guardado : quote.previousClose;
  }

  /// Cotações da B3 obtidas de uma vez só, indexadas pela posição do ativo.
  ///
  /// Sem chave da brapi a consulta em lote não se sustenta — apenas quatro
  /// papéis de demonstração respondem — então nada é tentado e cada ativo segue
  /// pelo caminho individual. Um papel que o lote não trouxer também cai lá,
  /// sem virar erro para o usuário.
  Future<Map<int, MarketQuote>> _cotacoesEmLote(List<int> indices) async {
    if (!brapiConfigured) return {};
    final brasileiros = indices
        .where((indice) => assets[indice].market == AssetMarket.b3)
        .toList(growable: false);
    if (brasileiros.length < 2) return {};
    try {
      final porSimbolo = await _quotes.fetchBrazilianBatch(
        [for (final indice in brasileiros) assets[indice].symbol],
      );
      if (porSimbolo.isEmpty) return {};
      return {
        for (final indice in brasileiros)
          if (porSimbolo[QuoteService.normalizeB3Symbol(
                  assets[indice].symbol)] !=
              null)
            indice: porSimbolo[
                QuoteService.normalizeB3Symbol(assets[indice].symbol)]!,
      };
    } catch (_) {
      // A consulta individual ainda vai acontecer para todos eles.
      return {};
    }
  }

  DateTime? _snapshotDateFor(InvestmentAsset asset) {
    if (asset.market == AssetMarket.b3 || asset.market == AssetMarket.usa) {
      return quoteDates[asset.syncKey];
    }
    if (asset.isFixedIncome) {
      return cdiRates.isEmpty ? null : cdiRates.last.date;
    }
    return DateTime.now();
  }

  double _exchangeRateForDate(DateTime date, double fallback) {
    final quote = dollarQuote;
    if (quote == null) return fallback;
    if (_sameDay(quote.priceDate, date)) return quote.current;
    final point = pointOnOrBefore(quote.history, date);
    return point?.value ?? fallback;
  }

  bool _sameDay(DateTime? a, DateTime b) {
    if (a == null) return false;
    final left = a.toLocal();
    final right = b.toLocal();
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }

  Future<void> ensureHistory(
    InvestmentAsset asset,
    HistoryPeriod period, {
    bool force = false,
    bool syncAfter = true,
    bool notify = true,
  }) async {
    final key = asset.syncKey;
    final taskKey = '$key:${period.name}';
    if (historyLoading.contains(taskKey)) return;
    historyLoading.add(taskKey);
    historyErrors.remove(key);
    if (notify) notifyListeners();
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
      if (notify) notifyListeners();
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
      if (notify) notifyListeners();
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

  /// Monta o balanço de [period]. Com `forceRebuild`, refaz também o
  /// rastreamento (históricos, câmbio, CDI e registros diários).
  Future<void> loadIntelligence(
    ReportPeriod period, {
    bool forceRebuild = false,
  }) async {
    if (intelligenceLoading) return;
    intelligenceLoading = true;
    intelligenceError = null;
    trackingReport = null;
    notifyListeners();
    final now = DateTime.now();
    if (period.start.isAfter(now)) {
      final start = period.start;
      intelligenceError = 'O relatório de ${period.label} começará a receber '
          'dados em ${start.day.toString().padLeft(2, '0')}/'
          '${start.month.toString().padLeft(2, '0')}/${start.year}.';
      intelligenceLoading = false;
      notifyListeners();
      return;
    }
    try {
      final today = DateTime(now.year, now.month, now.day);
      if (forceRebuild || _trackingPreparedOn != today) {
        await _prepareTracking(period.start, now);
        _trackingPreparedOn = today;
      }

      final results = await Future.wait([
        _database.loadPortfolioSnapshots(to: period.end),
        _database.loadTransactions(),
        _database.loadCdiRates(from: period.start, to: period.end),
      ]);
      trackingReport = calculateTrackingReport(
        period: period,
        snapshots: results[0] as List<PortfolioSnapshot>,
        transactions: results[1] as List<InvestmentTransaction>,
        cdiRates: results[2] as List<CdiRate>,
        entries: trackingEntryPoints,
      );
      if (trackingReport == null) {
        intelligenceError = 'Ainda não existem registros para ${period.label}.';
      }
    } catch (error) {
      intelligenceError = 'Não foi possível montar o relatório: $error';
    } finally {
      intelligenceLoading = false;
      notifyListeners();
    }
  }

  Future<void> _prepareTracking(DateTime fallbackStart, DateTime now) async {
    final trackingStarts =
        assets.map(trackingStartFor).whereType<DateTime>().toList();
    final earliest = trackingStarts.isEmpty
        ? fallbackStart
        : trackingStarts.reduce((a, b) => a.isBefore(b) ? a : b);

    // O CDI vem antes: a renda fixa é calculada a partir dele.
    await _fetchCdiFrom(earliest);
    final market = assets.where((asset) => !asset.isFixedIncome).toList();
    // Os downloads de mercado são independentes: em janelas paralelas a espera
    // deixa de ser a soma de todos os ativos.
    final dollar = _ensureDollarTrackingHistory(earliest);
    for (var i = 0; i < market.length; i += _janelaDeCotacoes) {
      await Future.wait(market.skip(i).take(_janelaDeCotacoes).map(
            (asset) => ensureHistory(
              asset,
              HistoryPeriod.maximum,
              syncAfter: false,
              notify: false,
            ),
          ));
    }
    await dollar;
    // A renda fixa segue em série: todos os títulos dividem o mesmo recálculo
    // e, com o CDI já em cache, só o primeiro chega a consultar a rede.
    for (final asset in assets.where((asset) => asset.isFixedIncome).toList()) {
      await ensureHistory(
        asset,
        HistoryPeriod.maximum,
        syncAfter: false,
        notify: false,
      );
    }
    await _backfillTrackingSnapshots(earliest, now);
    await _reloadLocalTrackingSummaries();
    if (tursoConfigured) await synchronize(silent: true);
  }

  Future<void> _ensureDollarTrackingHistory(DateTime from) async {
    if (!hasForeignAssets) return;
    try {
      final fetched = await _quotes.fetchDollarHistory(from);
      const dollarSeries = InvestmentAsset(
        stableKey: 'fx:USDBRL',
        symbol: 'USDBRL',
        name: 'Dólar comercial',
        market: AssetMarket.manual,
        currency: AssetCurrency.brl,
        quantity: 0,
        averagePrice: 1,
      );
      await _database.upsertHistory(
        dollarSeries,
        fetched,
        source: 'yahoo',
      );
      if (fetched.isNotEmpty) _historyDirtyForSync = true;
    } catch (_) {
      // Sem câmbio histórico não se inventa conversão para os dias ausentes.
    }
  }

  Future<void> _backfillTrackingSnapshots(
    DateTime from,
    DateTime to,
  ) async {
    final dollarHistory = await _database.loadAssetHistory(
      'fx:USDBRL',
      from: from,
    );
    final updatedAt = DateTime.now().toUtc();
    for (final asset in assets) {
      final start = trackingStartFor(asset);
      if (start == null) continue;
      final startDay = _dayOf(start);
      final prices = await _database.loadAssetHistory(
        asset.syncKey,
        from: startDay,
      );
      final transactions = [...transactionsFor(asset)]
        ..sort((a, b) => a.transactionDate.compareTo(b.transactionDate));
      // A posição só muda em dia de operação: ela é recalculada quando a
      // quantidade de operações já ocorridas cresce, não a cada pregão.
      var applied = -1;
      var position = calculateTrackedPosition(const []);
      final snapshots = <AssetDailySnapshot>[];
      for (final point in prices) {
        final day = _dayOf(point.date);
        if (day.isBefore(startDay) || day.isAfter(to)) continue;
        var count = 0;
        while (count < transactions.length &&
            !_dayOf(transactions[count].transactionDate).isAfter(day)) {
          count++;
        }
        if (count != applied) {
          position = calculateTrackedPosition(transactions.take(count));
          applied = count;
        }
        final fx = asset.currency == AssetCurrency.brl
            ? 1.0
            : pointOnOrBefore(dollarHistory, day)?.value;
        if (fx == null) continue;
        snapshots.add(AssetDailySnapshot(
          assetKey: asset.syncKey,
          date: day,
          quantity: position.quantity,
          averagePrice: position.averagePrice,
          exchangeRate: fx,
          currentPrice: point.value,
          valueBrl: point.value * position.quantity * fx,
          costBrl: position.averagePrice *
              position.quantity *
              position.averageExchangeRate,
          updatedAt: updatedAt,
        ));
      }
      await _database.saveAssetDailySnapshots(snapshots);
    }
    await _rebuildPortfolioTracking(from, to);
  }

  Future<void> _rebuildPortfolioTracking(DateTime from, DateTime to) async {
    final loaded = await Future.wait(assets.map(
      (asset) => _database.loadAssetDailySnapshots(
        asset.syncKey,
        from: from,
        to: to,
      ),
    ));
    final dates = <DateTime>{
      for (final snapshots in loaded) ...snapshots.map((item) => item.date),
    };
    final orderedDates = dates.toList()..sort();
    // Cada série já vem ordenada: um cursor por ativo avança junto com as
    // datas, sem varrer a série inteira para cada dia.
    final cursors = List.filled(loaded.length, -1);
    final rows = <({DateTime date, double total, double cost})>[];
    for (final date in orderedDates) {
      var value = 0.0;
      var cost = 0.0;
      var positions = 0;
      for (var i = 0; i < loaded.length; i++) {
        final snapshots = loaded[i];
        while (cursors[i] + 1 < snapshots.length &&
            !snapshots[cursors[i] + 1].date.isAfter(date)) {
          cursors[i]++;
        }
        if (cursors[i] >= 0) {
          final latest = snapshots[cursors[i]];
          value += latest.valueBrl;
          cost += latest.costBrl;
          positions++;
        }
      }
      if (positions > 0) rows.add((date: date, total: value, cost: cost));
    }
    await _database.savePortfolioSnapshots(rows);
    await _reloadSnapshots();
  }

  static DateTime _dayOf(DateTime value) =>
      DateTime(value.year, value.month, value.day);

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
      final existingIndex = assets.indexWhere((item) => item.id == asset.id);
      final existing = existingIndex < 0 ? null : assets[existingIndex];
      final existingTransactions =
          existing == null ? const <InvestmentTransaction>[] : transactionsFor(existing);
      if (existing != null &&
          existing.syncKey != normalized.syncKey &&
          existingTransactions.isNotEmpty) {
        return 'O código e o mercado não podem mudar depois do início do rastreamento.';
      }
      final positionChanged = existing != null &&
          (existing.quantity != normalized.quantity ||
              existing.averagePrice != normalized.averagePrice ||
              existing.averageExchangeRate != normalized.averageExchangeRate);
      if (positionChanged &&
          existingTransactions.any((item) =>
              item.type != InvestmentTransactionType.openingPosition)) {
        return 'Use “Registrar operação” para alterar quantidade ou preço médio.';
      }
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
      _trackingPreparedOn = null;
      await _database.ensureOpeningTransactions([saved]);
      if (positionChanged) await _database.updateOpeningTransaction(saved);
      await _reloadTransactions();
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
    _trackingPreparedOn = null;
    assets.removeWhere((item) => item.id == asset.id);
    assetHistories.remove(asset.syncKey);
    notifyListeners();
    if (tursoConfigured) await synchronize(silent: true);
  }

  Future<String?> recordTransaction({
    required InvestmentAsset asset,
    required InvestmentTransactionType type,
    required DateTime date,
    double quantity = 0,
    double unitPrice = 0,
    double exchangeRate = 1,
    double fees = 0,
    double cashValue = 0,
    String? notes,
  }) async {
    if (date.isAfter(DateTime.now().add(const Duration(days: 1)))) {
      return 'A data da operação não pode estar no futuro.';
    }
    if (type.changesPosition && (quantity <= 0 || unitPrice <= 0)) {
      return 'Informe uma quantidade e um preço válidos.';
    }
    if (type.isIncome && cashValue <= 0) {
      return 'Informe o valor recebido.';
    }
    if (asset.currency == AssetCurrency.usd && exchangeRate <= 0) {
      return 'Informe a cotação do dólar usada na operação.';
    }
    if (type == InvestmentTransactionType.sale && quantity > asset.quantity) {
      return 'A venda não pode superar a quantidade atual.';
    }
    try {
      final now = DateTime.now().toUtc();
      final transaction = InvestmentTransaction(
        id: 'txn:${asset.syncKey}:${now.microsecondsSinceEpoch}',
        assetKey: asset.syncKey,
        type: type,
        quantity: quantity,
        unitPrice: unitPrice,
        exchangeRate:
            asset.currency == AssetCurrency.usd ? exchangeRate : 1,
        fees: fees,
        cashValue: cashValue,
        transactionDate: DateTime(date.year, date.month, date.day),
        notes: notes?.trim().isEmpty == true ? null : notes?.trim(),
        createdAt: now,
        updatedAt: now,
      );
      await _database.saveTransaction(transaction);
      _trackingPreparedOn = null;
      final projected = calculateTrackedPosition([
        ...transactionsFor(asset),
        transaction,
      ]);
      if (type.changesPosition) {
        final updated = asset.copyWith(
          quantity: projected.quantity,
          averagePrice: projected.averagePrice,
          averageExchangeRate: projected.averageExchangeRate,
        );
        final saved = await _database.saveAsset(updated);
        final index = assets.indexWhere((item) => item.id == asset.id);
        if (index >= 0) assets[index] = saved;
      }
      await _reloadTransactions();
      notifyListeners();
      if (type.changesPosition) {
        await refresh();
      } else if (tursoConfigured) {
        await synchronize(silent: true);
      }
      return null;
    } catch (_) {
      return 'Não foi possível registrar a operação.';
    }
  }

  Future<String?> deleteTransaction(
    InvestmentAsset asset,
    InvestmentTransaction transaction,
  ) async {
    if (transaction.type == InvestmentTransactionType.openingPosition) {
      return 'A posição inicial protege a linha de largada do rastreamento.';
    }
    try {
      await _database.deleteTransaction(transaction.id);
      _trackingPreparedOn = null;
      final remaining = transactionsFor(asset)
          .where((item) => item.id != transaction.id)
          .toList();
      final position = calculateTrackedPosition(remaining);
      final saved = await _database.saveAsset(asset.copyWith(
        quantity: position.quantity,
        averagePrice: position.averagePrice,
        averageExchangeRate: position.averageExchangeRate,
      ));
      final index = assets.indexWhere((item) => item.id == asset.id);
      if (index >= 0) assets[index] = saved;
      await _reloadTransactions();
      notifyListeners();
      await refresh();
      return null;
    } catch (_) {
      return 'Não foi possível excluir a operação.';
    }
  }
}
