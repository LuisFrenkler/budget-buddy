import 'dart:math' as math;
import 'package:flutter/material.dart';

// A simple line chart with a soft area fill, drawn from a list of values.
class LineChart extends StatelessWidget {
  final List<double> values;
  final Color color;
  final double height;

  const LineChart(this.values, {super.key, required this.color, this.height = 150});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _LinePainter(values, color)),
    );
  }
}

class _LinePainter extends CustomPainter {
  final List<double> v;
  final Color color;
  _LinePainter(this.v, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (v.length < 2) return;

    double min = v.reduce(math.min);
    double max = v.reduce(math.max);
    if (max == min) {
      max += 1;
      min -= 1;
    }
    final dx = size.width / (v.length - 1);
    double y(int i) => size.height - (v[i] - min) / (max - min) * (size.height - 6) - 3;

    final line = Path()..moveTo(0, y(0));
    for (int i = 1; i < v.length; i++) {
      line.lineTo(i * dx, y(i));
    }

    // soft area fill under the line
    final fill = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(fill, Paint()..color = color.withValues(alpha: 0.12));

    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _LinePainter oldDelegate) => oldDelegate.v != v;
}
