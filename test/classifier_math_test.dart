import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:realidadaumentada/models/classification.dart';
import 'package:realidadaumentada/services/classifier_math.dart';
import 'package:realidadaumentada/services/waste_catalog.dart';

/// Imagen sintética determinista: mismo generador que el script de
/// verificación en Python (tools/verify_model.py), para comparar el tensor
/// contra los valores de referencia del modelo.
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
  group('preprocesamiento NHWC', () {
    test('normaliza con mean/std de ImageNet en orden RGB', () {
      final tensor = buildInputTensor(synthetic(224, 224));

      expect(tensor.length, 224 * 224 * 3);

      // Valores de referencia calculados con numpy sobre la misma imagen.
      void expectPixel(int y, int x, List<double> expected) {
        final base = (y * 224 + x) * 3;
        for (var c = 0; c < 3; c++) {
          expect(
            tensor[base + c],
            closeTo(expected[c], 1e-5),
            reason: 'píxel ($x,$y) canal $c',
          );
        }
      }

      expectPixel(0, 0, <double>[-2.117904, -2.035714, -1.804444]);
      expectPixel(0, 223, <double>[2.248908, -2.035714, 0.409063]);
      expectPixel(223, 0, <double>[-2.117904, 2.428571, 0.409063]);
      expectPixel(112, 56, <double>[-1.021920, 0.205182, -0.131242]);
      expectPixel(50, 200, <double>[1.786540, -1.037815, 0.670501]);
    });

    test('recorta el cuadrado central sin deformar la imagen', () {
      final wide = img.Image(width: 400, height: 300);
      img.fill(wide, color: img.ColorRgb8(10, 20, 30));
      // Marca en el centro para comprobar el desplazamiento del recorte.
      wide.setPixelRgb(200, 150, 200, 100, 50);

      final square = centerSquare(wide);
      expect(square.width, 300);
      expect(square.height, 300);
      // (200,150) en la original es (150,150) en el recorte.
      final pixel = square.getPixel(150, 150);
      expect(pixel.r.toInt(), 200);
      expect(pixel.g.toInt(), 100);
      expect(pixel.b.toInt(), 50);
    });

    test('una imagen ya cuadrada del tamaño del modelo no se remuestrea', () {
      final source = synthetic(224, 224);
      final tensor = buildInputTensor(source);
      final base = (10 * 224 + 10) * 3;
      final expected = (10 * 255 ~/ 223) / 255.0;
      expect(tensor[base], closeTo((expected - 0.485) / 0.229, 1e-6));
    });
  });

  group('marco de análisis ajustable', () {
    test('limita el tamaño a 25 %..100 % y mantiene el cuadro dentro', () {
      final tiny = const SquareCrop(
        size: 0.01,
        centerX: 0,
        centerY: 0,
      ).clamp(1.5);
      expect(tiny.size, SquareCrop.minSize);
      // Imagen 1.5:1 -> el cuadrado mide size/aspect del ancho.
      expect(tiny.centerX, greaterThan(0));
      expect(tiny.centerY, greaterThan(0));
      expect(tiny.centerX, lessThan(1));
      expect(tiny.centerY, lessThan(1));

      final huge = const SquareCrop(
        size: 5,
        centerX: 9,
        centerY: -4,
      ).clamp(0.5);
      expect(huge.size, 1.0);
      expect(huge.centerX, 0.5);
      // Imagen 0.5:1 (vertical): el cuadrado ocupa todo el ancho, así que el
      // centro vertical puede moverse entre 0.25 y 0.75.
      expect(huge.centerY, 0.25);
    });

    test('un marco del 50 % recorta la mitad del lado menor', () {
      final source = img.Image(width: 400, height: 300);
      img.fill(source, color: img.ColorRgb8(0, 0, 0));
      // Zona que debe quedar dentro del marco y zona que debe quedar fuera.
      source.setPixelRgb(200, 150, 255, 255, 255);
      source.setPixelRgb(10, 10, 255, 0, 0);

      final crop = cropRegion(source, const SquareCrop(size: 0.5));
      expect(crop.width, 150);
      expect(crop.height, 150);
      final inside = crop.getPixel(75, 75);
      expect(inside.r.toInt(), 255);
      expect(inside.g.toInt(), 255);
      expect(inside.b.toInt(), 255);
    });

    test('el centro desplazado mueve la región analizada', () {
      final source = img.Image(width: 400, height: 300);
      img.fill(source, color: img.ColorRgb8(0, 0, 0));
      // Mitad izquierda roja, mitad derecha verde.
      for (var y = 0; y < 300; y++) {
        for (var x = 0; x < 400; x++) {
          source.setPixelRgb(x, y, x < 200 ? 255 : 0, x < 200 ? 0 : 255, 0);
        }
      }

      final left = cropRegion(
        source,
        const SquareCrop(size: 0.5, centerX: 0.3, centerY: 0.5),
      );
      final right = cropRegion(
        source,
        const SquareCrop(size: 0.5, centerX: 0.7, centerY: 0.5),
      );
      expect(left.getPixel(75, 75).r.toInt(), 255);
      expect(left.getPixel(75, 75).g.toInt(), 0);
      expect(right.getPixel(75, 75).g.toInt(), 255);
      expect(right.getPixel(75, 75).r.toInt(), 0);
    });

    test('el tensor cambia según el marco y nunca sale de la imagen', () {
      final source = synthetic(320, 240);
      final full = buildInputTensor(source, size: 32);
      final zoom = buildInputTensor(
        source,
        size: 32,
        crop: const SquareCrop(size: 0.4, centerX: 0.75, centerY: 0.25),
      );

      expect(zoom.length, full.length);
      expect(zoom, isNot(equals(full)));

      // Un marco mayor a la imagen se limita en vez de lanzar excepción.
      final clamped = buildInputTensor(
        source,
        size: 32,
        crop: const SquareCrop(size: 10, centerX: 2, centerY: -1),
      );
      expect(clamped.length, full.length);
    });
  });

  group('softmax con temperatura', () {
    // Logits reales del modelo (float32 .tflite == ONNX) para la imagen
    // sintética, verificados con ai-edge-litert y onnxruntime.
    const logits = <double>[
      -3.9063000679016113,
      -2.695499897003174,
      5.874599933624268,
      1.1816999912261963,
      -3.331700086593628,
      -9.130900382995605,
      -4.7895002365112305,
    ];
    const expected = <double>[
      0.0299,
      0.0442,
      0.7069,
      0.1550,
      0.0360,
      0.0055,
      0.0225,
    ];

    test('reproduce las probabilidades del modelo', () {
      final probabilities = softmaxWithTemperature(logits);
      expect(probabilities.length, 7);
      expect(probabilities.reduce(math.max), closeTo(0.7069, 5e-4));
      for (var i = 0; i < 7; i++) {
        expect(probabilities[i], closeTo(expected[i], 5e-4));
      }
      expect(probabilities.reduce((a, b) => a + b), closeTo(1.0, 1e-9));
    });

    test('la temperatura suaviza la confianza', () {
      final calibrated = softmaxWithTemperature(logits);
      final sharp = softmaxWithTemperature(logits, temperature: 1);
      expect(sharp[2], greaterThan(calibrated[2]));
    });

    test('sin logits devuelve lista vacía y no divide por cero', () {
      expect(softmaxWithTemperature(const <double>[]), isEmpty);
      final zeroT = softmaxWithTemperature(const <double>[
        1,
        2,
      ], temperature: 0);
      expect(zeroT.length, 2);
      expect(zeroT.first.isFinite, isTrue);
    });
  });

  group('etiquetas y ranking', () {
    test('mapea las 7 clases del modelo al catálogo con su color', () {
      const labels = <String>[
        'azul_papel_carton',
        'amarillo_metales',
        'blanco_plasticos',
        'gris_vidrio',
        'marron_organicos',
        'rojo_peligrosos',
        'negro_generales',
      ];
      final expected = <String>[
        WasteCatalog.papelCarton.id,
        WasteCatalog.metales.id,
        WasteCatalog.plasticos.id,
        WasteCatalog.vidrio.id,
        WasteCatalog.organicos.id,
        WasteCatalog.peligrosos.id,
        WasteCatalog.generales.id,
      ];

      for (var i = 0; i < labels.length; i++) {
        final category = WasteCatalog.match(labels[i]);
        expect(category, isNotNull, reason: labels[i]);
        expect(category!.id, expected[i]);
      }
    });

    test('devuelve el top-3 ordenado', () {
      final scores = buildScores(
        <double>[0.05, 0.1, 0.6, 0.15, 0.05, 0.02, 0.03],
        const <String>[
          'azul_papel_carton',
          'amarillo_metales',
          'blanco_plasticos',
          'gris_vidrio',
          'marron_organicos',
          'rojo_peligrosos',
          'negro_generales',
        ],
      );
      expect(scores.length, 3);
      expect(scores[0].category.id, WasteCatalog.plasticos.id);
      expect(scores[0].scorePct, '60%');
      expect(scores[1].category.id, WasteCatalog.vidrio.id);
      expect(scores[2].category.id, WasteCatalog.metales.id);
    });

    test('una etiqueta desconocida cae en "Sin clasificar"', () {
      final scores = buildScores(
        <double>[0.9, 0.1],
        const <String>['clase_rara', 'vidrio'],
      );
      expect(scores.first.category.isUnknown, isTrue);
      expect(scores.first.name, 'clase_rara');
    });
  });

  group('voto mayoritario', () {
    Classification classification(String label, double score) {
      return Classification(
        top: <ClassScore>[
          ClassScore(
            category: WasteCatalog.match(label) ?? WasteCatalog.unknown,
            rawLabel: label,
            score: score,
          ),
        ],
      );
    }

    test('elige la clase más repetida y promedia su confianza', () {
      final window = <Classification>[
        classification('blanco_plasticos', 0.6),
        classification('blanco_plasticos', 0.8),
        classification('gris_vidrio', 0.9),
        classification('blanco_plasticos', 0.7),
        classification('gris_vidrio', 0.5),
      ];
      final result = majorityLabel(window)!;
      expect(result.category.id, WasteCatalog.plasticos.id);
      expect(result.votes, 3);
      expect(result.samples, 5);
      expect(result.score, closeTo(0.7, 1e-9));
      expect(result.agreement, closeTo(0.6, 1e-9));
    });

    test('sin resultados devuelve null', () {
      expect(majorityLabel(const <Classification>[]), isNull);
    });
  });
}
