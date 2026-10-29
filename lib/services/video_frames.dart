import 'package:flutter/services.dart';

class VideoMeta {
  final int durationMs;
  final int width;
  final int height;
  final int rotation;

  const VideoMeta({
    required this.durationMs,
    required this.width,
    required this.height,
    required this.rotation,
  });

  static VideoMeta fromMap(Map<String, dynamic> map) {
    return VideoMeta(
      durationMs: (map['durationMs'] as num?)?.toInt() ?? 0,
      width: (map['width'] as num?)?.toInt() ?? 0,
      height: (map['height'] as num?)?.toInt() ?? 0,
      rotation: (map['rotation'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Extrae fotogramas de un video local usando MediaMetadataRetriever.
///
/// El canal nativo está implementado en Android (`VideoFramesChannel.kt`).
/// En iOS/otras plataformas se lanza [UnsupportedError] con un mensaje claro.
class VideoFrames {
  static const MethodChannel _channel = MethodChannel('waste/video_frames');

  Future<VideoMeta> open(String path) async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'open',
        <String, Object>{'path': path},
      );
      if (result == null) {
        throw StateError('El video no devolvió metadatos.');
      }
      return VideoMeta.fromMap(result);
    } on MissingPluginException {
      throw UnsupportedError(
        'El análisis de video solo está implementado en Android por ahora.',
      );
    }
  }

  /// Devuelve el fotograma JPEG en [timeMs] ya rotado y escalado, o null.
  Future<Uint8List?> frame(int timeMs, {int maxWidth = 640}) async {
    try {
      return await _channel.invokeMethod<Uint8List>('frame', <String, Object>{
        'timeMs': timeMs,
        'maxWidth': maxWidth,
      });
    } on MissingPluginException {
      throw UnsupportedError(
        'El análisis de video solo está implementado en Android por ahora.',
      );
    }
  }

  Future<void> close() async {
    try {
      await _channel.invokeMethod<void>('close');
    } on MissingPluginException {
      // Nada que liberar en plataformas sin canal.
    } catch (_) {
      // El cierre no debe romper la navegación.
    }
  }
}
