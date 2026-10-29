import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../services/classifier_math.dart';

/// Imagen con un marco cuadrado ajustable: arrastra para moverlo y pellizca
/// para agrandarlo o achicarlo. Lo que queda fuera se oscurece.
class CropSelector extends StatefulWidget {
  final ui.Image image;
  final SquareCrop crop;
  final ValueChanged<SquareCrop> onChanged;
  final ValueChanged<SquareCrop>? onChangedEnd;

  const CropSelector({
    super.key,
    required this.image,
    required this.crop,
    required this.onChanged,
    this.onChangedEnd,
  });

  @override
  State<CropSelector> createState() => _CropSelectorState();
}

class _CropSelectorState extends State<CropSelector> {
  double _startSize = 1;
  double _centerX = 0.5;
  double _centerY = 0.5;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final box = Size(constraints.maxWidth, constraints.maxHeight);
        if (!box.width.isFinite ||
            !box.height.isFinite ||
            box.width <= 0 ||
            box.height <= 0) {
          return const SizedBox.shrink();
        }

        final aspect = widget.image.width / widget.image.height;
        final content = _containRect(box, aspect);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onScaleStart: (_) {
            _startSize = widget.crop.size;
            _centerX = widget.crop.centerX;
            _centerY = widget.crop.centerY;
          },
          onScaleUpdate: (details) {
            _centerX += details.focalPointDelta.dx / content.width;
            _centerY += details.focalPointDelta.dy / content.height;
            final next = SquareCrop(
              size: _startSize * details.scale,
              centerX: _centerX,
              centerY: _centerY,
            ).clamp(aspect);
            _centerX = next.centerX;
            _centerY = next.centerY;
            widget.onChanged(next);
          },
          onScaleEnd: (_) => widget.onChangedEnd?.call(widget.crop),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Positioned.fromRect(
                rect: content,
                child: RawImage(image: widget.image, fit: BoxFit.fill),
              ),
              CustomPaint(
                painter: CropPainter(content: content, crop: widget.crop),
              ),
            ],
          ),
        );
      },
    );
  }
}

Rect _containRect(Size box, double aspect) {
  final scale = math.min(box.width / aspect, box.height);
  return Rect.fromCenter(
    center: box.center(Offset.zero),
    width: aspect * scale,
    height: scale,
  );
}

/// Rectángulo que ocupa la imagen mostrada con `BoxFit.cover` dentro de [box].
///
/// Con `cover` la imagen se recorta para llenar el espacio, así que el
/// rectángulo puede sobresalir del widget. Es lo que hace el preview de la
/// cámara; el marco debe usar esta misma transformación para no mentir sobre
/// la región analizada.
Rect coverRect(Size box, double aspect) {
  if (aspect <= 0 || !aspect.isFinite) return Offset.zero & box;
  final height = math.max(box.width / aspect, box.height);
  return Rect.fromCenter(
    center: box.center(Offset.zero),
    width: aspect * height,
    height: height,
  );
}

/// Dibuja el marco y oscurece lo que queda fuera.
class CropPainter extends CustomPainter {
  /// Rectángulo que ocupa la imagen dentro del widget.
  final Rect content;
  final SquareCrop crop;

  const CropPainter({required this.content, required this.crop});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || content.isEmpty) return;

    final side = crop.size * math.min(content.width, content.height);
    final square = Rect.fromCenter(
      center: Offset(
        content.left + crop.centerX * content.width,
        content.top + crop.centerY * content.height,
      ),
      width: side,
      height: side,
    );

    // Zona de la imagen que no se analiza.
    final outside = Path.combine(
      PathOperation.difference,
      Path()..addRect(content),
      Path()..addRect(square),
    );
    canvas.drawPath(
      outside,
      Paint()..color = Colors.black.withValues(alpha: 0.5),
    );

    // Bandas del letterbox (fuera de la imagen).
    final letterbox = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addRect(content),
    );
    canvas.drawPath(
      letterbox,
      Paint()..color = Colors.black.withValues(alpha: 0.65),
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(square, const Radius.circular(10)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.white.withValues(alpha: 0.85),
    );

    // Esquinas.
    final corner = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = Colors.greenAccent;
    const arm = 18.0;
    void cornerPath(Offset point, double dx, double dy) {
      canvas.drawLine(point, point + Offset(dx * arm, 0), corner);
      canvas.drawLine(point, point + Offset(0, dy * arm), corner);
    }

    cornerPath(square.topLeft, 1, 1);
    cornerPath(square.topRight, -1, 1);
    cornerPath(square.bottomLeft, 1, -1);
    cornerPath(square.bottomRight, -1, -1);
  }

  @override
  bool shouldRepaint(covariant CropPainter oldDelegate) {
    return oldDelegate.crop != crop || oldDelegate.content != content;
  }
}
