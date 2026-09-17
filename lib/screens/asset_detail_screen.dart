import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../controllers/portfolio_controller.dart';
import '../models/fixed_income.dart';
import '../models/history_models.dart';
import '../models/investment_asset.dart';
import '../widgets/interactive_history_chart.dart';

const _ink = Color(0xFF0B1220);
const _green = Color(0xFF39E58C);
const _red = Color(0xFFFF6B78);
const _muted = Color(0xFF93A4BC);

enum AssetChartMode { price, relativeAverage }

class AssetDetailScreen extends StatefulWidget {
  const AssetDetailScreen({
    super.key,
    required this.controller,
    required this.asset,
    required this.onEdit,
  });

  final PortfolioController controller;
  final InvestmentAsset asset;
  final Future<void> Function() onEdit;

  @override
  State<AssetDetailScreen> createState() => _AssetDetailScreenState();
}

class _AssetDetailScreenState extends State<AssetDetailScreen> {
  HistoryPeriod period = HistoryPeriod.oneMonth;
  AssetChartMode mode = AssetChartMode.price;
  DateTime? selectedDate;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_controllerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_controllerChanged);
    super.dispose();
  }

  void _controllerChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _edit() async {
    await widget.onEdit();
    if (!mounted) return;
    final stillExists = widget.controller.assets
        .any((asset) => asset.syncKey == widget.asset.syncKey);
    if (!stillExists) Navigator.pop(context);
  }

  Future<void> _load() async {
    await widget.controller.ensureHistory(widget.asset, period);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final asset = widget.controller.assets.firstWhere(
      (item) => item.syncKey == widget.asset.syncKey,
      orElse: () => widget.asset,
    );
    final start = period.startFrom(DateTime.now());
    final raw = (widget.controller.assetHistories[asset.syncKey] ?? const [])
        .where((point) => start == null || !point.date.isBefore(start))
        .toList();
    final points = mode == AssetChartMode.price
        ? raw
        : relativeToAverage(raw, asset.averagePrice);
    final accrued = widget.controller.assetHistories[asset.syncKey] ?? const [];
    final position = asset.isFixedIncome
        ? fixedIncomePosition(asset: asset, accrued: accrued)
        : null;
    final selectedPoint =
        selectedDate == null ? null : pointOnOrBefore(points, selectedDate!);
    final currency = asset.currency == AssetCurrency.brl ? _brl : _usd;

    return Scaffold(
      backgroundColor: _ink,
      appBar: AppBar(
        backgroundColor: _ink,
        title: Text(asset.symbol),
        actions: [
          IconButton(
            tooltip: 'Editar ativo',
            onPressed: _edit,
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          children: [
            Text(asset.name,
                style: const TextStyle(color: _muted, fontSize: 15)),
            const SizedBox(height: 8),
            Text(
              currency.format(asset.currentPrice ?? asset.averagePrice),
              style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800),
            ),
            Text(
              'Hoje ${_signedPercent(widget.controller.assetDayPercent(asset))}',
              style: TextStyle(
                color: widget.controller.assetDayResult(asset) >= 0
                    ? _green
                    : _red,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                if (asset.isFixedIncome) ...[
                  _metric('Indexador', fixedIncomeRateLabel(asset)),
                  _metric(
                    'Aplicado em',
                    asset.applicationDate == null
                        ? '—'
                        : DateFormat('dd/MM/yyyy').format(asset.applicationDate!),
                  ),
                ] else ...[
                  _metric('Quantidade', _quantity(asset.quantity)),
                  _metric('Preço médio', currency.format(asset.averagePrice)),
                ],
                _metric(
                    asset.isFixedIncome ? 'Valor aplicado' : 'Valor investido',
                    _brl.format(widget.controller.costValue(asset))),
                _metric(asset.isFixedIncome ? 'Valor bruto' : 'Valor atual',
                    _brl.format(widget.controller.currentValue(asset))),
                _metric(
                    asset.isFixedIncome ? 'Rendimento bruto' : 'Lucro/prejuízo',
                    _signedMoney(widget.controller.assetTotalResult(asset)),
                    positive: widget.controller.assetTotalResult(asset) >= 0),
                _metric('Resultado total',
                    _signedPercent(widget.controller.assetTotalPercent(asset)),
                    positive: widget.controller.assetTotalResult(asset) >= 0),
                if (position != null) ...[
                  _metric(
                    position.taxRate == 0
                        ? 'Líquido (isento)'
                        : 'Líquido (IR ${_plainPercent(position.taxRate)})',
                    _brl.format(position.netValue),
                  ),
                  _metric('Dias úteis rendendo', '${position.businessDays}'),
                ],
                if (asset.maturityDate != null)
                  _metric(
                    asset.isMatured ? 'Venceu em' : 'Vence em',
                    DateFormat('dd/MM/yyyy').format(asset.maturityDate!),
                  ),
              ],
            ),
            const SizedBox(height: 22),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<HistoryPeriod>(
                segments: HistoryPeriod.values
                    .map((value) =>
                        ButtonSegment(value: value, label: Text(value.label)))
                    .toList(),
                selected: {period},
                showSelectedIcon: false,
                onSelectionChanged: (value) {
                  setState(() {
                    period = value.first;
                    selectedDate = null;
                  });
                  _load();
                },
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<AssetChartMode>(
              segments: [
                ButtonSegment(
                    value: AssetChartMode.price,
                    label: Text(asset.isFixedIncome ? 'Valor' : 'Preço')),
                ButtonSegment(
                  value: AssetChartMode.relativeAverage,
                  label: Text(asset.isFixedIncome
                      ? 'Rentabilidade'
                      : 'vs. meu preço médio'),
                ),
              ],
              selected: {mode},
              onSelectionChanged: (value) => setState(() {
                mode = value.first;
                selectedDate = null;
              }),
            ),
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 270,
                      child: widget.controller
                                  .isHistoryLoading(asset.syncKey) &&
                              points.isEmpty
                          ? const Center(child: CircularProgressIndicator())
                          : points.length < 2
                              ? const Center(
                                  child: Text('Sem histórico suficiente.',
                                      style: TextStyle(color: _muted)))
                              : InteractiveHistoryChart(
                                  series: {asset.syncKey: points},
                                  colors: {asset.syncKey: _green},
                                  showZeroLine:
                                      mode == AssetChartMode.relativeAverage,
                                  horizontalReference:
                                      mode == AssetChartMode.price
                                          ? asset.averagePrice
                                          : null,
                                  onDateSelected: (date) =>
                                      setState(() => selectedDate = date),
                                ),
                    ),
                    const SizedBox(height: 10),
                    if (mode == AssetChartMode.price)
                      Row(children: [
                        Container(
                            width: 18,
                            height: 2,
                            color: const Color(0xFFFFC857)),
                        const SizedBox(width: 8),
                        Text(
                            asset.isFixedIncome
                                ? 'Valor aplicado: ${currency.format(asset.averagePrice)}'
                                : 'Meu preço médio: ${currency.format(asset.averagePrice)}',
                            style:
                                const TextStyle(color: _muted, fontSize: 12)),
                      ]),
                    if (asset.isFixedIncome && accrued.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Corrigido pelo CDI publicado até '
                        '${DateFormat('dd/MM/yyyy').format(accrued.last.date)}. '
                        'O Banco Central divulga a taxa com um dia de atraso.',
                        style: const TextStyle(color: _muted, fontSize: 12),
                      ),
                    ],
                    if (selectedPoint != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        '${DateFormat('dd/MM/yyyy').format(selectedPoint.date)}  •  '
                        '${mode == AssetChartMode.price ? currency.format(selectedPoint.value) : _signedPercent(selectedPoint.value)}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                    if (widget.controller.historyErrors[asset.syncKey] !=
                        null) ...[
                      const SizedBox(height: 10),
                      Text(widget.controller.historyErrors[asset.syncKey]!,
                          style: const TextStyle(color: _red, fontSize: 12)),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(String title, String value, {bool? positive}) => SizedBox(
        width: 165,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(color: _muted, fontSize: 11)),
                const SizedBox(height: 5),
                FittedBox(
                  child: Text(value,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: positive == null
                            ? null
                            : (positive ? _green : _red),
                      )),
                ),
              ],
            ),
          ),
        ),
      );
}

final _brl =
    NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$', decimalDigits: 2);
final _usd =
    NumberFormat.currency(locale: 'pt_BR', symbol: 'US\$', decimalDigits: 2);
String _signedMoney(double value) =>
    '${value >= 0 ? '+' : '-'}${_brl.format(value.abs())}';
String _signedPercent(double value) =>
    '${value >= 0 ? '+' : ''}${value.toStringAsFixed(2).replaceAll('.', ',')}%';
String _quantity(double value) =>
    NumberFormat.decimalPattern('pt_BR').format(value);
String _plainPercent(double value) =>
    '${value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1).replaceAll('.', ',')}%';
