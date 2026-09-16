import 'package:flutter_test/flutter_test.dart';
import 'package:openstock/models/history_models.dart';
import 'package:openstock/models/investment_asset.dart';

void main() {
  test('normaliza cada série pelo primeiro fechamento disponível', () {
    final points = [
      PricePoint(DateTime(2026, 9, 10), 40),
      PricePoint(DateTime(2026, 9, 11), 44),
      PricePoint(DateTime(2026, 9, 14), 36),
    ];

    final normalized = normalizePerformance(points);

    expect(normalized[0].value, closeTo(0, 0.0001));
    expect(normalized[1].value, closeTo(10, 0.0001));
    expect(normalized[2].value, closeTo(-10, 0.0001));
    expect(normalized.length, 3); // fim de semana não foi fabricado
  });

  test('calcula série relativa ao preço médio', () {
    final result = relativeToAverage([
      PricePoint(DateTime(2026, 9, 14), 44),
      PricePoint(DateTime(2026, 9, 15), 36),
    ], 40);

    expect(result[0].value, closeTo(10, 0.0001));
    expect(result[1].value, closeTo(-10, 0.0001));
  });

  test('identidade separa B3 e EUA e normaliza sufixo SA', () {
    expect(buildAssetKey(AssetMarket.b3, 'prio3.sa'), 'b3:PRIO3');
    expect(buildAssetKey(AssetMarket.usa, 'aapl'), 'usa:AAPL');
    expect(buildAssetKey(AssetMarket.b3, 'AAPL'), isNot('usa:AAPL'));
  });

  test('carteira é normalizada pelo patrimônio dos snapshots, não por média',
      () {
    final portfolio = normalizePerformance([
      PricePoint(DateTime(2026, 9, 14), 1000),
      PricePoint(DateTime(2026, 9, 15), 1050),
    ]);
    final assetA = normalizePerformance([
      PricePoint(DateTime(2026, 9, 14), 100),
      PricePoint(DateTime(2026, 9, 15), 120),
    ]);
    final assetB = normalizePerformance([
      PricePoint(DateTime(2026, 9, 14), 100),
      PricePoint(DateTime(2026, 9, 15), 100),
    ]);

    expect(portfolio.last.value, closeTo(5, 0.0001));
    expect((assetA.last.value + assetB.last.value) / 2, closeTo(10, 0.0001));
    // O valor de carteira veio de 1000 -> 1050; os percentuais não são médios.
    expect(portfolio.last.value, isNot(closeTo(10, 0.0001)));
  });
}
