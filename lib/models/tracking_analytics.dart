import 'history_models.dart';
import 'investment_asset.dart';
import 'investment_transaction.dart';

class AssetTrackingSummary {
  const AssetTrackingSummary({
    required this.start,
    required this.end,
    required this.snapshotCount,
    required this.returnPercent,
    required this.cdiPercent,
    required this.currentUnderwaterDays,
    required this.longestUnderwaterDays,
    required this.incomeBrl,
    required this.realizedResultBrl,
  });

  final DateTime start;
  final DateTime end;
  final int snapshotCount;
  final double returnPercent;
  final double cdiPercent;
  final int currentUnderwaterDays;
  final int longestUnderwaterDays;
  final double incomeBrl;
  final double realizedResultBrl;

  double get differencePoints => returnPercent - cdiPercent;

  bool get beatsCdi => returnPercent >= cdiPercent;

  bool get isUnderwater => currentUnderwaterDays > 0;
}

/// Janela escolhida no relatório: um ano inteiro ou um mês específico.
class ReportPeriod {
  const ReportPeriod(this.year, [this.month]);

  final int year;

  /// `null` representa o ano inteiro.
  final int? month;

  bool get isMonthly => month != null;

  DateTime get start => DateTime(year, month ?? 1);

  /// Último instante do período; `DateTime(ano, mês + 1, 0)` é o último dia.
  DateTime get end => month == null
      ? DateTime(year, 12, 31, 23, 59, 59)
      : DateTime(year, month! + 1, 0, 23, 59, 59);

  String get label =>
      month == null ? '$year' : '${monthNames[month! - 1]} de $year';

  static const monthNames = [
    'janeiro',
    'fevereiro',
    'março',
    'abril',
    'maio',
    'junho',
    'julho',
    'agosto',
    'setembro',
    'outubro',
    'novembro',
    'dezembro',
  ];

  @override
  bool operator ==(Object other) =>
      other is ReportPeriod && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);
}

class TrackingReport {
  const TrackingReport({
    required this.period,
    required this.start,
    required this.end,
    required this.initialValueBrl,
    required this.finalValueBrl,
    required this.purchasesBrl,
    required this.salesBrl,
    required this.incomeBrl,
    required this.profitBrl,
    required this.returnPercent,
    required this.cdiPercent,
    required this.snapshotCount,
    this.trackedEntriesBrl = 0,
  });

  final ReportPeriod period;
  final DateTime start;
  final DateTime end;
  final double initialValueBrl;
  final double finalValueBrl;
  final double purchasesBrl;
  final double salesBrl;
  final double incomeBrl;
  final double profitBrl;
  final double returnPercent;
  final double cdiPercent;
  final int snapshotCount;

  /// Valor dos ativos que passaram a ser rastreados durante o período. Eles
  /// entram no patrimônio sem serem rendimento, como um aporte.
  final double trackedEntriesBrl;

  int get year => period.year;

  double get differencePoints => returnPercent - cdiPercent;

  bool get beatsCdi => returnPercent >= cdiPercent;
}

AssetTrackingSummary? calculateAssetTrackingSummary({
  required List<AssetDailySnapshot> snapshots,
  required List<InvestmentTransaction> transactions,
  required List<CdiRate> cdiRates,
}) {
  if (snapshots.isEmpty) return null;
  final ordered = [...snapshots]..sort((a, b) => a.date.compareTo(b.date));
  final start = ordered.first.date;
  final end = ordered.last.date;
  final index = assetReturnIndex(ordered, transactions);
  final returnPercent = index.length < 2
      ? 0.0
      : (index.last.value / index.first.value - 1) * 100;

  DateTime? currentStart;
  var currentDays = 0;
  var longestDays = 0;
  for (final snapshot in ordered) {
    if (snapshot.valueBrl < snapshot.costBrl) {
      currentStart ??= snapshot.date;
      currentDays = snapshot.date.difference(currentStart).inDays + 1;
      if (currentDays > longestDays) longestDays = currentDays;
    } else {
      currentStart = null;
      currentDays = 0;
    }
  }
  final position = calculateTrackedPosition(transactions);
  return AssetTrackingSummary(
    start: start,
    end: end,
    snapshotCount: ordered.length,
    returnPercent: returnPercent,
    cdiPercent: cdiReturnBetween(cdiRates, start, end),
    currentUnderwaterDays: currentDays,
    longestUnderwaterDays: longestDays,
    incomeBrl: position.incomeBrl,
    realizedResultBrl: position.realizedResultBrl,
  );
}

