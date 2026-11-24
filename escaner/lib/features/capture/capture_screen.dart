import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../crop/crop_screen.dart';

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  String? _error;
  String? _photoPath;
  bool _taking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  // La cámara se libera al salir de la app (o al abrir la galería) y se
  // vuelve a abrir al regresar.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      final controller = _controller;
      _controller = null;
      controller?.dispose();
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed && _controller == null) {
      _startCamera();
    }
  }

  Future<void> _startCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _error = 'No se encontró ninguna cámara.');
        return;
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.max,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _error = null;
      });
    } on CameraException catch (e) {
      if (mounted) setState(() => _error = e.description ?? e.code);
    }
  }

  Future<void> _takePicture() async {
    final controller = _controller;
    if (controller == null || _taking) return;
    setState(() => _taking = true);
    try {
      final file = await controller.takePicture();
      if (mounted) setState(() => _photoPath = file.path);
    } on CameraException catch (e) {
      if (mounted) setState(() => _error = e.description ?? e.code);
    } finally {
      if (mounted) setState(() => _taking = false);
    }
  }

  Future<void> _pickFromGallery() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file != null && mounted) setState(() => _photoPath = file.path);
  }

  /// Abre el recorte y, si el usuario termina todo el flujo (recorte, filtros),
  /// devuelve la ruta de la página terminada a la pantalla del documento.
  Future<void> _useCurrentPhoto() async {
    final path = _photoPath;
    if (path == null) return;
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => CropScreen(imagePath: path)),
    );
    if (result != null && mounted) Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    if (_photoPath != null) return _buildReview();
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(child: _buildCamera()),
    );
  }

  Widget _buildCamera() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            style: const TextStyle(color: Colors.white),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      children: [
        Expanded(child: Center(child: CameraPreview(controller))),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                onPressed: _pickFromGallery,
                icon: const Icon(Icons.photo_library, color: Colors.white),
                iconSize: 32,
              ),
              FloatingActionButton(
                onPressed: _taking ? null : _takePicture,
                child: const Icon(Icons.camera_alt),
              ),
              const SizedBox(width: 48),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildReview() {
    return Scaffold(
      appBar: AppBar(title: const Text('Vista previa')),
      body: Column(
        children: [
          Expanded(child: Image.file(File(_photoPath!))),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                OutlinedButton(
                  onPressed: () => setState(() => _photoPath = null),
                  child: const Text('Repetir'),
                ),
                FilledButton(
                  onPressed: _useCurrentPhoto,
                  child: const Text('Usar'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}