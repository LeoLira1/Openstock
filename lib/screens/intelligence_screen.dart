import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../controllers/portfolio_controller.dart';
import '../models/investment_asset.dart';
import '../models/tracking_analytics.dart';

const _green = Color(0xFF39E58C);
const _red = Color(0xFFFF6B78);
const _muted = Color(0xFF93A4BC);

class IntelligenceScreen extends StatefulWidget {
  const IntelligenceScreen({
    super.key,
    required this.controller,
    required this.active,
  });

  final PortfolioController controller;
  final bool active;

  @override
  State<IntelligenceScreen> createState() => _IntelligenceScreenState();
}

class _IntelligenceScreenState extends State<IntelligenceScreen> {
  late int year;

  @override
  void initState() {
    super.initState();
    year = DateTime.now().year;
    if (widget.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  @override
  void didUpdateWidget(covariant IntelligenceScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  Future<void> _load() => widget.controller.loadIntelligence(year);

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final report = controller.annualTrackingReport;
    final firstYear = controller.assets
        .map(controller.trackingStartFor)
        .whereType<DateTime>()
        .map((date) => date.year)
        .fold(DateTime.now().year, (a, b) => a < b ? a : b);
    final lastYear = DateTime.now().year + 1;
    final years = [for (var value = firstYear; value <= lastYear; value++) value];

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 110),
        children: [
          const Text('Inteligência',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text(
            'Sua jornada, o CDI e o resultado real sem confundir aportes com rendimento.',
            style: TextStyle(color: _muted),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            initialValue: year,
            decoration: const InputDecoration(
              labelText: 'Relatório anual',
              prefixIcon: Icon(Icons.calendar_month_outlined),
            ),
            items: years
                .map((value) => DropdownMenuItem(
                      value: value,
                      child: Text('Ano $value'),
                    ))
                .toList(),
            onChanged: controller.intelligenceLoading ? null : (value) {
              if (value == null || value == year) return;
              setState(() => year = value);
              _load();
            },
          ),
          if (controller.intelligenceLoading) ...[
            const SizedBox(height: 14),
            const LinearProgressIndicator(minHeight: 3),
            const SizedBox(height: 8),
            const Text(
              'Conferindo operações, fechamentos, câmbio e CDI…',
              style: TextStyle(color: _muted, fontSize: 12),
            ),
          ],
          const SizedBox(height: 18),
          if (report != null) _AnnualReportCard(report: report),
          if (controller.intelligenceError != null) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  controller.intelligenceError!,
                  style: const TextStyle(color: _muted),
                ),
              ),
            ),
          ],
          const SizedBox(height: 22),
          const Text('Jornada dos ativos',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text(
            'Desde o início do rastreamento, independentemente do ano escolhido.',
            style: TextStyle(color: _muted, fontSize: 12),
          ),
          const SizedBox(height: 10),
          for (final asset in controller.assets)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _AssetJourneyCard(
                asset: asset,
                summary: controller.trackingSummaryFor(asset),
              ),
            ),
        ],
      ),
    );
  }
}

class _AnnualReportCard extends StatelessWidget {
  const _AnnualReportCard({required this.report});

  final AnnualTrackingReport report;

  @override
  Widget build(BuildContext context) {
    final ahead = report.beatsCdi;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Balanço de ${report.year}',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 3),
            Text(
              '${_date(report.start)} a ${_date(report.end)} • '
              '${report.snapshotCount} dias registrados',
              style: const TextStyle(color: _muted, fontSize: 11),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 18,
              runSpacing: 14,
              children: [
                _value('Patrimônio inicial', _brl.format(report.initialValueBrl)),
                _value('Patrimônio final', _brl.format(report.finalValueBrl)),
                _value('Compras', _brl.format(report.purchasesBrl)),
                _value('Vendas', _brl.format(report.salesBrl)),
                _value('Proventos', _brl.format(report.incomeBrl), color: _green),
                _value(
                  'Lucro real',
                  _signedMoney(report.profitBrl),
                  color: report.profitBrl >= 0 ? _green : _red,
                ),
              ],
            ),
            const Divider(height: 28),
            _comparisonLine(
              'Minha carteira',
              report.returnPercent,
              report.returnPercent >= 0 ? _green : _red,
            ),
            const SizedBox(height: 7),
            _comparisonLine('CDI', report.cdiPercent, Colors.white),
            const SizedBox(height: 10),
            Text(
              '${_points(report.differencePoints)} '
              '${ahead ? 'acima' : 'abaixo'} do CDI',
              style: TextStyle(
                color: ahead ? _green : _red,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _value(String label, String value, {Color? color}) => SizedBox(
        width: 135,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(color: _muted, fontSize: 11)),
            const SizedBox(height: 3),
            Text(value,
                style: TextStyle(color: color, fontWeight: FontWeight.w800)),
          ],
        ),
      );

  Widget _comparisonLine(String label, double value, Color color) => Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(color: _muted))),
          Text(_percent(value),
              style: TextStyle(color: color, fontWeight: FontWeight.w800)),
        ],
      );
}

class _AssetJourneyCard extends StatelessWidget {
  const _AssetJourneyCard({required this.asset, required this.summary});

  final InvestmentAsset asset;
  final AssetTrackingSummary? summary;

  @override
  Widget build(BuildContext context) {
    final data = summary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: data == null
            ? Row(
                children: [
                  Expanded(
                    child: Text(asset.symbol,
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                  const Text('Aguardando histórico',
                      style: TextStyle(color: _muted, fontSize: 12)),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(asset.symbol,
                                style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800)),
                            Text(
                              'Desde ${_date(data.start)} • '
                              '${data.snapshotCount} fechamentos',
                              style: const TextStyle(
                                  color: _muted, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        _percent(data.returnPercent),
                        style: TextStyle(
                          color: data.returnPercent >= 0 ? _green : _red,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 13),
                  Row(
                    children: [
                      Expanded(
                        child: _smallMetric(
                          'CDI no período',
                          _percent(data.cdiPercent),
                        ),
                      ),
                      Expanded(
                        child: _smallMetric(
                          'Diferença',
                          _points(data.differencePoints),
                          color: data.beatsCdi ? _green : _red,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: (data.isUnderwater ? _red : _green)
                          .withValues(alpha: .10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      data.isUnderwater
                          ? 'No prejuízo há ${data.currentUnderwaterDays} dias • '
                              'maior sequência: ${data.longestUnderwaterDays} dias'
                          : 'Fora do prejuízo • maior sequência negativa: '
                              '${data.longestUnderwaterDays} dias',
                      style: TextStyle(
                        color: data.isUnderwater ? _red : _green,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _smallMetric(String label, String value, {Color? color}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: _muted, fontSize: 10)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(color: color, fontWeight: FontWeight.w800)),
        ],
      );
}

final _brl =
    NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$', decimalDigits: 2);
String _date(DateTime value) => DateFormat('dd/MM/yyyy').format(value);
String _signedMoney(double value) =>
    '${value >= 0 ? '+' : '-'}${_brl.format(value.abs())}';
String _percent(double value) =>
    '${value >= 0 ? '+' : ''}${value.toStringAsFixed(2).replaceAll('.', ',')}%';
String _points(double value) =>
    '${value >= 0 ? '+' : ''}${value.toStringAsFixed(2).replaceAll('.', ',')} p.p.';
