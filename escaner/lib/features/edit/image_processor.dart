import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:opencv_dart/opencv_dart.dart' as cv;

enum ScanFilter {
  original('Original'),
  enhanced('Mejorado'),
  gray('Grises'),
  blackWhite('Blanco y negro');

  const ScanFilter(this.label);

  final String label;
}

class ImageProcessor {
  const ImageProcessor._();

  /// Aplica [filter] y después gira [quarterTurns] cuartos de vuelta en sentido
  /// horario. Si [maxSide] es mayor que 0, la imagen se reduce antes para que su
  /// lado mayor no pase de ese valor (útil para vistas previas).
  /// Corre en un isolate y devuelve la ruta del JPG generado.
  static Future<String> process(
    String imagePath,
    ScanFilter filter, {
    int quarterTurns = 0,
    int maxSide = 0,
  }) async {
    final out =
        '${Directory.systemTemp.path}/scan_${filter.name}_${DateTime.now().microsecondsSinceEpoch}.jpg';
    final turns = ((quarterTurns % 4) + 4) % 4;
    final index = filter.index;
    await Isolate.run(
      () => _processSync(imagePath, index, turns, maxSide, out),
    );
    return out;
  }
}

void _processSync(
  String path,
  int filterIndex,
  int turns,
  int maxSide,
  String outPath,
) {
  final filter = ScanFilter.values[filterIndex];

  var base = cv.imread(path, flags: cv.IMREAD_COLOR);
  if (base.isEmpty) {
    throw Exception('No se pudo leer la imagen.');
  }

  if (maxSide > 0) {
    final longest = math.max(base.cols, base.rows);
    if (longest > maxSide) {
      final s = maxSide / longest;
      final small = cv.resize(
        base,
        ((base.cols * s).round(), (base.rows * s).round()),
        interpolation: cv.INTER_AREA,
      );
      base.dispose();
      base = small;
    }
  }

  final filtered = switch (filter) {
    ScanFilter.original => base,
    ScanFilter.enhanced => _enhance(base),
    ScanFilter.gray => cv.cvtColor(base, cv.COLOR_BGR2GRAY),
    ScanFilter.blackWhite => _blackWhite(base),
  };

  final rotated = turns == 0 ? filtered : cv.rotate(filtered, _rotateCode(turns));

  cv.imwrite(outPath, rotated);

  if (!identical(rotated, filtered)) rotated.dispose();
  if (!identical(filtered, base)) filtered.dispose();
  base.dispose();
}

int _rotateCode(int turns) => switch (turns) {
      1 => cv.ROTATE_90_CLOCKWISE,
      2 => cv.ROTATE_180,
      _ => cv.ROTATE_90_COUNTERCLOCKWISE,
    };

/// Mejora el contraste local sin alterar los colores: aplica CLAHE solo al
/// canal de luminosidad (L) en el espacio Lab.
cv.Mat _enhance(cv.Mat bgr) {
  final lab = cv.cvtColor(bgr, cv.COLOR_BGR2Lab);
  final channels = cv.split(lab);
  final clahe = cv.CLAHE(3.0, (8, 8));
  final lightness = clahe.apply(channels[0]);
  channels[0] = lightness;
  final merged = cv.merge(channels);
  final out = cv.cvtColor(merged, cv.COLOR_Lab2BGR);

  merged.dispose();
  lightness.dispose();
  clahe.dispose();
  channels.dispose();
  lab.dispose();
  return out;
}

/// Blanco y negro con umbral adaptativo: el umbral se calcula por zonas, así
/// que las sombras y la iluminación despareja no tiñen la hoja de gris.
cv.Mat _blackWhite(cv.Mat bgr) {
  final gray = cv.cvtColor(bgr, cv.COLOR_BGR2GRAY);

  // El tamaño de la zona crece con la imagen para que la vista previa y el
  // resultado final se parezcan. Debe ser impar.
  var block = (math.max(gray.cols, gray.rows) * 0.03).round();
  if (block < 11) block = 11;
  if (block.isEven) block += 1;

  // Con la media (y no la gaussiana) el costo no depende del tamaño de la zona.
  final out = cv.adaptiveThreshold(
    gray,
    255,
    cv.ADAPTIVE_THRESH_MEAN_C,
    cv.THRESH_BINARY,
    block,
    10,
  );
  gray.dispose();
  return out;
}