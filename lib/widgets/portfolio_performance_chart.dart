import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;

import '../models/history_models.dart';
import '../models/investment_transaction.dart';
import '../models/tracking_analytics.dart';

const _green = Color(0xFF39E58C);
const _red = Color(0xFFFF6B78);
const _muted = Color(0xFF93A4BC);

/// Janelas do gráfico da carteira, no espírito das cotações do Google.
enum PortfolioChartRange {
  fiveDays('5D', 'em 5 dias'),
  oneMonth('1M', 'em 1 mês'),
  sixMonths('6M', 'em 6 meses'),
  yearToDate('YTD', 'no ano'),
  oneYear('1A', 'em 1 ano'),
  maximum('Máx', 'desde o início');

  const PortfolioChartRange(this.label, this.description);
  final String label;
  final String description;

  DateTime? since(List<DateTime> dates, DateTime now) => switch (this) {
        // Cinco registros: o gráfico começa no pregão anterior a eles.
        PortfolioChartRange.fiveDays =>
          dates.length > 5 ? dates[dates.length - 5] : null,
        PortfolioChartRange.oneMonth =>
          DateTime(now.year, now.month - 1, now.day),
        PortfolioChartRange.sixMonths =>
          DateTime(now.year, now.month - 6, now.day),
        PortfolioChartRange.yearToDate => DateTime(now.year),
        PortfolioChartRange.oneYear =>
          DateTime(now.year - 1, now.month, now.day),
        PortfolioChartRange.maximum => null,
      };
}

enum _ChartUnit { money, percent }

/// Patrimônio da carteira com o resultado do período em R$ e %.
///
/// A linha mostra o ganho acumulado, não o patrimônio bruto: aportes, vendas
/// e ativos cadastrados depois não aparecem como alta ou queda, então a curva
/// sobe e desce só com o mercado. Tocar ou arrastar mostra o dia.
class PortfolioPerformanceCard extends StatefulWidget {
  const PortfolioPerformanceCard({
    super.key,
    required this.assetSnapshots,
    required this.transactionsByAsset,
    required this.transactionsVersion,
    required this.currentValue,
    required this.dayResult,
    required this.dayPercent,
    required this.dayLabel,
    required this.footer,
  });

  final Map<String, List<AssetDailySnapshot>> assetSnapshots;
  final Map<String, List<InvestmentTransaction>> transactionsByAsset;

  /// Lista trocada a cada recarga das operações; só serve para saber quando
  /// recalcular, já que o mapa de operações é reaproveitado.
  final Object transactionsVersion;
  final double currentValue;
  final double dayResult;
  final double dayPercent;
  final String dayLabel;
  final String footer;

  @override
  State<PortfolioPerformanceCard> createState() =>
      _PortfolioPerformanceCardState();
}

class _PortfolioPerformanceCardState extends State<PortfolioPerformanceCard> {
  var range = PortfolioChartRange.oneMonth;
  var unit = _ChartUnit.money;
  int? selected;

  List<PortfolioPerformancePoint>? _cache;
  Object? _cacheKey;

  List<PortfolioPerformancePoint> get points {
    final key = Object.hash(
      range,
      identityHashCode(widget.assetSnapshots),
      identityHashCode(widget.transactionsVersion),
    );
    if (_cacheKey == key && _cache != null) return _cache!;
    final all = calculatePortfolioPerformance(
      assetSnapshots: widget.assetSnapshots,
      transactionsByAsset: widget.transactionsByAsset,
    );
    final since = range.since(
      [for (final point in all) point.date],
      DateTime.now(),
    );
    _cache = since == null ? all : rebasePerformance(all, since);
    _cacheKey = key;
    return _cache!;
  }

