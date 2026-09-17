import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/history_models.dart';
import 'quote_service.dart' show QuoteException;

/// Série 12 do SGS: taxa diária do CDI, em % ao dia útil.
const _cdiSeriesId = 12;

/// Leitura da taxa diária do CDI direto do Banco Central.
///
/// Apenas dias efetivamente publicados são retornados; fins de semana,
/// feriados e dias sem divulgação continuam ausentes da série.
class CdiService {
  CdiService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<List<CdiRate>> fetchDailyRates({
    required DateTime start,
    DateTime? end,
  }) async {
    final last = end ?? DateTime.now();
    if (last.isBefore(start)) return const [];
    // As datas vêm normalizadas em dia local, então servem de chave direta.
    final rates = <DateTime, CdiRate>{};
    // O SGS recusa janelas muito longas; a série vem em blocos de dez anos.
    var windowStart = start;
    while (!windowStart.isAfter(last)) {
      final limit =
          DateTime(windowStart.year + 10, windowStart.month, windowStart.day);
      final windowEnd = limit.isBefore(last) ? limit : last;
      for (final rate in await _fetchWindow(windowStart, windowEnd)) {
        rates[rate.date] = rate;
      }
      if (!windowEnd.isBefore(last)) break;
      windowStart =
          DateTime(windowEnd.year, windowEnd.month, windowEnd.day + 1);
    }
    return rates.values.toList()..sort((a, b) => a.date.compareTo(b.date));
  }

  Future<List<CdiRate>> _fetchWindow(DateTime start, DateTime end) async {
    final uri = Uri.https(
      'api.bcb.gov.br',
      '/dados/serie/bcdata.sgs.$_cdiSeriesId/dados',
      {
        'formato': 'json',
        'dataInicial': _bcbDate(start),
        'dataFinal': _bcbDate(end),
      },
    );
    late final http.Response response;
    try {
      response = await _client
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 20));
    } catch (error) {
      throw QuoteException(
        'Falha de rede ao acessar api.bcb.gov.br (${error.runtimeType})',
      );
    }
    if (response.statusCode != 200) {
      throw QuoteException(
        'Banco Central respondeu ${response.statusCode} para o CDI',
      );
    }
    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      throw const QuoteException(
        'Resposta ilegível do Banco Central para a série do CDI',
      );
    }
    if (decoded is! List) {
      throw const QuoteException(
        'Resposta inesperada do Banco Central para a série do CDI',
      );
    }
    final rates = <CdiRate>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      final date = _parseBcbDate(item['data']?.toString());
      final value = double.tryParse(
        (item['valor']?.toString() ?? '').trim().replaceAll(',', '.'),
      );
      if (date == null || value == null) continue;
      rates.add(CdiRate(date: date, dailyPercent: value));
    }
    return rates;
  }
}

String _bcbDate(DateTime date) => '${date.day.toString().padLeft(2, '0')}/'
    '${date.month.toString().padLeft(2, '0')}/'
    '${date.year.toString().padLeft(4, '0')}';

DateTime? _parseBcbDate(String? raw) {
  final parts = raw?.split('/');
  if (parts == null || parts.length != 3) return null;
  final day = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  final year = int.tryParse(parts[2]);
  if (day == null || month == null || year == null) return null;
  return DateTime(year, month, day);
}
