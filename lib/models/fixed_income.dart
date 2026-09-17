import 'dart:math' as math;

import 'history_models.dart';
import 'investment_asset.dart';

/// Dias úteis de um ano na convenção brasileira de renda fixa.
const _businessDaysPerYear = 252;

/// Valor bruto de um título de renda fixa em cada dia útil publicado.
///
/// O calendário de dias úteis é a própria série do CDI: o Banco Central publica
/// a taxa exatamente nos dias em que o título rende, então feriados e fins de
/// semana ficam de fora sem precisar de uma tabela de feriados.
///
/// O rendimento começa no dia útil seguinte à aplicação e para no vencimento.
/// O primeiro ponto é sempre o valor aplicado, na data da aplicação.
List<PricePoint> accrueFixedIncome({
  required InvestmentAsset asset,
  required List<CdiRate> rates,
  DateTime? today,
}) {
  final application = asset.applicationDate;
  final rate = asset.indexerRate;
  final indexer = asset.indexer;
  if (application == null || indexer == null || rate == null) return const [];
  if (asset.principal <= 0) return const [];

  final now = today ?? DateTime.now();
  final end = asset.maturityDate != null && asset.maturityDate!.isBefore(now)
      ? asset.maturityDate!
      : now;
  final points = <PricePoint>[PricePoint(_day(application), asset.principal)];
  if (end.isBefore(application)) return points;

  final ordered = [...rates]..sort((a, b) => a.date.compareTo(b.date));
  var value = asset.principal;
  for (final daily in ordered) {
    final date = _day(daily.date);
    if (!date.isAfter(_day(application))) continue;
    if (date.isAfter(_day(end))) break;
    value *= switch (indexer) {
      // Convenção de mercado para "% do CDI": o percentual multiplica a taxa
      // do dia, não o fator acumulado.
      FixedIncomeIndexer.cdi => 1 + (daily.dailyPercent / 100) * (rate / 100),
      FixedIncomeIndexer.prefixed =>
        math.pow(1 + rate / 100, 1 / _businessDaysPerYear).toDouble(),
    };
    points.add(PricePoint(date, value));
  }
  return points;
}

/// Alíquota regressiva de IR sobre o rendimento, pelo prazo em dias corridos.
///
/// Vale para CDB e demais títulos tributados; LCI e LCA são isentas.
double incomeTaxRate(int days) {
  if (days <= 180) return 22.5;
  if (days <= 360) return 20;
  if (days <= 720) return 17.5;
  return 15;
}

/// Situação atual de um título: bruto, rendimento e valor líquido de IR.
class FixedIncomePosition {
  const FixedIncomePosition({
    required this.grossValue,
    required this.previousGrossValue,
    required this.principal,
    required this.taxRate,
    required this.elapsedDays,
    required this.businessDays,
  });

  final double grossValue;
  final double previousGrossValue;
  final double principal;

  /// Alíquota aplicada ao rendimento; zero para os títulos isentos.
  final double taxRate;
  final int elapsedDays;
  final int businessDays;

  double get grossYield => grossValue - principal;
  double get tax => grossYield <= 0 ? 0 : grossYield * taxRate / 100;
  double get netValue => grossValue - tax;
  double get netYield => netValue - principal;

  double get grossYieldPercent =>
      principal <= 0 ? 0 : grossYield / principal * 100;
}

/// Posição de um título a partir da série de valores já acumulada.
FixedIncomePosition? fixedIncomePosition({
  required InvestmentAsset asset,
  required List<PricePoint> accrued,
  DateTime? today,
}) {
  if (accrued.isEmpty) return null;
  final application = asset.applicationDate ?? accrued.first.date;
  final now = today ?? DateTime.now();
  final reference = asset.maturityDate != null && asset.maturityDate!.isBefore(now)
      ? asset.maturityDate!
      : now;
  final elapsed = _day(reference).difference(_day(application)).inDays;
  final exempt = asset.fixedIncomeKind?.taxExempt ?? false;
  return FixedIncomePosition(
    grossValue: accrued.last.value,
    previousGrossValue:
        accrued.length > 1 ? accrued[accrued.length - 2].value : accrued.last.value,
    principal: asset.principal,
    taxRate: exempt ? 0 : incomeTaxRate(elapsed),
    elapsedDays: elapsed,
    // O primeiro ponto é a aplicação, que ainda não rendeu.
    businessDays: accrued.length - 1,
  );
}

/// Texto curto do indexador, como "110% do CDI" ou "12,5% a.a.".
String fixedIncomeRateLabel(InvestmentAsset asset) {
  final rate = asset.indexerRate;
  if (rate == null || asset.indexer == null) return 'Sem indexador';
  var number = rate.toStringAsFixed(2);
  while (number.contains('.') &&
      (number.endsWith('0') || number.endsWith('.'))) {
    number = number.substring(0, number.length - 1);
  }
  final clean = number.replaceAll('.', ',');
  return switch (asset.indexer!) {
    FixedIncomeIndexer.cdi => '$clean% do CDI',
    FixedIncomeIndexer.prefixed => '$clean% a.a.',
  };
}

DateTime _day(DateTime date) => DateTime(date.year, date.month, date.day);
