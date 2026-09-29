import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

/// Detección: etiqueta COCO + score + caja normalizada [ymin, xmin, ymax, xmax].
class Detection {
  final String label;
  final double score;
  final double ymin, xmin, ymax, xmax;

  const Detection({
    required this.label,
    required this.score,
    required this.ymin,
    required this.xmin,
    required this.ymax,
    required this.xmax,
  });
}

/// Servicio de DETECCIÓN (SSD MobileNetV2 cuantizado, 300x300 uint8).
/// Una inferencia por foto capturada (no stream): sin throttle ni cooldown.
class DetectorService {
  static const String _modelAsset = 'assets/model/detect.tflite';
  static const String _labelsAsset = 'assets/model/coco_labels.txt';
  static const int inputSize = 300;
  static const int maxResults = 10;

  Interpreter? _interpreter;
  List<String> _labels = [];

  bool get isLoaded => _interpreter != null && _labels.isNotEmpty;

  /// Diagnóstico visible en UI (sin logcat): mejor score crudo + último error.
  String lastBest = '-';
  String lastError = '';
  String lastStack = '';

  /// Info del modelo + resultado del self-test (se muestran en vivo).
  String modelInfo = '';
  String selfTest = 'no ejecutado';

  Future<void> loadModel() async {
    try {
      debugPrint('[DET] Cargando modelo $_modelAsset ...');
      final bytes = await rootBundle.load(_modelAsset);
      debugPrint('[DET] Asset encontrado: ${bytes.lengthInBytes} bytes');
      final options = InterpreterOptions()..threads = 4;
      _interpreter = await Interpreter.fromAsset(_modelAsset, options: options);
      debugPrint('[DET] Interprete OK. '
          'input=${_interpreter!.getInputTensor(0).shape} '
          'type=${_interpreter!.getInputTensor(0).type}');

      final raw = await rootBundle.loadString(_labelsAsset);
      _labels =
          raw.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      debugPrint('[DET] Labels COCO: ${_labels.length}');

      // Ficha del modelo para mostrar en pantalla.
      final inT = _interpreter!.getInputTensor(0);
      final outT = _interpreter!.getOutputTensors();
      modelInfo =
          'in=${inT.shape} ${inT.type} | outs=${outT.map((t) => '${t.shape}').join(', ')}';

      // Self-test: ceros directos al intérprete, SIN foto ni preproceso.
      // Si esto falla, el problema es modelo↔runtime (no la cámara/JPEG).
      try {
        final zeros = List<int>.filled(
            inputSize * inputSize * 3, 0).reshape([1, inputSize, inputSize, 3]);
        // OJO: con N salidas se usa runForMultipleInputs, NO run()
        // (run() envuelve el Map como salida única y revienta en outputs[1]!).
        _interpreter!.runForMultipleInputs([zeros], _emptyOutputs());
        selfTest = 'OK';
      } catch (e, st) {
        selfTest = 'FALLO: $e';
        lastStack = '$st';
      }
    } catch (e, st) {
      debugPrint('[DET][ERROR] No se pudo cargar detector: $e\n$st');
      rethrow;
    }
  }

