import 'package:flutter/widgets.dart';

import 'status_bar_io.dart' if (dart.library.js_interop) 'status_bar_web.dart';

Color? _theme;
Color? _override;

void _apply() {
  final color = _override ?? _theme;
  if (color != null) applyStatusBarColor(color);
}

/// Cor que um ecrã impõe à barra de estado enquanto está aberto (ex.: o
/// ecrã preto de "Ler etiqueta"). `null` volta à do tema.
void setStatusBarOverride(Color? color) {
  _override = color;
  _apply();
}

/// Mantém a barra de estado do telemóvel na cor do fundo da app: a do tema
/// escolhido nas Definições (que pode não ser o do sistema) ou a imposta
/// por [setStatusBarOverride].
class StatusBarColor extends StatelessWidget {
  const StatusBarColor({required this.color, required this.child, super.key});

  /// Fundo do tema atual.
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    _theme = color;
    _apply();
    return child;
  }
}
