import 'package:guarda_roupa/core/domain/clock.dart';

final class FixedClock implements Clock {
  FixedClock(this.now);
  DateTime now;

  @override
  DateTime nowUtc() => now;
}

/// Gera IDs determinísticos: `id-1`, `id-2`, ...
String Function() sequentialIds() {
  var next = 0;
  return () => 'id-${++next}';
}
