import 'package:flutter_test/flutter_test.dart';
import 'package:guarda_roupa/features/wardrobe/domain/availability.dart';

void main() {
  group('Availability.resolveConflict (ADR-008)', () {
    test('suja prevalece sobre disponível, em qualquer ordem', () {
      expect(
        Availability.resolveConflict(
          Availability.needsCleaning,
          Availability.available,
        ),
        Availability.needsCleaning,
      );
      expect(
        Availability.resolveConflict(
          Availability.available,
          Availability.needsCleaning,
        ),
        Availability.needsCleaning,
      );
    });

    test('segue a ordem needs_cleaning > washing > drying > available', () {
      const ordered = [
        Availability.needsCleaning,
        Availability.washing,
        Availability.drying,
        Availability.available,
      ];
      for (var i = 0; i < ordered.length; i++) {
        for (var j = i; j < ordered.length; j++) {
          expect(
            Availability.resolveConflict(ordered[i], ordered[j]),
            ordered[i],
          );
          expect(
            Availability.resolveConflict(ordered[j], ordered[i]),
            ordered[i],
          );
        }
      }
    });

    test('um conflito nunca resulta em disponível se um lado não o for', () {
      for (final a in Availability.values) {
        for (final b in Availability.values) {
          final resolved = Availability.resolveConflict(a, b);
          if (!a.isAvailable || !b.isAvailable) {
            expect(resolved.isAvailable, isFalse, reason: '$a vs $b');
          }
        }
      }
    });
  });

  test('IDs estáveis fazem ida e volta e são únicos', () {
    final ids = Availability.values.map((a) => a.id).toList();
    expect(ids.toSet().length, ids.length);
    for (final a in Availability.values) {
      expect(Availability.fromId(a.id), a);
    }
    expect(Availability.fromId('cleaning_recommended'), isNull);
  });
}
