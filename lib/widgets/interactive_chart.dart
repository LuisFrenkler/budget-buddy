import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/history.dart';
import '../utils/dates.dart';
import '../utils/theme.dart';
import 'big_number.dart';

// A line chart you can touch: drag or long-press to read the value of any
// day. The line draws itself in, has a soft gradient below and a dotted line
// at the starting value. While scrubbing, the part right of the finger dims.
class InteractiveChart extends StatefulWidget {
  final List<ChartPoint> points;
  final double height;
  // called with the touched point, and with null when the finger lifts
  final ValueChanged<ChartPoint?>? onScrub;

  const InteractiveChart({super.key, required this.points, this.height = 160, this.onScrub});

  @override
  State<InteractiveChart> createState() => _InteractiveChartState();
}

class _InteractiveChartState extends State<InteractiveChart> with SingleTickerProviderStateMixin {
  late final AnimationController _reveal = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
    ..forward();
  int? _index;

  @override
  void didUpdateWidget(InteractiveChart old) {
    super.didUpdateWidget(old);
    // redraw the line when a different range or dataset is shown
    final a = old.points, b = widget.points;
    final changed = a.length != b.length ||
        (a.isNotEmpty && b.isNotEmpty && (a.first.date != b.first.date || a.last.cents != b.last.cents));
    if (changed) _reveal.forward(from: 0);
  }

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
  }

  void _scrubTo(double x, double width) {
    final n = widget.points.length;
    if (n < 2) return;
    final i = (x / width * (n - 1)).round().clamp(0, n - 1);
    if (i == _index) return;
    HapticFeedback.selectionClick();
    setState(() => _index = i);
    widget.onScrub?.call(widget.points[i]);
  }

  void _end() {
    if (_index == null) return;
    setState(() => _index = null);
    widget.onScrub?.call(null);
  }

  @override
  Widget build(BuildContext context) {
    final pts = widget.points;
    if (pts.length < 2) {
      return SizedBox(
        height: widget.height,
        child: Center(child: Text('Noch kein Verlauf', style: TextStyle(color: AppColors.textDim))),
      );
    }
    final up = pts.last.cents >= pts.first.cents;
    final color = up ? AppColors.positive : AppColors.error;

    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      // with a mouse (Mac, browser) hovering is enough to read a value
      return MouseRegion(
        onHover: (e) => _scrubTo(e.localPosition.dx, w),
        onExit: (_) => _end(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (d) => _scrubTo(d.localPosition.dx, w),
          onHorizontalDragUpdate: (d) => _scrubTo(d.localPosition.dx, w),
          onHorizontalDragEnd: (_) => _end(),
          onHorizontalDragCancel: _end,
          onLongPressStart: (d) => _scrubTo(d.localPosition.dx, w),
          onLongPressMoveUpdate: (d) => _scrubTo(d.localPosition.dx, w),
          onLongPressEnd: (_) => _end(),
          child: AnimatedBuilder(
            animation: _reveal,
            builder: (_, __) => SizedBox(
              height: widget.height,
              width: w,
              child: CustomPaint(
                painter: _ChartPainter(
                  values: [for (final p in pts) p.cents.toDouble()],
                  color: color,
                  dim: AppColors.textDim,
                  progress: Curves.easeOutCubic.transform(_reveal.value),
                  index: _index,
                ),
              ),
            ),
          ),
        ),
      );
    });
  }
}

class _ChartPainter extends CustomPainter {
  final List<double> values;
  final Color color;
  final Color dim;
  final double progress;
  final int? index;

  _ChartPainter({required this.values, required this.color, required this.dim, required this.progress, this.index});

