import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../domain/label_auto_shutter.dart';

const _width = 240;
web.HTMLCanvasElement? _canvas;

/// O centro do vídeo da câmara, pequeno e a cinzento. `null` se o vídeo
/// ainda não tem imagem ou o navegador não deixar ler.
LabelProbe? probeCameraVideo() {
  try {
    final videos = web.document.querySelectorAll('video');
    web.HTMLVideoElement? video;
    for (var i = 0; i < videos.length; i++) {
      final v = videos.item(i)! as web.HTMLVideoElement;
      if (v.videoWidth > 0 && v.videoHeight > 0) video = v;
    }
    if (video == null) return null;
    // Só o meio, onde está a moldura.
    final sw = video.videoWidth * 0.6;
    final sh = video.videoHeight * 0.6;
    final height = (_width * sh / sw).round().clamp(1, 480);
    final canvas = _canvas ??= web.HTMLCanvasElement();
    canvas
      ..width = _width
      ..height = height;
    final context =
        canvas.getContext('2d', {'willReadFrequently': true}.jsify())!
            as web.CanvasRenderingContext2D;
    context.drawImage(
      video,
      video.videoWidth * 0.2,
      video.videoHeight * 0.2,
      sw,
      sh,
      0,
      0,
      _width,
      height,
    );
    final rgba = context.getImageData(0, 0, _width, height).data.toDart;
    final gray = Uint8List(_width * height);
    for (var i = 0, j = 0; i < gray.length; i++, j += 4) {
      gray[i] = (rgba[j] * 77 + rgba[j + 1] * 150 + rgba[j + 2] * 29) >> 8;
    }
    return LabelProbe(_width, height, gray);
  } on Object {
    return null;
  }
}
