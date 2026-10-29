import 'package:flutter/material.dart';

import '../services/classifier_service.dart';
import 'live_camera_screen.dart';
import 'photo_screen.dart';
import 'video_screen.dart';
import 'widgets/category_legend.dart';
import 'widgets/model_status_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ClassifierService _classifier = ClassifierService.instance;

  @override
  void initState() {
    super.initState();
    _classifier.ensureLoaded();
  }

  void _open(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnimatedBuilder(
      animation: _classifier,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Clasificador de residuos'),
            actions: <Widget>[
              IconButton(
                tooltip: 'Cómo instalar el modelo',
                onPressed: () => _showInstructions(context),
                icon: const Icon(Icons.help_outline),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: <Widget>[
              ModelStatusCard(classifier: _classifier),
              const SizedBox(height: 18),
              _ActionCard(
                icon: Icons.videocam_outlined,
                title: 'Cámara en vivo',
                subtitle: 'Clasifica en vivo el residuo dentro del marco',
                color: const Color(0xFF2E7D32),
                onTap: () => _open(const LiveCameraScreen()),
              ),
              const SizedBox(height: 12),
              _ActionCard(
                icon: Icons.photo_library_outlined,
                title: 'Foto de galería',
                subtitle: 'Clasifica una imagen de tu galería',
                color: const Color(0xFF1565C0),
                onTap: () => _open(const PhotoScreen()),
              ),
              const SizedBox(height: 12),
              _ActionCard(
                icon: Icons.video_library_outlined,
                title: 'Video de galería',
                subtitle: 'Clasifica el video y resume sus clases',
                color: const Color(0xFF6A1B9A),
                onTap: () => _open(const VideoScreen()),
              ),
              const SizedBox(height: 26),
              Text(
                'Categorías',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              const CategoryLegend(),
              const SizedBox(height: 24),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '¿Aún estás entrenando el modelo?',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'La app funciona en modo demo con clases simuladas. '
                        'Cuando tengas el .tflite, colócalo en '
                        '${ClassifierService.modelAsset} y reconstruye.',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => _showInstructions(context),
                          icon: const Icon(Icons.terminal, size: 18),
                          label: const Text('Ver instrucciones'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showInstructions(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Instalar el modelo entrenado'),
          content: const SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '1. Entrena el clasificador de 7 clases y exporta el '
                  'modelo a TFLite float32:',
                ),
                SizedBox(height: 8),
                SelectableText(
                  "converter = tf.lite.TFLiteConverter.from_saved_model(\n"
                  "    'saved_model')\n"
                  "open('waste_classifier.tflite', 'wb').write(\n"
                  "    converter.convert())",
                  style: TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
                SizedBox(height: 12),
                Text('2. Copia el archivo como:'),
                SelectableText(
                  'assets/model/waste_classifier.tflite',
                  style: TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
                SizedBox(height: 12),
                Text(
                  '3. Verifica que assets/model/labels.txt tenga las 7 clases '
                  'en el MISMO orden que la capa de salida:',
                ),
                SelectableText(
                  'azul_papel_carton\namarillo_metales\nblanco_plasticos\n'
                  'gris_vidrio\nmarron_organicos\nrojo_peligrosos\n'
                  'negro_generales',
                  style: TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
                SizedBox(height: 12),
                Text(
                  '4. La entrada debe ser [1,224,224,3] float32 con '
                  'normalización ImageNet. Si reentrenas, actualiza la '
                  'temperatura (T = 3.09) en lib/services/classifier_math.dart.',
                ),
                SizedBox(height: 12),
                Text(
                  '5. Reconstruye (los assets nuevos no entran con hot reload):',
                ),
                SelectableText(
                  'flutter clean && flutter pub get && flutter run',
                  style: TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              colors: <Color>[
                color.withValues(alpha: 0.30),
                color.withValues(alpha: 0.10),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: color.withValues(alpha: 0.55)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: <Widget>[
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: color.withValues(alpha: 0.9)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
