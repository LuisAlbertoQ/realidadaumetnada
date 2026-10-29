import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realidadaumentada/services/classifier_math.dart';
import 'package:realidadaumentada/ui/photo_screen.dart';
import 'package:realidadaumentada/ui/widgets/crop_selector.dart';

Future<ui.Image> solidImage(int width, int height) {
  final bytes = Uint8List(width * height * 4);
  for (var i = 0; i < bytes.length; i += 4) {
    bytes[i] = 120;
    bytes[i + 1] = 120;
    bytes[i + 2] = 120;
    bytes[i + 3] = 255;
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    bytes,
    width,
    height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

void main() {
  group('CropSelector', () {
    late ui.Image image;

    setUp(() async {
      image = await solidImage(400, 300);
    });

    tearDown(() => image.dispose());

    Future<void> pumpSelector(
      WidgetTester tester, {
      required SquareCrop crop,
      required ValueChanged<SquareCrop> onChanged,
      ValueChanged<SquareCrop>? onChangedEnd,
    }) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                height: 300,
                child: CropSelector(
                  image: image,
                  crop: crop,
                  onChanged: onChanged,
                  onChangedEnd: onChangedEnd,
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('arrastrar mueve el marco sin cambiar su tamaño', (
      tester,
    ) async {
      SquareCrop current = const SquareCrop(size: 0.5);
      SquareCrop? ended;
      // Igual que la app: cada cambio reconstruye el widget con el nuevo marco.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                height: 300,
                child: StatefulBuilder(
                  builder: (context, setState) => CropSelector(
                    image: image,
                    crop: current,
                    onChanged: (crop) => setState(() => current = crop),
                    onChangedEnd: (crop) => ended = crop,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      // Gestos con varios pasos: el reconocedor necesita salir del "slop".
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(CropSelector)),
      );
      await tester.pump();
      for (var i = 0; i < 12; i++) {
        await gesture.moveBy(const Offset(10, 5));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();

      // 120 px a la derecha sobre 400 de ancho => +0.30; 60 px sobre 300 => +0.20.
      expect(current.centerX, closeTo(0.8, 0.03), reason: 'current=$current');
      expect(current.centerY, closeTo(0.7, 0.03), reason: 'current=$current');
      expect(current.size, closeTo(0.5, 0.01));
      expect(ended, isNotNull);
      expect(ended!.centerX, closeTo(current.centerX, 1e-9));
    });

    testWidgets('pellizcar hacia afuera agranda el marco', (tester) async {
      SquareCrop current = const SquareCrop(size: 0.5);
      await pumpSelector(tester, crop: current, onChanged: (c) => current = c);

      final center = tester.getCenter(find.byType(CropSelector));
      final first = await tester.startGesture(
        center - const Offset(20, 0),
        pointer: 1,
      );
      final second = await tester.startGesture(
        center + const Offset(20, 0),
        pointer: 2,
      );
      await tester.pump();
      await first.moveBy(const Offset(-60, 0));
      await second.moveBy(const Offset(60, 0));
      await tester.pump();
      await first.up();
      await second.up();
      await tester.pumpAndSettle();

      expect(current.size, greaterThan(0.9));
      expect(current.size, lessThanOrEqualTo(1.0));
    });

    testWidgets('pellizcar hacia adentro achica hasta el mínimo', (
      tester,
    ) async {
      SquareCrop current = const SquareCrop(size: 1);
      await pumpSelector(tester, crop: current, onChanged: (c) => current = c);

      final center = tester.getCenter(find.byType(CropSelector));
      final first = await tester.startGesture(
        center - const Offset(120, 0),
        pointer: 1,
      );
      final second = await tester.startGesture(
        center + const Offset(120, 0),
        pointer: 2,
      );
      await tester.pump();
      await first.moveBy(const Offset(110, 0));
      await second.moveBy(const Offset(-110, 0));
      await tester.pump();
      await first.up();
      await second.up();
      await tester.pumpAndSettle();

      expect(current.size, SquareCrop.minSize);
    });

    testWidgets('no deja salir el marco de la imagen', (tester) async {
      SquareCrop current = const SquareCrop(size: 0.5);
      await pumpSelector(tester, crop: current, onChanged: (c) => current = c);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(CropSelector)),
      );
      await tester.pump();
      for (var i = 0; i < 20; i++) {
        await gesture.moveBy(const Offset(30, 30));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();

      // 400×300 con marco al 50 %: el centro queda a 0.125 del borde.
      expect(current.centerX, lessThanOrEqualTo(0.875 + 1e-9));
      expect(current.centerY, lessThanOrEqualTo(0.875 + 1e-9));
    });

    test('coverRect reproduce la escala de BoxFit.cover', () {
      // Pantalla vertical 600×1200 (aspecto 0.5) con cámara 4:3 vertical
      // (aspecto 0.75): la imagen se escala por altura y sobra por los lados.
      const box = Size(600, 1200);
      final rect = coverRect(box, 0.75);
      expect(rect.height, 1200);
      expect(rect.width, 900);
      expect(rect.center, const Offset(300, 600));
      // La imagen cubre todo el widget, también en los bordes.
      expect(rect.left, lessThan(0));
      expect(rect.right, greaterThan(600));
    });
  });

  group('PhotoScreen', () {
    testWidgets('ofrece tomar foto y elegir de la galería', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: PhotoScreen()));

      expect(find.text('Tomar foto'), findsOneWidget);
      expect(find.text('Galería'), findsOneWidget);
      expect(
        find.textContaining('La foto tomada con la app es temporal'),
        findsOneWidget,
      );
    });

    testWidgets('un fallo del selector de fotos no rompe la pantalla', (
      tester,
    ) async {
      const channel = MethodChannel('plugins.flutter.io/image_picker');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'camera_error', message: 'sin cámara');
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      await tester.pumpWidget(const MaterialApp(home: PhotoScreen()));
      await tester.tap(find.text('Tomar foto'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('No se pudo analizar la foto'),
        findsOneWidget,
      );
    });

    testWidgets('cancelar la cámara deja la pantalla como estaba', (
      tester,
    ) async {
      const channel = MethodChannel('plugins.flutter.io/image_picker');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async => null);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      await tester.pumpWidget(const MaterialApp(home: PhotoScreen()));
      await tester.tap(find.text('Tomar foto'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Toma una foto o elige una de tu galería'),
        findsOneWidget,
      );
      expect(find.textContaining('No se pudo analizar'), findsNothing);
    });
  });
}
