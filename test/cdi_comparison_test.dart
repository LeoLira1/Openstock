import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openstock/models/history_models.dart';
import 'package:openstock/services/cdi_service.dart';
import 'package:openstock/services/quote_service.dart';

PortfolioSnapshot _snapshot(DateTime date, double total, double cost) =>
    PortfolioSnapshot(
      date: date,
      totalBrl: total,
      costBrl: cost,
      updatedAt: date,
    );

void main() {
  test('índice do CDI compõe as taxas diárias publicadas', () {
    final index = accumulateCdi([
      CdiRate(date: DateTime(2026, 9, 14), dailyPercent: 1),
      CdiRate(date: DateTime(2026, 9, 15), dailyPercent: 1),
    ]);

    expect(index.length, 2); // nenhum dia sem publicação foi inventado
    expect(index.first.value, closeTo(101, 0.0001));
    expect(index.last.value, closeTo(102.01, 0.0001));
  });

  test('rentabilidade da carteira não conta o aporte como valorização', () {
    final index = portfolioReturnIndex([
      _snapshot(DateTime(2026, 9, 14), 1000, 1000),
      _snapshot(DateTime(2026, 9, 15), 1100, 1000),
      _snapshot(DateTime(2026, 9, 16), 2100, 2000),
    ]);

    expect(index[1].value, closeTo(110, 0.0001)); // +10% de mercado
    expect(index[2].value, closeTo(110, 0.0001)); // aporte de R$ 1.000 é neutro
  });

  test('retirada no meio do período também não vira prejuízo', () {
    final index = portfolioReturnIndex([
      _snapshot(DateTime(2026, 9, 14), 1000, 1000),
      _snapshot(DateTime(2026, 9, 15), 600, 600),
    ]);

    expect(index.last.value, closeTo(100, 0.0001));
  });

  test('comparação usa a janela comum às duas séries', () {
    final comparison = compareToCdi(
      snapshots: [
        _snapshot(DateTime(2026, 9, 14), 1000, 1000),
        _snapshot(DateTime(2026, 9, 15), 1100, 1000),
        _snapshot(DateTime(2026, 9, 16), 2100, 2000),
      ],
      rates: [
        CdiRate(date: DateTime(2026, 9, 14), dailyPercent: 1),
        CdiRate(date: DateTime(2026, 9, 15), dailyPercent: 1),
        CdiRate(date: DateTime(2026, 9, 16), dailyPercent: 1),
      ],
    );

    expect(comparison, isNotNull);
    expect(comparison!.start, DateTime(2026, 9, 14));
    expect(comparison.end, DateTime(2026, 9, 16));
    expect(comparison.portfolioPercent, closeTo(10, 0.0001));
    expect(comparison.cdiPercent, closeTo(2.01, 0.0001));
    expect(comparison.differencePoints, closeTo(7.99, 0.0001));
    expect(comparison.percentOfCdi, closeTo(497.512, 0.01));
    expect(comparison.beatsCdi, isTrue);
  });

  test('sem datas em comum não existe comparação', () {
    final comparison = compareToCdi(
      snapshots: [
        _snapshot(DateTime(2026, 1, 5), 1000, 1000),
        _snapshot(DateTime(2026, 1, 7), 1100, 1000),
      ],
      rates: [CdiRate(date: DateTime(2026, 3, 2), dailyPercent: 0.05)],
    );

    expect(comparison, isNull);
  });

  test('um snapshot só não gera comparação', () {
    final comparison = compareToCdi(
      snapshots: [_snapshot(DateTime(2026, 9, 14), 1000, 1000)],
      rates: [CdiRate(date: DateTime(2026, 9, 14), dailyPercent: 0.05)],
    );

    expect(comparison, isNull);
  });

  group('CdiService', () {
    test('lê a série 12 do Banco Central no formato dd/MM/yyyy', () async {
      late Uri requested;
      final service = CdiService(
        client: MockClient((request) async {
          requested = request.url;
          return http.Response(
            jsonEncode([
              {'data': '14/09/2026', 'valor': '0.052531'},
              {'data': '15/09/2026', 'valor': '0.052531'},
            ]),
            200,
          );
        }),
      );

      final rates = await service.fetchDailyRates(
        start: DateTime(2026, 9, 14),
        end: DateTime(2026, 9, 15),
      );

      expect(requested.path, '/dados/serie/bcdata.sgs.12/dados');
      expect(requested.queryParameters['dataInicial'], '14/09/2026');
      expect(requested.queryParameters['dataFinal'], '15/09/2026');
      expect(rates.length, 2);
      expect(rates.first.date, DateTime(2026, 9, 14));
      expect(rates.first.dailyPercent, closeTo(0.052531, 0.000001));
    });

    test('janelas longas são divididas em blocos de dez anos', () async {
      final windows = <String>[];
      final service = CdiService(
        client: MockClient((request) async {
          windows.add(request.url.queryParameters['dataInicial']!);
          return http.Response('[]', 200);
        }),
      );

      await service.fetchDailyRates(
        start: DateTime(2004, 1, 1),
        end: DateTime(2026, 9, 15),
      );

      expect(windows, ['01/01/2004', '02/01/2014', '03/01/2024']);
    });

    test('erro do Banco Central vira mensagem legível', () async {
      final service = CdiService(
        client: MockClient((_) async => http.Response('erro', 500)),
      );

      await expectLater(
        service.fetchDailyRates(start: DateTime(2026, 9, 14)),
        throwsA(isA<QuoteException>()),
      );
    });

    test('resposta vazia não quebra a série', () async {
      final service = CdiService(
        client: MockClient((_) async => http.Response('[]', 200)),
      );

      expect(await service.fetchDailyRates(start: DateTime(2026, 9, 14)),
          isEmpty);
    });
  });
}
