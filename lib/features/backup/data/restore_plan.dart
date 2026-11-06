import '../../care/domain/care_policies.dart';
import '../../outfits/domain/outfit.dart';
import '../../wardrobe/domain/garment.dart';
import '../../care/domain/cleaning_event.dart';
import '../../wear/domain/wear_event.dart';
import '../domain/backup.dart';

/// Tabelas e coluna que marca uma linha como apagada ou desfeita. Uma linha
/// assim sai do stream e só o servidor (ou este dispositivo, antes de a
/// enviar) sabe que existiu.
enum RemovableTable {
  garments('garments', 'deleted_at'),
  wears('wear_events', 'voided_at'),
  cleanings('cleaning_events', 'voided_at'),
  outfits('outfits', 'deleted_at'),
  inspirations('inspirations', 'deleted_at'),
  preferences('style_preferences', 'deleted_at');

  const RemovableTable(this.table, this.column);
  final String table;
  final String column;
}

/// Ids do backup que esta conta conhece mas já apagou ou desfez.
typedef RemovedIds = Map<RemovableTable, Set<String>>;

/// O que a conta tem agora (só o que está ativo), para comparar.
final class AccountState {
  const AccountState({
    this.garments = const [],
    this.wears = const [],
    this.cleanings = const [],
    this.outfits = const [],
    this.policies = const {},
    this.inspirationIds = const {},
    this.preferenceIds = const {},
  });

  /// Só o que serve para reconhecer uma peça: id, categoria, nome e data
  /// de criação (que a recuperação mantém mesmo com id novo).
  final List<Garment> garments;
  final List<WearEvent> wears;
  final List<CleaningEvent> cleanings;
  final List<Outfit> outfits;

  /// (âmbito, alvo) com valor escolhido.
  final Set<(PolicyScope, String)> policies;
  final Set<String> inspirationIds;
  final Set<String> preferenceIds;
}

/// Juntar um backup a uma conta (P-11, decisão de 2026-11-06): só se
/// acrescenta o que falta; o que a conta já tem fica como está; o que foi
/// apagado ou desfeito depois do backup não volta, salvo as peças, se o
/// utilizador as escolher ([restoreRemoved]). Utilizações, limpezas e
/// conjuntos não se duplicam: o mesmo id, ou o mesmo conteúdo com as
/// mesmas peças, conta como já lá estar.
final class RestorePlan {
  const RestorePlan._({
    required this.newGarments,
    required this.present,
    required this.removedGarments,
    required this.history,
    required this.knownInspirations,
  });

