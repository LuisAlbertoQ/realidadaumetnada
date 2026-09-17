import 'package:flutter/material.dart';

/// FASE 5.3: Tarjeta flotante de alto contraste (legible a ~1m).
/// Amarillo brillante sobre negro 80% + sombras duras + escala grande.
class ArLabelCard extends StatelessWidget {
  final String palabra;
  final String labelEn;
  final double prob;

  const ArLabelCard({
    super.key,
    required this.palabra,
    required this.labelEn,
    required this.prob,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 22),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.yellowAccent, width: 3),
          boxShadow: const [
            BoxShadow(color: Colors.black54, blurRadius: 18, spreadRadius: 2),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '✨ OBJETO DETECTADO ✨',
              style: TextStyle(
                color: Colors.yellowAccent,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              palabra,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.yellowAccent,
                fontSize: 58,
                fontWeight: FontWeight.w900,
                height: 1.0,
                shadows: [
                  Shadow(color: Colors.black, blurRadius: 8, offset: Offset(2, 2)),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '($labelEn) · ${(prob * 100).toStringAsFixed(0)}% · 🔊',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                shadows: [Shadow(color: Colors.black, blurRadius: 6)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
