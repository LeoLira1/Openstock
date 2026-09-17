import 'history_models.dart';
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

class AnnualTrackingReport {
  const AnnualTrackingReport({
    required this.year,
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

  final int year;
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

AnnualTrackingReport? calculateAnnualTrackingReport({
  required int year,
  required List<PortfolioSnapshot> snapshots,
  required List<InvestmentTransaction> transactions,
  required List<CdiRate> cdiRates,
}) {
  final startOfYear = DateTime(year);
  final endOfYear = DateTime(year, 12, 31, 23, 59, 59);
  final all = snapshots.where((item) => !item.date.isAfter(endOfYear)).toList()
    ..sort((a, b) => a.date.compareTo(b.date));
  final withinYear = all
      .where((item) =>
          !item.date.isBefore(startOfYear) && !item.date.isAfter(endOfYear))
      .toList();
  if (withinYear.isEmpty) return null;
  PortfolioSnapshot? previous;
  for (final snapshot in all) {
    if (snapshot.date.isBefore(startOfYear)) previous = snapshot;
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
          !_day(item.transactionDate).isBefore(startOfYear) &&
          !_day(item.transactionDate).isAfter(_day(endOfYear)))
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
  final index = portfolioReturnIndexWithTransactions(
    ordered,
    periodTransactions,
  );
  final returnPercent = index.length < 2
      ? 0.0
      : (index.last.value / index.first.value - 1) * 100;
  final initial = ordered.first.totalBrl;
  final finalValue = ordered.last.totalBrl;
  return AnnualTrackingReport(
    year: year,
    start: withinYear.first.date,
    end: withinYear.last.date,
    initialValueBrl: initial,
    finalValueBrl: finalValue,
    purchasesBrl: purchases,
    salesBrl: sales,
    incomeBrl: income,
    profitBrl: finalValue + sales + income - initial - purchases,
    returnPercent: returnPercent,
    cdiPercent: cdiReturnBetween(cdiRates, flowStart, withinYear.last.date),
    snapshotCount: withinYear.length,
  );
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
