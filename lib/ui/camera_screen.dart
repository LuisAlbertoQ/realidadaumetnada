import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/audio_service.dart';
import '../services/dictionary_service.dart';
import '../services/ml_service.dart';
import 'widgets/ar_label_card.dart';
import 'widgets/detection_reticle.dart';
import 'widgets/status_panel.dart';

/// FASE 5: Cámara + TFLite + diccionario quechua + overlay + audio + polish.
///
/// UI: mirilla central, tarjeta AR de alto contraste, panel flotante de
/// estado. Logs por frame silenciados (ver `_verbose` en MlService).
///
/// Flujo: inferencia (throttle 800ms) -> prob >= 50% -> lookup JSON ->
/// overlay flotante + audio, con cooldown de 5s (anti-colapso 30fps).
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  final MlService _ml = MlService();
  final DictionaryService _dict = DictionaryService();
  final AudioService _audio = AudioService();

  bool _isProcessing = false;
  DateTime _lastRun = DateTime.fromMillisecondsSinceEpoch(0);
  static const _throttleMs = 800; // no enviar cada frame al modelo

  // Umbral + cooldown (CRÍTICO: 30fps sin esto = 30 audios/seg).
  static const double _minConfidence = 0.50;
  static const _cooldown = Duration(seconds: 5);
  DateTime _cooldownUntil = DateTime.fromMillisecondsSinceEpoch(0);

  String _status = 'Inicializando...';
  String _lastLabel = '-';
  VocabEntry? _match; // entrada activa para el overlay flotante
  double _matchProb = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      // 1. Permiso explícito (Regla #2)
      final perm = await Permission.camera.request();
      if (!perm.isGranted) {
        debugPrint('[CAMARA][ERROR] Permiso de cámara denegado: $perm');
        setState(() => _status = 'Permiso de cámara denegado');
        return;
      }

      // 2. Cámara trasera
      final cameras = await availableCameras();
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _controller = CameraController(
        back,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await _controller!.initialize();

      // 3. Modelo TFLite + diccionario en paralelo al arranque
      setState(() => _status = 'Cargando modelo + diccionario...');
      await Future.wait([_ml.loadModel(), _dict.load()]);

      if (!mounted) return;
      setState(() => _status = 'activo');
      await _controller!.startImageStream(_onFrame);
    } catch (e) {
      debugPrint('[CAMARA][ERROR] Fallo init: $e');
      if (mounted) setState(() => _status = 'Error: $e');
    }
  }

  Future<void> _onFrame(CameraImage frame) async {
    // Throttle + flag para no solapar inferencias (evita congelar el celular)
    final now = DateTime.now();
    if (_isProcessing || now.difference(_lastRun).inMilliseconds < _throttleMs) return;
    if (!_ml.isLoaded) return;
    _isProcessing = true;
    _lastRun = now;
    try {
      final res = await _ml.predict(frame);
      if (res == null || !mounted) return;
      setState(() => _lastLabel = '${res.label} ${(res.prob * 100).toStringAsFixed(1)}%');

      // 1. Umbral de confianza
      if (res.prob < _minConfidence) return;

      // 2. ¿Está en nuestro JSON?
      final entry = _dict.lookup(res.label);
      if (entry == null) return;

      // 3. Cooldown anti-colapso (silencioso: sin log por frame)
      if (now.isBefore(_cooldownUntil)) return;
      _cooldownUntil = now.add(_cooldown);

      // 4. Visual (overlay) + Audio
      setState(() {
        _match = entry;
        _matchProb = res.prob;
      });
      await _audio.play(entry.audioAsset);
    } finally {
      _isProcessing = false;
    }
  }

  @override
  void dispose() {
    _controller?.stopImageStream();
    _controller?.dispose();
    _ml.dispose();
    _audio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final match = _match;
    final found = match != null && DateTime.now().isBefore(_cooldownUntil);
    return Scaffold(
      appBar: AppBar(title: const Text('Cámara Parlante')),
      body: (c != null && c.value.isInitialized)
          ? Stack(
              fit: StackFit.expand,
              children: [
                CameraPreview(c),
                // 5.1 Mirilla central
                const DetectionReticle(),
                // 5.3 Tarjeta AR alto contraste durante el cooldown
                if (found)
                  ArLabelCard(
                    palabra: match.palabra,
                    labelEn: match.labelEn,
                    prob: _matchProb,
                  ),
                // 5.2 Panel flotante de estado
                StatusPanel(
                  status: _status,
                  lastLabel: found ? match.palabra : _lastLabel,
                  found: found,
                ),
              ],
            )
          : Center(child: Text(_status)),
    );
  }
}
