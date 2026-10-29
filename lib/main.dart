import 'package:flutter/material.dart';

import 'services/classifier_service.dart';
import 'ui/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Carga en segundo plano: la home escucha el ChangeNotifier.
  ClassifierService.instance.ensureLoaded();
  runApp(const WasteClassifierApp());
}

class WasteClassifierApp extends StatelessWidget {
  const WasteClassifierApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF2E7D32),
      brightness: Brightness.dark,
    );
    return MaterialApp(
      title: 'Clasificador de residuos',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF101410),
      ),
      home: const HomeScreen(),
    );
  }
}
