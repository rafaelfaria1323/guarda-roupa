import 'dart:typed_data';

/// Uma imagem pequena, em tons de cinzento (um byte por ponto), do que a
/// câmara está a ver. Serve só para medir nitidez e movimento.
final class LabelProbe {
  const LabelProbe(this.width, this.height, this.gray)
    : assert(gray.length == width * height, 'um byte por ponto');

  final int width;
  final int height;
  final Uint8List gray;
}

/// O que o disparo automático está a fazer.
enum AutoShutterState {
  /// Ainda não há nada nítido à frente da câmara.
  searching,

  /// Há algo nítido e com detalhe: falta ficar parado um instante.
  holding,

  /// Nítido e parado o tempo suficiente: tirar a foto agora.
  fire,
}

/// Decide quando tirar a foto da etiqueta sozinho: quando a imagem tem
/// detalhe fino (letras), está nítida e ficou parada. Não reconhece
/// etiquetas; isso é com quem lê a foto.
final class LabelAutoShutter {
  LabelAutoShutter({
    this.minSharpness = 14,
    this.minDetail = 0.1,
    this.maxMotion = 5,
    this.steadyFrames = 3,
  });

  /// Média do contraste entre cada ponto e os vizinhos (0–255).
  final double minSharpness;

  /// Parte dos pontos com contorno forte (0–1).
  final double minDetail;

  /// Diferença média para a imagem anterior (0–255).
  final double maxMotion;

  /// Imagens seguidas, boas e paradas, antes de disparar.
  final int steadyFrames;

  LabelProbe? _previous;
  int _steady = 0;
  bool _waitForMove = false;

  /// Depois de uma foto que não serviu: só volta a disparar quando a
  /// câmara se mexer (senão repetia a mesma foto).
  void rearmAfterMove() {
    _waitForMove = true;
    _steady = 0;
  }

  void reset() {
    _previous = null;
    _steady = 0;
    _waitForMove = false;
  }

  AutoShutterState add(LabelProbe probe) {
    final previous = _previous;
    _previous = probe;
    if (previous == null ||
        previous.width != probe.width ||
        previous.height != probe.height) {
      _steady = 0;
      return AutoShutterState.searching;
    }
    final moved = motion(previous, probe);
    if (_waitForMove) {
      if (moved > maxMotion * 2) _waitForMove = false;
      return AutoShutterState.searching;
    }
    final (sharp, detail) = sharpness(probe);
    if (sharp < minSharpness || detail < minDetail) {
      _steady = 0;
      return AutoShutterState.searching;
    }
    if (moved > maxMotion) {
      _steady = 0;
      return AutoShutterState.holding;
    }
    _steady++;
    if (_steady < steadyFrames) return AutoShutterState.holding;
    _steady = 0;
    return AutoShutterState.fire;
  }

  /// Nitidez (média do laplaciano) e detalhe (parte dos pontos com
  /// contorno forte).
  static (double, double) sharpness(LabelProbe p) {
    final w = p.width;
    final h = p.height;
    if (w < 3 || h < 3) return (0, 0);
    final g = p.gray;
    var sum = 0;
    var strong = 0;
    for (var y = 1; y < h - 1; y++) {
      final row = y * w;
      for (var x = 1; x < w - 1; x++) {
        final i = row + x;
        final lap = (4 * g[i] - g[i - 1] - g[i + 1] - g[i - w] - g[i + w])
            .abs();
        sum += lap;
        if (lap > 40) strong++;
      }
    }
    final n = (w - 2) * (h - 2);
    return (sum / n, strong / n);
  }

  /// Diferença média entre duas imagens do mesmo tamanho.
  static double motion(LabelProbe a, LabelProbe b) {
    var sum = 0;
    for (var i = 0; i < a.gray.length; i++) {
      sum += (a.gray[i] - b.gray[i]).abs();
    }
    return sum / a.gray.length;
  }
}
