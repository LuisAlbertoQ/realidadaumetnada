import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/classification.dart';
import '../../services/waste_catalog.dart';
import 'category_badge.dart';

class ClassCount {
  final WasteCategory category;
  final int count;
  final double bestScore;

  const ClassCount({
    required this.category,
    required this.count,
    required this.bestScore,
  });
}

/// Cuenta en cuántos fotogramas ganó cada clase (resumen de video).
List<ClassCount> summarizeScores(Iterable<ClassScore?> bestPerFrame) {
  final counts = <String, int>{};
  final best = <String, double>{};
  final categories = <String, WasteCategory>{};

  for (final score in bestPerFrame) {
    if (score == null) continue;
    final id = score.category.id;
    categories[id] = score.category;
    counts[id] = (counts[id] ?? 0) + 1;
    best[id] = math.max(best[id] ?? 0, score.score);
  }

  final result = <ClassCount>[
    for (final id in counts.keys)
      ClassCount(
        category: categories[id]!,
        count: counts[id]!,
        bestScore: best[id]!,
      ),
  ]..sort((a, b) => b.count.compareTo(a.count));
  return result;
}

/// Distribución de clases encontradas en los fotogramas analizados.
class ClassSummary extends StatelessWidget {
  final List<ClassCount> counts;
  final String unit;
  final String emptyMessage;

  const ClassSummary({
    super.key,
    required this.counts,
    this.unit = 'fotogramas',
    this.emptyMessage = 'No se pudo clasificar ningún fotograma.',
  });

  @override
  Widget build(BuildContext context) {
    if (counts.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: <Widget>[
            const Icon(Icons.search_off, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(emptyMessage)),
          ],
        ),
      );
    }

    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: <Widget>[
          for (var i = 0; i < counts.length; i++) ...<Widget>[
            if (i > 0) const Divider(height: 16),
            Row(
              children: <Widget>[
                CategoryDot(category: counts[i].category, size: 14),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        counts[i].category.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '${counts[i].category.container} · mejor '
                        '${(counts[i].bestScore * 100).round()}%',
                        style: TextStyle(fontSize: 11, color: muted),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${counts[i].count}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 4),
                Text(unit, style: TextStyle(fontSize: 11, color: muted)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
