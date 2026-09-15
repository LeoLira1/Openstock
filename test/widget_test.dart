import 'package:flutter_test/flutter_test.dart';
import 'package:openstock/models/investment_asset.dart';

void main() {
  test('um ativo B3 preserva sua moeda e seu mercado', () {
    const asset = InvestmentAsset(
      symbol: 'VALE3',
      name: 'Vale',
      market: AssetMarket.b3,
      currency: AssetCurrency.brl,
      quantity: 20,
      averagePrice: 58.40,
    );

    expect(asset.market, AssetMarket.b3);
    expect(asset.currency, AssetCurrency.brl);
    expect(asset.quantity * asset.averagePrice, closeTo(1168, 0.001));
  });
}
