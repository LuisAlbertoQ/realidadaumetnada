import 'package:flutter/material.dart';

import 'ui/camera_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Camara Parlante',
      debugShowCheckedModeBanner: false,
      home: CameraScreen(),
    );
  }
}
