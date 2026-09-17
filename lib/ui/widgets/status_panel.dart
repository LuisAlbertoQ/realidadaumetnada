import 'package:flutter/material.dart';

/// FASE 5.2: Panel flotante semitransparente inferior.
/// "Buscando objetos..." en reposo / "¡Encontrado: X!" tras match.
class StatusPanel extends StatelessWidget {
  final String status;
  final String lastLabel;
  final bool found;

  const StatusPanel({
    super.key,
    required this.status,
    required this.lastLabel,
    required this.found,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 16,
      right: 16,
      bottom: 18,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.62),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: found ? Colors.yellowAccent : Colors.white24,
              width: found ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                found ? Icons.check_circle : Icons.radar,
                color: found ? Colors.yellowAccent : Colors.greenAccent,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  found ? '¡Encontrado: $lastLabel!' : 'Buscando objetos...  ($status)',
                  style: TextStyle(
                    color: found ? Colors.yellowAccent : Colors.white,
                    fontSize: 15,
                    fontWeight: found ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
