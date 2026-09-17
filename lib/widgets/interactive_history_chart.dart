import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/history_models.dart';
import '../models/investment_asset.dart';

class InteractiveHistoryChart extends StatefulWidget {
  const InteractiveHistoryChart({
    super.key,
    required this.series,
    required this.colors,
    required this.onDateSelected,
    this.showZeroLine = false,
    this.horizontalReference,
  });

  final Map<String, List<PricePoint>> series;
  final Map<String, Color> colors;
  final ValueChanged<DateTime?> onDateSelected;
  final bool showZeroLine;
  final double? horizontalReference;

  @override
  State<InteractiveHistoryChart> createState() =>
      _InteractiveHistoryChartState();
}

class _InteractiveHistoryChartState extends State<InteractiveHistoryChart> {
  DateTime? selected;

  List<DateTime> get dates {
    final values = widget.series.values
        .expand((points) => points)
        .map((point) => _day(point.date))
        .toSet()
        .toList()
      ..sort();
    return values;
  }

  @override
  Widget build(BuildContext context) {
    final availableDates = dates;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (details) => _select(details.localPosition.dx, availableDates),
      onHorizontalDragUpdate: (details) =>
          _select(details.localPosition.dx, availableDates),
      onLongPressEnd: (_) {
        setState(() => selected = null);
        widget.onDateSelected(null);
      },
      child: CustomPaint(
        painter: HistoryChartPainter(
          series: widget.series,
          colors: widget.colors,
          selected: selected,
          showZeroLine: widget.showZeroLine,
          horizontalReference: widget.horizontalReference,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }

  void _select(double x, List<DateTime> availableDates) {
    if (availableDates.isEmpty) return;
    final box = context.findRenderObject() as RenderBox?;
    final width = box?.size.width ?? 1;
    final fraction = (x / width).clamp(0.0, 1.0);
    final first = availableDates.first;
    final span = availableDates.last.difference(first).inMilliseconds;
    final target = first.add(Duration(milliseconds: (span * fraction).round()));
    final value = availableDates.reduce((a, b) =>
        a.difference(target).abs() <= b.difference(target).abs() ? a : b);
    setState(() => selected = value);
    widget.onDateSelected(value);
  }
}

class HistoryChartPainter extends CustomPainter {
  HistoryChartPainter({
    required this.series,
    required this.colors,
    required this.selected,
    required this.showZeroLine,
    required this.horizontalReference,
  });

  final Map<String, List<PricePoint>> series;
  final Map<String, Color> colors;
  final DateTime? selected;
  final bool showZeroLine;
  final double? horizontalReference;

  @override
  void paint(Canvas canvas, Size size) {
    final all = series.values.expand((points) => points).toList();
    if (all.length < 2) return;
    final firstDate = all.map((point) => point.date).reduce(
          (a, b) => a.isBefore(b) ? a : b,
        );
    final lastDate = all.map((point) => point.date).reduce(
          (a, b) => a.isAfter(b) ? a : b,
        );
    var minValue = all.map((point) => point.value).reduce(math.min);
    var maxValue = all.map((point) => point.value).reduce(math.max);
    if (showZeroLine) {
      minValue = math.min(minValue, 0);
      maxValue = math.max(maxValue, 0);
    }
    if (horizontalReference != null) {
      minValue = math.min(minValue, horizontalReference!);
      maxValue = math.max(maxValue, horizontalReference!);
    }
    final padding = math.max((maxValue - minValue) * .08, .01);
    minValue -= padding;
    maxValue += padding;
    final range = maxValue - minValue;
    final duration = math.max(
      lastDate.difference(firstDate).inMilliseconds.toDouble(),
      1,
    );

    double xFor(DateTime date) =>
        date.difference(firstDate).inMilliseconds / duration * size.width;
    double yFor(double value) =>
        size.height - ((value - minValue) / range * (size.height - 10)) - 5;

    if (showZeroLine) {
      final y = yFor(0);
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..color = Colors.white.withValues(alpha: .35)
          ..strokeWidth = 1.4,
      );
    }
    if (horizontalReference != null) {
      final y = yFor(horizontalReference!);
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..color = const Color(0xFFFFC857).withValues(alpha: .8)
          ..strokeWidth = 1.5,
      );
    }

    for (final entry in series.entries) {
      final points = _pointsForPainting(entry.value);
      if (points.length < 2) continue;
      final path = Path();
      for (var i = 0; i < points.length; i++) {
        final offset = Offset(xFor(points[i].date), yFor(points[i].value));
        if (i == 0) {
          path.moveTo(offset.dx, offset.dy);
        } else {
          path.lineTo(offset.dx, offset.dy);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = colors[entry.key] ?? Colors.white
          ..strokeWidth = 2.4
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    if (selected != null) {
      final x = xFor(selected!).clamp(0.0, size.width);
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()
          ..color = Colors.white.withValues(alpha: .65)
          ..strokeWidth = 1,
      );
      for (final entry in series.entries) {
        final point = pointOnOrBefore(entry.value, selected!);
        if (point == null) continue;
        canvas.drawCircle(
          Offset(xFor(point.date), yFor(point.value)),
          4,
          Paint()..color = colors[entry.key] ?? Colors.white,
        );
      }
    }
  }

  List<PricePoint> _pointsForPainting(List<PricePoint> points) {
    if (points.length <= 900) return points;
    final step = (points.length / 900).ceil();
    return [
      for (var i = 0; i < points.length; i += step) points[i],
      if ((points.length - 1) % step != 0) points.last,
    ];
  }

  @override
  bool shouldRepaint(covariant HistoryChartPainter oldDelegate) =>
      oldDelegate.series != series ||
      oldDelegate.selected != selected ||
      oldDelegate.showZeroLine != showZeroLine ||
      oldDelegate.horizontalReference != horizontalReference;
}

DateTime _day(DateTime date) => DateTime(date.year, date.month, date.day);
