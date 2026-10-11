import 'dart:typed_data';

/// Saca los metadatos de un JPEG (EXIF con GPS, XMP, comentarios, etc.) sin
/// recomprimir: copia los segmentos de imagen y descarta los APP1..APP15 y COM
/// que hay antes de los datos. Se queda con APP0 (JFIF) y APP14 (Adobe, que
/// define el espacio de color).
class JpegSanitizer {
  JpegSanitizer._();

  /// `true` si [bytes] empieza con la firma de un JPEG.
  static bool isJpeg(Uint8List bytes) =>
      bytes.length > 3 && bytes[0] == 0xFF && bytes[1] == 0xD8;

  /// El JPEG sin metadatos. Si no es un JPEG o está cortado, lanza
  /// [FormatException]: mejor no subir nada que subir algo sin limpiar.
  static Uint8List stripMetadata(Uint8List bytes) {
    if (!isJpeg(bytes)) throw const FormatException('No es un JPEG');
    final out = BytesBuilder(copy: false)..add(const [0xFF, 0xD8]);
    var i = 2;
    while (i < bytes.length) {
      if (bytes[i] != 0xFF) throw const FormatException('JPEG corrupto');
      // Relleno 0xFF entre segmentos.
      while (i < bytes.length && bytes[i] == 0xFF) {
        i++;
      }
      if (i >= bytes.length) throw const FormatException('JPEG cortado');
      final marker = bytes[i++];
      if (marker == 0xD9) {
        out.add(const [0xFF, 0xD9]);
        return out.toBytes();
      }
      // Marcadores sin largo (RSTn, TEM).
      if ((marker >= 0xD0 && marker <= 0xD7) || marker == 0x01) {
        out.add([0xFF, marker]);
        continue;
      }
      if (i + 2 > bytes.length) throw const FormatException('JPEG cortado');
      final len = (bytes[i] << 8) | bytes[i + 1];
      if (len < 2 || i + len > bytes.length) {
        throw const FormatException('JPEG cortado');
      }
      if (marker == 0xDA) {
        // Comienzo de los datos: de acá al final se copia tal cual.
        out.add([0xFF, marker]);
        out.add(bytes.sublist(i));
        return out.toBytes();
      }
      final isMetadata = (marker >= 0xE1 && marker <= 0xEF && marker != 0xEE) ||
          marker == 0xFE;
      if (!isMetadata) {
        out.add([0xFF, marker]);
        out.add(bytes.sublist(i, i + len));
      }
      i += len;
    }
    throw const FormatException('JPEG sin datos de imagen');
  }
}
