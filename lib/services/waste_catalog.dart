import 'package:flutter/material.dart';

/// Categoría de separación de residuos (código de colores de Colombia).
@immutable
class WasteCategory {
  final String id;
  final String name;
  final String container;
  final Color color;
  final Color onColor;
  final List<String> aliases;
  final bool isUnknown;

  const WasteCategory({
    required this.id,
    required this.name,
    required this.container,
    required this.color,
    required this.onColor,
    this.aliases = const <String>[],
    this.isUnknown = false,
  });

  /// Blanco y amarillo necesitan contorno para no perderse en el fondo.
  bool get needsOutline => color.computeLuminance() > 0.75;

  String get label => isUnknown ? name : '$name · $container';
}

/// Catálogo de las 7 clases del modelo waste_classifier.
///
/// Los `id` deben coincidir con las líneas de `assets/model/labels.txt`.
/// En `match()` se aceptan alias en español/inglés para tolerar variantes
/// del `data.yaml` de entrenamiento (paper, cardboard, plastic, glass...).
class WasteCatalog {
  const WasteCatalog._();

  static const WasteCategory papelCarton = WasteCategory(
    id: 'papel_carton',
    name: 'Papel y cartón',
    container: 'Azul',
    color: Color(0xFF1565C0),
    onColor: Colors.white,
    aliases: <String>[
      'papel',
      'carton',
      'cartón',
      'paper',
      'cardboard',
      'paper_and_cardboard',
      'papel_y_carton',
      'carton_papel',
      'azul_papel_carton',
      'azul_papel_y_carton',
    ],
  );

  static const WasteCategory metales = WasteCategory(
    id: 'metales',
    name: 'Metales',
    container: 'Amarillo',
    color: Color(0xFFF9A825),
    onColor: Colors.black,
    aliases: <String>[
      'metal',
      'metálico',
      'metalico',
      'lata',
      'latas',
      'can',
      'cans',
      'aluminium',
      'aluminum',
      'metal_and_aluminium',
      'amarillo_metales',
    ],
  );

  static const WasteCategory plasticos = WasteCategory(
    id: 'plasticos',
    name: 'Plásticos',
    container: 'Blanco',
    color: Color(0xFFFFFFFF),
    onColor: Colors.black,
    aliases: <String>[
      'plastico',
      'plástico',
      'plastic',
      'plastics',
      'pet',
      'botella',
      'bottle',
      'bolsa',
      'bag',
      'blanco_plasticos',
    ],
  );

  static const WasteCategory vidrio = WasteCategory(
    id: 'vidrio',
    name: 'Vidrio',
    container: 'Gris',
    color: Color(0xFF757575),
    onColor: Colors.white,
    aliases: <String>['glass', 'botella_vidrio', 'glass_bottle', 'gris_vidrio'],
  );

  static const WasteCategory organicos = WasteCategory(
    id: 'organicos',
    name: 'Orgánicos',
    container: 'Marrón',
    color: Color(0xFF6D4C41),
    onColor: Colors.white,
    aliases: <String>[
      'organico',
      'orgánico',
      'organic',
      'organics',
      'food',
      'comida',
      'restos',
      'biodegradable',
      'marron_organicos',
    ],
  );

  static const WasteCategory peligrosos = WasteCategory(
    id: 'peligrosos',
    name: 'Peligrosos',
    container: 'Rojo',
    color: Color(0xFFC62828),
    onColor: Colors.white,
    aliases: <String>[
      'peligroso',
      'hazardous',
      'hazardous_waste',
      'bateria',
      'batería',
      'battery',
      'pilas',
      'medico',
      'medical',
      'rojo_peligrosos',
    ],
  );

  static const WasteCategory generales = WasteCategory(
    id: 'generales',
    name: 'Generales / No aprovechables',
    container: 'Negro',
    color: Color(0xFF212121),
    onColor: Colors.white,
    aliases: <String>[
      'general',
      'generales',
      'no_aprovechable',
      'no_aprovechables',
      'trash',
      'garbage',
      'basura',
      'other',
      'otros',
      'residuos',
      'negro_generales',
    ],
  );

  /// Orden canónico (el mismo de `labels.txt`).
  static const List<WasteCategory> categories = <WasteCategory>[
    papelCarton,
    metales,
    plasticos,
    vidrio,
    organicos,
    peligrosos,
    generales,
  ];

  /// Fallback para etiquetas que no estén en el catálogo.
  static const WasteCategory unknown = WasteCategory(
    id: 'desconocido',
    name: 'Sin clasificar',
    container: '—',
    color: Color(0xFF9E9E9E),
    onColor: Colors.black87,
    isUnknown: true,
  );

  static const Map<String, String> _replacements = <String, String>{
    'á': 'a',
    'é': 'e',
    'í': 'i',
    'ó': 'o',
    'ú': 'u',
    'ü': 'u',
    'ñ': 'n',
  };

  /// Normaliza "Papel y cartón" -> "papel_y_carton".
  static String normalize(String raw) {
    var value = raw.trim().toLowerCase();
    for (final entry in _replacements.entries) {
      value = value.replaceAll(entry.key, entry.value);
    }
    value = value.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    return value.replaceAll(RegExp(r'^_+|_+$'), '');
  }

  /// Resuelve una etiqueta del modelo a su categoría (por id o alias).
  static WasteCategory? match(String raw) {
    final normalized = normalize(raw);
    if (normalized.isEmpty) return null;
    for (final category in categories) {
      if (category.id == normalized) return category;
      for (final alias in category.aliases) {
        if (normalize(alias) == normalized) return category;
      }
    }
    return null;
  }
}
