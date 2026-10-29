import 'package:flutter/foundation.dart';

import '../services/waste_catalog.dart';

/// Probabilidad de una clase para una imagen o fotograma.
@immutable
class ClassScore {
  final WasteCategory category;
  final String rawLabel;
  final double score;

  const ClassScore({
    required this.category,
    required this.rawLabel,
    required this.score,
  });

  /// Nombre visible: el del catálogo o la etiqueta cruda si no se reconoce.
  String get name => category.isUnknown ? rawLabel : category.name;

  String get container =>
      category.isUnknown ? 'Sin clasificar' : category.container;

  String get scorePct => '${(score * 100).round()}%';
}

/// Resultado de clasificar una imagen completa: ranking de clases.
@immutable
class Classification {
  /// Ordenado de mayor a menor probabilidad. Puede estar vacío.
  final List<ClassScore> top;

  /// `true` cuando el resultado lo generó el modo demo (sin modelo).
  final bool demo;

  const Classification({required this.top, this.demo = false});

  static const Classification empty = Classification(top: <ClassScore>[]);

  ClassScore? get best => top.isEmpty ? null : top.first;

  bool get isEmpty => top.isEmpty;

  ClassScore? forCategory(WasteCategory category) {
    for (final item in top) {
      if (item.category.id == category.id) return item;
    }
    return null;
  }
}

/// Resultado estabilizado de varios cuadros consecutivos (cámara en vivo).
@immutable
class SmoothedLabel {
  final WasteCategory category;
  final String rawLabel;

  /// Confianza media de [category] dentro de la ventana.
  final double score;
  final int votes;
  final int samples;

  const SmoothedLabel({
    required this.category,
    required this.rawLabel,
    required this.score,
    required this.votes,
    required this.samples,
  });

  String get name => category.isUnknown ? rawLabel : category.name;
  String get container =>
      category.isUnknown ? 'Sin clasificar' : category.container;
  String get scorePct => '${(score * 100).round()}%';

  /// Proporción de cuadros de la ventana que votaron por esta categoría.
  double get agreement => samples == 0 ? 0 : votes / samples;
}
