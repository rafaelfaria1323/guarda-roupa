import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/plugin_label_camera.dart';

/// A câmara ao vivo do ecrã "Ler etiqueta". Os testes trocam-na por uma
/// a fingir.
abstract interface class LabelCamera {
  /// Abre a câmara de trás. `false` se não houver câmara, o utilizador
  /// recusar a permissão ou o navegador não deixar.
  Future<bool> open();

  /// A imagem ao vivo, a encher o espaço que lhe derem.
  Widget preview();

  /// Uma foto do que a câmara está a ver.
  Future<Uint8List> capture();

  Future<void> close();
}

/// Uma câmara nova por cada vez que o ecrã abre.
final labelCameraProvider = Provider<LabelCamera Function()>(
  (ref) => PluginLabelCamera.new,
);
