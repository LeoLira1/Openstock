import 'dart:convert';

import 'package:http/http.dart' as http;

class TursoException implements Exception {
  const TursoException(this.message);
  final String message;
  @override
  String toString() => message;
}

class TursoStatement {
  const TursoStatement(this.sql, [this.args = const []]);
  final String sql;
  final List<Object?> args;
}

class TursoService {
  TursoService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  Uri? _endpoint;
  String? _token;

  bool get isConfigured => _endpoint != null && _token != null;

  void configure(String url, String token) {
    final cleanToken = token.trim();
    var cleanUrl = url.trim();
    cleanUrl = cleanUrl
        .replaceFirst(RegExp(r'^libsql://'), 'https://')
        .replaceFirst(RegExp(r'^turso://'), 'https://');
    final base = Uri.tryParse(cleanUrl);
    if (base == null || base.scheme != 'https' || base.host.isEmpty) {
      throw const TursoException('Use uma URL Turso/libSQL válida.');
    }
    if (cleanToken.isEmpty) {
      throw const TursoException('Informe o token de autenticação do Turso.');
    }
    _endpoint = base.replace(path: '/v2/pipeline', query: null, fragment: null);
    _token = cleanToken;
  }

  void clear() {
    _endpoint = null;
    _token = null;
  }

  Future<void> testConnection() async {
    await execute(const TursoStatement('SELECT 1 AS connected'));
  }

  Future<List<Map<String, Object?>>> execute(TursoStatement statement) async {
    final results = await executeBatch([statement]);
    return results.single;
  }

  Future<List<List<Map<String, Object?>>>> executeBatch(
    List<TursoStatement> statements,
  ) async {
    if (!isConfigured) {
      throw const TursoException('Turso não está configurado.');
    }
    final requests = <Map<String, Object?>>[
      for (final statement in statements)
        {
          'type': 'execute',
          'stmt': {
            'sql': statement.sql,
            if (statement.args.isNotEmpty)
              'args': statement.args.map(_encodeValue).toList(),
          },
        },
      {'type': 'close'},
    ];
    late final http.Response response;
    try {
      response = await _client
          .post(
            _endpoint!,
            headers: {
              'Authorization': 'Bearer $_token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'requests': requests}),
          )
          .timeout(const Duration(seconds: 25));
    } catch (error) {
      throw TursoException(
          'Falha de rede ao acessar o Turso (${error.runtimeType}).');
    }
    if (response.statusCode != 200) {
      throw TursoException('Turso respondeu ${response.statusCode}.');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final rawResults = body['results'] as List<dynamic>?;
    if (rawResults == null || rawResults.length < statements.length) {
      throw const TursoException('Resposta incompleta do Turso.');
    }
    final decoded = <List<Map<String, Object?>>>[];
    for (var i = 0; i < statements.length; i++) {
      final item = rawResults[i] as Map<String, dynamic>;
      if (item['type'] != 'ok') {
        final error = item['error'] as Map<String, dynamic>?;
        throw TursoException(
          error?['message']?.toString() ?? 'O Turso rejeitou uma operação.',
        );
      }
      final responseData = item['response'] as Map<String, dynamic>?;
      final result = responseData?['result'] as Map<String, dynamic>?;
      final columns = (result?['cols'] as List<dynamic>? ?? const [])
          .map((column) => (column as Map<String, dynamic>)['name'] as String)
          .toList();
      final rows = <Map<String, Object?>>[];
      for (final rawRow in result?['rows'] as List<dynamic>? ?? const []) {
        final values = rawRow as List<dynamic>;
        rows.add({
          for (var column = 0; column < columns.length; column++)
            columns[column]: _decodeValue(values[column]),
        });
      }
      decoded.add(rows);
    }
    return decoded;
  }

  Map<String, Object?> _encodeValue(Object? value) {
    if (value == null) return const {'type': 'null'};
    if (value is int) return {'type': 'integer', 'value': value.toString()};
    if (value is num) return {'type': 'float', 'value': value};
    return {'type': 'text', 'value': value.toString()};
  }

  Object? _decodeValue(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final type = raw['type'];
    final value = raw['value'];
    return switch (type) {
      'null' => null,
      'integer' => int.tryParse(value.toString()),
      'float' => value is num ? value.toDouble() : double.tryParse('$value'),
      'text' => value?.toString(),
      'blob' => value?.toString(),
      _ => value,
    };
  }
}
