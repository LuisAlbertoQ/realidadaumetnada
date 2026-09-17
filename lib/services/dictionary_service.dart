import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Entrada del diccionario: etiqueta ImageNet -> palabra + audio.
class VocabEntry {
  final String labelEn;
  final String palabra;
  final String audioAsset; // ej. "audio/taza_quechua.mp3" (para AssetSource)

  const VocabEntry({
    required this.labelEn,
    required this.palabra,
    required this.audioAsset,
  });

  factory VocabEntry.fromJson(Map<String, dynamic> j) => VocabEntry(
        labelEn: (j['label_en'] as String).trim(),
        palabra: (j['palabra_quechua'] as String).trim(),
        audioAsset: (j['audio_asset'] as String).trim(),
      );
}

/// FASE 4: carga `assets/data/vocabulario.json` en memoria y resuelve matches.
class DictionaryService {
  static const String _dictAsset = 'assets/data/vocabulario.json';

  final Map<String, VocabEntry> _byLabel = {};

  int get size => _byLabel.length;

  Future<void> load() async {
    try {
      debugPrint('[DICC] Cargando $_dictAsset ...');
      final raw = await rootBundle.loadString(_dictAsset);
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      _byLabel.clear();
      for (final j in list) {
        final e = VocabEntry.fromJson(j);
        _byLabel[e.labelEn.toLowerCase()] = e;
      }
      debugPrint('[DICC] Entradas cargadas: ${_byLabel.length} (${_byLabel.keys.join(', ')})');
    } catch (e) {
      debugPrint('[DICC][ERROR] No se pudo cargar diccionario: $e');
      rethrow;
    }
  }

  /// Lookup case-insensitive. Retorna null si el label no está en el JSON.
  VocabEntry? lookup(String labelEn) {
    final e = _byLabel[labelEn.trim().toLowerCase()];
    if (e != null) {
      debugPrint('[DICC] Match: "$labelEn" -> "${e.palabra}" + ${e.audioAsset}');
    }
    return e;
  }
}
