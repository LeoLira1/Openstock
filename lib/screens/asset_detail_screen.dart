import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../controllers/portfolio_controller.dart';
import '../models/fixed_income.dart';
import '../models/history_models.dart';
import '../models/investment_asset.dart';
import '../models/investment_transaction.dart';
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
          if (!asset.isFixedIncome)
            IconButton(
              tooltip: 'Registrar operação',
              onPressed: () => _showTransactionSheet(context, asset),
              icon: const Icon(Icons.receipt_long_outlined),
            ),
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
            _TrackingCard(
              asset: asset,
              controller: widget.controller,
              onAdd: asset.isFixedIncome
                  ? null
                  : () => _showTransactionSheet(context, asset),
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

  Future<void> _showTransactionSheet(
    BuildContext context,
    InvestmentAsset asset,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TransactionSheet(
        controller: widget.controller,
        asset: asset,
      ),
    );
  }
}

class _TrackingCard extends StatelessWidget {
  const _TrackingCard({
    required this.asset,
    required this.controller,
    required this.onAdd,
  });

  final InvestmentAsset asset;
  final PortfolioController controller;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final transactions = controller.transactionsFor(asset);
    final start = controller.trackingStartFor(asset);
    final income = controller.incomeFor(asset);
    final realized = controller.realizedResultFor(asset);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.route_outlined, color: _green),
                const SizedBox(width: 9),
                const Expanded(
                  child: Text(
                    'Meu rastreamento',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                ),
                if (onAdd != null)
                  TextButton.icon(
                    onPressed: onAdd,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Operação'),
                  ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              start == null
                  ? 'O rastreamento começará na próxima atualização.'
                  : 'Acompanhando desde ${DateFormat('dd/MM/yyyy').format(start)}',
              style: const TextStyle(color: _muted, fontSize: 12),
            ),
            if (income != 0 || realized != 0) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  Text('Proventos ${_brl.format(income)}',
                      style: const TextStyle(
                          color: _green, fontWeight: FontWeight.w700)),
                  Text('Resultado realizado ${_signedMoney(realized)}',
                      style: TextStyle(
                          color: realized >= 0 ? _green : _red,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ],
            const SizedBox(height: 12),
            if (transactions.isEmpty)
              const Text('Nenhuma operação registrada.',
                  style: TextStyle(color: _muted))
            else
              ...transactions.map(
                (transaction) => _TransactionRow(
                  asset: asset,
                  transaction: transaction,
                  controller: controller,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({
    required this.asset,
    required this.transaction,
    required this.controller,
  });

  final InvestmentAsset asset;
  final InvestmentTransaction transaction;
  final PortfolioController controller;

  @override
  Widget build(BuildContext context) {
    final color = switch (transaction.type) {
      InvestmentTransactionType.sale => _red,
      InvestmentTransactionType.openingPosition => _muted,
      _ => _green,
    };
    final value = transaction.type.isIncome
        ? transaction.cashValue
        : transaction.grossValue;
    final formatter = asset.currency == AssetCurrency.usd ? _usd : _brl;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFF213047))),
      ),
      child: Row(
        children: [
          Icon(
            transaction.type.isIncome
                ? Icons.payments_outlined
                : transaction.type == InvestmentTransactionType.sale
                    ? Icons.remove_circle_outline
                    : Icons.add_circle_outline,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(transaction.type.label,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(
                  DateFormat('dd/MM/yyyy').format(transaction.transactionDate),
                  style: const TextStyle(color: _muted, fontSize: 11),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(formatter.format(value),
                  style: TextStyle(color: color, fontWeight: FontWeight.w700)),
              if (transaction.type.changesPosition)
                Text('${_quantity(transaction.quantity)} cotas',
                    style: const TextStyle(color: _muted, fontSize: 11)),
            ],
          ),
          if (transaction.type != InvestmentTransactionType.openingPosition)
            IconButton(
              tooltip: 'Excluir operação',
              icon: const Icon(Icons.delete_outline, size: 19),
              onPressed: () => _deleteTransaction(context),
            ),
        ],
      ),
    );
  }

  Future<void> _deleteTransaction(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir operação?'),
        content: const Text(
          'A posição e o preço médio serão recalculados com o histórico restante.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final error = await controller.deleteTransaction(asset, transaction);
    if (error != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    }
  }
}

class _TransactionSheet extends StatefulWidget {
  const _TransactionSheet({required this.controller, required this.asset});

  final PortfolioController controller;
  final InvestmentAsset asset;

  @override
  State<_TransactionSheet> createState() => _TransactionSheetState();
}

class _TransactionSheetState extends State<_TransactionSheet> {
  InvestmentTransactionType type = InvestmentTransactionType.purchase;
  DateTime date = DateTime.now();
  final quantity = TextEditingController();
  final price = TextEditingController();
  final fees = TextEditingController(text: '0');
  final cashValue = TextEditingController();
  final exchangeRate = TextEditingController();
  final notes = TextEditingController();
  bool saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.asset.currency == AssetCurrency.usd &&
        widget.controller.usdBrl > 0) {
      exchangeRate.text = widget.controller.usdBrl.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    quantity.dispose();
    price.dispose();
    fees.dispose();
    cashValue.dispose();
    exchangeRate.dispose();
    notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final income = type.isIncome;
    return Material(
      color: _ink,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          18,
          20,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Registrar em ${widget.asset.symbol}',
                style:
                    const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            DropdownButtonFormField<InvestmentTransactionType>(
              initialValue: type,
              decoration: const InputDecoration(labelText: 'Tipo de operação'),
              items: const [
                InvestmentTransactionType.purchase,
                InvestmentTransactionType.sale,
                InvestmentTransactionType.dividend,
                InvestmentTransactionType.interestOnCapital,
              ]
                  .map((value) =>
                      DropdownMenuItem(value: value, child: Text(value.label)))
                  .toList(),
              onChanged: (value) => setState(() => type = value!),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.event_outlined),
              label: Text(DateFormat('dd/MM/yyyy').format(date)),
            ),
            const SizedBox(height: 12),
            if (income)
              _numberField(cashValue, 'Valor recebido')
            else ...[
              _numberField(quantity, 'Quantidade'),
              const SizedBox(height: 12),
              _numberField(price, 'Preço por cota'),
              const SizedBox(height: 12),
              _numberField(fees, 'Taxas e corretagem'),
            ],
            if (widget.asset.currency == AssetCurrency.usd) ...[
              const SizedBox(height: 12),
              _numberField(exchangeRate, 'Dólar da operação (R\$)'),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: notes,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Observação opcional',
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: saving ? null : _save,
              icon: saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: const Text('Salvar operação'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _numberField(TextEditingController controller, String label) =>
      TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label),
      );

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => date = picked);
  }

  Future<void> _save() async {
    setState(() => saving = true);
    final error = await widget.controller.recordTransaction(
      asset: widget.asset,
      type: type,
      date: date,
      quantity: _parse(quantity.text),
      unitPrice: _parse(price.text),
      fees: _parse(fees.text),
      cashValue: _parse(cashValue.text),
      exchangeRate: widget.asset.currency == AssetCurrency.usd
          ? _parse(exchangeRate.text)
          : 1,
      notes: notes.text,
    );
    if (!mounted) return;
    if (error == null) {
      Navigator.pop(context);
    } else {
      setState(() => saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    }
  }
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
double _parse(String value) {
  final clean = value.trim();
  if (clean.isEmpty) return 0;
  return double.tryParse(clean.contains(',')
          ? clean.replaceAll('.', '').replaceAll(',', '.')
          : clean) ??
      0;
}
