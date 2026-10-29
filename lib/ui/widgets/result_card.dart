import 'package:flutter/material.dart';

import '../../models/classification.dart';
import '../../services/classifier_service.dart';
import '../../services/waste_catalog.dart';

/// Resultado de clasificación: color del contenedor, clase y confianza.
///
/// Se usa igual en cámara en vivo, foto y video. Con [compact] se reduce a una
/// sola línea de datos para superponer sobre el video.
class ResultCard extends StatelessWidget {
  final ClassScore? best;

  /// Ranking opcional (foto): clases siguientes con su probabilidad.
  final List<ClassScore> ranking;
  final bool demo;
  final int milliseconds;
  final bool compact;
  final String emptyMessage;

  const ResultCard({
    super.key,
    required this.best,
    this.ranking = const <ClassScore>[],
    this.demo = false,
    this.milliseconds = 0,
    this.compact = false,
    this.emptyMessage = 'Apunta al residuo y espera un instante…',
  });

  @override
  Widget build(BuildContext context) {
    final score = best;
    if (score == null) {
      return _EmptyResult(message: emptyMessage);
    }

    final category = score.category.isUnknown
        ? WasteCatalog.unknown
        : score.category;
    final lowConfidence = score.score < ClassifierService.minScore;
    final onColor = category.needsOutline ? Colors.black : Colors.white;

    if (compact) {
      return _CompactResult(
        score: score,
        category: category,
        onColor: onColor,
        lowConfidence: lowConfidence,
        demo: demo,
        milliseconds: milliseconds,
      );
    }

    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: category.color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: category.color.withValues(alpha: 0.65)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 54,
                height: 54,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: category.color,
                  borderRadius: BorderRadius.circular(12),
                  border: category.needsOutline
                      ? Border.all(color: Colors.black26)
                      : null,
                ),
                child: Icon(
                  category.isUnknown
                      ? Icons.help_outline
                      : Icons.recycling_outlined,
                  color: onColor,
                  size: 28,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      score.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      category.isUnknown
                          ? 'Etiqueta no reconocida: ${score.rawLabel}'
                          : 'Contenedor ${score.container.toLowerCase()}',
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                  ],
                ),
              ),
              Text(
                score.scorePct,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: lowConfidence ? muted : category.color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: score.score.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(
                lowConfidence ? muted : category.color,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              if (lowConfidence)
                _Chip(
                  icon: Icons.warning_amber_rounded,
                  label: 'Baja confianza · acerca el objeto',
                  color: const Color(0xFFFFB300),
                ),
              if (demo)
                _Chip(
                  icon: Icons.science_outlined,
                  label: 'Demo',
                  color: const Color(0xFFFFB300),
                ),
              if (!demo && milliseconds > 0)
                Text(
                  '$milliseconds ms',
                  style: TextStyle(fontSize: 11, color: muted),
                ),
            ],
          ),
          if (ranking.length > 1) ...<Widget>[
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Text(
              'Otras clases',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: muted,
              ),
            ),
            const SizedBox(height: 6),
            for (final item in ranking.skip(1))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: item.category.color,
                        shape: BoxShape.circle,
                        border: item.category.needsOutline
                            ? Border.all(color: Colors.black45, width: 0.8)
                            : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item.name,
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      item.scorePct,
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _CompactResult extends StatelessWidget {
  final ClassScore score;
  final WasteCategory category;
  final Color onColor;
  final bool lowConfidence;
  final bool demo;
  final int milliseconds;

  const _CompactResult({
    required this.score,
    required this.category,
    required this.onColor,
    required this.lowConfidence,
    required this.demo,
    required this.milliseconds,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.66),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: category.color.withValues(alpha: 0.85)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: category.color,
              borderRadius: BorderRadius.circular(10),
              border: category.needsOutline
                  ? Border.all(color: Colors.black26)
                  : null,
            ),
            child: Icon(
              category.isUnknown
                  ? Icons.help_outline
                  : Icons.recycling_outlined,
              color: onColor,
              size: 22,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  score.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  category.isUnknown
                      ? score.rawLabel
                      : 'Contenedor ${score.container.toLowerCase()}'
                            '${lowConfidence ? ' · baja confianza' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: lowConfidence
                        ? const Color(0xFFFFB300)
                        : Colors.white70,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            score.scorePct,
            style: TextStyle(
              color: lowConfidence ? Colors.white54 : Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyResult extends StatelessWidget {
  final String message;

  const _EmptyResult({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.center_focus_strong,
            color: Colors.white54,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _Chip({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
