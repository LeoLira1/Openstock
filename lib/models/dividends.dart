import 'investment_transaction.dart';

/// Provento anunciado pela empresa, como publicado pela B3.
class DividendAnnouncement {
  const DividendAnnouncement({
    required this.symbol,
    required this.label,
    required this.rate,
    required this.paymentDate,
    this.recordDate,
    this.exDate,
  });

  final String symbol;

  /// "DIVIDENDO", "JCP", "RENDIMENTO"…
  final String label;

  /// Valor bruto por ação ou cota, em reais.
  final double rate;
  final DateTime paymentDate;

  /// Data-com: quem tinha o papel no fim desse dia recebe.
  final DateTime? recordDate;
  final DateTime? exDate;

  bool get isInterestOnCapital {
    final upper = label.toUpperCase();
    // A B3 escreve "JRS CAP PROPRIO"; a brapi, "JCP".
    return upper.contains('JCP') ||
        upper.contains('JUROS') ||
        upper.contains('JRS');
  }

  String get displayLabel {
    final upper = label.toUpperCase();
    if (isInterestOnCapital) return 'JCP';
    if (upper.contains('RENDIMENTO')) return 'Rendimento';
    if (upper.contains('DIVIDENDO')) return 'Dividendo';
    if (upper.contains('AMORTIZA')) return 'Amortização';
    return label.isEmpty
        ? 'Provento'
        : label[0].toUpperCase() + label.substring(1).toLowerCase();
  }

  Map<String, Object?> toJson() => {
        'symbol': symbol,
        'label': label,
        'rate': rate,
        'paymentDate': _dateKey(paymentDate),
        'recordDate': recordDate == null ? null : _dateKey(recordDate!),
        'exDate': exDate == null ? null : _dateKey(exDate!),
      };

  static DividendAnnouncement fromJson(Map<String, dynamic> json) =>
      DividendAnnouncement(
        symbol: json['symbol'] as String,
        label: json['label'] as String? ?? '',
        rate: (json['rate'] as num).toDouble(),
        paymentDate: DateTime.parse(json['paymentDate'] as String),
        recordDate: json['recordDate'] == null
            ? null
            : DateTime.parse(json['recordDate'] as String),
        exDate: json['exDate'] == null
            ? null
            : DateTime.parse(json['exDate'] as String),
      );
}

/// Lê a lista `cashDividends` do cadastro público da B3 para [symbol].
///
/// A B3 devolve os proventos de todas as classes da empresa (ON, PN, units,
/// recibos de subscrição…); só ficam os do código ISIN que corresponde ao
/// papel. Datas vêm como `dd/MM/yyyy` e valores com vírgula decimal.
List<DividendAnnouncement> parseB3Dividends(
  String symbol,
  Map<String, dynamic> company,
) {
  final rows = company['cashDividends'] as List<dynamic>? ?? const [];
  final seen = <String>{};
  final parsed = <DividendAnnouncement>[];
  for (final item in rows) {
    if (item is! Map<String, dynamic>) continue;
    final isin = item['isinCode']?.toString() ?? '';
    if (!b3IsinMatchesSymbol(isin, symbol)) continue;
    final rate = double.tryParse(
      (item['rate']?.toString() ?? '').replaceAll('.', '').replaceAll(',', '.'),
    );
    final payment = _brDate(item['paymentDate']);
    if (rate == null || rate <= 0 || payment == null) continue;
    final announcement = DividendAnnouncement(
      symbol: symbol,
      label: (item['label']?.toString() ?? '').trim(),
      rate: rate,
      paymentDate: payment,
      recordDate: _brDate(item['lastDatePrior']),
    );
    final key = '${announcement.label}|${announcement.rate}|'
        '${_dateKey(payment)}|${announcement.recordDate}';
    if (seen.add(key)) parsed.add(announcement);
  }
  return parsed;
}

/// Diz se o ISIN é da classe negociada com [symbol].
///
/// O número do código da B3 indica a classe: 3 = ON (`ACNOR`), 4 = PN
/// (`ACNPR`), 5 a 8 = PNA a PND, 11 = unit (`CDAM`) ou cota de fundo (`CTF`).
bool b3IsinMatchesSymbol(String isin, String symbol) {
  final match = RegExp(r'^[A-Z0-9]{4}(\d{1,2})F?$').firstMatch(
    symbol.trim().toUpperCase(),
  );
  if (match == null || isin.length < 11) return false;
  final code = isin.substring(6, 11);
  return switch (match.group(1)) {
    '3' => code == 'ACNOR',
    '4' => code == 'ACNPR',
    '5' => code == 'ACNPA',
    '6' => code == 'ACNPB',
    '7' => code == 'ACNPC',
    '8' => code == 'ACNPD',
    '11' => code.startsWith('CDAM') || code.startsWith('CTF'),
    _ => false,
  };
}

DateTime? _brDate(Object? value) {
  final parts = value?.toString().split('/');
  if (parts == null || parts.length != 3) return null;
  final day = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  final year = int.tryParse(parts[2]);
  if (day == null || month == null || year == null) return null;
  return DateTime(year, month, day);
}

/// Quanto um provento anunciado vai render na sua carteira.
class UpcomingDividend {
  const UpcomingDividend({
    required this.announcement,
    required this.assetKey,
    required this.quantity,
    required this.estimated,
  });

  final DividendAnnouncement announcement;
  final String assetKey;

  /// Quantidade que dá direito ao provento.
  final double quantity;

  /// A quantidade é uma estimativa: a data-com ainda não chegou ou é
  /// anterior ao início do rastreamento.
  final bool estimated;

  double get grossBrl => announcement.rate * quantity;
}

/// Proventos com pagamento a partir de [today] e o valor para a sua posição.
///
/// A quantidade é a da data-com, calculada pelas operações registradas. Se a
/// data-com é anterior ao início do rastreamento, vale a posição inicial (a
/// carteira já existia antes de ser cadastrada); se ainda não chegou, vale a
/// posição atual. Nos dois casos o valor é marcado como estimado.
List<UpcomingDividend> projectUpcomingDividends({
  required String assetKey,
  required List<DividendAnnouncement> announcements,
  required List<InvestmentTransaction> transactions,
  required double currentQuantity,
  required DateTime today,
}) {
  final day = _day(today);
  final active = transactions.where((item) => item.deletedAt == null).toList()
    ..sort((a, b) => a.transactionDate.compareTo(b.transactionDate));
  final trackingStart =
      active.isEmpty ? null : _day(active.first.transactionDate);
  final upcoming = <UpcomingDividend>[];
  for (final announcement in announcements) {
    if (announcement.paymentDate.isBefore(day)) continue;
    final record = announcement.recordDate;
    double quantity;
    var estimated = false;
    if (record == null || record.isAfter(day)) {
      quantity = currentQuantity;
      estimated = true;
    } else if (trackingStart == null || record.isBefore(trackingStart)) {
      quantity = trackingStart == null
          ? currentQuantity
          : calculateTrackedPosition(active.where(
                  (item) => !_day(item.transactionDate).isAfter(trackingStart)))
              .quantity;
      estimated = true;
    } else {
      quantity = calculateTrackedPosition(active.where(
          (item) => !_day(item.transactionDate).isAfter(record))).quantity;
    }
    if (quantity <= 0) continue;
    upcoming.add(UpcomingDividend(
      announcement: announcement,
      assetKey: assetKey,
      quantity: quantity,
      estimated: estimated,
    ));
  }
  return upcoming;
}

DateTime _day(DateTime value) => DateTime(value.year, value.month, value.day);

String _dateKey(DateTime value) => '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
