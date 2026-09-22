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
}) =>
    calculateTrackingReport(
      period: ReportPeriod(year),
      snapshots: snapshots,
      transactions: transactions,
      cdiRates: cdiRates,
    );

/// Balanço de [period]: o último registro anterior ao período serve de ponto de
/// partida, para que o primeiro pregão do mês (ou do ano) já conte resultado.
TrackingReport? calculateTrackingReport({
  required ReportPeriod period,
  required List<PortfolioSnapshot> snapshots,
  required List<InvestmentTransaction> transactions,
  required List<CdiRate> cdiRates,
  Map<String, List<AssetDailySnapshot>>? assetSnapshots,
  Map<String, List<InvestmentTransaction>> transactionsByAsset = const {},
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
  var returnPercent = 0.0;
  var initial = ordered.first.totalBrl;
  var finalValue = ordered.last.totalBrl;
  double? profit;
  final series = assetSnapshots == null
      ? null
      : _assetSeries(assetSnapshots, transactionsByAsset);
  if (series != null && series.isNotEmpty) {
    // O resultado sai ativo por ativo: um total diário gravado por uma versão
    // antiga ou por outro aparelho não consegue mais distorcer o balanço.
    _SeriesPoint? base;
    _SeriesPoint? last;
    for (final point in series) {
      if (point.date.isAfter(periodEnd)) break;
      if (point.date.isBefore(periodStart)) {
        base = point;
      } else {
        base ??= point;
        last = point;
      }
    }
    if (base != null && last != null) {
      initial = base.value;
      finalValue = last.value;
      profit = last.result - base.result;
      returnPercent = (last.index / base.index - 1) * 100;
    }
  } else {
    final index = portfolioReturnIndexWithTransactions(
      ordered,
      periodTransactions,
    );
    returnPercent = index.length < 2
        ? 0.0
        : (index.last.value / index.first.value - 1) * 100;
  }
  return TrackingReport(
    period: period,
    start: withinYear.first.date,
    end: withinYear.last.date,
    initialValueBrl: initial,
    finalValueBrl: finalValue,
    purchasesBrl: purchases,
    salesBrl: sales,
    incomeBrl: income,
    profitBrl: profit ?? finalValue + sales + income - initial - purchases,
    returnPercent: returnPercent,
    cdiPercent: cdiReturnBetween(cdiRates, flowStart, withinYear.last.date),
    snapshotCount: withinYear.length,
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

  /// Patrimônio do dia: soma dos registros de cada ativo.
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
/// O último dia anterior a [since] vira a linha de base, como o "fechamento
/// anterior" dos gráficos de cotação.
List<PortfolioPerformancePoint> calculatePortfolioPerformance({
  required Map<String, List<AssetDailySnapshot>> assetSnapshots,
  required Map<String, List<InvestmentTransaction>> transactionsByAsset,
  DateTime? since,
}) {
  final series = _assetSeries(assetSnapshots, transactionsByAsset);
  if (series.isEmpty) return const [];
  final first = series.first;
  final all = [
    for (final point in series)
      PortfolioPerformancePoint(
        date: point.date,
        valueBrl: point.value,
        resultBrl: point.result - first.result,
        returnPercent: (point.index / first.index - 1) * 100,
      ),
  ];
  return since == null ? all : rebasePerformance(all, since);
}

/// Recorta [points] a partir de [since], com o dia anterior como base zero.
List<PortfolioPerformancePoint> rebasePerformance(
  List<PortfolioPerformancePoint> points,
  DateTime since,
) {
  if (points.isEmpty) return points;
  final firstInside =
      points.indexWhere((point) => !point.date.isBefore(_day(since)));
  final start = firstInside < 0
      ? points.length - 1
      : firstInside > 0
          ? firstInside - 1
          : 0;
  final base = points[start];
  final baseFactor = 1 + base.returnPercent / 100;
  return [
    for (final point in points.skip(start))
      PortfolioPerformancePoint(
        date: point.date,
        valueBrl: point.valueBrl,
        resultBrl: point.resultBrl - base.resultBrl,
        returnPercent:
            ((1 + point.returnPercent / 100) / baseFactor - 1) * 100,
      ),
  ];
}

class _SeriesPoint {
  const _SeriesPoint(this.date, this.value, this.result, this.index);
  final DateTime date;
  final double value;
  final double result;
  final double index;
}

/// Patrimônio, resultado acumulado e índice de rentabilidade dia a dia,
/// calculados ativo por ativo.
///
/// Cada dia só compara ativos que já existiam no dia anterior; um ativo que
/// aparece pela primeira vez entra neutro, sem virar alta nem queda. Compras,
/// vendas e proventos de cada ativo entram como fluxo daquele ativo.
List<_SeriesPoint> _assetSeries(
  Map<String, List<AssetDailySnapshot>> assetSnapshots,
  Map<String, List<InvestmentTransaction>> transactionsByAsset,
) {
  final keys = assetSnapshots.keys.toList();
  final ordered = [
    for (final key in keys)
      [...assetSnapshots[key]!]..sort((a, b) => a.date.compareTo(b.date)),
  ];
  final dates = <DateTime>{
    for (final snapshots in ordered) ...snapshots.map((item) => _day(item.date)),
  }.toList()
    ..sort();
  if (dates.isEmpty) return const [];
  final cursors = List.filled(keys.length, -1);
  final previous = List<AssetDailySnapshot?>.filled(keys.length, null);
  final points = <_SeriesPoint>[];
  var result = 0.0;
  var index = 100.0;
  for (var d = 0; d < dates.length; d++) {
    final date = dates[d];
    var value = 0.0;
    var gain = 0.0;
    var base = 0.0;
    final current = List<AssetDailySnapshot?>.filled(keys.length, null);
    for (var i = 0; i < keys.length; i++) {
      final snapshots = ordered[i];
      while (cursors[i] + 1 < snapshots.length &&
          !_day(snapshots[cursors[i] + 1].date).isAfter(date)) {
        cursors[i]++;
      }
      if (cursors[i] < 0) continue;
      final snapshot = snapshots[cursors[i]];
      current[i] = snapshot;
      value += snapshot.valueBrl;
      final before = previous[i];
      if (d == 0 || before == null) continue;
      final flows = _flowsBetween(
        transactionsByAsset[keys[i]] ?? const [],
        dates[d - 1],
        date,
      );
      gain += snapshot.valueBrl + flows.outflow - before.valueBrl - flows.inflow;
      base += before.valueBrl + flows.inflow;
    }
    if (d > 0) {
      result += gain;
      if (base > 0) index *= 1 + gain / base;
    }
    points.add(_SeriesPoint(date, value, result, index));
    for (var i = 0; i < keys.length; i++) {
      previous[i] = current[i];
    }
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
  DateTime through,
) {
  var inflow = 0.0;
  var outflow = 0.0;
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
