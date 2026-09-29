import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';

import '../services/audio_service.dart';
import '../services/detector_service.dart';
import '../services/dictionary_service.dart';
import 'widgets/boxes_painter.dart';
import 'widgets/word_sheet.dart';

/// PIVOTE: flujo foto estática + detección + boxes tocables.
/// 1. Vista cámara + botón "Capturar".
/// 2. Congela foto, corre SSD, dibuja boxes con CustomPaint.
/// 3. Tap en box -> BottomSheet con palabra, audios y ejemplos.
class PhotoScreen extends StatefulWidget {
  const PhotoScreen({super.key});

  @override
  State<PhotoScreen> createState() => _PhotoScreenState();
}

enum _Phase { live, processing, result }

class _PhotoScreenState extends State<PhotoScreen> {
  CameraController? _controller;
  final DetectorService _detector = DetectorService();
  final DictionaryService _dict = DictionaryService();
  final AudioService _audio = AudioService();

  _Phase _phase = _Phase.live;
  String _status = 'Inicializando...';
  File? _photo;
  Size? _photoSize;
  List<Detection> _detections = [];
  Set<int> _withTranslation = {};

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final perm = await Permission.camera.request();
      if (!perm.isGranted) {
        setState(() => _status = 'Permiso de cámara denegado');
        return;
      }
      await _startCamera();
      setState(() => _status = 'Cargando detector + diccionario...');
      await Future.wait([_detector.loadModel(), _dict.load()]);
      if (!mounted) return;
      setState(() {
        _status = 'Listo';
        _phase = _Phase.live;
      });
    } catch (e) {
      debugPrint('[FOTO][ERROR] init: $e');
      if (mounted) setState(() => _status = 'Error: $e');
    }
  }

  /// (Re)crea el controller desde cero. `resumePreview` se congela en
  /// varios Xiaomi/CameraX: por eso "Nueva foto" recrea en vez de reanudar.
  Future<void> _startCamera() async {
    final old = _controller;
    _controller = null;
    await old?.dispose();
    final cameras = await availableCameras();
    final back = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );
    final c = CameraController(back, ResolutionPreset.high, enableAudio: false);
    await c.initialize();
    if (!mounted) {
      await c.dispose();
      return;
    }
    setState(() => _controller = c);
  }

  Future<void> _capture() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _phase != _Phase.live) return;
    setState(() {
      _phase = _Phase.processing;
      _status = 'Detectando objetos...';
    });
    try {
      final xfile = await c.takePicture();
      await c.pausePreview();
      final file = File(xfile.path);
      final decoded = img.decodeImage(await file.readAsBytes());
      final size = decoded == null
          ? const Size(1, 1)
          : Size(decoded.width.toDouble(), decoded.height.toDouble());

      final dets = await _detector.detect(file);
      final hits = <int>{};
      for (int i = 0; i < dets.length; i++) {
        if (_dict.lookup(dets[i].label) != null) hits.add(i);
      }
      if (!mounted) return;
      setState(() {
        _photo = file;
        _photoSize = size;
        _detections = dets;
        _withTranslation = hits;
        _phase = _Phase.result;
        _status = dets.isEmpty ? 'Sin objetos (prueba otra foto)' : '${dets.length} objeto(s)';
      });
    } catch (e) {
      debugPrint('[FOTO][ERROR] captura/deteccion: $e');
      if (mounted) {
        setState(() {
          _phase = _Phase.live;
          _status = 'Error: $e';
        });
        await _controller?.resumePreview();
      }
    }
  }

  Future<void> _retake() async {
    setState(() {
      _phase = _Phase.processing;
      _status = 'Reiniciando cámara...';
      _photo = null;
      _detections = [];
      _withTranslation = {};
    });
    try {
      await _startCamera();
      if (!mounted) return;
      setState(() {
        _phase = _Phase.live;
        _status = 'Listo';
      });
    } catch (e) {
      debugPrint('[FOTO][ERROR] retake: $e');
      if (mounted) {
        setState(() {
          _phase = _Phase.live;
          _status = 'Error cámara: $e';
        });
      }
    }
  }

  /// Tap -> coordenadas normalizadas -> box que lo contenga -> BottomSheet.
  void _onTapDown(TapDownDetails d, Size widgetSize) {
    final imgSize = _photoSize;
    if (imgSize == null || _detections.isEmpty) return;
    final m = BoxesPainter.containMap(widgetSize, imgSize);
    final nx = (d.localPosition.dx - m.ox) / (imgSize.width * m.scale);
    final ny = (d.localPosition.dy - m.oy) / (imgSize.height * m.scale);
    if (nx < 0 || nx > 1 || ny < 0 || ny > 1) return;
    const pad = 0.02;
    for (int i = 0; i < _detections.length; i++) {
      final b = _detections[i];
      if (nx >= b.xmin - pad && nx <= b.xmax + pad && ny >= b.ymin - pad && ny <= b.ymax + pad) {
        _openSheet(b);
        return;
      }
    }
  }

  void _openSheet(Detection b) {
    final entry = _dict.lookup(b.label);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => WordSheet(
        detectedLabel: b.label,
        score: b.score,
        entry: entry,
        audio: _audio,
      ),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    _detector.dispose();
    _audio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Scaffold(
      appBar: AppBar(title: const Text('Cámara Parlante — Foto')),
      body: _buildBody(c),
      floatingActionButton: _phase == _Phase.live && c != null && c.value.isInitialized
          ? FloatingActionButton.extended(
              onPressed: _capture,
              icon: const Icon(Icons.camera_alt),
              label: const Text('Capturar'),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildBody(CameraController? c) {
    switch (_phase) {
      case _Phase.live:
        if (c == null || !c.value.isInitialized) {
          return Center(child: Text(_status));
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            CameraPreview(c),
            Positioned(
              left: 16,
              right: 16,
              bottom: 90,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.62),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    'Encuadra el objeto y pulsa Capturar\n'
                    '${_detector.modelInfo}\n'
                    'Self-test: ${_detector.selfTest}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
            ),
          ],
        );
      case _Phase.processing:
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('Detectando objetos...'),
            ],
          ),
        );
      case _Phase.result:
        final photo = _photo, imgSize = _photoSize;
        if (photo == null || imgSize == null) {
          return Center(child: Text(_status));
        }
        return Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (ctx, constraints) {
                  final wSize = Size(constraints.maxWidth, constraints.maxHeight);
                  return GestureDetector(
                    onTapDown: (d) => _onTapDown(d, wSize),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(photo, fit: BoxFit.contain),
                        CustomPaint(
                          painter: BoxesPainter(
                            detections: _detections,
                            imageSize: imgSize,
                            highlighted: _withTranslation,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: Colors.black87,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$_status · mejor: ${_detector.lastBest}',
                          style: const TextStyle(
                              color: Colors.greenAccent, fontSize: 13),
                        ),
                        if (_detector.lastError.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.only(top: 6),
                            padding: const EdgeInsets.all(8),
                            constraints:
                                const BoxConstraints(maxHeight: 180),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.redAccent),
                            ),
                            child: SingleChildScrollView(
                              child: SelectableText(
                                'ERR: ${_detector.lastError}\n${_detector.lastStack}',
                                style: const TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _retake,
                    icon: const Icon(Icons.refresh, color: Colors.white),
                    label: const Text('Nueva foto',
                        style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ),
          ],
        );
    }
  }
}
