import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openstock/models/history_models.dart';
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

  test('histórico B3 respeita período e usa símbolo SA', () async {
    late Uri requested;
    final service = QuoteService(client: MockClient((request) async {
      requested = request.url;
      return http.Response(
        jsonEncode({
          'chart': {
            'error': null,
            'result': [
              {
                'meta': {'regularMarketPrice': 44.0},
                'timestamp': [1789344000],
                'indicators': {
                  'quote': [
                    {
                      'close': [44.0]
                    }
                  ]
                }
              }
            ]
          }
        }),
        200,
      );
    }));
    const asset = InvestmentAsset(
      symbol: 'PRIO3',
      name: 'PRIO',
      market: AssetMarket.b3,
      currency: AssetCurrency.brl,
      quantity: 10,
      averagePrice: 40,
    );

    final history = await service.fetchHistory(asset, HistoryPeriod.fiveYears);

    expect(requested.path, '/v8/finance/chart/PRIO3.SA');
    expect(requested.queryParameters['range'], '5y');
    expect(requested.queryParameters['interval'], '1d');
    expect(history.single.value, 44);
  });
}
