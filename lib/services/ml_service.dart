import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// FASE 3: Servicio de ML on-device.
/// Carga MobileNetV2 (.tflite) + labels.txt y expone [predict] para un [CameraImage].
class MlService {
  static const String _modelAsset = 'assets/model/mobilenet_v2.tflite';
  static const String _labelsAsset = 'assets/model/labels.txt';
  static const int inputSize = 224;
  // FASE 5.4: logs por frame desactivados (rendimiento). Solo init/errores.
  static const bool _verbose = false;

  Interpreter? _interpreter;
  List<String> _labels = [];

  bool get isLoaded => _interpreter != null && _labels.isNotEmpty;

  /// Carga modelo y etiquetas. Log claro para depuración (Regla #3).
  Future<void> loadModel() async {
    try {
      debugPrint('[ML] Cargando modelo $_modelAsset ...');
      // 1. Verifica que el asset esté empaquetado (falla claro si pubspec está mal)
      final ByteData bytes;
      try {
        bytes = await rootBundle.load(_modelAsset);
        debugPrint('[ML] Asset encontrado: ${bytes.lengthInBytes} bytes');
      } catch (e) {
        debugPrint('[ML][ERROR] Asset NO encontrado en bundle. '
            'Revisa pubspec.yaml -> assets/model/mobilenet_v2.tflite. Detalle: $e');
        rethrow;
      }
      final options = InterpreterOptions()..threads = 2;
      // 2. Intento principal: mmap directo del asset (requiere noCompress tflite)
      try {
        _interpreter = await Interpreter.fromAsset(_modelAsset, options: options);
        debugPrint('[ML] Interprete creado vía fromAsset');
      } catch (e, st) {
        debugPrint('[ML][WARN] fromAsset falló ($e). Plan B: copiar a archivo temporal y usar fromFile...');
        debugPrint('[ML][WARN] Stack: $st');
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/mobilenet_v2.tflite');
        await file.writeAsBytes(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
          flush: true,
        );
        debugPrint('[ML] Modelo copiado a ${file.path} (${await file.length()} bytes)');
        _interpreter = Interpreter.fromFile(file, options: options);
        debugPrint('[ML] Interprete creado vía fromFile');
      }
      debugPrint('[ML] Modelo cargado. '
          'input=${_interpreter!.getInputTensor(0).shape} '
          'type=${_interpreter!.getInputTensor(0).type} '
          'output=${_interpreter!.getOutputTensor(0).shape}');

      final raw = await rootBundle.loadString(_labelsAsset);
      _labels = raw.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      debugPrint('[ML] Etiquetas cargadas: ${_labels.length}');
    } catch (e, st) {
      debugPrint('[ML][ERROR] No se pudo cargar modelo/labels: $e');
      debugPrint('[ML][ERROR] Stack: $st');
      rethrow;
    }
  }

  /// Ejecuta inferencia y retorna (label, probabilidad).
  /// Retorna null si el modelo no está cargado.
  Future<({String label, double prob})?> predict(CameraImage frame) async {
    if (!isLoaded) {
      debugPrint('[ML][WARN] predict() llamado sin modelo cargado');
      return null;
    }
    try {
      final input = _preprocess(frame); // [1][224][224][3] float32
      // El buffer de salida debe usar la dimensión REAL del modelo (1000),
      // no labels.length (1001 con 'background'). Si no, shape mismatch.
      final outputDim = _interpreter!.getOutputTensor(0).shape.last;
      final output = List.filled(outputDim, 0.0).reshape([1, outputDim]);
      _interpreter!.run(input, output);

      final probs = (output[0] as List).cast<double>();
      int bestIdx = 0;
      for (int i = 1; i < probs.length; i++) {
        if (probs[i] > probs[bestIdx]) bestIdx = i;
      }
      // labels.txt trae 'background' en 0 + 1000 clases; el modelo solo da 1000.
      // Se compensa con offset +1 cuando aplica.
      final hasBackgroundOffset = _labels.length == outputDim + 1;
      final labelIdx = hasBackgroundOffset ? bestIdx + 1 : bestIdx;
      final label = (labelIdx >= 0 && labelIdx < _labels.length)
          ? _labels[labelIdx]
          : 'idx_$bestIdx';
      final result = (label: label, prob: probs[bestIdx]);
      if (_verbose) {
        debugPrint('[ML] Detectado: ${result.label} (${(result.prob * 100).toStringAsFixed(1)}%)');
      }
      return result;
    } catch (e) {
      debugPrint('[ML][ERROR] Fallo inferencia: $e');
      return null;
    }
  }

  /// YUV420/BGRA -> RGB 224x224 float32 normalizado [-1, 1] (preprocess MobileNetV2).
  List _preprocess(CameraImage frame) {
    final rgb = _toRgbImage(frame);
    final resized = img.copyResize(rgb, width: inputSize, height: inputSize);

    // [1,224,224,3]
    final input = List.generate(
      1,
      (_) => List.generate(
        inputSize,
        (y) => List.generate(inputSize, (x) {
          final p = resized.getPixel(x, y);
          return [((p.r - 127.5) / 127.5), ((p.g - 127.5) / 127.5), ((p.b - 127.5) / 127.5)];
        }),
      ),
    );
    return input;
  }

  img.Image _toRgbImage(CameraImage frame) {
    if (frame.format.group == ImageFormatGroup.bgra8888) {
      // iOS: un solo plano BGRA
      final bytes = frame.planes[0].bytes;
      final w = frame.width, h = frame.height;
      final out = img.Image(width: w, height: h);
      for (int i = 0; i < w * h; i++) {
        final b = bytes[i * 4], g = bytes[i * 4 + 1], r = bytes[i * 4 + 2];
        out.setPixelRgb(i % w, i ~/ w, r, g, b);
      }
      return out;
    }
    // Android: YUV420 (3 planos)
    final w = frame.width, h = frame.height;
    final yPlane = frame.planes[0].bytes;
    final uPlane = frame.planes[1].bytes;
    final vPlane = frame.planes[2].bytes;
    final yRowStride = frame.planes[0].bytesPerRow;
    final uvRowStride = frame.planes[1].bytesPerRow;
    final uvPixelStride = frame.planes[1].bytesPerPixel ?? 1;

    final out = img.Image(width: w, height: h);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final yVal = yPlane[y * yRowStride + x];
        final uvX = x ~/ 2, uvY = y ~/ 2;
        final uVal = uPlane[uvY * uvRowStride + uvX * uvPixelStride];
        final vVal = vPlane[uvY * uvRowStride + uvX * uvPixelStride];
        final r = (yVal + 1.370705 * (vVal - 128)).clamp(0, 255).toInt();
        final g = (yVal - 0.337633 * (uVal - 128) - 0.698001 * (vVal - 128)).clamp(0, 255).toInt();
        final b = (yVal + 1.732446 * (uVal - 128)).clamp(0, 255).toInt();
        out.setPixelRgb(x, y, r, g, b);
      }
    }
    // Rotación 90° típica en portrait Android; si ves labels raros, ajusta aquí.
    return img.copyRotate(out, angle: 90);
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    debugPrint('[ML] Interpreter liberado');
  }
}
