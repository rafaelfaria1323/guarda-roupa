import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:guarda_roupa/features/photo_ai/application/label_camera.dart';

import 'fake_photos.dart';

/// Câmara a fingir: cada foto é um PNG de cor diferente.
class FakeLabelCamera implements LabelCamera {
  FakeLabelCamera({this.available = true});

  final bool available;
  int captures = 0;
  bool closed = false;

  @override
  Future<bool> open() async => available;

  @override
  Widget preview() => const ColoredBox(color: Color(0xFF8899AA));

  @override
  Future<Uint8List> capture() async => testPng(r: 40 + 20 * captures++);

  @override
  Future<void> close() async => closed = true;
}
