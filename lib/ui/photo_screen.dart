import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../models/classification.dart';
import '../services/classifier_math.dart';
import '../services/classifier_service.dart';
import 'widgets/crop_selector.dart';
import 'widgets/demo_banner.dart';
import 'widgets/result_card.dart';

/// Elige o toma una foto y la clasifica con un marco de análisis ajustable.
class PhotoScreen extends StatefulWidget {
  const PhotoScreen({super.key});

  @override
  State<PhotoScreen> createState() => _PhotoScreenState();
}

class _PhotoScreenState extends State<PhotoScreen> {
  static const SquareCrop _initialCrop = SquareCrop(size: 0.9);

  final ImagePicker _picker = ImagePicker();
  final ClassifierService _classifier = ClassifierService.instance;

  img.Image? _source;
  ui.Image? _uiImage;
  SquareCrop _crop = _initialCrop;
  Classification _classification = Classification.empty;
  bool _loading = false;
  String? _error;
  int _milliseconds = 0;

  @override
  void dispose() {
    _uiImage?.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    if (_loading) return;
    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 92,
      );
      if (picked == null) return;

      setState(() {
        _loading = true;
        _error = null;
      });

      final bytes = await picked.readAsBytes();
      final decoded = ClassifierService.decodeImageBytes(bytes);
      if (decoded == null) {
        throw StateError('No se pudo decodificar la imagen seleccionada.');
      }

      await _classifier.ensureLoaded();
      final uiImage = await _toUiImage(decoded);
      if (!mounted) {
        uiImage.dispose();
        return;
      }

      final previous = _uiImage;
      setState(() {
        _source = decoded;
        _uiImage = uiImage;
        _crop = _initialCrop;
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        previous?.dispose();
      });
      _classifyCurrent();
    } catch (e) {
      debugPrint('[FOTO] $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No se pudo analizar la foto.\n$e';
      });
    }
  }

  /// Clasifica la región seleccionada con el marco actual.
  void _classifyCurrent() {
    final source = _source;
    if (source == null) return;
    final classification = _classifier.classifySync(source, crop: _crop);
    if (!mounted) return;
    setState(() {
      _classification = classification;
      _milliseconds = _classifier.lastInferenceMs;
    });
  }

  void _setCropSize(double value) {
    final source = _source;
    if (source == null) return;
    setState(() {
      _crop = _crop.copyWith(size: value).clamp(source.width / source.height);
    });
  }

  Future<ui.Image> _toUiImage(img.Image image) {
    final rgba = image.getBytes(order: img.ChannelOrder.rgba);
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      image.width,
      image.height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  @override
  Widget build(BuildContext context) {
    final imageHeight = MediaQuery.sizeOf(context).height * 0.5;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Foto'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Tomar foto',
            onPressed: _loading ? null : () => _pick(ImageSource.camera),
            icon: const Icon(Icons.photo_camera_outlined),
          ),
          IconButton(
            tooltip: 'Elegir de la galería',
            onPressed: _loading ? null : () => _pick(ImageSource.gallery),
            icon: const Icon(Icons.photo_library_outlined),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          if (_classifier.isDemo) const DemoBanner(),
          SizedBox(height: imageHeight, child: _buildImageArea()),
          if (_uiImage != null) _buildCropControls(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              child: _buildResultPanel(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageArea() {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Clasificando imagen…'),
          ],
        ),
      );
    }

    final error = _error;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.broken_image_outlined, size: 48),
              const SizedBox(height: 12),
              Text(error, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              _SourceButtons(onPick: _pick),
            ],
          ),
        ),
      );
    }

    final uiImage = _uiImage;
    if (uiImage == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.photo_camera_outlined, size: 56),
              const SizedBox(height: 12),
              const Text(
                'Toma una foto o elige una de tu galería.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              _SourceButtons(onPick: _pick),
              const SizedBox(height: 10),
              const Text(
                'La foto tomada con la app es temporal: '
                'no se guarda en la galería.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11),
              ),
            ],
          ),
        ),
      );
    }

    return CropSelector(
      image: uiImage,
      crop: _crop,
      onChanged: (crop) => setState(() => _crop = crop),
      onChangedEnd: (_) => _classifyCurrent(),
    );
  }

  Widget _buildCropControls() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 16, 0),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.crop_free, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Slider(
                  value: _crop.size,
                  min: SquareCrop.minSize,
                  max: 1,
                  onChanged: _setCropSize,
                  onChangeEnd: (_) => _classifyCurrent(),
                ),
              ),
              SizedBox(
                width: 46,
                child: Text(
                  '${(_crop.size * 100).round()}%',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          Text(
            'Arrastra el marco para moverlo y pellizca para agrandarlo o '
            'achicarlo. Solo se analiza lo que queda dentro.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              height: 1.3,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultPanel() {
    if (_uiImage == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: 10),
        if (_classification.isEmpty)
          const Text('El modelo no devolvió clases para esta imagen.')
        else
          ResultCard(
            best: _classification.best,
            ranking: _classification.top,
            demo: _classification.demo,
            milliseconds: _milliseconds,
          ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            TextButton.icon(
              onPressed: _loading ? null : () => _classifyCurrent(),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Analizar de nuevo'),
            ),
            TextButton.icon(
              onPressed: _loading ? null : () => _pick(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined, size: 18),
              label: const Text('Otra foto'),
            ),
          ],
        ),
        Text(
          'Región analizada: ${(_crop.size * 100).round()}% del lado menor · '
          '${_classifier.inputWidth}×${_classifier.inputHeight} · '
          '$_milliseconds ms',
          style: TextStyle(
            fontSize: 11,
            height: 1.4,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _SourceButtons extends StatelessWidget {
  final ValueChanged<ImageSource> onPick;

  const _SourceButtons({required this.onPick});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        FilledButton.icon(
          onPressed: () => onPick(ImageSource.camera),
          icon: const Icon(Icons.photo_camera_outlined),
          label: const Text('Tomar foto'),
        ),
        OutlinedButton.icon(
          onPressed: () => onPick(ImageSource.gallery),
          icon: const Icon(Icons.photo_library_outlined),
          label: const Text('Galería'),
        ),
      ],
    );
  }
}
