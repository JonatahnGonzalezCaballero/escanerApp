import 'dart:io';

import 'package:flutter/material.dart';

import 'features/document/document_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _cleanTempFiles();
  runApp(const EscanerApp());
}

/// Borra los JPG sueltos de la caché (fotos, recortes y vistas previas de
/// sesiones anteriores). Como el documento vive solo en memoria, al iniciar no
/// hay nada que conservar.
Future<void> _cleanTempFiles() async {
  try {
    await for (final entity in Directory.systemTemp.list()) {
      if (entity is File && entity.path.toLowerCase().endsWith('.jpg')) {
        await entity.delete();
      }
    }
  } catch (_) {
    // Limpiar la caché es opcional: si falla, la app arranca igual.
  }
}

class EscanerApp extends StatelessWidget {
  const EscanerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Escáner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const DocumentScreen(),
    );
  }
}