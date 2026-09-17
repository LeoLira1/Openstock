import 'package:flutter_test/flutter_test.dart';
import 'package:openstock/models/investment_transaction.dart';

InvestmentTransaction _transaction({
  required String id,
  required InvestmentTransactionType type,
  double quantity = 0,
  double price = 0,
  double exchange = 1,
  double fees = 0,
  double cash = 0,
}) {
  final created = DateTime.utc(
    2026,
    9,
    17,
    type == InvestmentTransactionType.openingPosition ? 12 : 13,
  );
  return InvestmentTransaction(
    id: id,
    assetKey: 'b3:PRIO3',
    type: type,
    quantity: quantity,
    unitPrice: price,
    exchangeRate: exchange,
    fees: fees,
    cashValue: cash,
    transactionDate: DateTime(2026, 9, 17),
    createdAt: created,
    updatedAt: created,
  );
}

void main() {
  test('compras recalculam o preço médio ponderado', () {
    final position = calculateTrackedPosition([
      _transaction(
        id: 'opening',
        type: InvestmentTransactionType.openingPosition,
        quantity: 10,
        price: 20,
      ),
      _transaction(
        id: 'buy',
        type: InvestmentTransactionType.purchase,
        quantity: 10,
        price: 30,
      ),
    ]);

    expect(position.quantity, 20);
    expect(position.averagePrice, 25);
  });

  test('venda preserva preço médio e calcula resultado realizado', () {
    final position = calculateTrackedPosition([
      _transaction(
        id: 'opening',
        type: InvestmentTransactionType.openingPosition,
        quantity: 10,
        price: 20,
      ),
      _transaction(
        id: 'sale',
        type: InvestmentTransactionType.sale,
        quantity: 4,
        price: 30,
        fees: 2,
      ),
    ]);

    expect(position.quantity, 6);
    expect(position.averagePrice, 20);
    expect(position.realizedResultBrl, 38);
  });

  test('proventos são acumulados em reais usando o câmbio da operação', () {
    final position = calculateTrackedPosition([
      _transaction(
        id: 'dividend',
        type: InvestmentTransactionType.dividend,
        cash: 10,
        exchange: 5.20,
      ),
      _transaction(
        id: 'jcp',
        type: InvestmentTransactionType.interestOnCapital,
        cash: 20,
      ),
    ]);

    expect(position.incomeBrl, closeTo(72, 0.000001));
  });
}
