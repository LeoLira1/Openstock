import 'package:flutter_test/flutter_test.dart';
import 'package:openstock/models/dividends.dart';
import 'package:openstock/models/investment_transaction.dart';

InvestmentTransaction _tx(String id, InvestmentTransactionType type,
        DateTime date, double quantity) =>
    InvestmentTransaction(
      id: id,
      assetKey: 'b3:PETR4',
      type: type,
      quantity: quantity,
      unitPrice: 30,
      transactionDate: date,
      createdAt: date.toUtc(),
      updatedAt: date.toUtc(),
    );

DividendAnnouncement _ann(DateTime payment, DateTime? record,
        {double rate = 0.5, String label = 'DIVIDENDO'}) =>
    DividendAnnouncement(
      symbol: 'PETR4',
      label: label,
      rate: rate,
      paymentDate: payment,
      recordDate: record,
    );

void main() {
  test('lê cashDividends da brapi no dia da B3 e descarta repetidos', () {
    final row = {
      'paymentDate': '2026-12-21T03:00:00.000Z',
      'rate': 0.471567,
      'label': 'DIVIDENDO',
      'lastDatePrior': '2026-08-21T03:00:00.000Z',
      'exDate': '2026-08-24T03:00:00.000Z',
    };
    final parsed = parseBrapiDividends('PETR4', {
      'dividendsData': {
        'cashDividends': [
          row,
          row,
          {...row, 'label': 'JCP', 'rate': 0.2},
          {...row, 'rate': null},
          {...row, 'paymentDate': null},
        ],
      },
    });

    expect(parsed, hasLength(2));
    expect(parsed.first.paymentDate, DateTime(2026, 12, 21));
    expect(parsed.first.recordDate, DateTime(2026, 8, 21));
    expect(parsed.last.displayLabel, 'JCP');
    expect(
      DividendAnnouncement.fromJson(parsed.first.toJson()).paymentDate,
      DateTime(2026, 12, 21),
    );
  });

  test('usa a quantidade da data-com e ignora pagamentos já feitos', () {
    final transactions = [
      _tx('open', InvestmentTransactionType.openingPosition,
          DateTime(2026, 9, 1), 100),
      _tx('buy', InvestmentTransactionType.purchase, DateTime(2026, 9, 10), 50),
    ];
    final upcoming = projectUpcomingDividends(
      assetKey: 'b3:PETR4',
      announcements: [
        _ann(DateTime(2026, 9, 20), DateTime(2026, 9, 5)), // já pago
        _ann(DateTime(2026, 10, 15), DateTime(2026, 9, 5)),
        _ann(DateTime(2026, 11, 15), DateTime(2026, 9, 12)),
        _ann(DateTime(2026, 12, 15), DateTime(2026, 8, 20)),
        _ann(DateTime(2027, 1, 15), DateTime(2026, 12, 1)),
      ],
      transactions: transactions,
      currentQuantity: 150,
      today: DateTime(2026, 9, 22),
    );

    expect(upcoming.map((item) => item.quantity), [100, 150, 100, 150]);
    expect(upcoming.map((item) => item.estimated), [false, false, true, true]);
    expect(upcoming.first.grossBrl, 50);
  });

  test('posição zerada na data-com não recebe', () {
    final upcoming = projectUpcomingDividends(
      assetKey: 'b3:PETR4',
      announcements: [_ann(DateTime(2026, 10, 15), DateTime(2026, 9, 12))],
      transactions: [
        _tx('open', InvestmentTransactionType.openingPosition,
            DateTime(2026, 9, 1), 100),
        _tx('sell', InvestmentTransactionType.sale, DateTime(2026, 9, 10), 100),
      ],
      currentQuantity: 0,
      today: DateTime(2026, 9, 22),
    );

    expect(upcoming, isEmpty);
  });
}
