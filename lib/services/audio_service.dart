import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// FASE 4: reproductor de audios locales (100% offline).
///
/// Cómo funciona:
/// - Los `.mp3` viven en `assets/audio/` y se declaran en `pubspec.yaml`
///   (`- assets/audio/` empaqueta todo el directorio).
/// - El JSON guarda la ruta relativa SIN el prefijo `assets/`,
///   ej. "audio/taza_quechua.mp3" -> se reproduce con `AssetSource(...)`.
/// - Si el archivo falta, `audioplayers` lanza excepción: aquí se captura
///   y se deja log claro en vez de crashear.
class AudioService {
  final AudioPlayer _player = AudioPlayer();

  AudioService() {
    // Volumen al máximo para demo en aula; el modo release evita ducking raro.
    _player.setVolume(1.0);
  }

  /// Reproduce [assetPath] ej. "audio/taza_quechua.mp3". Corta el anterior.
  Future<void> play(String assetPath) async {
    try {
      debugPrint('[AUDIO] Reproduciendo $assetPath ...');
      await _player.stop();
      await _player.play(AssetSource(assetPath));
      debugPrint('[AUDIO] OK playing $assetPath');
    } catch (e) {
      debugPrint('[AUDIO][ERROR] No se pudo reproducir "$assetPath". '
          '¿Existe el .mp3 en assets/audio/ y reinstalaste el APK? Detalle: $e');
    }
  }

  Future<void> dispose() async {
    await _player.dispose();
    debugPrint('[AUDIO] Player liberado');
  }
}
