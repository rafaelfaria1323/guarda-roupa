import 'dart:typed_data';

import '../../wardrobe/domain/foreground_mask.dart';

/// Recorte de fundo. `null` se não conseguir (o chamador segue sem máscara).
abstract interface class BackgroundRemover {
  Future<ForegroundMask?> mask(Uint8List bytes);

  Future<void> close();
}
