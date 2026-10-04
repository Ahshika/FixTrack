import 'package:flutter/material.dart';

/// لوحة 3×3 لتسجيل باترن فتح الشاشة زي ما العميل بيرسمه.
/// النقط مترقمة من 1 لـ 9 (من فوق شمال لتحت يمين)، والنتيجة زي "1-5-9-6".
class PatternPad extends StatefulWidget {
  const PatternPad({super.key, required this.onChanged, this.initial = const [], this.size = 220, this.readOnly = false});

  final ValueChanged<List<int>> onChanged;
  final List<int> initial;
  final double size;
  final bool readOnly;

  static String encode(List<int> dots) => dots.join('-');
  static List<int> decode(String? s) =>
      (s ?? '').split('-').map(int.tryParse).whereType<int>().where((d) => d >= 1 && d <= 9).toList();

  @override
  State<PatternPad> createState() => _PatternPadState();
}

class _PatternPadState extends State<PatternPad> {
  late List<int> _dots = [...widget.initial];
  Offset? _finger;

  Offset _center(int dot) {
    final cell = widget.size / 3;
    final i = dot - 1;
    return Offset((i % 3) * cell + cell / 2, (i ~/ 3) * cell + cell / 2);
  }

  int? _hit(Offset p) {
    for (var d = 1; d <= 9; d++) {
      if ((_center(d) - p).distance < widget.size / 9) return d;
    }
    return null;
  }

  void _add(Offset p) {
    final d = _hit(p);
    if (d == null || _dots.contains(d)) return;
    // لو العميل عدّى على نقطة في النص بين نقطتين، بتتحسب زي ما الموبايل بيعمل
    if (_dots.isNotEmpty) {
      final last = _dots.last;
      final mid = (last + d) ~/ 2;
      final aligned = (last + d).isEven &&
          ((last - 1) % 3 + (d - 1) % 3).isEven &&
          ((last - 1) ~/ 3 + (d - 1) ~/ 3).isEven;
      if (aligned && !_dots.contains(mid)) _dots.add(mid);
    }
    _dots.add(d);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pad = Directionality(
      // الباترن دايماً من الشمال لليمين زي شاشة الموبايل، حتى لو البرنامج عربي
      textDirection: TextDirection.ltr,
      child: GestureDetector(
        onPanStart: widget.readOnly
            ? null
            : (d) => setState(() {
                  _dots = [];
                  _add(d.localPosition);
                  _finger = d.localPosition;
                }),
        onPanUpdate: widget.readOnly
            ? null
            : (d) => setState(() {
                  _add(d.localPosition);
                  _finger = d.localPosition;
                }),
        onPanEnd: widget.readOnly
            ? null
            : (_) {
                setState(() => _finger = null);
                widget.onChanged(_dots);
              },
        child: CustomPaint(
          size: Size.square(widget.size),
          painter: _PatternPainter(
            dots: _dots,
            finger: _finger,
            center: _center,
            dotColor: scheme.outline,
            activeColor: scheme.primary,
            size: widget.size,
          ),
        ),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(16),
          ),
          child: pad,
        ),
        if (!widget.readOnly) ...[
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_dots.isEmpty ? 'ارسم الباترن بالماوس أو بصباعك' : 'الباترن: ${PatternPad.encode(_dots)}',
                  textDirection: TextDirection.rtl),
              if (_dots.isNotEmpty)
                TextButton(
                  onPressed: () {
                    setState(() => _dots = []);
                    widget.onChanged(_dots);
                  },
                  child: const Text('مسح'),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _PatternPainter extends CustomPainter {
  _PatternPainter({
    required this.dots,
    required this.finger,
    required this.center,
    required this.dotColor,
    required this.activeColor,
    required this.size,
  });

  final List<int> dots;
  final Offset? finger;
  final Offset Function(int) center;
  final Color dotColor;
  final Color activeColor;
  final double size;

  @override
  void paint(Canvas canvas, Size _) {
    final line = Paint()
      ..color = activeColor.withValues(alpha: 0.7)
      ..strokeWidth = size / 40
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    if (dots.isNotEmpty) {
      final path = Path()..moveTo(center(dots.first).dx, center(dots.first).dy);
      for (final d in dots.skip(1)) {
        path.lineTo(center(d).dx, center(d).dy);
      }
      if (finger != null) path.lineTo(finger!.dx, finger!.dy);
      canvas.drawPath(path, line);
    }
    for (var d = 1; d <= 9; d++) {
      final active = dots.contains(d);
      canvas.drawCircle(center(d), size / 22, Paint()..color = active ? activeColor : dotColor);
      if (active) {
        canvas.drawCircle(center(d), size / 12, Paint()..color = activeColor.withValues(alpha: 0.15));
        // رقم ترتيب النقطة عشان الفني يعرف البداية
        if (d == dots.first) {
          canvas.drawCircle(
            center(d),
            size / 12,
            Paint()
              ..color = activeColor
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_PatternPainter old) => true;
}
