import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/features/photo_ai/domain/label_auto_shutter.dart';

import '../../support/label_probes.dart';

void main() {
  test('nítida e parada dispara ao fim de umas imagens', () {
    final shutter = LabelAutoShutter();
    expect(shutter.add(sharpProbe()), AutoShutterState.searching);
    expect(shutter.add(sharpProbe()), AutoShutterState.holding);
    expect(shutter.add(sharpProbe()), AutoShutterState.holding);
    expect(shutter.add(sharpProbe()), AutoShutterState.fire);
    // Recomeça a contar.
    expect(shutter.add(sharpProbe()), AutoShutterState.holding);
  });

  test('lisa ou desfocada não dispara', () {
    final shutter = LabelAutoShutter();
    for (var i = 0; i < 10; i++) {
      expect(shutter.add(flatProbe()), AutoShutterState.searching);
    }
  });

  test('a mexer não dispara, mas avisa para segurar', () {
    final shutter = LabelAutoShutter();
    shutter.add(sharpProbe());
    for (var i = 1; i < 10; i++) {
      expect(shutter.add(sharpProbe(shift: i * 2)), AutoShutterState.holding);
    }
  });

  test('depois de uma foto que não serviu, espera que a câmara se mexa', () {
    final shutter = LabelAutoShutter();
    for (var i = 0; i < 4; i++) {
      shutter.add(sharpProbe());
    }
    shutter.rearmAfterMove();
    for (var i = 0; i < 10; i++) {
      expect(shutter.add(sharpProbe()), AutoShutterState.searching);
    }
    // Mexeu: volta a contar.
    expect(shutter.add(sharpProbe(shift: 2)), AutoShutterState.searching);
    expect(shutter.add(sharpProbe(shift: 2)), AutoShutterState.holding);
    expect(shutter.add(sharpProbe(shift: 2)), AutoShutterState.holding);
    expect(shutter.add(sharpProbe(shift: 2)), AutoShutterState.fire);
  });
}
