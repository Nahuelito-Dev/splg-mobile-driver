import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

import 'package:splg_driver/services/jpeg_sanitizer.dart';

/// De dónde se toma la foto.
enum PhotoSource { camera, gallery }

/// Saca o elige una foto lista para subir: JPEG de hasta 1280 px, calidad 70 y
/// SIN metadatos (ni EXIF ni GPS). Devuelve null si el chofer cancela.
abstract class PhotoPicker {
  Future<Uint8List?> pick(PhotoSource source);
}

class ImagePickerPhotoPicker implements PhotoPicker {
  ImagePickerPhotoPicker({ImagePicker? picker})
      : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<Uint8List?> pick(PhotoSource source) async {
    final file = await _picker.pickImage(
      source: source == PhotoSource.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 70,
      requestFullMetadata: false,
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    // Aunque el plugin recomprima, se limpia por las dudas.
    return JpegSanitizer.stripMetadata(bytes);
  }
}
