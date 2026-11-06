import 'dart:convert';

import '../../wear/domain/calendar_day.dart';
import 'garment.dart';

/// Peças iguais (ex.: três t-shirts brancas da mesma marca): continuam a
/// ser peças distintas, cada uma com o seu histórico e estado, mas
/// mostram-se juntas e, ao registar "Vesti hoje", basta escolher o grupo.
///
/// Iguais = mesma categoria, nome e marca (sem diferença de maiúsculas ou
/// espaços), mesmas cores, os mesmos detalhes e o mesmo arquivo. Sem nome
/// nem cores não há como saber: cada peça fica sozinha.
abstract final class GarmentTwins {
  static String? key(Garment g) {
    String? norm(String? s) {
      final t = s?.trim().toLowerCase();
      return t == null || t.isEmpty ? null : t;
    }

    final name = norm(g.name);
    if (name == null && g.colors.isEmpty) return null;
    return jsonEncode([
      g.category.id,
      name,
      norm(g.brand),
      [for (final c in g.colors) c.rgb],
      g.attributes.toColumns(),
      g.isArchived,
    ]);
  }

  /// Agrupa mantendo a ordem da primeira peça de cada grupo.
  static List<List<Garment>> group(Iterable<Garment> garments) {
    final groups = <String, List<Garment>>{};
    final out = <List<Garment>>[];
    for (final g in garments) {
      final k = key(g);
      if (k == null) {
        out.add([g]);
        continue;
      }
      final existing = groups[k];
      if (existing != null) {
        existing.add(g);
      } else {
        final list = [g];
        groups[k] = list;
        out.add(list);
      }
    }
    return out;
  }

  /// A unidade a usar quando se escolhe o grupo: disponível primeiro e,
  /// entre essas, a que está há mais tempo sem uso (nunca usada primeiro).
  /// Empates: a mais antiga.
  static Garment pick(
    List<Garment> units, {
    required Map<GarmentId, CalendarDay> lastWorn,
  }) {
    final sorted = [...units]
      ..sort((a, b) {
        final available = (b.isCandidate ? 1 : 0) - (a.isCandidate ? 1 : 0);
        if (available != 0) return available;
        final la = lastWorn[a.id];
        final lb = lastWorn[b.id];
        if (la != lb) {
          if (la == null) return -1;
          if (lb == null) return 1;
          return la.compareTo(lb);
        }
        return a.createdAt.compareTo(b.createdAt);
      });
    return sorted.first;
  }
}
