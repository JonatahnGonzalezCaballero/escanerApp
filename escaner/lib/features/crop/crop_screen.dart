import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../edit/edit_screen.dart';
import 'document_scanner.dart';

const _handleSize = 44.0;

class CropScreen extends StatefulWidget {
  const CropScreen({super.key, required this.imagePath});

  final String imagePath;

  @override
  State<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<CropScreen> {
  DetectionResult? _detection;
  List<Offset> _corners = [];
  String? _error;
  bool _cropping = false;

  @override
  void initState() {
    super.initState();
    _analyze();
  }

  Future<void> _analyze() async {
    try {
      final d = await DocumentScanner.detect(widget.imagePath);
      if (!mounted) return;
      setState(() {
        _detection = d;
        _corners = List.of(d.corners);
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  void _useAutoCorners() {
    setState(() => _corners = List.of(_detection!.corners));
  }

  void _useFullImage() {
    setState(() {
      _corners = List.of(const [
        Offset(0, 0),
        Offset(1, 0),
        Offset(1, 1),
        Offset(0, 1),
      ]);
    });
  }

  Future<void> _crop() async {
    if (!DocumentScanner.isValidQuad(_corners)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Las esquinas se cruzan. Ajústalas para formar un cuadrilátero.'),
        ),
      );
      return;
    }
    setState(() => _cropping = true);
    try {
      final path = await DocumentScanner.crop(widget.imagePath, _corners);
      if (!mounted) return;
      final result = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => EditScreen(imagePath: path)),
      );
      if (result != null && mounted) Navigator.of(context).pop(result);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo recortar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _cropping = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recortar')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }
    final d = _detection;
    if (d == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      children: [
        Expanded(child: _buildEditor(d)),
        if (!d.detected)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              'No se detectó el documento. Ajusta las esquinas a mano.',
              textAlign: TextAlign.center,
            ),
          ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: _useAutoCorners,
                  child: const Text('Automático'),
                ),
                TextButton(
                  onPressed: _useFullImage,
                  child: const Text('Imagen completa'),
                ),
                FilledButton(
                  onPressed: _cropping ? null : _crop,
                  child: _cropping
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Recortar'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEditor(DetectionResult d) {
    return LayoutBuilder(
      builder: (context, box) {
        // Zona de la pantalla que ocupa la imagen (equivale a BoxFit.contain).
        final scale = math.min(box.maxWidth / d.width, box.maxHeight / d.height);
        final w = d.width * scale;
        final h = d.height * scale;
        final rect = Rect.fromLTWH(
          (box.maxWidth - w) / 2,
          (box.maxHeight - h) / 2,
          w,
          h,
        );

        Offset toScreen(Offset n) =>
            Offset(rect.left + n.dx * rect.width, rect.top + n.dy * rect.height);
        Offset toNormalized(Offset p) => Offset(
              ((p.dx - rect.left) / rect.width).clamp(0.0, 1.0).toDouble(),
              ((p.dy - rect.top) / rect.height).clamp(0.0, 1.0).toDouble(),
            );

        final points = [for (final c in _corners) toScreen(c)];
        final color = Theme.of(context).colorScheme.primary;

        return Stack(
          children: [
            Positioned.fromRect(
              rect: rect,
              child: Image.file(
                File(widget.imagePath),
                fit: BoxFit.fill,
                cacheWidth: 1600,
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _QuadPainter(points, color)),
              ),
            ),
            for (var i = 0; i < 4; i++)
              Positioned(
                left: points[i].dx - _handleSize / 2,
                top: points[i].dy - _handleSize / 2,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (u) {
                    final moved = toNormalized(toScreen(_corners[i]) + u.delta);
                    setState(() => _corners = List.of(_corners)..[i] = moved);
                  },
                  child: _Handle(color: color),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Handle extends StatelessWidget {
  const _Handle({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _handleSize,
      height: _handleSize,
      child: Center(
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
        ),
      ),
    );
  }
}

class _QuadPainter extends CustomPainter {
  _QuadPainter(this.points, this.color);

  final List<Offset> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..addPolygon(points, true);
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.18));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_QuadPainter oldDelegate) => true;
}