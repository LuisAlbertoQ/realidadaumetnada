import 'package:flutter/material.dart';

/// Aviso visible cuando las clasificaciones son simuladas (sin modelo).
class DemoBanner extends StatelessWidget {
  final String? message;

  const DemoBanner({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: const Color(0xFFF9A825),
      child: Row(
        children: <Widget>[
          const Icon(Icons.science_outlined, color: Colors.black87, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message ??
                  'MODO DEMO: el modelo no está instalado, '
                      'las clases son simuladas.',
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
