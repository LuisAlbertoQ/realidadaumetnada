import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/classification.dart';
import 'classifier_math.dart';
import 'waste_catalog.dart';

enum ClassifierStatus { idle, loading, ready, demo, error }

/// Clasificador on-device de residuos (7 clases, imagen completa).
///
/// Espera un modelo de clasificación en [modelAsset] con entrada
/// `[1, 224, 224, 3]` NHWC y salida `[1, 7]` logits. Si el archivo no está,
/// entra en [ClassifierStatus.demo] con resultados simulados para poder
/// probar cámara, foto y video.
class ClassifierService extends ChangeNotifier {
  ClassifierService._();

  static final ClassifierService instance = ClassifierService._();

  static const String modelAsset = 'assets/model/waste_classifier.tflite';
  static const String labelsAsset = 'assets/model/labels.txt';

  /// Confianza mínima para considerar fiable una predicción.
  static const double minScore = 0.35;

  /// Cuántas clases devolver en el ranking (`top-3` en la UI).
  static const int topK = 3;

  Interpreter? _interpreter;
  List<String> _labels = const <String>[];
  ClassifierStatus _status = ClassifierStatus.idle;
  int _inputW = kModelSize;
  int _inputH = kModelSize;
  Future<void>? _loading;
  int _demoTick = 0;

  String modelInfo = 'Sin cargar';
  String selfTest = 'no ejecutado';
  String lastBest = '-';
  String lastError = '';
  int lastInferenceMs = 0;

  ClassifierStatus get status => _status;
  bool get isReady => _status == ClassifierStatus.ready;
  bool get isDemo => _status == ClassifierStatus.demo;
  bool get hasModel => _interpreter != null;
  List<String> get labels => List<String>.unmodifiable(_labels);
  int get labelCount => _labels.length;
  int get inputWidth => _inputW;
  int get inputHeight => _inputH;

  /// Carga perezosa e idempotente (una sola vez por proceso).
  Future<void> ensureLoaded() {
    if (_status == ClassifierStatus.ready ||
        _status == ClassifierStatus.demo ||
        _status == ClassifierStatus.error) {
      return Future<void>.value();
    }
    return _loading ??= _load();
  }

  Future<void> _load() async {
    _status = ClassifierStatus.loading;
    notifyListeners();

    try {
      _labels = await _readLabels();
    } catch (e, stack) {
      _status = ClassifierStatus.error;
      lastError = 'No se pudo leer $labelsAsset: $e';
      debugPrint('[CLS] $lastError\n$stack');
      notifyListeners();
      return;
    }

    Interpreter interpreter;
    try {
      interpreter = await Interpreter.fromAsset(
        modelAsset,
        options: InterpreterOptions()..threads = 4,
      );
    } catch (e, stack) {
      _interpreter = null;
      _status = ClassifierStatus.demo;
      modelInfo = 'Modo demo · falta ${modelAsset.split('/').last}';
      selfTest = 'no aplica';
      lastError =
          'Modelo no instalado. Las clasificaciones son simuladas.\n'
          'Coloca tu .tflite en $modelAsset y reconstruye la app.\n\n$e';
      debugPrint('[CLS] Modelo no disponible: $e\n$stack');
      notifyListeners();
      return;
    }

    try {
      _interpreter = interpreter;
      final inputTensor = interpreter.getInputTensor(0);
      final shape = inputTensor.shape;
      if (shape.length != 4 || shape.last != 3) {
        throw StateError(
          'Entrada no soportada: $shape. Se espera [1, alto, ancho, 3] (NHWC).',
        );
      }
      if (inputTensor.type != TensorType.float32 &&
          inputTensor.type != TensorType.uint8 &&
          inputTensor.type != TensorType.int8) {
        throw StateError(
          'Entrada ${inputTensor.type.name} no soportada en CPU. '
          'Usa float32 (recomendado) o int8/uint8.',
        );
      }
      _inputH = shape[1];
      _inputW = shape[2];

      final outputTensor = interpreter.getOutputTensor(0);
      modelInfo =
          '${modelAsset.split('/').last} · in $shape ${inputTensor.type.name}'
          ' · out ${outputTensor.shape}'
          ' · T=${kTemperature.toStringAsFixed(2)}';
      _status = ClassifierStatus.ready;
      lastError = '';
      _runSelfTest();
      debugPrint('[CLS] $modelInfo · self-test $selfTest');
      debugPrint('[CLS] labels=${_labels.length} (${_labels.join(', ')})');
    } catch (e, stack) {
      _status = ClassifierStatus.error;
      lastError = 'Modelo incompatible: $e';
      debugPrint('[CLS] $lastError\n$stack');
    }
    notifyListeners();
  }

  Future<List<String>> _readLabels() async {
    final raw = await rootBundle.loadString(labelsAsset);
    final labels = <String>[];
    for (final line in raw.split('\n')) {
      final value = line.trim();
      if (value.isEmpty || value.startsWith('#')) continue;
      labels.add(value);
    }
    if (labels.isEmpty) {
      throw StateError('$labelsAsset no contiene etiquetas.');
    }
    return labels;
  }

  void _runSelfTest() {
    try {
      final sample = img.Image(width: _inputW, height: _inputH);
      img.fill(sample, color: img.ColorRgb8(128, 128, 128));
      final logits = _runModel(sample, const SquareCrop());
      final finite = logits.every((value) => value.isFinite);
      selfTest = finite && logits.isNotEmpty
          ? 'OK'
          : 'FALLO: logits no finitos';
    } catch (e, stack) {
      selfTest = 'FALLO: $e';
      debugPrint('[CLS] Self-test falló: $e\n$stack');
    }
  }