TrackingReport? calculateAnnualTrackingReport({
  required int year,
  required List<PortfolioSnapshot> snapshots,
  required List<InvestmentTransaction> transactions,
  required List<CdiRate> cdiRates,
  List<PricePoint> entries = const [],
}) =>
    calculateTrackingReport(
      period: ReportPeriod(year),
      snapshots: snapshots,
      transactions: transactions,
      cdiRates: cdiRates,
      entries: entries,
    );

/// Primeiro registro de cada ativo com posição: o dia em que ele passou a
/// fazer parte do patrimônio rastreado.
///
/// Um ativo cadastrado depois do início do rastreamento faz o patrimônio
/// saltar. Sem esse marco, o salto era lido como rendimento e inflava o
/// resultado (e o gráfico) com dinheiro que já existia.
List<PricePoint> trackingEntries(
  Iterable<({List<AssetDailySnapshot> snapshots,
          List<InvestmentTransaction> transactions})>
      assets,
) {
  final entries = <PricePoint>[];
  for (final asset in assets) {
    // Só a posição inicial é "entrada": compras já contam como aporte.
    final opening = asset.transactions
        .where((item) =>
            item.deletedAt == null &&
            item.type == InvestmentTransactionType.openingPosition)
        .fold<double>(0, (sum, item) => sum + item.quantity);
    if (opening <= 0) continue;
    final ordered = [...asset.snapshots]
      ..sort((a, b) => a.date.compareTo(b.date));
    for (final snapshot in ordered) {
      if (snapshot.quantity <= 0) continue;
      // Compras no mesmo dia já são contadas como aporte; a entrada fica só
      // com a fatia da posição inicial.
      final share = (opening / snapshot.quantity).clamp(0.0, 1.0);
      entries.add(PricePoint(_day(snapshot.date), snapshot.valueBrl * share));
      break;
    }
  }
  return entries;
}

