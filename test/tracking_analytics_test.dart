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
}
