import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/waste_catalog.dart';

class TimelineSegment {
  final int timeMs;
  final WasteCategory? category;

  const TimelineSegment({required this.timeMs, required this.category});
}

/// Franja de color con la clase detectada en cada fotograma del video.
///
/// Cada segmento ocupa desde su marca de tiempo hasta el siguiente muestreo,
/// así que se puede tocar para saltar a ese momento.
class ClassificationTimeline extends StatelessWidget {
  final List<TimelineSegment> segments;
  final int durationMs;
  final int positionMs;
  final ValueChanged<int>? onSeek;
  final double height;

  const ClassificationTimeline({
    super.key,
    required this.segments,
    required this.durationMs,
    required this.positionMs,
    this.onSeek,
    this.height = 10,
  });

  @override
  Widget build(BuildContext context) {
    final total = math.max(1, durationMs);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        void seek(Offset local) {
          if (onSeek == null || width <= 0) return;
          onSeek!((local.dx / width * total).round().clamp(0, total).toInt());
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) => seek(details.localPosition),
          onHorizontalDragUpdate: (details) => seek(details.localPosition),
          child: SizedBox(
            height: height,
            width: width,
            child: CustomPaint(
              painter: _TimelinePainter(
                segments: segments,
                durationMs: total,
                positionMs: positionMs.clamp(0, total).toInt(),
                emptyColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TimelinePainter extends CustomPainter {
  final List<TimelineSegment> segments;
  final int durationMs;
  final int positionMs;
  final Color emptyColor;

  const _TimelinePainter({
    required this.segments,
    required this.durationMs,
    required this.positionMs,
    required this.emptyColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final background = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(4),
    );
    canvas.drawRRect(background, Paint()..color = emptyColor);

    final paint = Paint();
    for (var i = 0; i < segments.length; i++) {
      final start = segments[i].timeMs.clamp(0, durationMs).toInt();
      final end = i + 1 < segments.length
          ? segments[i + 1].timeMs.clamp(start, durationMs).toInt()
          : durationMs;
      if (end <= start) continue;
      paint.color = segments[i].category?.color ?? Colors.grey.shade700;
      final left = size.width * start / durationMs;
      final right = size.width * end / durationMs;
      canvas.drawRect(
        Rect.fromLTRB(left, 0, math.max(left + 1, right), size.height),
        paint,
      );
    }

    final x = size.width * positionMs / durationMs;
    canvas.drawLine(
      Offset(x, 0),
      Offset(x, size.height),
      Paint()
        ..color = Colors.white
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter oldDelegate) {
    return oldDelegate.positionMs != positionMs ||
        oldDelegate.durationMs != durationMs ||
        oldDelegate.segments != segments ||
        oldDelegate.emptyColor != emptyColor;
  }
}
