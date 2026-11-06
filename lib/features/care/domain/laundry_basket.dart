import '../../wardrobe/domain/availability.dart';
import '../../wardrobe/domain/garment.dart';
import '../../wardrobe/domain/garment_attributes.dart';
import '../../wardrobe/domain/oklab.dart';
import 'laundry_policy.dart';

/// Como se lava uma peça do cesto: pela lavagem marcada, ou pelo texto
/// da etiqueta quando pede limpeza profissional.
enum WashProgram {
  professional('professional'),
  hand('hand'),
  machine30('machine_30'),
  machine40('machine_40'),
  machine60('machine_60'),
  unknown('unknown');

  const WashProgram(this.id);

  final String id;

  static WashProgram of(GarmentAttributes a) {
    if (LaundryPolicy.isProfessional(a)) return professional;
    return switch (a.wash) {
      WashCare.hand => hand,
      WashCare.machine30 => machine30,
      WashCare.machine40 => machine40,
      WashCare.machine60 => machine60,
      WashCare.professional => professional,
      null => unknown,
    };
  }
}

/// Tom da cor principal, para não juntar brancos com escuros.
enum Shade {
  light('light'),
  colored('colored'),
  dark('dark'),
  unknown('unknown');

  const Shade(this.id);

  final String id;

  /// Claras a partir de bege/azul-claro/rosa (L ≈ 0,8); escuras até
  /// castanho (L ≈ 0,45). O resto é "cores".
  static const lightFrom = 0.78;
  static const darkUpTo = 0.47;

  static Shade of(Garment g) {
    if (g.colors.isEmpty) return unknown;
    final main = g.colors.reduce((a, b) => b.proportion > a.proportion ? b : a);
    final l = Oklab.fromRgb(main.rgb).l;
    if (l >= lightFrom) return light;
    if (l <= darkUpTo) return dark;
    return colored;
  }
}

/// Uma máquina (ou ida à lavandaria): peças que se lavam juntas.
final class WashLoad {
  const WashLoad(this.program, this.shade, this.garments);

  final WashProgram program;

  /// `null` para a limpeza profissional e à mão, em que o tom não conta.
  final Shade? shade;
  final List<Garment> garments;
}

/// O cesto: peças por lavar, agrupadas em máquinas; as que estão a lavar
/// ou a secar; e as que estão na lavandaria.
final class LaundryBasket {
  const LaundryBasket({
    required this.loads,
    required this.inProgress,
    required this.atCleaners,
  });

  factory LaundryBasket.of(Iterable<Garment> garments) {
    final dirty = <(WashProgram, Shade?), List<Garment>>{};
    final inProgress = <Garment>[];
    final atCleaners = <Garment>[];
    for (final g in garments) {
      if (g.isArchived) continue;
      switch (g.availability) {
        case Availability.needsCleaning:
          final program = WashProgram.of(g.attributes);
          final shade = switch (program) {
            WashProgram.professional || WashProgram.hand => null,
            _ => Shade.of(g),
          };
          (dirty[(program, shade)] ??= []).add(g);
        case Availability.washing || Availability.drying:
          inProgress.add(g);
        case Availability.atCleaners:
          atCleaners.add(g);
        case Availability.available:
          break;
      }
    }
    int order((WashProgram, Shade?) k) => k.$1.index * 10 + (k.$2?.index ?? 0);
    final keys = dirty.keys.toList()
      ..sort((a, b) => order(a).compareTo(order(b)));
    return LaundryBasket(
      loads: [for (final k in keys) WashLoad(k.$1, k.$2, dirty[k]!)],
      inProgress: inProgress,
      atCleaners: atCleaners,
    );
  }

  final List<WashLoad> loads;
  final List<Garment> inProgress;
  final List<Garment> atCleaners;

  int get dirtyCount => loads.fold(0, (n, l) => n + l.garments.length);

  int get count => dirtyCount + inProgress.length + atCleaners.length;

  bool get isEmpty => count == 0;
}
