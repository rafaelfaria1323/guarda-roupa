import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

import '../domain/photo_picker.dart';

final class ImagePickerPhotoPicker implements PhotoPicker {
  const ImagePickerPhotoPicker();

  @override
  Future<Uint8List?> pick(PhotoSource source) async {
    final file = await ImagePicker().pickImage(
      source: switch (source) {
        PhotoSource.camera => ImageSource.camera,
        PhotoSource.gallery => ImageSource.gallery,
      },
      // Sem pedir localização/metadados completos: são removidos de
      // qualquer forma no processamento.
      requestFullMetadata: false,
    );
    return file?.readAsBytes();
  }
}
