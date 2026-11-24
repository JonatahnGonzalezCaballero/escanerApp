import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:opencv_dart/opencv_dart.dart' as cv;

typedef _P = (double, double);

/// Alto (en píxeles) al que se reduce la imagen para buscar el documento.
/// Detectar sobre una copia pequeña es más rápido y menos sensible al ruido.
const _workHeight = 600;

/// Tamaño de la imagen original y esquinas del documento.
///
/// Las esquinas van normalizadas (0..1) respecto al ancho y alto de la imagen,
/// en el orden: arriba-izquierda, arriba-derecha, abajo-derecha, abajo-izquierda.
class DetectionResult {
  const DetectionResult({
    required this.width,
    required this.height,
    required this.corners,
    required this.detected,
  });

  final int width;
  final int height;
  final List<Offset> corners;

  /// false si no se encontró ningún documento y las esquinas son las de relleno.
  final bool detected;
}

class DocumentScanner {
  const DocumentScanner._();

  /// Busca el documento en la imagen. Corre en un isolate para no bloquear la UI.
  static Future<DetectionResult> detect(String imagePath) async {
    final r = await Isolate.run(() => _detectSync(imagePath));
    final c = r.$3;
    return DetectionResult(
      width: r.$1,
      height: r.$2,
      detected: r.$4,
      corners: [for (var i = 0; i < 4; i++) Offset(c[i * 2], c[i * 2 + 1])],
    );
  }

  /// Corrige la perspectiva con las esquinas dadas (normalizadas, mismo orden
  /// que en [DetectionResult]) y guarda el resultado como JPG. Devuelve la ruta.
  static Future<String> crop(String imagePath, List<Offset> corners) async {
    final flat = [
      for (final o in corners) ...[o.dx, o.dy],
    ];
    final out =
        '${Directory.systemTemp.path}/scan_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await Isolate.run(() => _cropSync(imagePath, flat, out));
    return out;
  }

  /// Un cuadrilátero válido es convexo: las esquinas no se cruzan.
  static bool isValidQuad(List<Offset> q) {
    return _isConvex([for (final o in q) (o.dx, o.dy)]);
  }
}

(int, int, List<double>, bool) _detectSync(String path) {
  final src = cv.imread(path, flags: cv.IMREAD_COLOR);
  if (src.isEmpty) {
    throw Exception('No se pudo leer la imagen.');
  }
  final width = src.cols;
  final height = src.rows;

  final scale = math.min(1.0, _workHeight / height);
  final small = cv.resize(
    src,
    ((width * scale).round(), (height * scale).round()),
    interpolation: cv.INTER_AREA,
  );
  final gray = cv.cvtColor(small, cv.COLOR_BGR2GRAY);
  final blur = cv.gaussianBlur(gray, (5, 5), 0);
  final edges = cv.canny(blur, 50, 150);
  final kernel = cv.getStructuringElement(cv.MORPH_RECT, (3, 3));
  // Cierra pequeños huecos en el borde para que el contorno quede continuo.
  final closed = cv.dilate(edges, kernel);

  final (contours, hierarchy) = cv.findContours(
    closed,
    cv.RETR_EXTERNAL,
    cv.CHAIN_APPROX_SIMPLE,
  );

  final sw = small.cols.toDouble();
  final sh = small.rows.toDouble();
  final minArea = sw * sh * 0.15; // el documento debe ocupar al menos el 15 %
  var bestArea = 0.0;
  List<_P>? best;

  for (var i = 0; i < contours.length; i++) {
    final contour = contours[i];
    final area = cv.contourArea(contour);
    if (area < minArea || area <= bestArea) continue;

    final epsilon = 0.02 * cv.arcLength(contour, true);
    final approx = cv.approxPolyDP(contour, epsilon, true);
    if (approx.length == 4) {
      final pts = <_P>[
        for (final p in approx) (p.x.toDouble(), p.y.toDouble()),
      ];
      if (_isConvex(pts)) {
        bestArea = area;
        best = pts;
      }
    }
    approx.dispose();
  }

  final found = best != null;
  final List<double> flat;
  if (best == null) {
    flat = [0.08, 0.08, 0.92, 0.08, 0.92, 0.92, 0.08, 0.92];
  } else {
    flat = [
      for (final p in _order(best)) ...[p.$1 / sw, p.$2 / sh],
    ];
  }

  contours.dispose();
  hierarchy.dispose();
  closed.dispose();
  kernel.dispose();
  edges.dispose();
  blur.dispose();
  gray.dispose();
  small.dispose();
  src.dispose();

  return (width, height, flat, found);
}

