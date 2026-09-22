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

  bool get isInterestOnCapital =>
      label.toUpperCase().contains('JCP') ||
      label.toUpperCase().contains('JUROS');

  String get displayLabel {
    final upper = label.toUpperCase();
    if (isInterestOnCapital) return 'JCP';
    if (upper.contains('RENDIMENTO')) return 'Rendimento';
    if (upper.contains('DIVIDENDO')) return 'Dividendo';
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

/// Lê `dividendsData.cashDividends` de um resultado da brapi.
///
/// As datas chegam como meia-noite de Brasília em UTC (`T03:00:00.000Z`);
/// elas viram o dia do calendário da B3, independentemente do fuso do
/// aparelho. Linhas repetidas, que a fonte às vezes devolve, são descartadas.
List<DividendAnnouncement> parseBrapiDividends(
  String symbol,
  Map<String, dynamic> result,
) {
  final data = result['dividendsData'];
  final rows = data is Map<String, dynamic>
      ? data['cashDividends'] as List<dynamic>? ?? const []
      : const [];
  final seen = <String>{};
  final parsed = <DividendAnnouncement>[];
  for (final item in rows) {
    if (item is! Map<String, dynamic>) continue;
    final rate = (item['rate'] as num?)?.toDouble();
    final payment = _b3Day(item['paymentDate']);
    if (rate == null || rate <= 0 || payment == null) continue;
    final announcement = DividendAnnouncement(
      symbol: symbol,
      label: (item['label'] as String? ?? '').trim(),
      rate: rate,
      paymentDate: payment,
      recordDate: _b3Day(item['lastDatePrior']),
      exDate: _b3Day(item['exDate']),
    );
    final key = '${announcement.label}|${announcement.rate}|'
        '${_dateKey(payment)}|${announcement.recordDate}';
    if (seen.add(key)) parsed.add(announcement);
  }
  return parsed;
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

DateTime? _b3Day(Object? value) {
  if (value is! String || value.isEmpty) return null;
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return null;
  final brasilia = parsed.toUtc().subtract(const Duration(hours: 3));
  return DateTime(brasilia.year, brasilia.month, brasilia.day);
}

DateTime _day(DateTime value) => DateTime(value.year, value.month, value.day);

String _dateKey(DateTime value) => '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
