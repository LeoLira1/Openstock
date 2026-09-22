import 'package:flutter_test/flutter_test.dart';
import 'package:openstock/models/history_models.dart';
import 'package:openstock/models/investment_asset.dart';
import 'package:openstock/models/investment_transaction.dart';
import 'package:openstock/models/tracking_analytics.dart';

AssetDailySnapshot _assetDay(int day, double value, double cost) =>
    AssetDailySnapshot(
      assetKey: 'b3:TEST3',
      date: DateTime(2026, 9, day),
      quantity: 10,
      averagePrice: cost / 10,
      exchangeRate: 1,
      currentPrice: value / 10,
      valueBrl: value,
      costBrl: cost,
      updatedAt: DateTime.utc(2026, 9, day),
    );

InvestmentTransaction _transaction({
  required String id,
  required InvestmentTransactionType type,
  required DateTime date,
  double quantity = 0,
  double price = 0,
  double cash = 0,
}) =>
    InvestmentTransaction(
      id: id,
      assetKey: 'b3:TEST3',
      type: type,
      quantity: quantity,
      unitPrice: price,
      cashValue: cash,
      transactionDate: date,
      createdAt: date.toUtc(),
      updatedAt: date.toUtc(),
    );

void main() {
  test('mede sequência atual e maior período no prejuízo', () {
    final summary = calculateAssetTrackingSummary(
      snapshots: [
        _assetDay(1, 90, 100),
        _assetDay(2, 95, 100),
        _assetDay(3, 105, 100),
        _assetDay(4, 98, 100),
        _assetDay(7, 99, 100),
      ],
      transactions: const [],
      cdiRates: const [],
    );

    expect(summary, isNotNull);
    expect(summary!.currentUnderwaterDays, 4);
    expect(summary.longestUnderwaterDays, 4);
    expect(summary.isUnderwater, isTrue);
  });

  test('retorno do ativo desconta compras e inclui proventos', () {
    final index = assetReturnIndex(
      [
        _assetDay(1, 1000, 1000),
        _assetDay(2, 1600, 1500),
        _assetDay(3, 1600, 1500),
      ],
      [
        _transaction(
          id: 'buy',
          type: InvestmentTransactionType.purchase,
          date: DateTime(2026, 9, 2),
          quantity: 5,
          price: 100,
        ),
        _transaction(
          id: 'dividend',
          type: InvestmentTransactionType.dividend,
          date: DateTime(2026, 9, 3),
          cash: 10,
        ),
      ],
    );

    expect(index.last.value, closeTo(107.333333, 0.0001));
  });

  test('operação com horário entra no fechamento do mesmo dia', () {
    final index = assetReturnIndex(
      [
        _assetDay(1, 1000, 1000),
        _assetDay(2, 1500, 1500),
      ],
      [
        _transaction(
          id: 'buy-at-noon',
          type: InvestmentTransactionType.purchase,
          date: DateTime(2026, 9, 2, 12, 30),
          quantity: 5,
          price: 100,
        ),
      ],
    );

    expect(index.last.value, 100);
  });

  test('relatório anual separa dinheiro investido de lucro real', () {
    final report = calculateAnnualTrackingReport(
      year: 2027,
      snapshots: [
        PortfolioSnapshot(
          date: DateTime(2027, 1, 4),
          totalBrl: 1000,
          costBrl: 1000,
          updatedAt: DateTime.utc(2027, 1, 4),
        ),
        PortfolioSnapshot(
          date: DateTime(2027, 12, 30),
          totalBrl: 1600,
          costBrl: 1500,
          updatedAt: DateTime.utc(2027, 12, 30),
        ),
      ],
      transactions: [
        _transaction(
          id: 'buy',
          type: InvestmentTransactionType.purchase,
          date: DateTime(2027, 6, 1),
          quantity: 5,
          price: 100,
        ),
        _transaction(
          id: 'dividend',
          type: InvestmentTransactionType.dividend,
          date: DateTime(2027, 9, 1),
          cash: 10,
        ),
      ],
      cdiRates: const [],
    );

    expect(report, isNotNull);
    expect(report!.purchasesBrl, 500);
    expect(report.incomeBrl, 10);
    expect(report.profitBrl, 110);
  });

  test('CDI usa somente taxas posteriores ao início e até o fim', () {
    final result = cdiReturnBetween(
      [
        CdiRate(date: DateTime(2026, 9, 1), dailyPercent: 1),
        CdiRate(date: DateTime(2026, 9, 2), dailyPercent: 1),
        CdiRate(date: DateTime(2026, 9, 3), dailyPercent: 1),
        CdiRate(date: DateTime(2026, 9, 4), dailyPercent: 1),
      ],
      DateTime(2026, 9, 1),
      DateTime(2026, 9, 3),
    );

    expect(result, closeTo(2.01, 0.000001));
  });

  PortfolioSnapshot portfolioDay(DateTime date, double total) =>
      PortfolioSnapshot(
        date: date,
        totalBrl: total,
        costBrl: total,
        updatedAt: date.toUtc(),
      );

  test('relatório mensal parte do último registro do mês anterior', () {
    final report = calculateTrackingReport(
      period: const ReportPeriod(2026, 9),
      snapshots: [
        portfolioDay(DateTime(2026, 8, 3), 800),
        portfolioDay(DateTime(2026, 8, 31), 1000),
        portfolioDay(DateTime(2026, 9, 1), 1020),
        portfolioDay(DateTime(2026, 9, 30), 1600),
        portfolioDay(DateTime(2026, 10, 1), 9999),
      ],
      transactions: [
        _transaction(
          id: 'buy-aug',
          type: InvestmentTransactionType.purchase,
          date: DateTime(2026, 8, 10),
          quantity: 1,
          price: 100,
        ),
        _transaction(
          id: 'buy-sep',
          type: InvestmentTransactionType.purchase,
          date: DateTime(2026, 9, 15),
          quantity: 5,
          price: 100,
        ),
        _transaction(
          id: 'dividend-oct',
          type: InvestmentTransactionType.dividend,
          date: DateTime(2026, 10, 1),
          cash: 10,
        ),
      ],
      cdiRates: [
        CdiRate(date: DateTime(2026, 8, 31), dailyPercent: 1),
        CdiRate(date: DateTime(2026, 9, 1), dailyPercent: 1),
        CdiRate(date: DateTime(2026, 9, 30), dailyPercent: 1),
      ],
    );

    expect(report, isNotNull);
    expect(report!.period.label, 'setembro de 2026');
    expect(report.start, DateTime(2026, 9, 1));
    expect(report.end, DateTime(2026, 9, 30));
    expect(report.snapshotCount, 2);
    expect(report.initialValueBrl, 1000);
    expect(report.finalValueBrl, 1600);
    expect(report.purchasesBrl, 500);
    expect(report.incomeBrl, 0);
    expect(report.profitBrl, 100);
    // Só as taxas de setembro, depois do registro de 31/08.
    expect(report.cdiPercent, closeTo(2.01, 0.000001));
  });

  test('mês sem registros não gera relatório', () {
    final report = calculateTrackingReport(
      period: const ReportPeriod(2026, 7),
      snapshots: [portfolioDay(DateTime(2026, 9, 1), 1000)],
      transactions: const [],
      cdiRates: const [],
    );

    expect(report, isNull);
  });

  test('período mensal termina no último dia do mês', () {
    expect(const ReportPeriod(2028, 2).end, DateTime(2028, 2, 29, 23, 59, 59));
    expect(const ReportPeriod(2026, 12).end, DateTime(2026, 12, 31, 23, 59, 59));
    expect(const ReportPeriod(2026).label, '2026');
  });

  test('ativo incluído depois do início não vira lucro', () {
    // 16/09 só um ativo; 17/09 outro passa a ser rastreado com R$ 10 mil.
    final snapshots = [
      portfolioDay(DateTime(2026, 9, 16), 38000),
      portfolioDay(DateTime(2026, 9, 17), 48100),
      portfolioDay(DateTime(2026, 9, 18), 47900),
    ];
    final entries = [PricePoint(DateTime(2026, 9, 17), 10000)];

    final points = calculatePortfolioPerformance(
      snapshots: snapshots,
      transactions: const [],
      entries: entries,
    );

    expect(points, hasLength(3));
    expect(points[1].resultBrl, closeTo(100, 0.0001));
    expect(points[2].resultBrl, closeTo(-100, 0.0001));
    expect(points[1].returnPercent, closeTo(100 / 480, 0.0001));

    final report = calculateTrackingReport(
      period: const ReportPeriod(2026, 9),
      snapshots: snapshots,
      transactions: const [],
      cdiRates: const [],
      entries: entries,
    );
    expect(report!.profitBrl, closeTo(-100, 0.0001));
    expect(report.trackedEntriesBrl, 10000);
    expect(report.returnPercent, lessThan(0));
  });

  test('gráfico da carteira parte do registro anterior à janela', () {
    final points = calculatePortfolioPerformance(
      snapshots: [
        portfolioDay(DateTime(2026, 8, 1), 900),
        portfolioDay(DateTime(2026, 8, 20), 1000),
        portfolioDay(DateTime(2026, 9, 1), 1100),
        portfolioDay(DateTime(2026, 9, 2), 1650),
      ],
      transactions: [
        _transaction(
          id: 'buy',
          type: InvestmentTransactionType.purchase,
          date: DateTime(2026, 9, 2),
          quantity: 5,
          price: 100,
        ),
      ],
      since: DateTime(2026, 8, 22),
    );

    expect(points.first.date, DateTime(2026, 8, 20));
    expect(points.map((item) => item.resultBrl), [0, 100, 150]);
    // 1100/1000 e depois 1650/(1100 + 500): retorno ponderado pelo tempo.
    expect(points.last.returnPercent, closeTo(13.4375, 0.0001));
  });

  test('entrada no rastreamento ignora compras do mesmo dia', () {
    AssetDailySnapshot day(int d, double quantity, double value) =>
        AssetDailySnapshot(
          assetKey: 'b3:TEST3',
          date: DateTime(2026, 9, d),
          quantity: quantity,
          averagePrice: 10,
          exchangeRate: 1,
          currentPrice: value / quantity,
          valueBrl: value,
          costBrl: quantity * 10,
          updatedAt: DateTime.utc(2026, 9, d),
        );
    final entries = trackingEntries([
      (
        snapshots: [day(18, 15, 150), day(17, 10, 100)],
        transactions: [
          _transaction(
            id: 'open',
            type: InvestmentTransactionType.openingPosition,
            date: DateTime(2026, 9, 17),
            quantity: 5,
            price: 10,
          ),
        ],
      ),
      (snapshots: [day(17, 10, 100)], transactions: const []),
    ]);

    expect(entries, hasLength(1));
    expect(entries.single.date, DateTime(2026, 9, 17));
    expect(entries.single.value, 50);
  });
}
