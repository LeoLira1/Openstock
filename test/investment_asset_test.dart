import 'package:flutter_test/flutter_test.dart';
import 'package:openstock/models/investment_asset.dart';

void main() {
  test('serializa e restaura um ativo internacional sem perder valores', () {
    final original = InvestmentAsset(
      id: 7,
      symbol: 'VOO',
      name: 'Vanguard S&P 500 ETF',
      market: AssetMarket.usa,
      currency: AssetCurrency.usd,
      quantity: 3.5,
      averagePrice: 480.25,
      averageExchangeRate: 5.12,
      currentPrice: 510.40,
      previousClose: 508.10,
      updatedAt: DateTime.utc(2026, 9, 15),
    );

    final restored = InvestmentAsset.fromMap(original.toMap());

    expect(restored.id, 7);
    expect(restored.symbol, 'VOO');
    expect(restored.market, AssetMarket.usa);
    expect(restored.currency, AssetCurrency.usd);
    expect(restored.quantity, 3.5);
    expect(restored.averageExchangeRate, 5.12);
    expect(restored.currentPrice, 510.40);
  });

  test('ativo sem cotação não afirma que possui preço de mercado', () {
    const asset = InvestmentAsset(
      symbol: 'PRIO3',
      name: 'PRIO',
      market: AssetMarket.b3,
      currency: AssetCurrency.brl,
      quantity: 10,
      averagePrice: 40,
    );
    expect(asset.hasQuote, isFalse);
  });
}

