import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

/// De dónde se toma la foto.
enum PhotoSource { camera, gallery }

/// Saca o elige una foto lista para subir: orientada, de hasta 1280 px, JPEG
/// calidad 70 y SIN metadatos (ni EXIF ni GPS). Devuelve null si el chofer
/// cancela.
abstract class PhotoPicker {
  Future<Uint8List?> pick(PhotoSource source);
}

class ImagePickerPhotoPicker implements PhotoPicker {
  ImagePickerPhotoPicker({ImagePicker? picker, bool? scaleBySystem})
      : _picker = picker ?? ImagePicker(),
        // En Android el selector deja en el cache una copia de la original
        // (con su EXIF y GPS) cuando escala, y sólo devuelve la escalada: esa
        // copia no se podría borrar. Se pide la original, se reduce acá y se
        // borra el único archivo.
        _scaleBySystem = scaleBySystem ?? !Platform.isAndroid;

  final bool _scaleBySystem;

  /// Lado mayor de la foto que se sube.
  static const maxSide = 1280;

  /// Calidad JPEG de la foto que se sube.
  static const jpegQuality = 70;

  final ImagePicker _picker;

  @override
  Future<Uint8List?> pick(PhotoSource source) async {
    final file = await _picker.pickImage(
      source: source == PhotoSource.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      maxWidth: _scaleBySystem ? maxSide.toDouble() : null,
      maxHeight: _scaleBySystem ? maxSide.toDouble() : null,
      imageQuality: _scaleBySystem ? jpegQuality : null,
    );
    if (file == null) return null;
    return fromFile(file);
  }

  /// Lee y limpia la foto; el temporal del selector se borra siempre (la copia
  /// que deja `image_picker` en el disco puede traer el GPS).
  static Future<Uint8List> fromFile(XFile file) async {
    try {
      return await sanitize(await file.readAsBytes());
    } finally {
      await _deleteQuietly(file.path);
    }
  }

  static Future<void> _deleteQuietly(String path) async {
    if (kIsWeb || path.isEmpty) return;
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  /// Aplica la orientación EXIF, reduce a [maxSide] y recodifica a JPEG desde
  /// los píxeles: el resultado no conserva ningún metadato de la original.
  /// Acepta lo que decodifica `package:image` (JPEG, PNG, WebP, GIF, BMP,
  /// TIFF); lo que no puede leer lanza [FormatException]: mejor no subir nada
  /// que subir algo sin limpiar.
  static Future<Uint8List> sanitize(Uint8List original) async {
    final bytes = await compute(_reencode, original);
    if (bytes == null) throw const FormatException('No se pudo leer la foto');
    return bytes;
  }
}

Uint8List? _reencode(Uint8List original) {
  final decoded = img.decodeImage(original);
  if (decoded == null) return null;
  // `decodeImage` ya aplica la orientación EXIF al decodificar: no hace falta
  // `bakeOrientation` (que además duplicaría la imagen en memoria).
  var image = decoded;
  const side = ImagePickerPhotoPicker.maxSide;
  final longest = image.width > image.height ? image.width : image.height;
  if (longest > side) {
    image = image.width >= image.height
        ? img.copyResize(image,
            width: side, interpolation: img.Interpolation.average)
        : img.copyResize(image,
            height: side, interpolation: img.Interpolation.average);
  }
  image.exif = img.ExifData();
  image.iccProfile = null;
  return Uint8List.fromList(
      img.encodeJpg(image, quality: ImagePickerPhotoPicker.jpegQuality));
}
