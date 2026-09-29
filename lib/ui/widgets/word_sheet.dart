import 'package:flutter/material.dart';

import '../../services/audio_service.dart';
import '../../services/dictionary_service.dart';

/// BottomSheet de la palabra: término quechua + audio + ejemplos con audios.
class WordSheet extends StatelessWidget {
  final String detectedLabel;
  final double score;
  final VocabEntry? entry;
  final AudioService audio;

  const WordSheet({
    super.key,
    required this.detectedLabel,
    required this.score,
    required this.entry,
    required this.audio,
  });

  @override
  Widget build(BuildContext context) {
    final e = entry;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey[400], borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '($detectedLabel) · ${(score * 100).toStringAsFixed(0)}%',
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
            if (e == null) ...[
              const SizedBox(height: 8),
              const Text('Sin traducción aún',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const Text('Este objeto no está en el diccionario.',
                  style: TextStyle(color: Colors.grey)),
            ] else ...[
              Text(e.palabra,
                  style: const TextStyle(
                      fontSize: 40, fontWeight: FontWeight.w900, height: 1.1)),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: () => audio.play(e.audioAsset),
                icon: const Icon(Icons.volume_up),
                label: const Text('Escuchar palabra'),
              ),
              const SizedBox(height: 12),
              const Text('Diccionario / Contexto',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              if (e.ejemplos.isEmpty)
                const Text('Aún no hay oraciones de ejemplo.',
                    style: TextStyle(color: Colors.grey)),
              for (final ex in e.ejemplos)
                Card(
                  child: ListTile(
                    title: Text(ex.textoQuechua,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(ex.traduccionEs),
                    trailing: IconButton(
                      icon: const Icon(Icons.play_circle_fill, size: 32),
                      onPressed: () => audio.play(ex.audio),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
