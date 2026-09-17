import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../controllers/portfolio_controller.dart';
import '../models/history_models.dart';
import '../models/investment_asset.dart';
import '../widgets/interactive_history_chart.dart';

const _green = Color(0xFF39E58C);
const _red = Color(0xFFFF6B78);
const _muted = Color(0xFF93A4BC);
const _cdiColor = Color(0xFFCBD5E1);
const _portfolioKey = '__portfolio__';
const _cdiKey = cdiSeriesKey;
const _palette = <Color>[
  Color(0xFF39E58C),
  Color(0xFF5DA9FF),
  Color(0xFFFFC857),
  Color(0xFFFF6B78),
  Color(0xFFB98CFF),
  Color(0xFF40D9D0),
  Color(0xFFFF8A4C),
];

class ComparisonScreen extends StatefulWidget {
  const ComparisonScreen({super.key, required this.controller});
  final PortfolioController controller;

  @override
  State<ComparisonScreen> createState() => _ComparisonScreenState();
}

class _ComparisonScreenState extends State<ComparisonScreen> {
  final selected = <String>{_portfolioKey, _cdiKey};
  HistoryPeriod period = HistoryPeriod.oneMonth;
  ChartMode mode = ChartMode.performance;
  DateTime? selectedDate;

  @override
  void initState() {
    super.initState();
    selected
        .addAll(widget.controller.assets.take(3).map((asset) => asset.syncKey));
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  List<InvestmentAsset> get selectedAssets => widget.controller.assets
      .where((asset) => selected.contains(asset.syncKey))
      .toList();

  Future<void> _load() =>
      widget.controller.loadComparison(selectedAssets, period);

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final series = <String, List<PricePoint>>{};
    for (final asset in selectedAssets) {
      final start = period.startFrom(DateTime.now());
      final raw = (controller.assetHistories[asset.syncKey] ?? const [])
          .where((point) => start == null || !point.date.isBefore(start))
          .toList();
      series[asset.syncKey] =
          mode == ChartMode.performance ? normalizePerformance(raw) : raw;
    }
    if (selected.contains(_portfolioKey)) {
      series[_portfolioKey] = mode == ChartMode.performance
          ? normalizePerformance(controller.portfolioHistory)
          : controller.portfolioHistory;
    }
    // O CDI é um índice, não tem preço em reais: fora do modo Desempenho ele
    // só distorceria a escala do gráfico.
    if (selected.contains(_cdiKey) && mode == ChartMode.performance) {
      series[_cdiKey] = normalizePerformance(controller.cdiHistory);
    }
    series.removeWhere((_, points) => points.isEmpty);
    final colors = <String, Color>{};
    var colorIndex = 0;
    for (final key in selected) {
      // O CDI é referência, não um ativo: cor fixa e neutra, e fora do rodízio
      // da paleta para não trocar as cores já conhecidas dos ativos.
      colors[key] = key == _cdiKey
          ? _cdiColor
          : _palette[colorIndex++ % _palette.length];
    }
    final loading = controller.cdiLoading ||
        selectedAssets.any(
          (asset) => controller.isHistoryLoading(asset.syncKey),
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 110),
      children: [
        const Text('Comparar',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        const Text(
          'Compare desempenhos a partir de 0%, sem confundir preço nominal.',
          style: TextStyle(color: _muted),
        ),
        const SizedBox(height: 16),
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
        SegmentedButton<ChartMode>(
          segments: const [
            ButtonSegment(
                value: ChartMode.performance, label: Text('Desempenho %')),
            ButtonSegment(value: ChartMode.price, label: Text('Preço')),
          ],
          selected: {mode},
          onSelectionChanged: (value) => setState(() {
            mode = value.first;
            selectedDate = null;
          }),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    _selector(
                      keyValue: _portfolioKey,
                      label: 'Minha carteira',
                      color: colors[_portfolioKey] ?? _palette.first,
                    ),
                    _selector(
                      keyValue: _cdiKey,
                      label: 'CDI',
                      color: colors[_cdiKey] ?? _cdiColor,
                    ),
                    for (final asset in controller.assets)
                      _selector(
                        keyValue: asset.syncKey,
                        label: asset.symbol,
                        color: colors[asset.syncKey] ?? _muted,
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 260,
                  child: loading && series.isEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : series.isEmpty
                          ? const Center(
                              child: Text(
                                'Sem histórico no período selecionado.',
                                style: TextStyle(color: _muted),
                              ),
                            )
                          : InteractiveHistoryChart(
                              series: series,
                              colors: colors,
                              showZeroLine: mode == ChartMode.performance,
                              onDateSelected: (date) =>
                                  setState(() => selectedDate = date),
                            ),
                ),
                if (selectedDate != null) ...[
                  const SizedBox(height: 15),
                  _SelectionValues(
                    date: selectedDate!,
                    series: series,
                    assets: controller.assets,
                    mode: mode,
                    colors: colors,
                  ),
                ],
                if (loading) ...[
                  const SizedBox(height: 10),
                  const LinearProgressIndicator(minHeight: 2),
                ],
              ],
            ),
          ),
        ),
        if (selected.contains(_cdiKey)) ...[
          const SizedBox(height: 14),
          if (controller.cdiComparison case final comparison?)
            _CdiSummary(comparison: comparison, period: period)
          else if (!controller.cdiLoading)
            const Text(
              'A comparação com o CDI aparece quando existirem dois snapshots '
              'reais da carteira dentro do período escolhido.',
              style: TextStyle(color: _muted, fontSize: 12),
            ),
          if (controller.cdiError != null) ...[
            const SizedBox(height: 8),
            Text(
              controller.cdiError!,
              style: const TextStyle(color: _red, fontSize: 12),
            ),
          ],
          if (mode == ChartMode.price) ...[
            const SizedBox(height: 8),
            const Text(
              'O CDI é um índice acumulado e só aparece no gráfico em '
              'Desempenho %.',
              style: TextStyle(color: _muted, fontSize: 12),
            ),
          ],
        ],
        if (mode == ChartMode.price &&
            selectedAssets.map((a) => a.currency).toSet().length > 1) ...[
          const SizedBox(height: 10),
          const Text(
            'Modo Preço mistura escalas BRL e USD. Use Desempenho % para uma comparação neutra de moeda.',
            style: TextStyle(color: _muted, fontSize: 12),
          ),
        ],
        const SizedBox(height: 12),
        for (final asset in selectedAssets)
          if (controller.historyErrors[asset.syncKey] != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '${asset.symbol}: ${controller.historyErrors[asset.syncKey]}',
                style: const TextStyle(color: _red, fontSize: 12),
              ),
            ),
        if (selected.contains(_portfolioKey) &&
            controller.portfolioHistory.length < 2)
          const Text(
            'Minha carteira aparecerá após existirem pelo menos dois snapshots reais. Não foi criado histórico anterior artificial.',
            style: TextStyle(color: _muted, fontSize: 12),
          ),
      ],
    );
  }

  Widget _selector({
    required String keyValue,
    required String label,
    required Color color,
  }) {
    final active = selected.contains(keyValue);
    return FilterChip(
      selected: active,
      label: Text(label),
      avatar: CircleAvatar(backgroundColor: active ? color : _muted, radius: 5),
      onSelected: (value) {
        setState(() {
          value ? selected.add(keyValue) : selected.remove(keyValue);
          selectedDate = null;
        });
        _load();
      },
    );
  }
}

