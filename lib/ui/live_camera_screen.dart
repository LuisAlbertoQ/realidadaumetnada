import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';

import '../models/classification.dart';
import '../services/classifier_math.dart';
import '../services/classifier_service.dart';
import 'widgets/crop_selector.dart';
import 'widgets/demo_banner.dart';
import 'widgets/result_card.dart';

/// Clasificación continua sobre el stream de la cámara.
///
/// Se analiza el cuadrado central del fotograma (la misma región que marca la
/// guía en pantalla) y se estabiliza la etiqueta con voto mayoritario.
class LiveCameraScreen extends StatefulWidget {
  const LiveCameraScreen({super.key});

  @override
  State<LiveCameraScreen> createState() => _LiveCameraScreenState();
}

class _LiveCameraScreenState extends State<LiveCameraScreen>
    with WidgetsBindingObserver {
  static const Duration _interval = Duration(milliseconds: 450);
  static const int _windowSize = 5;

  CameraController? _controller;
  final ClassifierService _classifier = ClassifierService.instance;
  final List<Classification> _window = <Classification>[];

  bool _starting = true;
  bool _busy = false;
  String? _error;
  ClassScore? _best;
  SquareCrop _crop = const SquareCrop(size: 0.9);
  SmoothedLabel? _smoothed;
  DateTime _lastRun = DateTime.fromMillisecondsSinceEpoch(0);
  int _sensorOrientation = 90;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
    ]);
    _init();
  }

  Future<void> _init() async {
    if (mounted) {
      setState(() {
        _starting = true;
        _error = null;
      });
    }
    try {
      final permission = await Permission.camera.request();
      if (!permission.isGranted) {
        if (!mounted) return;
        setState(() {
          _starting = false;
          _error =
              'Permiso de cámara denegado.\n'
              'Actívalo en Ajustes > Permisos de la app.';
        });
        return;
      }

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw StateError('No hay cámaras disponibles en este dispositivo.');
      }
      final back = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      _sensorOrientation = back.sensorOrientation;

      final controller = CameraController(
        back,
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      await _classifier.ensureLoaded();

      if (!mounted) {
        await controller.dispose();
        return;
      }
      _controller = controller;
      await controller.startImageStream(_onFrame);
      if (!mounted) return;
      setState(() => _starting = false);
    } catch (e) {
      debugPrint('[LIVE] init: $e');
      if (!mounted) return;
      setState(() {
        _starting = false;
        _error = 'No se pudo iniciar la cámara.\n$e';
      });
    }
  }

  void _onFrame(CameraImage frame) {
    final now = DateTime.now();
    if (_busy ||
        now.difference(_lastRun) < _interval ||
        (!_classifier.isReady && !_classifier.isDemo)) {
      return;
    }

    _busy = true;
    _lastRun = now;
    try {
      final image = _toSquareImage(frame);
      if (image == null) return;
      final result = _classifier.classifySync(image, crop: _crop);

      _window.add(result);
      if (_window.length > _windowSize) _window.removeAt(0);
      final smoothed = majorityLabel(_window);

      if (!mounted) return;
      setState(() {
        _best = smoothed == null
            ? null
            : ClassScore(
                category: smoothed.category,
                rawLabel: smoothed.rawLabel,
                score: smoothed.score,
              );
        _smoothed = smoothed;
      });
    } catch (e) {
      debugPrint('[LIVE] frame: $e');
    } finally {
      _busy = false;
    }
  }

  void _setCropSize(double value) {
    setState(() {
      _crop = _crop.copyWith(size: value);
      // La ventana de votos ya no representa el nuevo encuadre.
      _window.clear();
    });
  }

  /// CameraImage -> imagen cuadrada del centro, ya en orientación vertical.
  ///
  /// Solo se convierten los píxeles del cuadrado analizado, no el fotograma
  /// completo: menos trabajo por cuadro en el isolate de UI.
  img.Image? _toSquareImage(CameraImage frame) {
    final width = frame.width;
    final height = frame.height;
    if (width <= 0 || height <= 0) return null;
    final side = math.min(width, height);
    final left = (width - side) ~/ 2;
    final top = (height - side) ~/ 2;

    if (frame.format.group == ImageFormatGroup.bgra8888) {
      final bytes = frame.planes[0].bytes;
      final pixelStride = frame.planes[0].bytesPerPixel ?? 4;
      final rowStride = frame.planes[0].bytesPerRow;
      final rgb = Uint8List(side * side * 3);
      var out = 0;
      for (var y = 0; y < side; y++) {
        final row = (y + top) * rowStride;
        for (var x = 0; x < side; x++) {
          final offset = row + (x + left) * pixelStride;
          if (offset + 2 < bytes.length) {
            rgb[out] = bytes[offset + 2];
            rgb[out + 1] = bytes[offset + 1];
            rgb[out + 2] = bytes[offset];
          }
          out += 3;
        }
      }
      return _rotateUpright(
        img.Image.fromBytes(
          width: side,
          height: side,
          bytes: rgb.buffer,
          numChannels: 3,
          order: img.ChannelOrder.rgb,
        ),
      );
    }

    if (frame.format.group != ImageFormatGroup.yuv420 ||
        frame.planes.length < 3) {
      return null;
    }

    final yPlane = frame.planes[0].bytes;
    final uPlane = frame.planes[1].bytes;
    final vPlane = frame.planes[2].bytes;
    final yRowStride = frame.planes[0].bytesPerRow;
    final uRowStride = frame.planes[1].bytesPerRow;
    final vRowStride = frame.planes[2].bytesPerRow;
    final uPixelStride = frame.planes[1].bytesPerPixel ?? 1;
    final vPixelStride = frame.planes[2].bytesPerPixel ?? 1;

    final rgb = Uint8List(side * side * 3);
    var out = 0;
    for (var y = 0; y < side; y++) {
      final sourceY = y + top;
      final yIndexBase = sourceY * yRowStride;
      final uvY = sourceY ~/ 2;
      for (var x = 0; x < side; x++) {
        final sourceX = x + left;
        final yIndex = yIndexBase + sourceX;
        final uvX = sourceX ~/ 2;
        final uIndex = uvY * uRowStride + uvX * uPixelStride;
        final vIndex = uvY * vRowStride + uvX * vPixelStride;
        if (yIndex < yPlane.length &&
            uIndex < uPlane.length &&
            vIndex < vPlane.length) {
          final yValue = yPlane[yIndex];
          final uValue = uPlane[uIndex];
          final vValue = vPlane[vIndex];
          rgb[out] = (yValue + 1.370705 * (vValue - 128)).clamp(0, 255).toInt();
          rgb[out + 1] =
              (yValue - 0.337633 * (uValue - 128) - 0.698001 * (vValue - 128))
                  .clamp(0, 255)
                  .toInt();
          rgb[out + 2] = (yValue + 1.732446 * (uValue - 128))
              .clamp(0, 255)
              .toInt();
        }
        out += 3;
      }
    }

    return _rotateUpright(
      img.Image.fromBytes(
        width: side,
        height: side,
        bytes: rgb.buffer,
        numChannels: 3,
        order: img.ChannelOrder.rgb,
      ),
    );
  }

  img.Image _rotateUpright(img.Image image) {
    // En Android el buffer llega con la orientación del sensor y la app está
    // bloqueada en vertical. `sensorOrientation` suele ser 90.
    if (defaultTargetPlatform == TargetPlatform.android &&
        _sensorOrientation % 360 != 0) {
      return img.copyRotate(image, angle: _sensorOrientation);
    }
    return image;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null) return;
    if (state == AppLifecycleState.inactive) {
      _controller = null;
      controller.dispose();
      if (mounted) setState(() => _starting = true);
    } else if (state == AppLifecycleState.resumed) {
      _init();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black38,
        foregroundColor: Colors.white,
        title: const Text('Cámara en vivo'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final error = _error;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.videocam_off, size: 48, color: Colors.white54),
              const SizedBox(height: 12),
              Text(
                error,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: _init, child: const Text('Reintentar')),
            ],
          ),
        ),
      );
    }

    final controller = _controller;
    if (_starting || controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    final uprightAspect = 1 / controller.value.aspectRatio;

    return Column(
      children: <Widget>[
        if (_classifier.isDemo) const DemoBanner(),
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              FittedBox(
                fit: BoxFit.cover,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: 1000 * uprightAspect,
                  height: 1000,
                  child: controller.buildPreview(),
                ),
              ),
              LayoutBuilder(
                builder: (context, constraints) {
                  // El preview usa BoxFit.cover: el marco se calcula con la
                  // misma escala para que coincida con lo que analiza el modelo.
                  return CustomPaint(
                    painter: CropPainter(
                      content: coverRect(constraints.biggest, uprightAspect),
                      crop: _crop,
                    ),
                  );
                },
              ),
              Positioned(
                top: 12,
                left: 12,
                right: 12,
                child: _StatusPill(
                  ready: _classifier.isReady,
                  milliseconds: _classifier.lastInferenceMs,
                  smoothed: _smoothed,
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    _CropControl(value: _crop.size, onChanged: _setCropSize),
                    const SizedBox(height: 8),
                    ResultCard(
                      best: _best,
                      demo: _classifier.isDemo,
                      milliseconds: _classifier.lastInferenceMs,
                      compact: true,
                      emptyMessage: 'Coloca el residuo dentro del marco.',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  final bool ready;
  final int milliseconds;
  final SmoothedLabel? smoothed;

  const _StatusPill({
    required this.ready,
    required this.milliseconds,
    required this.smoothed,
  });

  @override
  Widget build(BuildContext context) {
    final label = smoothed;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            ready ? Icons.memory : Icons.science_outlined,
            size: 16,
            color: ready ? Colors.greenAccent : Colors.amberAccent,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              ready
                  ? 'Inferencia ${milliseconds}ms · cada 0.45s'
                  : 'Modo demo · sin inferencia real',
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ),
          if (label != null)
            Text(
              '${label.votes}/${label.samples} estable',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }
}

class _CropControl extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;

  const _CropControl({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.crop_free, size: 16, color: Colors.white70),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: SliderComponentShape.noOverlay,
              ),
              child: Slider(
                value: value,
                min: SquareCrop.minSize,
                max: 1,
                onChanged: onChanged,
              ),
            ),
          ),
          SizedBox(
            width: 38,
            child: Text(
              '${(value * 100).round()}%',
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