void _cropSync(String path, List<double> c, String outPath) {
  final src = cv.imread(path, flags: cv.IMREAD_COLOR);
  if (src.isEmpty) {
    throw Exception('No se pudo leer la imagen.');
  }
  final w = src.cols.toDouble();
  final h = src.rows.toDouble();

  final pts = <_P>[
    for (var i = 0; i < 4; i++) (c[i * 2] * w, c[i * 2 + 1] * h),
  ];

  double dist(_P a, _P b) =>
      math.sqrt(math.pow(a.$1 - b.$1, 2) + math.pow(a.$2 - b.$2, 2));

  // Tamaño de salida: el lado más largo de cada par de lados opuestos.
  final outW = math.max(dist(pts[0], pts[1]), dist(pts[3], pts[2])).round();
  final outH = math.max(dist(pts[0], pts[3]), dist(pts[1], pts[2])).round();
  if (outW < 2 || outH < 2) {
    throw Exception('El área seleccionada es demasiado pequeña.');
  }

  final from = cv.VecPoint.fromList([
    for (final p in pts) cv.Point(p.$1.round(), p.$2.round()),
  ]);
  final to = cv.VecPoint.fromList([
    cv.Point(0, 0),
    cv.Point(outW - 1, 0),
    cv.Point(outW - 1, outH - 1),
    cv.Point(0, outH - 1),
  ]);

  final matrix = cv.getPerspectiveTransform(from, to);
  final out = cv.warpPerspective(src, matrix, (outW, outH));
  cv.imwrite(outPath, out);

  out.dispose();
  matrix.dispose();
  to.dispose();
  from.dispose();
  src.dispose();
}

/// Ordena 4 puntos como: arriba-izq, arriba-der, abajo-der, abajo-izq.
/// La esquina superior izquierda tiene la menor suma x+y y la inferior derecha
/// la mayor; la superior derecha tiene la menor diferencia y-x y la inferior
/// izquierda la mayor.
List<_P> _order(List<_P> p) {
  double sum(_P a) => a.$1 + a.$2;
  double diff(_P a) => a.$2 - a.$1;
  final tl = p.reduce((a, b) => sum(a) <= sum(b) ? a : b);
  final br = p.reduce((a, b) => sum(a) >= sum(b) ? a : b);
  final tr = p.reduce((a, b) => diff(a) <= diff(b) ? a : b);
  final bl = p.reduce((a, b) => diff(a) >= diff(b) ? a : b);
  return [tl, tr, br, bl];
}

/// true si los 4 puntos forman un cuadrilátero convexo (todos los giros van
/// en el mismo sentido).
bool _isConvex(List<_P> q) {
  if (q.length != 4) return false;
  var sign = 0;
  for (var i = 0; i < 4; i++) {
    final a = q[i];
    final b = q[(i + 1) % 4];
    final c = q[(i + 2) % 4];
    final cross = (b.$1 - a.$1) * (c.$2 - b.$2) - (b.$2 - a.$2) * (c.$1 - b.$1);
    if (cross == 0) return false;
    final s = cross > 0 ? 1 : -1;
    if (sign == 0) sign = s;
    if (s != sign) return false;
  }
  return true;
}