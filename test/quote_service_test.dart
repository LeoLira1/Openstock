import 'package:flutter_test/flutter_test.dart';
import 'package:openstock/models/investment_asset.dart';
import 'package:openstock/services/quote_service.dart';

void main() {
  group('resolvePreviousClose', () {
    test('ignora a cotação parcial de hoje', () {
      final result = resolvePreviousClose(
        history: [
          PricePoint(DateTime(2026, 9, 14, 17), 64.19),
          PricePoint(DateTime(2026, 9, 15, 14), 65.40),
        ],
        current: 65.40,
        providerPrevious: 58.63,
        now: DateTime(2026, 9, 15, 16),
      );

      expect(result, 64.19);
    });

    test('usa o último pregão quando a série termina ontem', () {
      final result = resolvePreviousClose(
        history: [
          PricePoint(DateTime(2026, 9, 11, 17), 63.80),
          PricePoint(DateTime(2026, 9, 14, 17), 64.19),
        ],
        current: 65.40,
        providerPrevious: 58.63,
        now: DateTime(2026, 9, 15, 16),
      );

      expect(result, 64.19);
    });

    test('recorre ao metadado quando não há histórico', () {
      final result = resolvePreviousClose(
        history: const [],
        current: 65.40,
        providerPrevious: 64.19,
      );

      expect(result, 64.19);
    });
  });
}