/// Balanço de [period]: o último registro anterior ao período serve de ponto de
/// partida, para que o primeiro pregão do mês (ou do ano) já conte resultado.
TrackingReport? calculateTrackingReport({
  required ReportPeriod period,
  required List<PortfolioSnapshot> snapshots,
  required List<InvestmentTransaction> transactions,
  required List<CdiRate> cdiRates,
  List<PricePoint> entries = const [],
}) {
  final periodStart = period.start;
  final periodEnd = period.end;
  final all = snapshots.where((item) => !item.date.isAfter(periodEnd)).toList()
    ..sort((a, b) => a.date.compareTo(b.date));
  final withinYear = all
      .where((item) =>
          !item.date.isBefore(periodStart) && !item.date.isAfter(periodEnd))
      .toList();
  if (withinYear.isEmpty) return null;
  PortfolioSnapshot? previous;
  for (final snapshot in all) {
    if (snapshot.date.isBefore(periodStart)) previous = snapshot;
  }
  final ordered = [
    if (previous != null) previous,
    ...withinYear,
  ];
  final flowStart = previous?.date ?? withinYear.first.date;
  final periodTransactions = transactions
      .where((item) =>
          item.deletedAt == null &&
          item.type != InvestmentTransactionType.openingPosition &&
          _day(item.transactionDate).isAfter(_day(flowStart)) &&
          !_day(item.transactionDate).isBefore(periodStart) &&
          !_day(item.transactionDate).isAfter(_day(periodEnd)))
      .toList();
  var purchases = 0.0;
  var sales = 0.0;
  var income = 0.0;
  for (final item in periodTransactions) {
    if (item.type == InvestmentTransactionType.purchase) {
      purchases += (item.grossValue + item.fees) * item.exchangeRate;
    } else if (item.type == InvestmentTransactionType.sale) {
      sales += (item.grossValue - item.fees) * item.exchangeRate;
    } else if (item.type.isIncome) {
      income += item.cashValueBrl;
    }
  }
  final periodEntries = entries
      .where((item) =>
          _day(item.date).isAfter(_day(flowStart)) &&
          !_day(item.date).isAfter(_day(periodEnd)))
      .toList();
  final entered =
      periodEntries.fold<double>(0, (sum, item) => sum + item.value);
  final index = portfolioReturnIndexWithTransactions(
    ordered,
    periodTransactions,
    entries: periodEntries,
  );
  final returnPercent = index.length < 2
      ? 0.0
      : (index.last.value / index.first.value - 1) * 100;
  final initial = ordered.first.totalBrl;
  final finalValue = ordered.last.totalBrl;
  return TrackingReport(
    period: period,
    start: withinYear.first.date,
    end: withinYear.last.date,
    initialValueBrl: initial,
    finalValueBrl: finalValue,
    purchasesBrl: purchases,
    salesBrl: sales,
    incomeBrl: income,
    profitBrl: finalValue + sales + income - initial - purchases - entered,
    returnPercent: returnPercent,
    cdiPercent: cdiReturnBetween(cdiRates, flowStart, withinYear.last.date),
    snapshotCount: withinYear.length,
    trackedEntriesBrl: entered,
  );
}

/// Um dia do gráfico de desempenho da carteira.
class PortfolioPerformancePoint {
  const PortfolioPerformancePoint({
    required this.date,
    required this.valueBrl,
    required this.resultBrl,
    required this.returnPercent,
  });

  final DateTime date;

  /// Patrimônio do dia, como gravado.
  final double valueBrl;

  /// Ganho ou perda acumulado desde o primeiro ponto, sem contar aportes,
  /// retiradas nem ativos que passaram a ser rastreados no meio do caminho.
  final double resultBrl;

  /// Rentabilidade acumulada desde o primeiro ponto (retorno ponderado pelo
  /// tempo, a mesma régua do relatório).
  final double returnPercent;
}

/// Série do gráfico da carteira a partir de [since] (ou de tudo, se nulo).
///
/// O último registro anterior a [since] vira a linha de base, como o
/// "fechamento anterior" dos gráficos de cotação.
List<PortfolioPerformancePoint> calculatePortfolioPerformance({
  required List<PortfolioSnapshot> snapshots,
  required List<InvestmentTransaction> transactions,
  List<PricePoint> entries = const [],
  DateTime? since,
}) {
  final ordered = [...snapshots]..sort((a, b) => a.date.compareTo(b.date));
  if (ordered.isEmpty) return const [];
  var startIndex = 0;
  if (since != null) {
    final firstInside =
        ordered.indexWhere((item) => !item.date.isBefore(_day(since)));
    if (firstInside < 0) {
      startIndex = ordered.length - 1;
    } else {
      startIndex = firstInside > 0 ? firstInside - 1 : 0;
    }
  }
  final window = ordered.sublist(startIndex);
  final base = window.first;
  final index = portfolioReturnIndexWithTransactions(
    window,
    transactions,
    entries: entries,
  );
  final points = <PortfolioPerformancePoint>[
    PortfolioPerformancePoint(
      date: base.date,
      valueBrl: base.totalBrl,
      resultBrl: 0,
      returnPercent: 0,
    ),
  ];
  var netInflow = 0.0;
  for (var i = 1; i < window.length; i++) {
    final flows = _flowsBetween(
      transactions,
      window[i - 1].date,
      window[i].date,
      entries: entries,
    );
    netInflow += flows.inflow - flows.outflow;
    points.add(PortfolioPerformancePoint(
      date: window[i].date,
      valueBrl: window[i].totalBrl,
      resultBrl: window[i].totalBrl - base.totalBrl - netInflow,
      returnPercent: (index[i].value / index.first.value - 1) * 100,
    ));
  }
  return points;
}

