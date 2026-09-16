import 'investment_asset.dart';

enum HistoryPeriod {
  oneMonth('1M'),
  threeMonths('3M'),
  sixMonths('6M'),
  oneYear('1A'),
  fiveYears('5A'),
  maximum('Máx');

  const HistoryPeriod(this.label);
  final String label;

  DateTime? startFrom(DateTime now) => switch (this) {
        HistoryPeriod.oneMonth => DateTime(now.year, now.month - 1, now.day),
        HistoryPeriod.threeMonths => DateTime(now.year, now.month - 3, now.day),
        HistoryPeriod.sixMonths => DateTime(now.year, now.month - 6, now.day),
        HistoryPeriod.oneYear => DateTime(now.year - 1, now.month, now.day),
        HistoryPeriod.fiveYears => DateTime(now.year - 5, now.month, now.day),
        HistoryPeriod.maximum => null,
      };

  String get providerRange => switch (this) {
        HistoryPeriod.oneMonth => '1mo',
        HistoryPeriod.threeMonths => '3mo',
        HistoryPeriod.sixMonths => '6mo',
        HistoryPeriod.oneYear => '1y',
        HistoryPeriod.fiveYears => '5y',
        HistoryPeriod.maximum => 'max',
      };
}

enum ChartMode { performance, price }

class AssetPriceRecord {
  const AssetPriceRecord({
    required this.assetKey,
    required this.date,
    required this.close,
    required this.currency,
    required this.source,
    required this.updatedAt,
  });

  final String assetKey;
  final DateTime date;
  final double close;
  final AssetCurrency currency;
  final String source;
  final DateTime updatedAt;

  PricePoint toPoint() => PricePoint(date, close);
}

class PortfolioSnapshot {
  const PortfolioSnapshot({
    required this.date,
    required this.totalBrl,
    required this.costBrl,
    required this.updatedAt,
  });

  final DateTime date;
  final double totalBrl;
  final double costBrl;
  final DateTime updatedAt;

  PricePoint toPoint() => PricePoint(date, totalBrl);
}

List<PricePoint> normalizePerformance(List<PricePoint> points) {
  if (points.isEmpty || points.first.value == 0) return const [];
  final initial = points.first.value;
  return points
      .map((point) => PricePoint(point.date, (point.value / initial - 1) * 100))
      .toList(growable: false);
}

List<PricePoint> relativeToAverage(
  List<PricePoint> points,
  double averagePrice,
) {
  if (averagePrice <= 0) return const [];
  return points
      .map((point) =>
          PricePoint(point.date, (point.value / averagePrice - 1) * 100))
      .toList(growable: false);
}
