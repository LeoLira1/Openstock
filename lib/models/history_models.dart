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

class AssetDailySnapshot {
  const AssetDailySnapshot({
    required this.assetKey,
    required this.date,
    required this.quantity,
    required this.averagePrice,
    required this.exchangeRate,
    required this.currentPrice,
    required this.valueBrl,
    required this.costBrl,
    required this.updatedAt,
  });

  final String assetKey;
  final DateTime date;
  final double quantity;
  final double averagePrice;
  final double exchangeRate;
  final double currentPrice;
  final double valueBrl;
  final double costBrl;
  final DateTime updatedAt;
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

/// Identidade da série do CDI dentro das comparações.
const cdiSeriesKey = '__cdi__';

/// Taxa diária do CDI publicada pelo Banco Central, em % por dia útil.
class CdiRate {
  const CdiRate({required this.date, required this.dailyPercent});

  final DateTime date;
  final double dailyPercent;

  double get factor => 1 + dailyPercent / 100;
}

/// Índice acumulado do CDI a partir das taxas diárias reais.
///
/// O valor de cada dia já inclui o rendimento daquele dia, como o fechamento de
/// um ativo. Dias sem publicação (fins de semana e feriados) não são criados.
List<PricePoint> accumulateCdi(List<CdiRate> rates, {double base = 100}) {
  if (rates.isEmpty) return const [];
  final ordered = [...rates]..sort((a, b) => a.date.compareTo(b.date));
  final points = <PricePoint>[];
  var index = base;
  for (final rate in ordered) {
    index *= rate.factor;
    points.add(PricePoint(rate.date, index));
  }
  return points;
}

/// Rentabilidade acumulada da carteira isolando aportes e retiradas.
///
/// Cada intervalo entre dois snapshots é medido contra o patrimônio anterior
/// somado ao fluxo do período — a variação do custo investido —, de modo que um
/// aporte não apareça como valorização. O encadeamento dos intervalos produz o
/// retorno ponderado no tempo, que é o número comparável ao CDI.
List<PricePoint> portfolioReturnIndex(
  List<PortfolioSnapshot> snapshots, {
  double base = 100,
}) {
  if (snapshots.isEmpty) return const [];
  final ordered = [...snapshots]..sort((a, b) => a.date.compareTo(b.date));
  var index = base;
  final points = <PricePoint>[PricePoint(ordered.first.date, index)];
  for (var i = 1; i < ordered.length; i++) {
    final previous = ordered[i - 1];
    final current = ordered[i];
    final flow = current.costBrl - previous.costBrl;
    final invested = previous.totalBrl + flow;
    if (invested > 0) index *= current.totalBrl / invested;
    points.add(PricePoint(current.date, index));
  }
  return points;
}

/// Último ponto publicado até a data, sem inventar o dia ausente.
PricePoint? pointOnOrBefore(List<PricePoint> points, DateTime date) {
  final target = DateTime(date.year, date.month, date.day);
  PricePoint? found;
  for (final point in points) {
    final day = DateTime(point.date.year, point.date.month, point.date.day);
    if (day.isAfter(target)) break;
    found = point;
  }
  return found;
}

/// Resultado da carteira medido contra o CDI na mesma janela.
class CdiComparison {
  const CdiComparison({
    required this.start,
    required this.end,
    required this.portfolioPercent,
    required this.cdiPercent,
  });

  final DateTime start;
  final DateTime end;

  /// Rentabilidade da carteira no período, já sem o efeito dos aportes.
  final double portfolioPercent;

  /// CDI acumulado exatamente entre as mesmas datas.
  final double cdiPercent;

  double get differencePoints => portfolioPercent - cdiPercent;

  bool get beatsCdi => portfolioPercent >= cdiPercent;

  /// Quanto a carteira rendeu em relação ao CDI (130 significa 130% do CDI).
  ///
  /// Nulo quando o CDI do período não é positivo, caso em que a razão não tem
  /// leitura útil.
  double? get percentOfCdi =>
      cdiPercent <= 0 ? null : portfolioPercent / cdiPercent * 100;
}

/// Compara carteira e CDI apenas na janela em que as duas séries existem.
///
/// Sem sobreposição real de datas o resultado é nulo: nenhum trecho é
/// extrapolado para forçar uma comparação.
CdiComparison? compareToCdi({
  required List<PortfolioSnapshot> snapshots,
  required List<CdiRate> rates,
}) {
  final portfolio = portfolioReturnIndex(snapshots);
  final cdi = accumulateCdi(rates);
  if (portfolio.length < 2 || cdi.isEmpty) return null;

  final start = portfolio.first.date.isAfter(cdi.first.date)
      ? portfolio.first.date
      : cdi.first.date;
  final end = portfolio.last.date.isBefore(cdi.last.date)
      ? portfolio.last.date
      : cdi.last.date;
  if (!end.isAfter(start)) return null;

  final portfolioStart = pointOnOrBefore(portfolio, start);
  final portfolioEnd = pointOnOrBefore(portfolio, end);
  final cdiStart = pointOnOrBefore(cdi, start);
  final cdiEnd = pointOnOrBefore(cdi, end);
  if (portfolioStart == null ||
      portfolioEnd == null ||
      cdiStart == null ||
      cdiEnd == null) {
    return null;
  }
  if (portfolioStart.value == 0 || cdiStart.value == 0) return null;

  return CdiComparison(
    start: start,
    end: end,
    portfolioPercent: (portfolioEnd.value / portfolioStart.value - 1) * 100,
    cdiPercent: (cdiEnd.value / cdiStart.value - 1) * 100,
  );
}
