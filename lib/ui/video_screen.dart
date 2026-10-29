import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../models/classification.dart';
import '../services/classifier_service.dart';
import '../services/video_frames.dart';
import 'widgets/class_summary.dart';
import 'widgets/classification_timeline.dart';
import 'widgets/demo_banner.dart';
import 'widgets/result_card.dart';

class _FrameResult {
  final int timeMs;
  final ClassScore? best;

  const _FrameResult({required this.timeMs, required this.best});
}

/// Clasifica un video de galería, lo reproduce con la clase del fotograma
/// actual y muestra la distribución de clases encontradas.
class VideoScreen extends StatefulWidget {
  const VideoScreen({super.key});

  @override
  State<VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends State<VideoScreen> {
  static const int _maxFrames = 80;

  final ImagePicker _picker = ImagePicker();
  final ClassifierService _classifier = ClassifierService.instance;
  final VideoFrames _frames = VideoFrames();

  VideoPlayerController? _player;
  String? _path;
  List<_FrameResult> _results = const <_FrameResult>[];
  bool _analyzing = false;
  double _progress = 0;
  String? _error;
  int _durationMs = 0;
  int _shownIndex = 0;
  bool _wasPlaying = false;
  DateTime _lastUiUpdate = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void dispose() {
    final player = _player;
    _player = null;
    player?.removeListener(_onPlayback);
    player?.dispose();
    _frames.close();
    super.dispose();
  }

  Future<void> _pickVideo() async {
    if (_analyzing) return;
    try {
      final picked = await _picker.pickVideo(source: ImageSource.gallery);
      if (picked == null) return;
      await _prepare(picked.path);
    } catch (e) {
      debugPrint('[VIDEO] pick: $e');
      if (mounted) setState(() => _error = _describeError(e));
    }
  }

  Future<void> _prepare(String path) async {
    _releasePlayer();
    setState(() {
      _path = path;
      _analyzing = true;
      _progress = 0;
      _error = null;
      _results = const <_FrameResult>[];
      _durationMs = 0;
      _shownIndex = 0;
    });

    try {
      await _classifier.ensureLoaded();
      final meta = await _frames.open(path);
      final durationMs = meta.durationMs;

      final step = math.max(400, (durationMs / _maxFrames).ceil());
      final times = <int>[];
      for (var t = 0; t < durationMs && times.length < _maxFrames; t += step) {
        times.add(t);
      }
      if (times.isEmpty) times.add(0);

      final results = <_FrameResult>[];
      for (var i = 0; i < times.length; i++) {
        final bytes = await _frames.frame(times[i], maxWidth: 640);
        if (bytes != null) {
          final decoded = img.decodeImage(bytes);
          if (decoded != null) {
            final classification = _classifier.classifySync(decoded);
            results.add(
              _FrameResult(timeMs: times[i], best: classification.best),
            );
          }
        }
        if (!mounted) return;
        setState(() => _progress = (i + 1) / times.length);
        // Deja respirar a la UI entre fotogramas.
        await Future<void>.delayed(Duration.zero);
      }

      if (!mounted) return;
      final controller = VideoPlayerController.file(File(path));
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      controller.addListener(_onPlayback);

      setState(() {
        _results = results;
        _player = controller;
        _durationMs = durationMs > 0
            ? durationMs
            : controller.value.duration.inMilliseconds;
        _analyzing = false;
        _shownIndex = 0;
        _wasPlaying = false;
      });
    } catch (e) {
      debugPrint('[VIDEO] prepare: $e');
      if (mounted) {
        setState(() {
          _analyzing = false;
          _error = _describeError(e);
        });
      }
    } finally {
      await _frames.close();
    }
  }

  void _releasePlayer() {
    final player = _player;
    _player = null;
    player?.removeListener(_onPlayback);
    player?.dispose();
  }

  void _onPlayback() {
    final player = _player;
    if (player == null || !mounted || !player.value.isInitialized) return;

    final value = player.value;
    final index = _indexAt(value.position.inMilliseconds);
    final now = DateTime.now();
    final shouldUpdate =
        index != _shownIndex ||
        value.isPlaying != _wasPlaying ||
        now.difference(_lastUiUpdate) > const Duration(milliseconds: 180);
    if (!shouldUpdate) return;

    _lastUiUpdate = now;
    setState(() {
      _shownIndex = index;
      _wasPlaying = value.isPlaying;
    });
  }

  int _indexAt(int milliseconds) {
    if (_results.isEmpty) return 0;
    var best = 0;
    var bestDiff = 1 << 62;
    for (var i = 0; i < _results.length; i++) {
      final diff = (_results[i].timeMs - milliseconds).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        best = i;
      }
    }
    return best;
  }

