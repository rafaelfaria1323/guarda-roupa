import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:guarda_roupa/features/photo_ai/application/label_camera.dart';
import 'package:guarda_roupa/features/photo_ai/domain/label_auto_shutter.dart';

import 'fake_photos.dart';

/// Câmara a fingir: cada foto é um PNG de cor diferente.
class FakeLabelCamera implements LabelCamera {
  FakeLabelCamera({this.available = true, this.probes});

  final bool available;

  /// O que a sonda devolve de cada vez; sem lista, não há sonda.
  final LabelProbe? Function()? probes;
  int captures = 0;
  bool closed = false;

  @override
  Future<bool> open() async => available;

  @override
  Widget preview() => const ColoredBox(color: Color(0xFF8899AA));

  @override
  Future<Uint8List> capture() async => testPng(r: 40 + 20 * captures++);

  @override
  LabelProbe? probe() => probes?.call();

  @override
  Future<void> close() async => closed = true;
}