class _SelectionValues extends StatelessWidget {
  const _SelectionValues({
    required this.date,
    required this.series,
    required this.assets,
    required this.mode,
    required this.colors,
  });
  final DateTime date;
  final Map<String, List<PricePoint>> series;
  final List<InvestmentAsset> assets;
  final ChartMode mode;
  final Map<String, Color> colors;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(DateFormat('dd/MM/yyyy').format(date),
              style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          for (final entry in series.entries)
            if (pointOnOrBefore(entry.value, date) case final point?)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: colors[entry.key],
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_label(entry.key))),
                    Text(
                      _format(entry.key, point.value),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: mode == ChartMode.performance
                            ? (point.value >= 0 ? _green : _red)
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
        ],
      );

  String _label(String key) => switch (key) {
        _portfolioKey => 'Minha carteira',
        _cdiKey => 'CDI',
        _ => assets.firstWhere((asset) => asset.syncKey == key).symbol,
      };

  String _format(String key, double value) {
    if (mode == ChartMode.performance) return _percentText(value);
    if (key == _cdiKey) return value.toStringAsFixed(2).replaceAll('.', ',');
    if (key == _portfolioKey) return _brl.format(value);
    final asset = assets.firstWhere((asset) => asset.syncKey == key);
    return (asset.currency == AssetCurrency.brl ? _brl : _usd).format(value);
  }
}

final _brl =
    NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$', decimalDigits: 2);
final _usd =
    NumberFormat.currency(locale: 'pt_BR', symbol: 'US\$', decimalDigits: 2);

/// Resultado da carteira contra o CDI no mesmo intervalo de datas.
class _CdiSummary extends StatelessWidget {
  const _CdiSummary({required this.comparison, required this.period});

  final CdiComparison comparison;
  final HistoryPeriod period;

  @override
  Widget build(BuildContext context) {
    final ahead = comparison.beatsCdi;
    // Com a carteira no vermelho a razão viraria um "-40% do CDI" sem leitura
    // útil; nesse caso a diferença em pontos percentuais já conta a história.
    final ratio =
        comparison.portfolioPercent >= 0 ? comparison.percentOfCdi : null;
    final dates = DateFormat('dd/MM/yyyy');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'CARTEIRA × CDI',
              style: TextStyle(
                color: _muted,
                fontSize: 12,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${period.label} · ${dates.format(comparison.start)} a '
              '${dates.format(comparison.end)}',
              style: const TextStyle(color: _muted, fontSize: 12),
            ),
            const SizedBox(height: 14),
            _line(
              label: 'Minha carteira',
              value: comparison.portfolioPercent,
              color: comparison.portfolioPercent >= 0 ? _green : _red,
            ),
            const SizedBox(height: 6),
            _line(label: 'CDI no período', value: comparison.cdiPercent),
            const Divider(height: 24),
            Text(
              '${_percentPoints(comparison.differencePoints)} '
              '${ahead ? 'acima' : 'abaixo'} do CDI',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: ahead ? _green : _red,
              ),
            ),
            if (ratio != null) ...[
              const SizedBox(height: 4),
              Text(
                'A carteira rendeu ${ratio.toStringAsFixed(0)}% do CDI.',
                style: const TextStyle(color: _muted),
              ),
            ],
            const SizedBox(height: 10),
            const Text(
              'A rentabilidade da carteira desconta aportes e retiradas pela '
              'variação do valor aplicado, então ela mede o desempenho dos '
              'ativos, e não o dinheiro que entrou.',
              style: TextStyle(color: _muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _line({required String label, required double value, Color? color}) =>
      Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            _percentText(value),
            style: TextStyle(fontWeight: FontWeight.w700, color: color),
          ),
        ],
      );
}

String _percentText(double value) =>
    '${value >= 0 ? '+' : ''}${value.toStringAsFixed(2).replaceAll('.', ',')}%';

/// A distância em pontos percentuais; o sinal vira palavra no texto ao lado.
String _percentPoints(double value) =>
    '${value.abs().toStringAsFixed(2).replaceAll('.', ',')} p.p.';
