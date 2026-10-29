import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show immutable;
import 'package:image/image.dart' as img;

import '../models/classification.dart';
import 'waste_catalog.dart';

/// Temperatura de calibración del modelo (`temperature.npy` = 3.0924).
///
/// Sin dividir los logits por este valor las probabilidades salen
/// sobreconfiadas; con él quedan calibradas.
const double kTemperature = 3.092362530435132;

/// Normalización ImageNet usada durante el entrenamiento.
const List<double> kImageNetMean = <double>[0.485, 0.456, 0.406];
const List<double> kImageNetStd = <double>[0.229, 0.224, 0.225];

/// Tamaño de entrada del clasificador (cuadrado).
const int kModelSize = 224;

/// Región cuadrada de la imagen que se analiza, en coordenadas normalizadas.
///
/// `size` es la fracción del lado menor de la imagen (1.0 = cuadrado máximo
/// centrado); `centerX`/`centerY` son el centro en 0..1 del ancho/alto.
@immutable
class SquareCrop {
  /// Tamaño mínimo: más pequeño que esto el recorte pierde demasiado contexto.
  static const double minSize = 0.25;

  final double size;
  final double centerX;
  final double centerY;

  const SquareCrop({this.size = 1.0, this.centerX = 0.5, this.centerY = 0.5});

  SquareCrop copyWith({double? size, double? centerX, double? centerY}) {
    return SquareCrop(
      size: size ?? this.size,
      centerX: centerX ?? this.centerX,
      centerY: centerY ?? this.centerY,
    );
  }

