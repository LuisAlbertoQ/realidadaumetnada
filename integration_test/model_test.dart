import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:realidadaumentada/services/classifier_math.dart';
import 'package:realidadaumentada/services/classifier_service.dart';
import 'package:realidadaumentada/services/waste_catalog.dart';

/// Misma imagen sintética que `test/classifier_math_test.dart` y
/// `tools/verify_model.py`.
img.Image synthetic(int width, int height) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgb(
        x,
        y,
        x * 255 ~/ (width - 1),
        y * 255 ~/ (height - 1),
        (x + y) * 255 ~/ (width + height - 2),
      );
    }
  }
  return image;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('el .tflite real reproduce la predicción de referencia', (
    tester,
  ) async {
    final classifier = ClassifierService.instance;
    await classifier.ensureLoaded();

    expect(
      classifier.status,
      ClassifierStatus.ready,
      reason: 'Modelo no cargado: ${classifier.lastError}',
    );
    expect(classifier.labels.length, 7);
    expect(classifier.selfTest, 'OK');

    final result = classifier.classifySync(synthetic(224, 224));

    expect(result.best, isNotNull, reason: classifier.lastError);
    expect(
      result.best!.category.id,
      WasteCatalog.plasticos.id,
      reason: 'La referencia en Python da argmax=2 (blanco_plasticos)',
    );
    expect(result.best!.score, closeTo(0.7069, 0.01));
    expect(result.top.length, 3);
    expect(result.demo, isFalse);

    // La segunda clase de la referencia es vidrio (0.155).
    expect(result.top[1].category.id, WasteCatalog.vidrio.id);
  });

  testWidgets('el marco ajustable cambia de verdad la región analizada', (
    tester,
  ) async {
    final classifier = ClassifierService.instance;
    await classifier.ensureLoaded();
    expect(classifier.status, ClassifierStatus.ready);

    // Imagen de 448×448: cada recorte del 50 % mide exactamente 224×224, así
    // que el resultado no depende del remuestreo. Referencias calculadas con
    // onnxruntime sobre la misma imagen sintética.
    final source = synthetic(448, 448);

    final centered = classifier.classifySync(
      source,
      crop: const SquareCrop(size: 0.5),
    );
    expect(
      centered.best!.category.id,
      WasteCatalog.plasticos.id,
      reason: 'recorte central: argmax=2, p≈0.4738',
    );
    expect(centered.best!.score, closeTo(0.4738, 0.01));

    final bottomLeft = classifier.classifySync(
      source,
      crop: const SquareCrop(size: 0.5, centerX: 0.25, centerY: 0.75),
    );
    expect(
      bottomLeft.best!.category.id,
      WasteCatalog.vidrio.id,
      reason: 'esquina inferior izquierda: argmax=3, p≈0.3852',
    );
    expect(bottomLeft.best!.score, closeTo(0.3852, 0.01));

    final topRight = classifier.classifySync(
      source,
      crop: const SquareCrop(size: 0.5, centerX: 0.75, centerY: 0.25),
    );
    expect(
      topRight.best!.category.id,
      WasteCatalog.papelCarton.id,
      reason: 'esquina superior derecha: argmax=0, p≈0.2622',
    );
    expect(topRight.best!.score, closeTo(0.2622, 0.01));

    // Cada marco produce una predicción distinta: el recorte llega al modelo.
    expect(centered.best!.category.id, isNot(bottomLeft.best!.category.id));
    expect(centered.best!.category.id, isNot(topRight.best!.category.id));
  });
}
