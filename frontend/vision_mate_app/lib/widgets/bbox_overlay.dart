import 'package:flutter/material.dart';
import '../models/api_models.dart';

class BBoxOverlay extends StatelessWidget {
  final List<ObjectDetection> objects;
  final double previewWidth;
  final double previewHeight;
  const BBoxOverlay({
    super.key,
    required this.objects,
    required this.previewWidth,
    required this.previewHeight,
  });

  Color _colorFor(String name) {
    if (name.contains('person')) return Colors.greenAccent;
    if (name.contains('chair')) return Colors.orangeAccent;
    if (name.contains('door')) return Colors.blueAccent;
    return Colors.purpleAccent;
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _BBoxPainter(objects, previewWidth, previewHeight, _colorFor),
      size: Size.infinite,
    );
  }
}

class _BBoxPainter extends CustomPainter {
  final List<ObjectDetection> objects;
  final double w;
  final double h;
  final Color Function(String) colorFor;
  _BBoxPainter(this.objects, this.w, this.h, this.colorFor);

  @override
  void paint(Canvas canvas, Size size) {
    if (w == 0 || h == 0) return;
    final scaleX = size.width / w;
    final scaleY = size.height / h;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final textStyle = TextStyle(
      color: Colors.white,
      fontSize: 10,
      shadows: [Shadow(color: Colors.black, blurRadius: 4)],
    );

    for (final o in objects) {
      paint.color = colorFor(o.name).withOpacity(0.9);
      final rect = Rect.fromLTWH(
        o.x * scaleX,
        o.y * scaleY,
        o.w * scaleX,
        o.h * scaleY,
      );
      canvas.drawRect(rect, paint);
      final tp = TextPainter(
        text: TextSpan(text: o.name, style: textStyle),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, rect.topLeft.translate(2, -tp.height));
    }
  }

  @override
  bool shouldRepaint(covariant _BBoxPainter old) => old.objects != objects;
}
