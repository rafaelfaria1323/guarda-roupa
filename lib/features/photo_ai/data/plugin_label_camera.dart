import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../application/label_camera.dart';

/// A câmara pelo plugin `camera` (no navegador, getUserMedia).
final class PluginLabelCamera implements LabelCamera {
  CameraController? _controller;

  @override
  Future<bool> open() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return false;
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      // A maior resolução que a câmara der: a letra das etiquetas é miúda.
      final controller = CameraController(
        back,
        ResolutionPreset.max,
        enableAudio: false,
      );
      await controller.initialize();
      _controller = controller;
      return true;
    } on Object {
      return false;
    }
  }

  @override
  Widget preview() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.expand();
    }
    // No navegador o vídeo já enche a caixa (object-fit: cover).
    if (kIsWeb) return SizedBox.expand(child: controller.buildPreview());
    final size = controller.value.previewSize;
    if (size == null) return CameraPreview(controller);
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: size.height,
          height: size.width,
          child: CameraPreview(controller),
        ),
      ),
    );
  }

  @override
  Future<Uint8List> capture() async {
    final controller = _controller;
    if (controller == null) throw StateError('câmara fechada');
    final file = await controller.takePicture();
    return file.readAsBytes();
  }

  @override
  Future<void> close() async {
    final controller = _controller;
    _controller = null;
    await controller?.dispose();
  }
}