  factory RestorePlan.build(
    BackupContents contents,
    AccountState account,
    RemovedIds removed, {
    required bool restoreRemoved,
  }) {
    Set<String> gone(RemovableTable t) => removed[t] ?? const {};

    // Peças: o mesmo id, ou a mesma peça recuperada antes com id novo.
    final active = {for (final g in account.garments) g.id: g};
    final unmatched = [...account.garments];
    final present = <GarmentId, GarmentId>{};
    final created = <Garment>[];
    final removedGarments = <Garment>[];
    for (final g in contents.garments) {
      if (active.containsKey(g.id)) {
        present[g.id] = g.id;
        unmatched.removeWhere((a) => a.id == g.id);
        continue;
      }
      final twin = unmatched.indexWhere(
        (a) =>
            a.createdAt.isAtSameMomentAs(g.createdAt) &&
            a.category == g.category &&
            a.name == g.name,
      );
      if (twin >= 0) {
        present[g.id] = unmatched.removeAt(twin).id;
        continue;
      }
      if (gone(RemovableTable.garments).contains(g.id.value)) {
        removedGarments.add(g);
        if (!restoreRemoved) continue;
      }
      created.add(g);
    }
    final kept = {...present.keys, for (final g in created) g.id};

    /// Id na conta, só para peças que já lá estavam (as novas não têm
    /// nada para comparar).
    GarmentId? inAccount(GarmentId g) => present[g];

    final history = contents.history;
    bool known(RemovableTable t, String id, Iterable<String> ids) =>
        gone(t).contains(id) || ids.contains(id);

    final wearIds = {for (final w in account.wears) w.id};
    final wears = <WearEvent>[];
    for (final w in history.wears) {
      if (known(RemovableTable.wears, w.id, wearIds)) continue;
      final ids = [
        for (final g in w.garmentIds)
          if (kept.contains(g)) g,
      ];
      if (ids.isEmpty) continue;
      final mapped = {for (final g in ids) inAccount(g)};
      if (!mapped.contains(null) &&
          account.wears.any(
            (a) =>
                a.wornOn == w.wornOn &&
                a.garmentIds.toSet().length == mapped.length &&
                a.garmentIds.toSet().containsAll(mapped),
          )) {
        continue;
      }
      wears.add(
        WearEvent(
          id: w.id,
          wornOn: w.wornOn,
          garmentIds: ids,
          createdAt: w.createdAt,
        ),
      );
    }

    final cleaningIds = {for (final c in account.cleanings) c.id};
    final cleanings = [
      for (final c in history.cleanings)
        if (!known(RemovableTable.cleanings, c.id, cleaningIds) &&
            kept.contains(c.garmentId) &&
            !account.cleanings.any(
              (a) =>
                  a.garmentId == inAccount(c.garmentId) &&
                  a.cleanedOn == c.cleanedOn,
            ))
          c,
    ];

    final policies = [
      for (final p in history.policies)
        if (switch (p.scope) {
          PolicyScope.category => !account.policies.contains((
            p.scope,
            p.target,
          )),
          PolicyScope.garment =>
            kept.contains(GarmentId(p.target)) &&
                !account.policies.contains((
                  p.scope,
                  inAccount(GarmentId(p.target))?.value,
                )),
        })
          p,
    ];

    final outfitIds = {for (final o in account.outfits) o.id};
    final outfits = <Outfit>[];
    for (final o in history.outfits) {
      if (known(RemovableTable.outfits, o.id, outfitIds)) continue;
      final items = [
        for (final i in o.items)
          if (kept.contains(i.garmentId)) i,
      ];
      if (items.isEmpty) continue;
      final mapped = {
        for (final i in items)
          if (inAccount(i.garmentId) case final g?) OutfitItem(g, i.role),
      };
      if (mapped.length == items.length &&
          account.outfits.any(
            (a) =>
                a.items.toSet().length == mapped.length &&
                a.items.toSet().containsAll(mapped),
          )) {
        continue;
      }
      outfits.add(
        Outfit(
          id: o.id,
          name: o.name,
          occasions: o.occasions,
          items: items,
          createdAt: o.createdAt,
          updatedAt: o.updatedAt,
        ),
      );
    }

    // Inspirações e preferências: o mesmo id já na conta fica como está
    // (mesmo que tenha sido editado); o conteúdo igual também não se
    // repete (HistoryImport).
    final knownInspirations = <String, String>{
      for (final i in history.inspirations)
        if (account.inspirationIds.contains(i.id)) i.id: i.id,
    };
    final inspirations = [
      for (final i in history.inspirations)
        if (!known(RemovableTable.inspirations, i.id, account.inspirationIds))
          i,
    ];
    final preferences = [
      for (final p in history.preferences)
        if (!known(RemovableTable.preferences, p.id, account.preferenceIds)) p,
    ];

    return RestorePlan._(
      newGarments: created,
      present: present,
      removedGarments: removedGarments,
      history: BackupHistory(
        wears: wears,
        cleanings: cleanings,
        policies: policies,
        outfits: outfits,
        inspirations: inspirations,
        preferences: preferences,
      ),
      knownInspirations: knownInspirations,
    );
  }

  /// Peças a criar (ids novos), incluindo as apagadas, se escolhidas.
  final List<Garment> newGarments;

  /// Peça do backup → a mesma peça na conta, que fica como está.
  final Map<GarmentId, GarmentId> present;

  /// Peças do backup apagadas nesta conta depois do backup.
  final List<Garment> removedGarments;

  /// O que falta acrescentar, ainda com os ids das peças do backup.
  final BackupHistory history;

  /// Inspiração do backup → a mesma na conta.
  final Map<String, String> knownInspirations;

  int get photos => newGarments.fold(0, (n, g) => n + g.photos.length);

  bool get nothingToAdd =>
      newGarments.isEmpty &&
      history.wears.isEmpty &&
      history.cleanings.isEmpty &&
      history.policies.isEmpty &&
      history.outfits.isEmpty &&
      history.inspirations.isEmpty &&
      history.preferences.isEmpty;
}
