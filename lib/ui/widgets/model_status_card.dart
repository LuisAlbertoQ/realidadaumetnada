import 'package:flutter/material.dart';

import '../../services/classifier_service.dart';
import '../../services/waste_catalog.dart';

/// Ficha del estado del modelo: cargado / demo / error + shapes reales.
class ModelStatusCard extends StatelessWidget {
  final ClassifierService classifier;

  const ModelStatusCard({super.key, required this.classifier});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final (:color, :icon, :title, :detail) = switch (classifier.status) {
      ClassifierStatus.idle || ClassifierStatus.loading => (
        color: Colors.blueGrey,
        icon: Icons.hourglass_top,
        title: 'Cargando modelo…',
        detail: 'Leyendo ${ClassifierService.labelsAsset}',
      ),
      ClassifierStatus.ready => (
        color: const Color(0xFF66BB6A),
        icon: Icons.check_circle_outline,
        title: 'Modelo listo',
        detail: classifier.modelInfo,
      ),
      ClassifierStatus.demo => (
        color: const Color(0xFFFFB300),
        icon: Icons.science_outlined,
        title: 'Modo demo · sin modelo',
        detail:
            'La app funciona con clases simuladas. '
            'Instala ${ClassifierService.modelAsset} para clasificar de verdad.',
      ),
      ClassifierStatus.error => (
        color: const Color(0xFFEF5350),
        icon: Icons.error_outline,
        title: 'Error del modelo',
        detail: classifier.lastError.isEmpty
            ? 'Revisa el .tflite y labels.txt'
            : classifier.lastError,
      ),
    };

    final warnSelfTest = classifier.isReady && classifier.selfTest != 'OK';
    final warnLabels =
        classifier.isReady &&
        classifier.labelCount != WasteCatalog.categories.length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              if (classifier.isReady)
                Text(
                  '${classifier.labelCount} clases',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            detail,
            maxLines: 6,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (classifier.isReady) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              'Self-test: ${classifier.selfTest}'
              '${classifier.lastBest != '-' ? ' · última: ${classifier.lastBest}' : ''}',
              style: TextStyle(
                fontSize: 11,
                color: warnSelfTest
                    ? const Color(0xFFFFB300)
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (warnLabels) ...<Widget>[
            const SizedBox(height: 6),
            const Text(
              'labels.txt no tiene 7 clases: revisa que el orden coincida '
              'con el entrenamiento.',
              style: TextStyle(fontSize: 11, color: Color(0xFFFFB300)),
            ),
          ],
        ],
      ),
    );
  }
}