  Future<void> _togglePlay() async {
    final player = _player;
    if (player == null) return;
    if (player.value.isPlaying) {
      await player.pause();
    } else {
      final duration = player.value.duration;
      if (duration > Duration.zero &&
          player.value.position >=
              duration - const Duration(milliseconds: 250)) {
        await player.seekTo(Duration.zero);
      }
      await player.play();
    }
    if (mounted) setState(() {});
  }

  void _seek(double milliseconds) {
    final player = _player;
    if (player == null) return;
    player.seekTo(Duration(milliseconds: milliseconds.round()));
    setState(() => _shownIndex = _indexAt(milliseconds.round()));
  }

  String _describeError(Object error) {
    if (error is UnsupportedError) {
      return error.message ?? error.toString();
    }
    return error.toString().replaceFirst('Exception: ', '');
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Video de galería'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Elegir otro video',
            onPressed: _analyzing ? null : _pickVideo,
            icon: const Icon(Icons.video_library_outlined),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          if (_classifier.isDemo) const DemoBanner(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_path == null) {
      return _EmptyView(onPick: _pickVideo);
    }
    if (_analyzing) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.movie_filter_outlined, size: 56),
              const SizedBox(height: 16),
              const Text(
                'Clasificando video…',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              LinearProgressIndicator(value: _progress == 0 ? null : _progress),
              const SizedBox(height: 10),
              Text(
                '${(_progress * 100).round()}% '
                '(extrayendo y clasificando fotogramas)',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
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
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 12),
              Text(error, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: <Widget>[
                  FilledButton.icon(
                    onPressed: _pickVideo,
                    icon: const Icon(Icons.video_library_outlined),
                    label: const Text('Elegir otro video'),
                  ),
                  if (_path != null)
                    OutlinedButton.icon(
                      onPressed: () => _prepare(_path!),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reintentar'),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    final player = _player;
    if (player == null || !player.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return _buildPlayer(player);
  }

  Widget _buildPlayer(VideoPlayerController player) {
    final index = _results.isEmpty
        ? 0
        : _shownIndex.clamp(0, _results.length - 1).toInt();
    final best = _results.isEmpty ? null : _results[index].best;
    final aspect = player.value.aspectRatio > 0
        ? player.value.aspectRatio
        : 1.0;
    final counts = summarizeScores(_results.map((result) => result.best));
    final durationMs = math.max(1, _durationMs);
    final positionMs = player.value.position.inMilliseconds
        .clamp(0, durationMs)
        .toInt();
    final segments = <TimelineSegment>[
      for (final result in _results)
        TimelineSegment(timeMs: result.timeMs, category: result.best?.category),
    ];

    return Column(
      children: <Widget>[
        Expanded(
          child: Container(
            color: Colors.black,
            alignment: Alignment.center,
            child: AspectRatio(
              aspectRatio: aspect,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  VideoPlayer(player),
                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: 8,
                    child: ResultCard(
                      best: best,
                      demo: _classifier.isDemo,
                      compact: true,
                      emptyMessage: 'Sin clase para este fotograma',
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'fotograma ${index + 1}/${_results.length}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: ClassificationTimeline(
            segments: segments,
            durationMs: durationMs,
            positionMs: positionMs,
            onSeek: (value) => _seek(value.toDouble()),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 12, 0),
          child: Row(
            children: <Widget>[
              IconButton(
                onPressed: _togglePlay,
                iconSize: 30,
                icon: Icon(
                  player.value.isPlaying ? Icons.pause : Icons.play_arrow,
                ),
              ),
              Expanded(
                child: Slider(
                  min: 0,
                  max: durationMs.toDouble(),
                  value: positionMs.toDouble(),
                  onChanged: _seek,
                ),
              ),
              Text(
                '${_formatDuration(Duration(milliseconds: positionMs))}'
                ' / ${_formatDuration(Duration(milliseconds: durationMs))}',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 200,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Expanded(
                      child: Text(
                        'Resumen del video',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Text(
                      '${_results.length} fotogramas',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClassSummary(
                  counts: counts,
                  unit: 'fotogramas',
                  emptyMessage: 'No se pudo clasificar ningún fotograma.',
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _pickVideo,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Elegir otro video'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyView extends StatelessWidget {
  final VoidCallback onPick;

  const _EmptyView({required this.onPick});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.video_library_outlined, size: 64),
            const SizedBox(height: 14),
            const Text(
              'Elige un video de tu galería.\n'
              'Se clasificarán hasta 80 fotogramas y luego podrás '
              'reproducirlo con la clase de cada momento.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onPick,
              icon: const Icon(Icons.video_library_outlined),
              label: const Text('Abrir galería'),
            ),
          ],
        ),
      ),
    );
  }
}
