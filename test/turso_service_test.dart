import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openstock/services/turso_service.dart';

void main() {
  test('converte URL libsql, envia bearer e decodifica linhas', () async {
    late http.Request request;
    final client = MockClient((received) async {
      request = received;
      return http.Response(
        jsonEncode({
          'results': [
            {
              'type': 'ok',
              'response': {
                'type': 'execute',
                'result': {
                  'cols': [
                    {'name': 'symbol'}
                  ],
                  'rows': [
                    [
                      {'type': 'text', 'value': 'PRIO3'}
                    ]
                  ],
                  'affected_row_count': 0,
                }
              }
            },
            {
              'type': 'ok',
              'response': {'type': 'close'}
            }
          ]
        }),
        200,
      );
    });
    final service = TursoService(client: client)
      ..configure('libsql://openstock-user.turso.io', 'secret');

    final rows = await service.execute(
      const TursoStatement('SELECT ? AS symbol', ['PRIO3']),
    );

    expect(
        request.url.toString(), 'https://openstock-user.turso.io/v2/pipeline');
    expect(request.headers['authorization'], 'Bearer secret');
    expect(rows.single['symbol'], 'PRIO3');
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    final requests = body['requests'] as List<dynamic>;
    expect(requests, hasLength(2));
  });
}