  @override
  Widget build(BuildContext context) {
    final data = points;
    final hasChart = data.length >= 2;
    final focus =
        selected != null && selected! < data.length ? data[selected!] : null;
    final last = hasChart ? data.last : null;
    final shown = focus ?? last;
    final result = shown?.resultBrl ?? 0;
    final percent = shown?.returnPercent ?? 0;
    final positive = (last?.resultBrl ?? 0) >= 0;
    final lineColor = positive ? _green : _red;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('PATRIMÔNIO INVESTIDO',
                style:
                    TextStyle(color: _muted, fontSize: 12, letterSpacing: 1.2)),
            const SizedBox(height: 8),
            FittedBox(
              child: Text(
                _money(focus?.valueBrl ?? widget.currentValue),
                style: const TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1,
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (hasChart)
              Text.rich(
                TextSpan(children: [
                  TextSpan(
                    text:
                        '${_signedMoney(result)} (${_signedPercent(percent)}) '
                        '${result >= 0 ? '↑' : '↓'} ',
                    style: TextStyle(
                      color: result >= 0 ? _green : _red,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  TextSpan(
                    text: focus == null
                        ? range.description
                        : 'até ${_longDate(focus.date)}',
                    style: TextStyle(color: result >= 0 ? _green : _red),
                  ),
                ]),
                style: const TextStyle(fontSize: 14),
              ),
            const SizedBox(height: 4),
            Text(
              '${widget.dayLabel == 'hoje' ? 'Hoje' : 'Último pregão'}: '
              '${_signedMoney(widget.dayResult)} '
              '(${_signedPercent(widget.dayPercent)})',
              style: const TextStyle(color: _muted, fontSize: 12),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final value in PortfolioChartRange.values)
                          _RangeChip(
                            label: value.label,
                            selected: value == range,
                            onTap: () => setState(() {
                              range = value;
                              selected = null;
                            }),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                _UnitToggle(
                  unit: unit,
                  onChanged: (value) => setState(() => unit = value),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 190,
              width: double.infinity,
              child: hasChart
                  ? _Chart(
                      points: data,
                      unit: unit,
                      color: lineColor,
                      selected: selected,
                      onSelected: (value) => setState(() => selected = value),
                    )
                  : const Center(
                      child: Text(
                        'O gráfico aparece a partir do segundo dia registrado.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: _muted),
                      ),
                    ),
            ),
            const SizedBox(height: 10),
            Text(
              hasChart
                  ? 'Resultado sem contar aportes, vendas e ativos incluídos '
                      'no período • ${widget.footer}'
                  : widget.footer,
              style: const TextStyle(color: _muted, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _RangeChip extends StatelessWidget {
  const _RangeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 4),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(
              color: selected
                  ? Colors.white.withValues(alpha: .12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : _muted,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ),
      );
}

class _UnitToggle extends StatelessWidget {
  const _UnitToggle({required this.unit, required this.onChanged});

  final _ChartUnit unit;
  final ValueChanged<_ChartUnit> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFF25344B)),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final value in _ChartUnit.values)
              InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => onChanged(value),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: value == unit
                        ? Colors.white.withValues(alpha: .12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(
                    value == _ChartUnit.money ? 'R\$' : '%',
                    style: TextStyle(
                      color: value == unit ? Colors.white : _muted,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
}

class _Chart extends StatelessWidget {
  const _Chart({
    required this.points,
    required this.unit,
    required this.color,
    required this.selected,
    required this.onSelected,
  });

  final List<PortfolioPerformancePoint> points;
  final _ChartUnit unit;
  final Color color;
  final int? selected;
  final ValueChanged<int?> onSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final geometry = _ChartGeometry(points, constraints.biggest);
      void pick(Offset position) =>
          onSelected(geometry.nearestIndex(position.dx));
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (details) {
          final index = geometry.nearestIndex(details.localPosition.dx);
          onSelected(index == selected ? null : index);
        },
        onHorizontalDragStart: (details) => pick(details.localPosition),
        onHorizontalDragUpdate: (details) => pick(details.localPosition),
        onHorizontalDragEnd: (_) => onSelected(null),
        onHorizontalDragCancel: () => onSelected(null),
        child: CustomPaint(
          painter: _ChartPainter(
            points: points,
            unit: unit,
            color: color,
            selected: selected,
            geometry: geometry,
          ),
          child: const SizedBox.expand(),
        ),
      );
    });
  }
}

/// Posição horizontal proporcional ao tempo, com espaço para os rótulos.
class _ChartGeometry {
  _ChartGeometry(this.points, this.size);

  final List<PortfolioPerformancePoint> points;
  final Size size;

  final left = 0.0;
  final right = 70.0;
  final bottom = 20.0;
  final top = 8.0;

  double get plotWidth => math.max(size.width - left - right, 1);
  double get plotHeight => math.max(size.height - top - bottom, 1);

  double xFor(DateTime date) {
    final first = points.first.date;
    final span = math.max(
      points.last.date.difference(first).inMinutes.toDouble(),
      1,
    );
    return left + date.difference(first).inMinutes / span * plotWidth;
  }

  int nearestIndex(double x) {
    var best = 0;
    var distance = double.infinity;
    for (var i = 0; i < points.length; i++) {
      final current = (xFor(points[i].date) - x).abs();
      if (current < distance) {
        distance = current;
        best = i;
      }
    }
    return best;
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.points,
    required this.unit,
    required this.color,
    required this.selected,
    required this.geometry,
  });

  final List<PortfolioPerformancePoint> points;
  final _ChartUnit unit;
  final Color color;
  final int? selected;
  final _ChartGeometry geometry;

  double valueOf(PortfolioPerformancePoint point) =>
      unit == _ChartUnit.money ? point.resultBrl : point.returnPercent;

  @override
  void paint(Canvas canvas, Size size) {
    final values = points.map(valueOf).toList();
    // A linha de base (zero) sempre aparece, como o fechamento anterior.
    var minValue = math.min(values.reduce(math.min), 0.0);
    var maxValue = math.max(values.reduce(math.max), 0.0);
    final minimumSpan = unit == _ChartUnit.money ? 10.0 : .1;
    if (maxValue - minValue < minimumSpan) {
      maxValue += minimumSpan / 2;
      minValue -= minimumSpan / 2;
    }
    final pad = (maxValue - minValue) * .08;
    minValue -= pad;
    maxValue += pad;
    final range = maxValue - minValue;
    final plotRight = geometry.left + geometry.plotWidth;

    double yFor(double value) =>
        geometry.top +
        geometry.plotHeight -
        (value - minValue) / range * geometry.plotHeight;

    // Grade com três rótulos à direita.
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: .07)
      ..strokeWidth = 1;
    for (var i = 0; i < 3; i++) {
      final value = minValue + pad + (range - 2 * pad) * i / 2;
      final y = yFor(value);
      canvas.drawLine(Offset(geometry.left, y), Offset(plotRight, y), grid);
      _text(canvas, _axisLabel(value), Offset(plotRight + 6, y - 7),
          const TextStyle(color: _muted, fontSize: 10));
    }

    // Linha de base tracejada no zero.
    final zeroY = yFor(0);
    final dash = Paint()
      ..color = Colors.white.withValues(alpha: .35)
      ..strokeWidth = 1;
    for (var x = geometry.left; x < plotRight; x += 7) {
      canvas.drawLine(
        Offset(x, zeroY),
        Offset(math.min(x + 3.5, plotRight), zeroY),
        dash,
      );
    }

    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final offset = Offset(geometry.xFor(points[i].date), yFor(values[i]));
      if (i == 0) {
        path.moveTo(offset.dx, offset.dy);
      } else {
        path.lineTo(offset.dx, offset.dy);
      }
    }
    final area = Path.from(path)
      ..lineTo(geometry.xFor(points.last.date), zeroY)
      ..lineTo(geometry.xFor(points.first.date), zeroY)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: .26), color.withValues(alpha: .02)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2.4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Datas no eixo de baixo: início, meio e fim.
    final labelY = size.height - geometry.bottom + 5;
    final longRange =
        points.last.date.difference(points.first.date).inDays > 200;
    final format = DateFormat(longRange ? 'MMM yy' : 'dd/MM', 'pt_BR');
    final labelIndexes = {0, points.length ~/ 2, points.length - 1};
    for (final index in labelIndexes) {
      final label = format.format(points[index].date);
      final x = geometry.xFor(points[index].date);
      _text(canvas, label, Offset(x, labelY),
          const TextStyle(color: _muted, fontSize: 10),
          align: index == 0
              ? TextAlign.left
              : index == points.length - 1
                  ? TextAlign.right
                  : TextAlign.center);
    }

    final index = selected;
    if (index != null && index < points.length) {
      final point = points[index];
      final x = geometry.xFor(point.date);
      final y = yFor(values[index]);
      final guide = Paint()
        ..color = Colors.white.withValues(alpha: .6)
        ..strokeWidth = 1;
      for (var dy = geometry.top;
          dy < geometry.top + geometry.plotHeight;
          dy += 6) {
        canvas.drawLine(Offset(x, dy), Offset(x, dy + 3), guide);
      }
      final pointColor = values[index] >= 0 ? _green : _red;
      canvas.drawCircle(
          Offset(x, y), 6, Paint()..color = pointColor.withValues(alpha: .25));
      canvas.drawCircle(Offset(x, y), 3.8, Paint()..color = pointColor);
    }
  }

