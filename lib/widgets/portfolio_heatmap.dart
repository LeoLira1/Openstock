import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show NumberFormat;

import '../models/treemap.dart';

/// Um bloco do mapa: o tamanho vem de [value] e a cor de [percent].
class HeatmapTile {
  const HeatmapTile({
    required this.symbol,
    required this.value,
    required this.percent,
    this.onTap,
  });

  final String symbol;
  final double value;
  final double percent;
  final VoidCallback? onTap;
}

/// Mapa de calor da carteira, no estilo dos mapas de mercado da B3.
///
/// Cada ativo ocupa uma área proporcional ao seu peso no patrimônio; a cor
/// vai do vermelho ao verde conforme a variação, saturando em [colorCap]%.
class PortfolioHeatmap extends StatelessWidget {
  const PortfolioHeatmap({
    super.key,
    required this.tiles,
    required this.total,
    this.colorCap = 3,
    this.height = 360,
  });

  final List<HeatmapTile> tiles;
  final double total;
  final double colorCap;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: LayoutBuilder(builder: (context, constraints) {
        final bounds = Offset.zero & constraints.biggest;
        final rects = squarifiedTreemap(
          [for (final tile in tiles) tile.value],
          bounds,
        );
        return ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            children: [
              for (var i = 0; i < tiles.length; i++)
                if (!rects[i].isEmpty)
                  Positioned.fromRect(
                    rect: rects[i],
                    child: _Tile(
                      tile: tiles[i],
                      share: total <= 0 ? 0 : tiles[i].value / total,
                      color: heatColor(tiles[i].percent, colorCap),
                    ),
                  ),
            ],
          ),
        );
      }),
    );
  }
}

/// Vermelho → cinza-azulado → verde, com a intensidade da variação.
Color heatColor(double percent, double cap) {
  const neutral = Color(0xFF2A3445);
  const up = Color(0xFF17A35A);
  const down = Color(0xFFD23B45);
  if (percent.isNaN || percent.abs() < 0.005) return neutral;
  final t = math.min(percent.abs() / cap, 1.0);
  // Mesmo uma variação pequena já ganha um tom, como nos mapas de mercado.
  final eased = .35 + .65 * t;
  return Color.lerp(neutral, percent > 0 ? up : down, eased)!;
}

class _Tile extends StatelessWidget {
  const _Tile({required this.tile, required this.share, required this.color});

  final HeatmapTile tile;
  final double share;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(.75),
      child: Material(
        color: color,
        child: InkWell(
          onTap: tile.onTap,
          child: LayoutBuilder(builder: (context, constraints) {
            final width = constraints.maxWidth;
            final height = constraints.maxHeight;
            final side = math.min(width, height);
            if (width < 26 || height < 16) return const SizedBox.expand();
            final big = side >= 90;
            final medium = side >= 44;
            final symbolSize = big
                ? math.min(26.0, side / 4.2)
                : medium
                    ? 13.0
                    : 10.0;
            return Padding(
              padding: EdgeInsets.all(big ? 8 : 3),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      tile.symbol,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: symbolSize,
                        height: 1.1,
                      ),
                    ),
                    if (medium && height >= 38) ...[
                      if (big)
                        Text(
                          _compactMoney(tile.value),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .85),
                            fontSize: symbolSize * .6,
                            height: 1.3,
                          ),
                        ),
                      Text(
                        _percent(tile.percent),
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: big ? symbolSize * .72 : 11,
                          height: 1.25,
                        ),
                      ),
                      if (big)
                        Text(
                          '${(share * 100).toStringAsFixed(1).replaceAll('.', ',')}% da carteira',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .7),
                            fontSize: symbolSize * .45,
                            height: 1.4,
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

final _compact = NumberFormat.compactCurrency(
  locale: 'pt_BR',
  symbol: 'R\$',
  decimalDigits: 1,
);
String _compactMoney(double value) => _compact.format(value);

String _percent(double value) {
  final clean = value.abs() < 0.005 ? 0.0 : value;
  return '${clean >= 0 ? '+' : ''}${clean.toStringAsFixed(2).replaceAll('.', ',')}%';
}
