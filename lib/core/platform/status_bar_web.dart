import 'dart:ui';

import 'package:web/web.dart' as web;

String? _applied;

/// Na PWA, a barra de estado segue `<meta name="theme-color">` e o fundo da
/// página. Os do index.html seguem o tema do sistema; aqui passam a seguir
/// o que a app mostra.
void applyStatusBarColor(Color color) {
  final hex =
      '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
  if (hex == _applied) return;
  _applied = hex;
  final metas = web.document.querySelectorAll('meta[name="theme-color"]');
  for (var i = 0; i < metas.length; i++) {
    final meta = metas.item(i)! as web.HTMLMetaElement;
    meta.removeAttribute('media');
    meta.content = hex;
  }
  web.document.body?.style.backgroundColor = hex;
}