  /// Corre el detector sobre la foto [file]. Retorna detecciones con
  /// score >= [minScore], ordenadas de mayor a menor.
  /// NO usa el JSON: detecta todo lo que el modelo ve; el diccionario
  /// solo decide el resaltado y el contenido del BottomSheet (en la UI).
  Future<List<Detection>> detect(File file, {double minScore = 0.5}) async {
    if (!isLoaded) {
      lastError = 'modelo no cargado';
      return [];
    }
    // Etapa 1: preproceso (fuera del try de inferencia para aislar el fallo)
    late final Object input;
    try {
      // Lista anidada [1,300,300,3] de ints 0-255: el formato que
      // tflite_flutter acepta sin null-check (Uint8List crudo lo rompe).
      input = _preprocess(file).reshape([1, inputSize, inputSize, 3]);
    } catch (e) {
      lastError = 'preproceso: $e';
      return [];
    }
    // Etapa 2: buffers dimensionados con las formas REALES del modelo
    // (no asumir [1,10]/[1] a mano: ahí estaba el crash de null-check).
    late final Map<int, Object> outs;
    try {
      outs = _emptyOutputs();
    } catch (e) {
      lastError = 'buffers: $e';
      return [];
    }
    // Etapa 3: inferencia (runForMultipleInputs: el modelo tiene 4 salidas;
    // run() simple las envolvería como una sola y fallaría en outputs[1]!).
    try {
      _interpreter!.runForMultipleInputs([input], outs);
    } catch (e, st) {
      lastError = 'inferencia: $e';
      lastStack = '$st';
      return [];
    }
    // Etapa 4: lectura defensiva (acepta escalar o [1] en el conteo)
    try {
      final boxes = outs[0] as List;
      final classes = outs[1] as List;
      final scores = outs[2] as List;
      final n = _readCount(outs[3]).clamp(0, maxResults);
      double topScore = 0;
      String topLabel = '-';
      final int m = n.clamp(0, (boxes[0] as List).length);
      for (int i = 0; i < m; i++) {
        final s = ((scores[0] as List)[i] as num).toDouble();
        if (s > topScore) {
          topScore = s;
          final ci = ((classes[0] as List)[i] as num).toInt();
          topLabel = (ci >= 0 && ci < _labels.length) ? _labels[ci] : 'cls_$ci';
        }
      }
      lastBest = '$topLabel ${(topScore * 100).toStringAsFixed(0)}% (n=$n)';
      lastError = '';
      final out = <Detection>[];
      for (int i = 0; i < m; i++) {
        final score = ((scores[0] as List)[i] as num).toDouble();
        if (score < minScore) continue;
        final cls = ((classes[0] as List)[i] as num).toInt();
        if (cls < 0 || cls >= _labels.length) continue;
        final b = ((boxes[0] as List)[i] as List).map((e) => (e as num).toDouble()).toList();
        out.add(Detection(
          label: _labels[cls],
          score: score,
          ymin: b[0].clamp(0.0, 1.0),
          xmin: b[1].clamp(0.0, 1.0),
          ymax: b[2].clamp(0.0, 1.0),
          xmax: b[3].clamp(0.0, 1.0),
        ));
      }
      out.sort((a, b) => b.score.compareTo(a.score));
      return out;
    } catch (e, st) {
      lastError = 'lectura: $e';
      lastStack = '$st';
      return [];
    }
  }

  /// Buffers de salida vacíos con las formas reales del modelo.
  Map<int, Object> _emptyOutputs() {
    final outTensors = _interpreter!.getOutputTensors();
    return {
      for (int i = 0; i < outTensors.length; i++)
        i: List.filled(
          outTensors[i].shape.reduce((a, b) => a * b),
          0.0,
        ).reshape(outTensors[i].shape),
    };
  }

  /// El tensor de conteo puede venir como [1] anidado o escalar según runtime.
  int _readCount(Object? o) {
    if (o is List && o.isNotEmpty) {
      final f = o[0];
      if (f is List && f.isNotEmpty && f[0] is num) return (f[0] as num).toInt();
      if (f is num) return f.toInt();
    }
    if (o is num) return o.toInt();
    return maxResults;
  }

  /// JPEG -> lista plana RGB 300x300 de ints 0-255
  /// (el modelo cuantizado NO normaliza; el reshape a [1,300,300,3] lo hace run).
  List<int> _preprocess(File file) {
    final decoded = img.decodeImage(file.readAsBytesSync());
    if (decoded == null) throw StateError('No se pudo decodificar la foto');
    final resized = img.copyResize(decoded, width: inputSize, height: inputSize);
    final bytes = List<int>.filled(inputSize * inputSize * 3, 0);
    int o = 0;
    for (int y = 0; y < inputSize; y++) {
      for (int x = 0; x < inputSize; x++) {
        final p = resized.getPixel(x, y);
        bytes[o++] = p.r.toInt().clamp(0, 255);
        bytes[o++] = p.g.toInt().clamp(0, 255);
        bytes[o++] = p.b.toInt().clamp(0, 255);
      }
    }
    return bytes;
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
  }
}
