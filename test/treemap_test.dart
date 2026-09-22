import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstock/models/treemap.dart';

void main() {
  test('áreas proporcionais aos valores e dentro dos limites', () {
    const bounds = Rect.fromLTWH(0, 0, 300, 200);
    final values = <double>[50, 20, 10, 10, 5, 3, 2];
    final rects = squarifiedTreemap(values, bounds);
    final total = values.reduce((a, b) => a + b);

    for (var i = 0; i < values.length; i++) {
      final area = rects[i].width * rects[i].height;
      expect(area, closeTo(values[i] / total * 60000, 0.01));
      expect(bounds.inflate(0.001).contains(rects[i].topLeft), isTrue);
      expect(rects[i].right, lessThanOrEqualTo(300.001));
      expect(rects[i].bottom, lessThanOrEqualTo(200.001));
    }
    // Sem sobreposição entre blocos.
    for (var i = 0; i < rects.length; i++) {
      for (var j = i + 1; j < rects.length; j++) {
        final overlap = rects[i].intersect(rects[j]);
        expect(overlap.width <= 0.001 || overlap.height <= 0.001, isTrue);
      }
    }
  });

  test('valores zerados ficam fora do mapa', () {
    final rects =
        squarifiedTreemap([10, 0, -3], const Rect.fromLTWH(0, 0, 100, 100));
    expect(rects[0], const Rect.fromLTWH(0, 0, 100, 100));
    expect(rects[1], Rect.zero);
    expect(rects[2], Rect.zero);
  });
}