  String _axisLabel(double value) {
    if (unit == _ChartUnit.percent) {
      return '${value >= 0.05 ? '+' : ''}'
          '${value.toStringAsFixed(1).replaceAll('.', ',')}%';
    }
    final abs = value.abs();
    final sign = value < -0.5
        ? '-'
        : value > 0.5
            ? '+'
            : '';
    if (abs >= 1000) {
      final digits = abs >= 10000 ? 0 : 1;
      return '${sign}R\$ ${(abs / 1000).toStringAsFixed(digits).replaceAll('.', ',')} mil';
    }
    return '${sign}R\$ ${abs.toStringAsFixed(0)}';
  }

  void _text(
    Canvas canvas,
    String text,
    Offset anchor,
    TextStyle style, {
    TextAlign align = TextAlign.left,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = switch (align) {
      TextAlign.center => anchor.dx - painter.width / 2,
      TextAlign.right => anchor.dx - painter.width,
      _ => anchor.dx,
    };
    painter.paint(canvas, Offset(dx, anchor.dy));
  }

  @override
  bool shouldRepaint(covariant _ChartPainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.unit != unit ||
      oldDelegate.color != color ||
      oldDelegate.selected != selected ||
      oldDelegate.geometry.size != geometry.size;
}

final _brl =
    NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$', decimalDigits: 2);
String _money(double value) => _brl.format(value);
String _signedMoney(double value) =>
    '${value >= 0 ? '+' : '-'}${_brl.format(value.abs())}';
String _signedPercent(double value) {
  final clean = value.abs() < 0.005 ? 0.0 : value;
  return '${clean >= 0 ? '+' : ''}${clean.toStringAsFixed(2).replaceAll('.', ',')}%';
}

String _longDate(DateTime date) =>
    DateFormat("EEE., d 'de' MMM", 'pt_BR').format(date);