  /// Ajusta el tamaño y el centro para que el cuadrado quede dentro de la
  /// imagen con aspecto [aspect] (ancho/alto).
  SquareCrop clamp(double aspect) {
    if (aspect <= 0 || !aspect.isFinite) return this;
    final value = size.clamp(minSize, 1.0).toDouble();
    final halfW = value / 2 * (aspect >= 1 ? 1 / aspect : 1.0);
    final halfH = value / 2 * (aspect >= 1 ? 1.0 : aspect);
    return SquareCrop(
      size: value,
      centerX: centerX.clamp(halfW, 1 - halfW).toDouble(),
      centerY: centerY.clamp(halfH, 1 - halfH).toDouble(),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SquareCrop &&
        other.size == size &&
        other.centerX == centerX &&
        other.centerY == centerY;
  }

  @override
  int get hashCode => Object.hash(size, centerX, centerY);

  @override
  String toString() => 'SquareCrop(size: $size, center: $centerX/$centerY)';
}

/// Recorta la región [crop] de la imagen (cuadrada y siempre dentro de ella).
img.Image cropRegion(img.Image source, SquareCrop crop) {
  final clamped = crop.clamp(source.width / source.height);
  final maxSide = math.min(source.width, source.height);
  final side = (maxSide * clamped.size).round().clamp(1, maxSide).toInt();
  final centerX = (source.width * clamped.centerX).round();
  final centerY = (source.height * clamped.centerY).round();
  final x = (centerX - side ~/ 2).clamp(0, source.width - side).toInt();
  final y = (centerY - side ~/ 2).clamp(0, source.height - side).toInt();
  if (x == 0 && y == 0 && side == source.width && side == source.height) {
    return source;
  }
  return img.copyCrop(source, x: x, y: y, width: side, height: side);
}

/// Recorta el cuadrado central de la imagen.
img.Image centerSquare(img.Image source) {
  return cropRegion(source, const SquareCrop());
}

/// Imagen -> tensor NHWC `[1, size, size, 3]` float32 normalizado.
///
/// Orden de canales RGB, `(p / 255 - mean) / std`. El `.tflite` exportado ya
/// está en NHWC (el ONNX de origen era NCHW).
Float32List buildInputTensor(
  img.Image source, {
  int size = kModelSize,
  SquareCrop crop = const SquareCrop(),
}) {
  final square = cropRegion(source, crop);
  // Evita remuestrear cuando ya tiene el tamaño exacto (p. ej. un recorte
  // de 224×224): el resultado es bit a bit el mismo píxel.
  final resized = square.width == size && square.height == size
      ? square
      : img.copyResize(
          square,
          width: size,
          height: size,
          interpolation: img.Interpolation.linear,
        );
  final rgb = resized.getBytes(order: img.ChannelOrder.rgb);

  const meanR = 0.485, meanG = 0.456, meanB = 0.406;
  const stdR = 0.229, stdG = 0.224, stdB = 0.225;

  final tensor = Float32List(size * size * 3);
  for (var i = 0; i < tensor.length; i += 3) {
    tensor[i] = (rgb[i] / 255.0 - meanR) / stdR;
    tensor[i + 1] = (rgb[i + 1] / 255.0 - meanG) / stdG;
    tensor[i + 2] = (rgb[i + 2] / 255.0 - meanB) / stdB;
  }
  return tensor;
}

/// `softmax(logits / temperature)`, estable numéricamente.
List<double> softmaxWithTemperature(
  List<double> logits, {
  double temperature = kTemperature,
}) {
  if (logits.isEmpty) return const <double>[];
  final t = temperature > 0 ? temperature : 1.0;

  final scaled = List<double>.filled(logits.length, 0);
  var maxValue = double.negativeInfinity;
  for (var i = 0; i < logits.length; i++) {
    final value = logits[i] / t;
    scaled[i] = value;
    if (value > maxValue) maxValue = value;
  }

  var sum = 0.0;
  for (var i = 0; i < scaled.length; i++) {
    final e = math.exp(scaled[i] - maxValue);
    scaled[i] = e;
    sum += e;
  }
  if (!sum.isFinite || sum <= 0) {
    return List<double>.filled(logits.length, 1 / logits.length);
  }
  for (var i = 0; i < scaled.length; i++) {
    scaled[i] /= sum;
  }
  return scaled;
}

/// Convierte probabilidades + etiquetas en el ranking de [ClassScore].
List<ClassScore> buildScores(
  List<double> probabilities,
  List<String> labels, {
  int topK = 3,
}) {
  final scores = <ClassScore>[];
  for (var i = 0; i < probabilities.length; i++) {
    final rawLabel = i < labels.length ? labels[i] : 'clase_$i';
    scores.add(
      ClassScore(
        category: WasteCatalog.match(rawLabel) ?? WasteCatalog.unknown,
        rawLabel: rawLabel,
        score: probabilities[i],
      ),
    );
  }
  scores.sort((a, b) => b.score.compareTo(a.score));
  if (scores.length > topK) return scores.sublist(0, topK);
  return scores;
}

/// Voto mayoritario sobre una ventana de clasificaciones.
///
/// Evita que la etiqueta parpadee en cámara en vivo: gana la categoría que
/// más veces apareció como mejor opción y su confianza es el promedio.
SmoothedLabel? majorityLabel(Iterable<Classification> window) {
  final votes = <String, int>{};
  final sums = <String, double>{};
  final categories = <String, WasteCategory>{};
  final labels = <String, String>{};
  var samples = 0;

  for (final classification in window) {
    final best = classification.best;
    if (best == null) continue;
    samples++;
    final id = best.category.id;
    categories[id] = best.category;
    labels[id] = best.rawLabel;
    votes[id] = (votes[id] ?? 0) + 1;
    sums[id] = (sums[id] ?? 0) + best.score;
  }
  if (votes.isEmpty) return null;

  String winner = votes.keys.first;
  for (final id in votes.keys) {
    final current = votes[id]!;
    final bestVotes = votes[winner]!;
    if (current > bestVotes ||
        (current == bestVotes && sums[id]! > sums[winner]!)) {
      winner = id;
    }
  }

  return SmoothedLabel(
    category: categories[winner]!,
    rawLabel: labels[winner]!,
    score: sums[winner]! / votes[winner]!,
    votes: votes[winner]!,
    samples: samples,
  );
}
