import 'dart:io';

import 'package:flutter/material.dart';

import 'image_processor.dart';

class EditScreen extends StatefulWidget {
  const EditScreen({super.key, required this.imagePath});

  /// Imagen ya recortada.
  final String imagePath;

  @override
  State<EditScreen> createState() => _EditScreenState();
}

class _EditScreenState extends State<EditScreen> {
  /// Lado mayor (en píxeles) de las vistas previas de cada filtro.
  static const _previewSide = 1400;

  ScanFilter _filter = ScanFilter.original;
  int _turns = 0; // cuartos de vuelta en sentido horario (0 a 3)
  bool _saving = false;

  // Vistas previas ya calculadas, por filtro. La rotación se aplica en pantalla
  // (instantánea) y solo se calcula de verdad al terminar.
  final Map<ScanFilter, String> _previews = {};
  final Set<ScanFilter> _loading = {};

  @override
  void initState() {
    super.initState();
    _previews[ScanFilter.original] = widget.imagePath;
  }

  Future<void> _select(ScanFilter f) async {
    final needsPreview = !_previews.containsKey(f) && !_loading.contains(f);
    setState(() {
      _filter = f;
      if (needsPreview) _loading.add(f);
    });
    if (!needsPreview) return;

    try {
      final path = await ImageProcessor.process(
        widget.imagePath,
        f,
        maxSide: _previewSide,
      );
      if (!mounted) return;
      setState(() => _previews[f] = path);
    } catch (e) {
      _showError('No se pudo aplicar el filtro: $e');
    } finally {
      if (mounted) setState(() => _loading.remove(f));
    }
  }

  Future<void> _finish() async {
    setState(() => _saving = true);
    try {
      // Resultado final: resolución completa, filtro y rotación aplicados.
      final path = _filter == ScanFilter.original && _turns == 0
          ? widget.imagePath
          : await ImageProcessor.process(
              widget.imagePath,
              _filter,
              quarterTurns: _turns,
            );
      if (!mounted) return;
      Navigator.of(context).pop(path);
    } catch (e) {
      _showError('No se pudo generar la imagen: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    // Mientras el filtro elegido se calcula, se sigue mostrando el original.
    final shown = _previews[_filter] ?? _previews[ScanFilter.original]!;

    return Scaffold(
      appBar: AppBar(title: const Text('Editar')),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Center(
                      child: RotatedBox(
                        quarterTurns: _turns,
                        child: Image.file(File(shown), cacheWidth: 1600),
                      ),
                    ),
                  ),
                ),
                if (_loading.contains(_filter))
                  const Center(child: CircularProgressIndicator()),
              ],
            ),
          ),
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final f in ScanFilter.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Center(
                      child: ChoiceChip(
                        label: Text(f.label),
                        selected: f == _filter,
                        onSelected: (_) => _select(f),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 12, 12),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Girar a la izquierda',
                    onPressed: () => setState(() => _turns = (_turns + 3) % 4),
                    icon: const Icon(Icons.rotate_left),
                  ),
                  IconButton(
                    tooltip: 'Girar a la derecha',
                    onPressed: () => setState(() => _turns = (_turns + 1) % 4),
                    icon: const Icon(Icons.rotate_right),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _saving ? null : _finish,
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Listo'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}