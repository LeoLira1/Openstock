import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;

import '../controllers/portfolio_controller.dart';
import '../models/dividends.dart';

const _green = Color(0xFF39E58C);
const _muted = Color(0xFF93A4BC);
const _amber = Color(0xFFFFC857);

/// Resumo dos proventos anunciados para a carteira, na tela inicial.
class UpcomingDividendsCard extends StatelessWidget {
  const UpcomingDividendsCard({super.key, required this.controller});

  final PortfolioController controller;

  static const _preview = 5;

  @override
  Widget build(BuildContext context) {
    final items = controller.upcomingDividends;
    final total = items.fold<double>(0, (sum, item) => sum + item.grossBrl);
    final soon = DateTime.now().add(const Duration(days: 30));
    final nextMonth = items
        .where((item) => !item.announcement.paymentDate.isAfter(soon))
        .fold<double>(0, (sum, item) => sum + item.grossBrl);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('A RECEBER',
                          style: TextStyle(
                              color: _muted, fontSize: 11, letterSpacing: 1.1)),
                      const SizedBox(height: 4),
                      Text(
                        _money(total),
                        style: const TextStyle(
                          color: _green,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (items.isNotEmpty)
                        Text(
                          '${_money(nextMonth)} nos próximos 30 dias • '
                          '${items.length} pagamento${items.length == 1 ? '' : 's'}',
                          style: const TextStyle(color: _muted, fontSize: 12),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Atualizar proventos',
                  onPressed: controller.dividendsLoading
                      ? null
                      : () => controller.loadUpcomingDividends(force: true),
                  icon: controller.dividendsLoading
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded, color: _muted),
                ),
              ],
            ),
            if (controller.dividendsMessage != null) ...[
              const SizedBox(height: 8),
              Text(controller.dividendsMessage!,
                  style: const TextStyle(color: _amber, fontSize: 12)),
            ],
            const SizedBox(height: 8),
            if (items.isEmpty && !controller.dividendsLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Nenhum provento anunciado para os seus ativos da B3.',
                  style: TextStyle(color: _muted),
                ),
              ),
            for (final item in items.take(_preview))
              _DividendRow(item: item, controller: controller),
            if (items.length > _preview)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          UpcomingDividendsScreen(controller: controller),
                    ),
                  ),
                  child: Text('Ver todos (${items.length})'),
                ),
              ),
            const Padding(
              padding: EdgeInsets.only(top: 4, bottom: 6),
              child: Text(
                'Valores brutos anunciados na B3. JCP tem imposto retido na '
                'fonte. "Estimado" usa a posição atual ou inicial.',
                style: TextStyle(color: _muted, fontSize: 10.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Todos os proventos a receber, agrupados por mês de pagamento.
class UpcomingDividendsScreen extends StatelessWidget {
  const UpcomingDividendsScreen({super.key, required this.controller});

  final PortfolioController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final items = controller.upcomingDividends;
        final byMonth = <DateTime, List<UpcomingDividend>>{};
        for (final item in items) {
          final date = item.announcement.paymentDate;
          byMonth
              .putIfAbsent(DateTime(date.year, date.month), () => [])
              .add(item);
        }
        return Scaffold(
          appBar: AppBar(title: const Text('Proventos a receber')),
          body: RefreshIndicator(
            onRefresh: () => controller.loadUpcomingDividends(force: true),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
              children: [
                for (final entry in byMonth.entries) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _capitalize(DateFormat('MMMM yyyy', 'pt_BR')
                                .format(entry.key)),
                            style: const TextStyle(
                                fontSize: 17, fontWeight: FontWeight.w800),
                          ),
                        ),
                        Text(
                          _money(entry.value.fold<double>(
                              0, (sum, item) => sum + item.grossBrl)),
                          style: const TextStyle(
                              color: _green, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 4),
                      child: Column(
                        children: [
                          for (final item in entry.value)
                            _DividendRow(item: item, controller: controller),
                        ],
                      ),
                    ),
                  ),
                ],
                if (items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Nenhum provento anunciado para os seus ativos da B3.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _muted),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DividendRow extends StatelessWidget {
  const _DividendRow({required this.item, required this.controller});

  final UpcomingDividend item;
  final PortfolioController controller;

  @override
  Widget build(BuildContext context) {
    final a = item.announcement;
    final record = a.recordDate;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Container(
            width: 46,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: _green.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                Text(
                  a.paymentDate.day.toString().padLeft(2, '0'),
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 16, height: 1.1),
                ),
                Text(
                  DateFormat('MMM', 'pt_BR')
                      .format(a.paymentDate)
                      .replaceAll('.', '')
                      .toUpperCase(),
                  style: const TextStyle(color: _muted, fontSize: 10),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        '${a.symbol} · ${a.displayLabel}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    if (item.estimated) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          border:
                              Border.all(color: _amber.withValues(alpha: .6)),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('estimado',
                            style: TextStyle(color: _amber, fontSize: 9.5)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${_quantity(item.quantity)} × ${_rate(a.rate)}'
                  '${record == null ? '' : ' • data-com ${DateFormat('dd/MM/yy').format(record)}'}',
                  style: const TextStyle(color: _muted, fontSize: 11.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _money(item.grossBrl),
            style: const TextStyle(
                color: _green, fontWeight: FontWeight.w800, fontSize: 15),
          ),
        ],
      ),
    );
  }
}

final _brl =
    NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$', decimalDigits: 2);
String _money(double value) => _brl.format(value);
String _rate(double value) => NumberFormat.currency(
      locale: 'pt_BR',
      symbol: 'R\$',
      decimalDigits: value < 0.1 ? 6 : 4,
    ).format(value);
String _quantity(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : NumberFormat.decimalPattern('pt_BR').format(value);
String _capitalize(String value) =>
    value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);