  /// Decodifica bytes (JPEG/PNG) aplicando la orientación EXIF.
  static img.Image? decodeImageBytes(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    return img.bakeOrientation(decoded);
  }

  /// Clasifica la imagen completa (recorte central cuadrado).
  ///
  /// Es síncrona porque TFLite ya bloquea; la cámara la llama con throttling
  /// y el video entre fotogramas con `await Future<void>.delayed`.
  Classification classifySync(
    img.Image source, {
    SquareCrop crop = const SquareCrop(),
    double minScore = ClassifierService.minScore,
  }) {
    if (isDemo) return _demoClassification();

    if (_status != ClassifierStatus.ready || _interpreter == null) {
      lastError = 'Modelo no cargado (estado: ${_status.name})';
      return Classification.empty;
    }

    final stopwatch = Stopwatch()..start();
    try {
      final logits = _runModel(source, crop);
      final probabilities = softmaxWithTemperature(logits);
      final scores = buildScores(probabilities, _labels, topK: topK);

      stopwatch.stop();
      lastInferenceMs = stopwatch.elapsedMilliseconds;
      lastError = '';

      if (scores.isEmpty) {
        lastBest = 'sin salida';
      } else {
        final best = scores.first;
        lastBest =
            '${best.name} ${best.scorePct}'
            '${best.score < minScore ? ' (baja)' : ''}';
      }
      return Classification(top: scores);
    } catch (e, stack) {
      lastError = 'Inferencia: $e';
      debugPrint('[CLS] $lastError\n$stack');
      return Classification.empty;
    }
  }

  /// Prepara el tensor y ejecuta el intérprete. Devuelve los logits crudos.
  List<double> _runModel(img.Image source, SquareCrop crop) {
    final interpreter = _interpreter!;
    final inputTensor = interpreter.getInputTensor(0);
    final input = buildInputTensor(source, size: _inputW, crop: crop);

    switch (inputTensor.type) {
      case TensorType.float32:
        // Copia directa de bytes: evita 150k conversiones por elemento.
        inputTensor.data = input.buffer.asUint8List(
          input.offsetInBytes,
          input.lengthInBytes,
        );
      case TensorType.int8:
      case TensorType.uint8:
        final scale = inputTensor.params.scale != 0
            ? inputTensor.params.scale
            : 1.0 / 255.0;
        final zeroPoint = inputTensor.params.zeroPoint;
        final low = inputTensor.type == TensorType.int8 ? -128 : 0;
        final high = inputTensor.type == TensorType.int8 ? 127 : 255;
        final bytes = Uint8List(input.length);
        for (var i = 0; i < input.length; i++) {
          final q = (input[i] / scale + zeroPoint).round().clamp(low, high);
          bytes[i] = q & 0xFF;
        }
        inputTensor.data = bytes;
      default:
        throw StateError(
          'Entrada ${inputTensor.type.name} no soportada en CPU.',
        );
    }

    interpreter.invoke();
    return _readLogits(interpreter.getOutputTensor(0));
  }

  List<double> _readLogits(Tensor tensor) {
    final bytes = tensor.data;
    final data = ByteData.sublistView(bytes);
    switch (tensor.type) {
      case TensorType.float32:
        final count = bytes.length ~/ 4;
        return <double>[
          for (var i = 0; i < count; i++) data.getFloat32(i * 4, Endian.little),
        ];
      case TensorType.int8:
      case TensorType.uint8:
        final scale = tensor.params.scale;
        final zeroPoint = tensor.params.zeroPoint;
        final signed = tensor.type == TensorType.int8;
        final values = <double>[];
        for (var i = 0; i < bytes.length; i++) {
          final raw = signed ? data.getInt8(i) : data.getUint8(i);
          values.add((raw - zeroPoint) * scale);
        }
        return values;
      default:
        throw StateError(
          'Salida ${tensor.type.name} no soportada. Exporta el modelo en '
          'float32 (las capas float16 no corren en CPU).',
        );
    }
  }

  /// Predicción simulada determinista para probar la UI sin modelo.
  Classification _demoClassification() {
    _demoTick++;
    final specs = <(WasteCategory, double)>[
      (WasteCatalog.plasticos, 0.82),
      (WasteCatalog.papelCarton, 0.74),
      (WasteCatalog.metales, 0.69),
      (WasteCatalog.organicos, 0.63),
    ];
    final pick = specs[_demoTick % specs.length];
    final categories = WasteCatalog.categories;
    final scores = <ClassScore>[
      ClassScore(category: pick.$1, rawLabel: pick.$1.id, score: pick.$2),
      for (final category in categories)
        if (category.id != pick.$1.id)
          ClassScore(
            category: category,
            rawLabel: category.id,
            score: (1 - pick.$2) / (categories.length - 1),
          ),
    ]..sort((a, b) => b.score.compareTo(a.score));

    lastInferenceMs = 0;
    lastError = '';
    lastBest = 'DEMO · ${pick.$1.name} ${(pick.$2 * 100).round()}%';
    return Classification(top: scores.take(topK).toList(), demo: true);
  }

  @override
  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    super.dispose();
  }
}