  @override
  void paint(Canvas canvas, Size size) {
    var minV = values.reduce(math.min);
    var maxV = values.reduce(math.max);
    // show at least 4 % of the value as range, so a coffee does not look
    // like a crash on a 1.250 € balance
    final minSpan = math.max(maxV.abs(), minV.abs()) * 0.04;
    if (maxV - minV < minSpan) {
      final mid = (maxV + minV) / 2;
      maxV = mid + minSpan / 2;
      minV = mid - minSpan / 2;
    }
    if (maxV == minV) {
      maxV += 1;
      minV -= 1;
    }
    const top = 8.0, bottom = 8.0;
    final h = size.height - top - bottom;
    final dx = size.width / (values.length - 1);
    double x(int i) => i * dx;
    double y(double v) => top + h - (v - minV) / (maxV - minV) * h;

    final line = Path()..moveTo(0, y(values[0]));
    for (int i = 1; i < values.length; i++) {
      line.lineTo(x(i), y(values[i]));
    }

    // draw in from left to right
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width * progress, size.height));

    // soft gradient under the line
    final fill = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0.0)],
        ).createShader(Offset.zero & size),
    );

    // dotted line at the starting value
    final baseY = y(values.first);
    final dotPaint = Paint()
      ..color = dim.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    for (double sx = 0; sx < size.width; sx += 6) {
      canvas.drawLine(Offset(sx, baseY), Offset(sx + 2, baseY), dotPaint);
    }

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    if (index == null) {
      canvas.drawPath(line, stroke..color = color);
    } else {
      // strong left of the finger, dimmed right of it
      final sx = x(index!);
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0, 0, sx, size.height));
      canvas.drawPath(line, stroke..color = color);
      canvas.restore();
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(sx, 0, size.width - sx, size.height));
      canvas.drawPath(line, stroke..color = color.withValues(alpha: 0.3));
      canvas.restore();

      // vertical marker and dot
      canvas.drawLine(Offset(sx, 0), Offset(sx, size.height), Paint()..color = dim.withValues(alpha: 0.6));
      final p = Offset(sx, y(values[index!]));
      canvas.drawCircle(p, 7, Paint()..color = color.withValues(alpha: 0.25));
      canvas.drawCircle(p, 4.5, Paint()..color = color);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) =>
      old.values != values || old.progress != progress || old.index != index || old.color != color || old.dim != dim;
}

// Row of range buttons like "1M 3M 6M 1J Max".
class RangeSelector extends StatelessWidget {
  final List<String> labels;
  final String selected;
  final ValueChanged<String> onChanged;

  const RangeSelector({super.key, required this.labels, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final l in labels)
          GestureDetector(
            onTap: () {
              if (l == selected) return;
              HapticFeedback.selectionClick();
              onChanged(l);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: l == selected ? AppColors.surfaceAlt : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(l,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: l == selected ? AppColors.text : AppColors.textDim,
                  )),
            ),
          ),
      ],
    );
  }
}

// Big number above a chart: shows the current value, or the touched day's
// value and date while scrubbing, plus the change since the range start.
class ChartHeader extends StatelessWidget {
  final String label;
  final int cents;
  final int startCents;
  final String period;
  final ChartPoint? scrub;
  // first day of the shown range, named while scrubbing ("seit 26. Sep.")
  final DateTime? startDate;
  // a percentage means little for a bank balance, so it can be left out
  final bool showPercent;

  const ChartHeader({
    super.key,
    required this.label,
    required this.cents,
    required this.startCents,
    required this.period,
    this.scrub,
    this.startDate,
    this.showPercent = true,
  });

  @override
  Widget build(BuildContext context) {
    final value = scrub?.cents ?? cents;
    final change = value - startCents;
    return BigNumber(
      label: scrub == null ? label : Dates.full(scrub!.date),
      cents: value,
      animate: scrub == null,
      below: ChangeLabel(
        cents: change,
        percent: showPercent && startCents > 0 ? change / startCents * 100 : null,
        suffix: scrub == null ? period : (startDate != null ? 'seit ${Dates.dayMonth(startDate!)}' : null),
      ),
    );
  }
}
