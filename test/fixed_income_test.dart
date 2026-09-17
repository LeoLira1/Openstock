import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:openstock/models/fixed_income.dart';
import 'package:openstock/models/history_models.dart';
import 'package:openstock/models/investment_asset.dart';

InvestmentAsset _title({
  required FixedIncomeIndexer indexer,
  required double rate,
  FixedIncomeKind kind = FixedIncomeKind.cdb,
  double principal = 1000,
  DateTime? application,
  DateTime? maturity,
}) =>
    InvestmentAsset(
      symbol: 'CDB TESTE',
      name: 'Banco Teste',
      market: AssetMarket.fixedIncome,
      currency: AssetCurrency.brl,
      quantity: 1,
      averagePrice: principal,
      fixedIncomeKind: kind,
      indexer: indexer,
      indexerRate: rate,
      applicationDate: application ?? DateTime(2026, 9, 14),
      maturityDate: maturity,
    );

/// Dias úteis seguidos com a mesma taxa, como o Banco Central publica.
List<CdiRate> _rates(List<DateTime> dates, double dailyPercent) => [
      for (final date in dates) CdiRate(date: date, dailyPercent: dailyPercent),
    ];

void main() {
  final businessDays = [
    DateTime(2026, 9, 14),
    DateTime(2026, 9, 15),
    DateTime(2026, 9, 16),
  ];

  test('o dia da aplicação ainda não rende', () {
    final series = accrueFixedIncome(
      asset: _title(indexer: FixedIncomeIndexer.cdi, rate: 110),
      rates: _rates(businessDays, 0.05),
      today: DateTime(2026, 9, 16),
    );

    expect(series.first.date, DateTime(2026, 9, 14));
    expect(series.first.value, 1000);
    expect(series.length, 3); // aplicação + 15/09 + 16/09
  });

  test('percentual do CDI multiplica a taxa do dia, não o fator', () {
    final series = accrueFixedIncome(
      asset: _title(indexer: FixedIncomeIndexer.cdi, rate: 110),
      rates: _rates(businessDays, 0.05),
      today: DateTime(2026, 9, 16),
    );

    // Dois dias úteis a 0,05% × 1,10 = fator (1 + 0,00055)².
    expect(series.last.value, closeTo(1000 * 1.00055 * 1.00055, 0.000001));
  });

  test('100% do CDI reproduz o índice do CDI no mesmo período', () {
    final rates = _rates(businessDays, 0.05);
    final series = accrueFixedIncome(
      asset: _title(indexer: FixedIncomeIndexer.cdi, rate: 100),
      rates: rates,
      today: DateTime(2026, 9, 16),
    );
    final index = accumulateCdi(rates);
    final cdiReturn = index.last.value / index.first.value;

    expect(series.last.value / series.first.value, closeTo(cdiReturn, 1e-12));
  });

  test('prefixado usa a convenção de 252 dias úteis', () {
    final series = accrueFixedIncome(
      asset: _title(indexer: FixedIncomeIndexer.prefixed, rate: 10),
      rates: _rates(businessDays, 0.05),
      today: DateTime(2026, 9, 16),
    );

    // Dois dias úteis de uma taxa de 10% ao ano: (1,10) elevado a 2/252.
    expect(series.last.value, closeTo(1000 * math.pow(1.1, 2 / 252), 1e-9));
  });

  test('taxa do CDI não altera o prefixado', () {
    double valueWithCdi(double cdi) => accrueFixedIncome(
          asset: _title(indexer: FixedIncomeIndexer.prefixed, rate: 12),
          rates: _rates(businessDays, cdi),
          today: DateTime(2026, 9, 16),
        ).last.value;

    expect(valueWithCdi(0.05), closeTo(valueWithCdi(0.02), 1e-9));
  });

  test('o título para de render no vencimento', () {
    final series = accrueFixedIncome(
      asset: _title(
        indexer: FixedIncomeIndexer.cdi,
        rate: 100,
        maturity: DateTime(2026, 9, 15),
      ),
      rates: _rates(businessDays, 0.05),
      today: DateTime(2026, 9, 16),
    );

    expect(series.last.date, DateTime(2026, 9, 15));
    expect(series.last.value, closeTo(1000 * 1.0005, 0.000001));
  });

  test('título sem indexador ou sem data não gera série', () {
    final incomplete = InvestmentAsset(
      symbol: 'CDB SEM DADOS',
      name: '',
      market: AssetMarket.fixedIncome,
      currency: AssetCurrency.brl,
      quantity: 1,
      averagePrice: 1000,
    );

    expect(
      accrueFixedIncome(
          asset: incomplete, rates: _rates(businessDays, 0.05)),
      isEmpty,
    );
  });

  group('imposto de renda', () {
    test('a alíquota cai conforme o prazo', () {
      expect(incomeTaxRate(180), 22.5);
      expect(incomeTaxRate(181), 20);
      expect(incomeTaxRate(360), 20);
      expect(incomeTaxRate(361), 17.5);
      expect(incomeTaxRate(720), 17.5);
      expect(incomeTaxRate(721), 15);
    });

    test('CDB de curto prazo paga 22,5% sobre o rendimento', () {
      final asset = _title(indexer: FixedIncomeIndexer.cdi, rate: 100);
      final accrued = [
        PricePoint(DateTime(2026, 9, 14), 1000),
        PricePoint(DateTime(2026, 9, 15), 1100),
      ];

      final position = fixedIncomePosition(
        asset: asset,
        accrued: accrued,
        today: DateTime(2026, 9, 15),
      )!;

      expect(position.grossYield, closeTo(100, 0.000001));
      expect(position.taxRate, 22.5);
      expect(position.tax, closeTo(22.5, 0.000001));
      expect(position.netValue, closeTo(1077.5, 0.000001));
      expect(position.businessDays, 1);
    });

    test('LCI e LCA não pagam imposto', () {
      for (final kind in [FixedIncomeKind.lci, FixedIncomeKind.lca]) {
        final position = fixedIncomePosition(
          asset: _title(
              indexer: FixedIncomeIndexer.cdi, rate: 95, kind: kind),
          accrued: [
            PricePoint(DateTime(2026, 9, 14), 1000),
            PricePoint(DateTime(2026, 9, 15), 1100),
          ],
          today: DateTime(2026, 9, 15),
        )!;

        expect(position.taxRate, 0);
        expect(position.netValue, closeTo(position.grossValue, 0.000001));
      }
    });
  });

  test('etiqueta do indexador é legível', () {
    expect(
      fixedIncomeRateLabel(_title(indexer: FixedIncomeIndexer.cdi, rate: 110)),
      '110% do CDI',
    );
    expect(
      fixedIncomeRateLabel(
          _title(indexer: FixedIncomeIndexer.prefixed, rate: 12.5)),
      '12,5% a.a.',
    );
  });
}
