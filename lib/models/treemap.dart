import 'dart:math' as math;
import 'dart:ui';

/// Divide [bounds] em retângulos com área proporcional a [values].
///
/// Usa o algoritmo "squarified" (Bruls, Huizing e van Wijk): os blocos saem o
/// mais próximo possível de quadrados, o que deixa os rótulos legíveis. O
/// resultado segue a ordem de [values]; valores zerados ou negativos recebem
/// [Rect.zero].
List<Rect> squarifiedTreemap(List<double> values, Rect bounds) {
  final result = List<Rect>.filled(values.length, Rect.zero);
  final order = [
    for (var i = 0; i < values.length; i++)
      if (values[i] > 0) i,
  ]..sort((a, b) => values[b].compareTo(values[a]));
  final total = order.fold<double>(0, (sum, i) => sum + values[i]);
  if (order.isEmpty || total <= 0 || bounds.isEmpty) return result;

  final scale = bounds.width * bounds.height / total;
  var free = bounds;
  var row = <int>[];

  double worst(List<int> items, double side) {
    final areas = items.map((i) => values[i] * scale);
    final sum = areas.fold<double>(0, (a, b) => a + b);
    final maxArea = areas.reduce(math.max);
    final minArea = areas.reduce(math.min);
    final side2 = side * side;
    final sum2 = sum * sum;
    return math.max(side2 * maxArea / sum2, sum2 / (side2 * minArea));
  }

  void layout(List<int> items) {
    final sum = items.fold<double>(0, (a, i) => a + values[i] * scale);
    if (free.width >= free.height) {
      // Coluna à esquerda do espaço livre.
      final width = free.height == 0 ? 0.0 : sum / free.height;
      var y = free.top;
      for (final i in items) {
        final height = width == 0 ? 0.0 : values[i] * scale / width;
        result[i] = Rect.fromLTWH(free.left, y, width, height);
        y += height;
      }
      free = Rect.fromLTRB(free.left + width, free.top, free.right, free.bottom);
    } else {
      // Linha no topo do espaço livre.
      final height = free.width == 0 ? 0.0 : sum / free.width;
      var x = free.left;
      for (final i in items) {
        final width = height == 0 ? 0.0 : values[i] * scale / height;
        result[i] = Rect.fromLTWH(x, free.top, width, height);
        x += width;
      }
      free =
          Rect.fromLTRB(free.left, free.top + height, free.right, free.bottom);
    }
  }

  for (final index in order) {
    final side = math.min(free.width, free.height);
    if (row.isEmpty || worst([...row, index], side) <= worst(row, side)) {
      row.add(index);
    } else {
      layout(row);
      row = [index];
    }
  }
  if (row.isNotEmpty) layout(row);
  return result;
}