List<PricePoint> assetReturnIndex(
  List<AssetDailySnapshot> snapshots,
  List<InvestmentTransaction> transactions, {
  double base = 100,
}) {
  if (snapshots.isEmpty) return const [];
  final ordered = [...snapshots]..sort((a, b) => a.date.compareTo(b.date));
  var index = base;
  final points = <PricePoint>[PricePoint(ordered.first.date, index)];
  for (var i = 1; i < ordered.length; i++) {
    final previous = ordered[i - 1];
    final current = ordered[i];
    final flows = _flowsBetween(
      transactions,
      previous.date,
      current.date,
    );
    final denominator = previous.valueBrl + flows.inflow;
    if (denominator > 0) {
      index *= (current.valueBrl + flows.outflow) / denominator;
    }
    points.add(PricePoint(current.date, index));
  }
  return points;
}

List<PricePoint> portfolioReturnIndexWithTransactions(
  List<PortfolioSnapshot> snapshots,
  List<InvestmentTransaction> transactions, {
  double base = 100,
  List<PricePoint> entries = const [],
}) {
  if (snapshots.isEmpty) return const [];
  final ordered = [...snapshots]..sort((a, b) => a.date.compareTo(b.date));
  var index = base;
  final points = <PricePoint>[PricePoint(ordered.first.date, index)];
  for (var i = 1; i < ordered.length; i++) {
    final previous = ordered[i - 1];
    final current = ordered[i];
    final flows = _flowsBetween(
      transactions,
      previous.date,
      current.date,
      entries: entries,
    );
    final denominator = previous.totalBrl + flows.inflow;
    if (denominator > 0) {
      index *= (current.totalBrl + flows.outflow) / denominator;
    }
    points.add(PricePoint(current.date, index));
  }
  return points;
}

double cdiReturnBetween(List<CdiRate> rates, DateTime start, DateTime end) {
  var factor = 1.0;
  for (final rate in rates) {
    if (rate.date.isAfter(start) && !rate.date.isAfter(end)) {
      factor *= rate.factor;
    }
  }
  return (factor - 1) * 100;
}

({double inflow, double outflow}) _flowsBetween(
  List<InvestmentTransaction> transactions,
  DateTime after,
  DateTime through, {
  List<PricePoint> entries = const [],
}) {
  var inflow = 0.0;
  var outflow = 0.0;
  for (final entry in entries) {
    final day = _day(entry.date);
    if (day.isAfter(_day(after)) && !day.isAfter(_day(through))) {
      inflow += entry.value;
    }
  }
  for (final item in transactions) {
    final transactionDay = _day(item.transactionDate);
    if (item.deletedAt != null ||
        item.type == InvestmentTransactionType.openingPosition ||
        !transactionDay.isAfter(_day(after)) ||
        transactionDay.isAfter(_day(through))) {
      continue;
    }
    if (item.type == InvestmentTransactionType.purchase) {
      inflow += (item.grossValue + item.fees) * item.exchangeRate;
    } else if (item.type == InvestmentTransactionType.sale) {
      outflow += (item.grossValue - item.fees) * item.exchangeRate;
    } else if (item.type.isIncome) {
      outflow += item.cashValueBrl;
    }
  }
  return (inflow: inflow, outflow: outflow);
}

DateTime _day(DateTime value) =>
    DateTime(value.year, value.month, value.day);
