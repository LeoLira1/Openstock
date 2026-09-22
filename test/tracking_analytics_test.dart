import 'package:flutter_test/flutter_test.dart';
import 'package:openstock/models/history_models.dart';
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

  AssetDailySnapshot asset(String key, DateTime date, double value,
          {double quantity = 10}) =>
      AssetDailySnapshot(
        assetKey: key,
        date: date,
        quantity: quantity,
        averagePrice: 1,
        exchangeRate: 1,
        currentPrice: value / quantity,
        valueBrl: value,
        costBrl: quantity,
        updatedAt: date.toUtc(),
      );

  test('ativos incluídos depois do início não viram lucro nem prejuízo', () {
    // Caso do print: 16/09 só um ativo; 17/09 outros 38 passam a ser
    // rastreados, somando R\$ 11.100.
    final d16 = DateTime(2026, 9, 16);
    final d17 = DateTime(2026, 9, 17);
    final d18 = DateTime(2026, 9, 18);
    final snapshots = <String, List<AssetDailySnapshot>>{
      'a': [asset('a', d16, 38700), asset('a', d17, 38800), asset('a', d18, 38750)],
      for (var i = 0; i < 38; i++)
        'n$i': [
          asset('n$i', d17, 11100 / 38),
          asset('n$i', d18, 11100 / 38 + 1),
        ],
    };

    final points = calculatePortfolioPerformance(
      assetSnapshots: snapshots,
      transactionsByAsset: const {},
    );

    expect(points, hasLength(3));
    expect(points[1].valueBrl, closeTo(49900, 0.0001));
    expect(points[1].resultBrl, closeTo(100, 0.0001));
    expect(points[1].returnPercent, closeTo(100 / 38700 * 100, 0.0001));
    expect(points[2].resultBrl, closeTo(100 - 50 + 38, 0.0001));

    final report = calculateTrackingReport(
      period: const ReportPeriod(2026, 9),
      snapshots: [
        // Total antigo, gravado sem todos os ativos: não pode mais distorcer.
        portfolioDay(d16, 38731.33),
        portfolioDay(d18, 49975.70),
      ],
      transactions: const [],
      cdiRates: const [],
      assetSnapshots: snapshots,
    );
    expect(report!.profitBrl, closeTo(88, 0.0001));
    expect(report.initialValueBrl, 38700);
    expect(report.returnPercent, greaterThan(0));
    expect(report.returnPercent, lessThan(1));
  });

  test('compra no meio do período é aporte e venda com provento é saída', () {
    final d1 = DateTime(2026, 9, 1);
    final d2 = DateTime(2026, 9, 2);
    final d3 = DateTime(2026, 9, 3);
    InvestmentTransaction tx(String id, InvestmentTransactionType type,
            DateTime date,
            {double quantity = 0, double price = 0, double cash = 0}) =>
        InvestmentTransaction(
          id: id,
          assetKey: 'a',
          type: type,
          quantity: quantity,
          unitPrice: price,
          cashValue: cash,
          transactionDate: date,
          createdAt: date.toUtc(),
          updatedAt: date.toUtc(),
        );

    final points = calculatePortfolioPerformance(
      assetSnapshots: {
        'a': [
          asset('a', d1, 1000),
          asset('a', d2, 1550, quantity: 15),
          asset('a', d3, 1100, quantity: 10),
        ],
      },
      transactionsByAsset: {
        'a': [
          tx('buy', InvestmentTransactionType.purchase, d2,
              quantity: 5, price: 100),
          tx('sell', InvestmentTransactionType.sale, d3,
              quantity: 5, price: 100),
          tx('div', InvestmentTransactionType.dividend, d3, cash: 20),
        ],
      },
    );

    // 1000 → 1550 com R$ 500 de compra: +50.
    expect(points[1].resultBrl, closeTo(50, 0.0001));
    // 1550 → 1100 com R$ 500 de venda e R$ 20 de provento: +70.
    expect(points[2].resultBrl, closeTo(120, 0.0001));
  });

  test('janela do gráfico parte do dia anterior e zera o resultado', () {
    final points = calculatePortfolioPerformance(
      assetSnapshots: {
        'a': [
          asset('a', DateTime(2026, 8, 1), 900),
          asset('a', DateTime(2026, 8, 20), 1000),
          asset('a', DateTime(2026, 9, 1), 1100),
          asset('a', DateTime(2026, 9, 2), 1210),
        ],
      },
      transactionsByAsset: const {},
      since: DateTime(2026, 8, 22),
    );

    expect(points.first.date, DateTime(2026, 8, 20));
    expect(points.map((item) => item.resultBrl), [0, 100, 210]);
    expect(points.last.returnPercent, closeTo(21, 0.0001));
  });
}
