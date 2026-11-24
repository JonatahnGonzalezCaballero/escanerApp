import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../capture/capture_screen.dart';

class DocumentScreen extends StatefulWidget {
  const DocumentScreen({super.key});

  @override
  State<DocumentScreen> createState() => _DocumentScreenState();
}

class _DocumentScreenState extends State<DocumentScreen> {
  /// Rutas de las páginas, en orden. Cada una es un JPG ya recortado y filtrado.
  /// El documento vive solo en memoria: al cerrar la app se descarta.
  final List<String> _pages = [];

  Future<void> _addPage() async {
    final path = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const CaptureScreen()),
    );
    if (path != null && mounted) setState(() => _pages.add(path));
  }

  void _reorder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    setState(() => _pages.insert(newIndex, _pages.removeAt(oldIndex)));
  }

  /// Quita la página de la lista y ofrece deshacer. El archivo solo se borra
  /// cuando el aviso se cierra sin que se haya pulsado "Deshacer".
  void _removeAt(int index) {
    final path = _pages[index];
    setState(() => _pages.removeAt(index));

    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger
        .showSnackBar(
          SnackBar(
            content: const Text('Página eliminada'),
            action: SnackBarAction(
              label: 'Deshacer',
              onPressed: () {
                setState(() => _pages.insert(math.min(index, _pages.length), path));
              },
            ),
          ),
        )
        .closed
        .then((reason) {
      if (reason != SnackBarClosedReason.action) _deleteFile(path);
    });
  }

  Future<void> _startOver() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Empezar de nuevo?'),
        content: const Text('Se descartarán todas las páginas del documento.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    for (final p in _pages) {
      _deleteFile(p);
    }
    setState(() => _pages.clear());
  }

  Future<void> _deleteFile(String path) async {
    try {
      await File(path).delete();
    } catch (_) {
      // Si el archivo ya no existe no hay nada que hacer.
    }
  }

  void _view(int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _PageViewer(pages: List.of(_pages), initialIndex: index),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Documento'),
        actions: [
          IconButton(
            tooltip: 'Empezar de nuevo',
            onPressed: _pages.isEmpty ? null : _startOver,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: _pages.isEmpty ? _buildEmpty() : _buildList(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addPage,
        icon: const Icon(Icons.add_a_photo_outlined),
        label: Text(_pages.isEmpty ? 'Escanear' : 'Agregar página'),
      ),
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Text(
          'Todavía no hay páginas.\nToca "Escanear" para empezar.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildList() {
    return ReorderableListView.builder(
      padding: const EdgeInsets.only(bottom: 96),
      buildDefaultDragHandles: false,
      itemCount: _pages.length,
      onReorder: _reorder,
      itemBuilder: (context, i) {
        final path = _pages[i];
        return ListTile(
          key: ValueKey(path),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.file(
              File(path),
              width: 48,
              height: 64,
              fit: BoxFit.cover,
              cacheWidth: 150,
            ),
          ),
          title: Text('Página ${i + 1}'),
          onTap: () => _view(i),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Eliminar',
                onPressed: () => _removeAt(i),
                icon: const Icon(Icons.delete_outline),
              ),
              ReorderableDragStartListener(
                index: i,
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.drag_handle),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Visor a pantalla completa: se pasa de página deslizando y se amplía con
/// dos dedos.
class _PageViewer extends StatefulWidget {
  const _PageViewer({required this.pages, required this.initialIndex});

  final List<String> pages;
  final int initialIndex;

  @override
  State<_PageViewer> createState() => _PageViewerState();
}

class _PageViewerState extends State<_PageViewer> {
  late final PageController _controller =
      PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Página ${_index + 1} de ${widget.pages.length}'),
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.pages.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (_, i) => InteractiveViewer(
          maxScale: 8,
          child: Center(
            child: Image.file(File(widget.pages[i]), cacheWidth: 2400),
          ),
        ),
      ),
    );
  }
}