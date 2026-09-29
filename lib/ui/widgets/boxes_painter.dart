import 'package:flutter/material.dart';

import '../../services/detector_service.dart';

/// Dibuja los bounding boxes sobre la foto (coordenadas normalizadas 0-1).
/// El mapeo letterbox (BoxFit.contain) se calcula aquí mismo.
class BoxesPainter extends CustomPainter {
  final List<Detection> detections;
  final Size imageSize;
  final Set<int> highlighted; // índices con traducción en el diccionario

  BoxesPainter({
    required this.detections,
    required this.imageSize,
    required this.highlighted,
  });

  /// Mapeo contain: también lo usa el hit-test de taps (ver PhotoScreen).
  static ({double scale, double ox, double oy}) containMap(Size widget, Size image) {
    final scale = (widget.width / image.width).clamp(0.0, double.infinity);
    final s = scale < (widget.height / image.height) ? scale : widget.height / image.height;
    final dw = image.width * s, dh = image.height * s;
    return (scale: s, ox: (widget.width - dw) / 2, oy: (widget.height - dh) / 2);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final m = containMap(size, imageSize);
    for (int i = 0; i < detections.length; i++) {
      final d = detections[i];
      final rect = Rect.fromLTRB(
        m.ox + d.xmin * imageSize.width * m.scale,
        m.oy + d.ymin * imageSize.height * m.scale,
        m.ox + d.xmax * imageSize.width * m.scale,
        m.oy + d.ymax * imageSize.height * m.scale,
      );
      final ok = highlighted.contains(i);
      final color = ok ? Colors.yellowAccent : Colors.white70;
      canvas.drawRect(
        rect,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = ok ? 3.5 : 2,
      );
      // Chip con etiqueta + score
      final label = '${d.label} ${(d.score * 100).toStringAsFixed(0)}%';
      final tp = TextPainter(
        text: TextSpan(
          text: ' $label ',
          style: const TextStyle(
              color: Colors.black, fontSize: 13, fontWeight: FontWeight.bold),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final chipTop = (rect.top - 22).clamp(0.0, size.height - 22);
      canvas.drawRect(
        Rect.fromLTWH(rect.left, chipTop, tp.width, 20),
        Paint()..color = color,
      );
      tp.paint(canvas, Offset(rect.left, chipTop + 2));
    }
  }

  @override
  bool shouldRepaint(covariant BoxesPainter old) =>
      old.detections != detections || old.highlighted != highlighted;
}
