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
  test('lê os proventos da B3 só da classe do papel', () {
    Map<String, String> row(String isin, String label, String rate,
            String payment, String record) =>
        {
          'isinCode': isin,
          'label': label,
          'rate': rate,
          'paymentDate': payment,
          'lastDatePrior': record,
        };
    final company = {
      'cashDividends': [
        row('BRPETRACNPR6', 'JRS CAP PROPRIO', '0,67407131000', '23/11/2026',
            '21/08/2026'),
        row('BRPETRACNPR6', 'JRS CAP PROPRIO', '0,67407131000', '23/11/2026',
            '21/08/2026'),
        row('BRPETRACNOR9', 'DIVIDENDO', '0,47', '21/12/2026', '21/08/2026'),
        row('BRPETRACNPR6', 'DIVIDENDO', '1.234,5', '21/12/2026', '21/08/2026'),
        row('BRPETRACNPR6', 'DIVIDENDO', '0,1', '', '21/08/2026'),
      ],
    };

    final pn = parseB3Dividends('PETR4', company);
    expect(pn, hasLength(2));
    expect(pn.first.displayLabel, 'JCP');
    expect(pn.first.rate, closeTo(0.67407131, 1e-9));
    expect(pn.first.paymentDate, DateTime(2026, 11, 23));
    expect(pn.first.recordDate, DateTime(2026, 8, 21));
    expect(pn.last.rate, 1234.5);
    expect(
      DividendAnnouncement.fromJson(pn.first.toJson()).paymentDate,
      DateTime(2026, 11, 23),
    );

    final on = parseB3Dividends('PETR3', company);
    expect(on.single.displayLabel, 'Dividendo');
  });

  test('classe do ISIN: ON, PN, unit e FII', () {
    expect(b3IsinMatchesSymbol('BRBBASACNOR3', 'BBAS3'), isTrue);
    expect(b3IsinMatchesSymbol('BRBBASA04OR8', 'BBAS3'), isFalse);
    expect(b3IsinMatchesSymbol('BRALUPCDAM15', 'ALUP11'), isTrue);
    expect(b3IsinMatchesSymbol('BRALUPACNOR8', 'ALUP11'), isFalse);
    expect(b3IsinMatchesSymbol('BRMXRFCTF008', 'MXRF11'), isTrue);
    expect(b3IsinMatchesSymbol('BRMXRFR27M13', 'MXRF11'), isFalse);
    expect(b3IsinMatchesSymbol('BRITSAACNPR7', 'ITSA4F'), isTrue);
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
