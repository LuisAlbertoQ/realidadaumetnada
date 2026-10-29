import 'package:flutter_test/flutter_test.dart';
import 'package:realidadaumentada/main.dart';

void main() {
  testWidgets('home muestra los tres accesos y la leyenda', (tester) async {
    await tester.pumpWidget(const WasteClassifierApp());

    // La carga del modelo es asíncrona; basta con unos frames para que la
    // home pinte sus tarjetas (el modo demo/error no las oculta).
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Cámara en vivo'), findsOneWidget);
    expect(find.text('Foto de galería'), findsOneWidget);
    expect(find.text('Video de galería'), findsOneWidget);
    expect(find.text('Papel y cartón'), findsOneWidget);
    expect(find.text('Generales / No aprovechables'), findsOneWidget);
  });
}
