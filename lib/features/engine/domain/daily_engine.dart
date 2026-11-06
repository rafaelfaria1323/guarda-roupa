import '../../care/domain/laundry_policy.dart';
import '../../care/domain/rotation_policy.dart';
import '../../inspirations/domain/style_preference.dart';
import '../../outfits/domain/outfit.dart';
import '../../wardrobe/domain/garment.dart';
import '../../wardrobe/domain/garment_attributes.dart';
import '../../wardrobe/domain/garment_category.dart';
import 'comfort.dart';
import 'outfit_harmony.dart';
import 'suggestion.dart';

/// Motor diário (docs/features/motor-de-combinacoes.md): regras
/// obrigatórias primeiro, depois uma ordem explícita, sem pesos inventados.
///
/// - **Obrigatório:** só peças candidatas (não arquivadas e disponíveis);
///   uma peça não se repete; uma peça com ocasiões indicadas que não
///   incluem a pedida fica de fora (sem ocasiões = desconhecido, entra com
///   nota).
/// - **Modelos:** top + parte de baixo + calçado, ou peça única + calçado.
///   Uma t-shirt chega como top único; camadas só quando o conforto as pede
///   (frio com peça leve/média) ou como sugestão opcional.
/// - **Ordem de cada papel:** conforto, chuva/vento (casaco e calçado),
///   rotatividade (elegíveis primeiro, P-06), preferências (gosto − evito),
///   menos usadas, usadas há mais tempo, seed.
/// - **Conjunto:** combinações de cor preferidas/evitadas (P-21) somam às
///   preferências; padrões ou texturas fortes repetidos só desempatam
///   ([OutfitHarmony]).
/// - **Lavagem** (P-07) só gera aviso.
abstract final class DailyEngine {
  static SuggestionResult suggest(
    WardrobeSnapshot snapshot,
    SuggestionRequest request,
  ) {
    final ctx = _Context(snapshot, request);

    final tops = ctx.pool(_Slot.top);
    final bottoms = ctx.pool(_Slot.bottom);
    final onePieces = ctx.pool(_Slot.onePiece);
    final footwear = ctx.pool(_Slot.footwear);
    final outer = ctx.pool(_Slot.outer);
    ctx.outerAvailable = outer.ranked.isNotEmpty;
    for (final p in [tops, bottoms, onePieces, footwear, outer]) {
      ctx.rank(p);
    }

    final drafts = <_Draft>[];
    final seen = <String>{};
    void add(_Draft d) {
      if (seen.add(d.key)) drafts.add(d);
    }

    final max = request.maxResults;
    // Conjuntos guardados para esta ocasião, primeiro (um igual gerado a
    // seguir já não entra). As peças têm de servir hoje (disponíveis e da
    // ocasião); se só uma não serve, entra outra no lugar dela. O casaco
    // decide-o o tempo, como nos outros; camadas intermédias e acessórios
    // o motor ainda não põe.
    final pools = {
      _Slot.top: tops,
      _Slot.bottom: bottoms,
      _Slot.onePiece: onePieces,
      _Slot.footwear: footwear,
      _Slot.outer: outer,
    };
    for (final o in ctx.outfits) {
      final own = {for (final i in o.items) i.garmentId};
      final mains = <(_Entry, OutfitRole)>[];
      final removed = <OutfitRole, GarmentId>{};
      _Pool? ownFootwear;
      _Pool? ownOuter;
      for (final item in o.items) {
        final slot = _slotOf(item.role);
        if (slot == null) continue;
        final pool = pools[slot]!;
        final entry = pool.ranked
            .where((e) => e.garment.id == item.garmentId)
            .firstOrNull;
        switch (slot) {
          case _Slot.outer:
            if (entry != null) ownOuter = _Pool(slot, pool.cause, [entry]);
          case _Slot.footwear:
            if (entry != null) {
              ownFootwear = _Pool(slot, pool.cause, [entry]);
            } else {
              removed[item.role] = item.garmentId;
            }
          case _Slot.top || _Slot.bottom || _Slot.onePiece:
            if (entry != null) {
              mains.add((entry, item.role));
              continue;
            }
            removed[item.role] = item.garmentId;
            final other = _best([
              for (final e in pool.ranked)
                if (!own.contains(e.garment.id)) e,
            ]);
            if (other != null) mains.add((other, item.role));
        }
      }
      final roles = [for (final (_, r) in mains) r];
      final shape =
          (roles.length == 2 &&
              roles.contains(OutfitRole.mainTop) &&
              roles.contains(OutfitRole.bottom)) ||
          (roles.length == 1 && roles.single == OutfitRole.onePiece);
      if (removed.length > 1 || !shape) continue;
      if (removed.containsKey(OutfitRole.footwear) && footwear.ranked.isEmpty) {
        continue;
      }
      // A parte de cima primeiro: é ela que decide o casaco.
      mains.sort(
        (a, b) => _Context._layer(a.$2).compareTo(_Context._layer(b.$2)),
      );
      add(
        ctx.compose(
          0,
          mains,
          footwear: ownFootwear ?? footwear,
          outer: ownOuter ?? outer,
          variant: removed.isEmpty ? null : (o, removed),
        ),
      );
    }

    final separatesOk = tops.ranked.isNotEmpty && bottoms.ranked.isNotEmpty;
    if (separatesOk) {
      final n = _min(max, _max(tops.ranked.length, bottoms.ranked.length));
      for (var i = 0; i < n; i++) {
        add(
          ctx.compose(
            i,
            [
              (tops.at(i), OutfitRole.mainTop),
              (bottoms.at(i), OutfitRole.bottom),
            ],
            footwear: footwear,
            outer: outer,
          ),
        );
      }
    }
    final onePieceOk = onePieces.ranked.isNotEmpty;
    if (onePieceOk) {
      final n = _min(max, onePieces.ranked.length);
      for (var i = 0; i < n; i++) {
        add(
          ctx.compose(
            i,
            [(onePieces.at(i), OutfitRole.onePiece)],
            footwear: footwear,
            outer: outer,
          ),
        );
      }
    }

    drafts.sort(_Draft.compare);
    final candidates = [for (final d in drafts.take(max)) d.candidate];

    final gaps = <RoleGap>[
      // Os papéis principais só faltam se nenhum modelo resultou.
      if (!separatesOk && !onePieceOk) ...[
        if (tops.ranked.isEmpty) RoleGap(OutfitRole.mainTop, tops.cause),
        if (bottoms.ranked.isEmpty) RoleGap(OutfitRole.bottom, bottoms.cause),
        RoleGap(OutfitRole.onePiece, onePieces.cause),
      ],
      if (footwear.ranked.isEmpty) RoleGap(OutfitRole.footwear, footwear.cause),
      if (outer.ranked.isEmpty &&
          candidates.any(
            (c) => c.notes.any(
              (n) => n is MissingRole && n.role == OutfitRole.outerLayer,
            ),
          ))
        RoleGap(OutfitRole.outerLayer, outer.cause),
    ];

    final SuggestionStatus status;
    if (candidates.any((c) => c.isComplete)) {
      status = SuggestionStatus.valid;
    } else if (candidates.isNotEmpty) {
      status = SuggestionStatus.partial;
    } else {
      final noneOwned =
          (tops.cause == GapCause.none || bottoms.cause == GapCause.none) &&
          onePieces.cause == GapCause.none;
      status = noneOwned
          ? SuggestionStatus.insufficientData
          : SuggestionStatus.notFound;
    }

    return SuggestionResult(
      status: status,
      candidates: candidates,
      gaps: gaps,
      notes: [if (request.weather == null) const NoWeather()],
    );
  }

  /// Avalia peças já escolhidas (um dia planeado) com as regras do dia:
  /// as mesmas notas que uma sugestão teria. `null` para uma peça que já
  /// não existe.
  static List<SuggestedItem?> assess(
    WardrobeSnapshot snapshot,
    SuggestionRequest request,
    List<OutfitItem> items,
  ) {
    final ctx = _Context(snapshot, request);
    final byId = {for (final g in snapshot.garments) g.id: g};
    return [
      for (final i in items)
        if (byId[i.garmentId] case final g?)
          SuggestedItem(g, i.role, ctx._entry(g, _slotOf(i.role)).notes)
        else
          null,
    ];
  }

  /// Troca só as peças em [replace], mantendo as restantes (escolhas do
  /// utilizador). Cada substituta é a primeira do seu papel na ordem do
  /// motor que ainda não está no conjunto, de preferência sem avisos. Sem substituta, ou numa camada
  /// intermédia/acessório, a peça sai e o papel fica em [Replacement.dropped].
  /// [add]: papéis a juntar (ex.: casaco que o frio passou a pedir).
  static Replacement replace(
    WardrobeSnapshot snapshot,
    SuggestionRequest request,
    List<OutfitItem> items, {
    required Set<GarmentId> replace,
    Set<OutfitRole> add = const {},
  }) {
    final ctx = _Context(snapshot, request);
    final pools = {for (final s in _Slot.values) s: ctx.pool(s)};
    ctx.outerAvailable = pools[_Slot.outer]!.ranked.isNotEmpty;
    for (final p in pools.values) {
      ctx.rank(p);
    }
    final taken = {
      for (final i in items)
        if (!replace.contains(i.garmentId)) i.garmentId,
    };
    final out = <OutfitItem>[];
    final added = <OutfitItem>[];
    final dropped = <OutfitRole>[];
    for (final i in items) {
      if (!replace.contains(i.garmentId)) {
        out.add(i);
        continue;
      }
      final slot = _slotOf(i.role);
      final options = slot == null
          ? const <_Entry>[]
          : [
              for (final e in pools[slot]!.ranked)
                if (!taken.contains(e.garment.id) &&
                    e.garment.id != i.garmentId)
                  e,
            ];
      final pick = _best(options);
      if (pick == null) {
        dropped.add(i.role);
        continue;
      }
      taken.add(pick.garment.id);
      final item = OutfitItem(pick.garment.id, i.role);
      out.add(item);
      added.add(item);
    }
    for (final role in add) {
      final slot = _slotOf(role);
      final pick = slot == null
          ? null
          : _best([
              for (final e in pools[slot]!.ranked)
                if (!taken.contains(e.garment.id)) e,
            ]);
      if (pick == null) {
        dropped.add(role);
        continue;
      }
      taken.add(pick.garment.id);
      final item = OutfitItem(pick.garment.id, role);
      out.add(item);
      added.add(item);
    }
    out.sort(
      (a, b) => _Context._layer(a.role).compareTo(_Context._layer(b.role)),
    );
    return Replacement(items: out, added: added, dropped: dropped);
  }

  /// A primeira sem avisos (lavar recomendado não entra na ordem), senão a
  /// primeira.
  static _Entry? _best(List<_Entry> ranked) =>
      ranked.where((e) => !e.notes.any(SuggestedItem.isWarning)).firstOrNull ??
      ranked.firstOrNull;

  static _Slot? _slotOf(OutfitRole role) => switch (role) {
    OutfitRole.mainTop => _Slot.top,
    OutfitRole.bottom => _Slot.bottom,
    OutfitRole.onePiece => _Slot.onePiece,
    OutfitRole.footwear => _Slot.footwear,
    OutfitRole.outerLayer => _Slot.outer,
    OutfitRole.midLayer || OutfitRole.accessory => null,
  };

  static int _min(int a, int b) => a < b ? a : b;
  static int _max(int a, int b) => a > b ? a : b;
}

enum _Slot { top, bottom, onePiece, footwear, outer }

extension on _Slot {
  CategoryGroup get group => switch (this) {
    _Slot.top => CategoryGroup.top,
    _Slot.bottom => CategoryGroup.bottom,
    _Slot.onePiece => CategoryGroup.onePiece,
    _Slot.footwear => CategoryGroup.footwear,
    _Slot.outer => CategoryGroup.outerwear,
  };

  /// O casaco cobre o tronco: só estes pedem camada no frio.
  bool get upperBody => this == _Slot.top || this == _Slot.onePiece;

  bool get exposed => this == _Slot.outer || this == _Slot.footwear;
}

final class _Entry {
  _Entry(this.garment, this.notes, this.order);

  final Garment garment;
  final List<SuggestionNote> notes;

  /// Chave lexicográfica (menor = melhor).
  final List<Comparable<dynamic>> order;
  ComfortFit? fit;
  int position = 0;

  int get preference => notes.whereType<PreferenceMatch>().fold(
    0,
    (sum, m) => sum + (m.preference.stance == PreferenceStance.like ? 1 : -1),
  );
}

final class _Pool {
  _Pool(this.slot, this.cause, this.ranked);

  final _Slot slot;
  final GapCause cause;
  final List<_Entry> ranked;

  _Entry at(int i) => ranked[i % ranked.length];
}

final class _Context {
  _Context(this.snapshot, this.request)
    : band = request.weather == null
          ? null
          : request.comfort.bandFor(request.weather!),
      rotation = RotationPolicy.evaluate(
        garments: snapshot.garments,
        wears: snapshot.wears,
        policies: snapshot.policies,
        today: request.day,
      ),
      laundry = LaundryPolicy.evaluate(
        garments: snapshot.garments,
        wears: snapshot.wears,
        cleanings: snapshot.cleanings,
        policies: snapshot.policies,
      ),
      preferences = [
        for (final p in snapshot.preferences)
          if (p.occasions.isEmpty ||
              (request.occasion != null &&
                  p.occasions.contains(request.occasion)))
            p,
      ],
      outfits = [
        for (final o in snapshot.outfits)
          if (o.occasions.isEmpty ||
              request.occasion == null ||
              o.occasions.contains(request.occasion))
            o,
      ];

  final WardrobeSnapshot snapshot;
  final SuggestionRequest request;
  final ComfortBand? band;
  final Map<GarmentId, RotationState> rotation;
  final Map<GarmentId, LaundryState> laundry;
  final List<StylePreference> preferences;

  /// Conjuntos guardados que servem para a ocasião pedida.
  final List<Outfit> outfits;
  bool outerAvailable = false;

  bool get rain => request.weather?.rain ?? false;
  bool get windy =>
      request.weather != null && request.comfort.isWindy(request.weather!);

  _Pool pool(_Slot slot) {
    final owned = [
      for (final g in snapshot.garments)
        if (g.category.group == slot.group) g,
    ];
    final usable = owned.where((g) => g.isCandidate).toList();
    final occasion = request.occasion;
    final fitting = [
      for (final g in usable)
        if (occasion == null ||
            g.attributes.occasions.isEmpty ||
            g.attributes.occasions.contains(occasion))
          g,
    ];
    final cause = owned.isEmpty
        ? GapCause.none
        : usable.isEmpty
        ? GapCause.unavailable
        : GapCause.otherOccasions;
    return _Pool(slot, cause, [for (final g in fitting) _entry(g, slot)]);
  }

  /// Ordena depois de se saber se há casacos (o frio depende disso).
  void rank(_Pool pool) {
    for (final e in pool.ranked) {
      if (e.fit case final fit?) e.order[0] = _comfortTier(fit);
    }
    pool.ranked.sort((a, b) {
      for (var i = 0; i < a.order.length; i++) {
        final c = a.order[i].compareTo(b.order[i]);
        if (c != 0) return c;
      }
      return 0;
    });
    for (var i = 0; i < pool.ranked.length; i++) {
      pool.ranked[i].position = i;
    }
  }

  int _comfortTier(ComfortFit fit) => switch (fit) {
    ComfortFit.fits => 0,
    ComfortFit.fitsWithOuterLayer => outerAvailable ? 1 : 3,
    ComfortFit.unknown => 2,
    ComfortFit.mismatch => 3,
  };

  /// [slot] `null`: camada intermédia ou acessório (sem regras de conforto
  /// nem de chuva).
  _Entry _entry(Garment g, _Slot? slot) {
    final notes = <SuggestionNote>[];

    if (request.occasion case final o?) {
      notes.add(
        g.attributes.occasions.isEmpty
            ? const OccasionUnknown()
            : OccasionMatches(o),
      );
    }

    ComfortFit? fit;
    if (band case final b?
        when slot != null && slot != _Slot.footwear && slot != _Slot.outer) {
      fit = _fitOf(g.attributes.warmth, b, upperBody: slot.upperBody);
      notes.add(ComfortNote(fit, b, g.attributes.warmth));
    }

    var weatherTier = 0;
    if ((slot?.exposed ?? false) && (rain || windy)) {
      final flags = [
        if (rain) (true, g.attributes.rainOk),
        if (windy) (false, g.attributes.windOk),
      ];
      for (final (isRain, ok) in flags) {
        notes.add(WeatherFlagNote(rain: isRain, ok: ok));
      }
      final oks = flags.map((f) => f.$2);
      weatherTier = oks.any((ok) => ok == false)
          ? 2
          : oks.every((ok) => ok == true)
          ? 0
          : 1;
    }

    final state = rotation[g.id]!;
    final last = state.lastWornOn;
    if (state.eligibleFrom case final from?) {
      notes.add(RotationExceeded(lastWornOn: last!, eligibleFrom: from));
    } else if (last == null) {
      notes.add(const NeverWorn());
    } else if (state.recentUses > 0) {
      notes.add(RecentUses(state.recentUses, last));
    }

    var preference = 0;
    for (final p in preferences) {
      if (!_matches(p, g)) continue;
      notes.add(PreferenceMatch(p));
      preference += p.stance == PreferenceStance.like ? 1 : -1;
    }

    final wash = laundry[g.id]!;
    if (wash.washRecommended) {
      notes.add(WashRecommended(wash.usesSinceCleaning, wash.threshold));
    }

    return _Entry(g, notes, [
      0, // conforto, preenchido em rank()
      weatherTier,
      state.isEligible ? 0 : 1,
      -preference,
      state.recentUses,
      // Nunca usadas primeiro; depois as usadas há mais tempo.
      last == null ? '' : last.iso,
      _seedKey(request.seed, g.id.value),
      g.id.value,
    ])..fit = fit;
  }

  static ComfortFit _fitOf(
    Warmth? warmth,
    ComfortBand band, {
    required bool upperBody,
  }) {
    if (upperBody) return ComfortRules.fitOf(warmth, band);
    // Partes de baixo: o casaco não as cobre; só os extremos não servem.
    if (warmth == null) return ComfortFit.unknown;
    return switch ((band, warmth)) {
      (ComfortBand.hot, Warmth.warm) => ComfortFit.mismatch,
      (ComfortBand.cold, Warmth.light) => ComfortFit.mismatch,
      _ => ComfortFit.fits,
    };
  }

  /// Cor, padrão e textura aplicam-se a cada peça. As combinações de cor
  /// são do conjunto ([compose]); a formalidade ainda não entra.
  static bool _matches(StylePreference p, Garment g) => switch (p.subject) {
    PreferenceSubject.color => g.colors.any((c) => '${c.rgb}' == p.value),
    PreferenceSubject.pattern => g.attributes.pattern?.id == p.value,
    PreferenceSubject.texture => g.attributes.texture?.id == p.value,
    PreferenceSubject.formality || PreferenceSubject.combo => false,
  };

  /// [variant]: um conjunto guardado com peças trocadas (papel → a peça
  /// dele que não serve hoje).
  _Draft compose(
    int i,
    List<(_Entry, OutfitRole)> mains, {
    required _Pool footwear,
    required _Pool outer,
    (Outfit, Map<OutfitRole, GarmentId>)? variant,
  }) {
    final items = <(_Entry, OutfitRole)>[...mains];
    final notes = <SuggestionNote>[];

    final upper = mains.first.$1;
    final needsOuter = upper.fit == ComfortFit.fitsWithOuterLayer;
    _Entry? optional;
    if (needsOuter) {
      if (outer.ranked.isEmpty) {
        notes.add(const MissingRole(OutfitRole.outerLayer));
      } else {
        items.add((outer.at(i), OutfitRole.outerLayer));
      }
    } else if (outer.ranked.isNotEmpty) {
      final best = outer.at(i);
      final shelter =
          (rain && best.garment.attributes.rainOk == true) ||
          (windy && best.garment.attributes.windOk == true);
      if (band == ComfortBand.mild || shelter) optional = best;
    }

    if (footwear.ranked.isEmpty) {
      notes.add(const MissingRole(OutfitRole.footwear));
    } else {
      items.add((footwear.at(i), OutfitRole.footwear));
    }

    items.sort((a, b) => _layer(a.$2).compareTo(_layer(b.$2)));

    final combos = OutfitHarmony.combos([
      for (final (e, role) in items) (e.garment, role),
    ]);
    var comboPreference = 0;
    final matched = <StyleCombo>{};
    if (combos != null) {
      for (final p in preferences) {
        if (p.subject != PreferenceSubject.combo) continue;
        final combo = StyleCombo.fromId(p.value);
        if (combo == null || !combos.contains(combo)) continue;
        matched.add(combo);
        notes.add(PreferenceMatch(p));
        comboPreference += p.stance == PreferenceStance.like ? 1 : -1;
      }
      final described = combos.difference(matched);
      if (described.isNotEmpty) notes.add(ColorCombosNote(described));
    }
    final surface = OutfitHarmony.surface([
      for (final (e, _) in items) e.garment,
    ]);
    final load = OutfitHarmony.load(surface);
    if (load > 0) {
      notes.add(
        SurfaceMixNote(
          patterned: surface.patterned,
          textured: surface.textured,
        ),
      );
    }

    // É um conjunto guardado: todas as peças dele estão aqui (o casaco
    // não conta, depende do tempo).
    final ids = {for (final (e, _) in items) e.garment.id};
    final saved = outfits.where((o) {
      final needed = [
        for (final i in o.items)
          if (DailyEngine._slotOf(i.role) case final s? when s != _Slot.outer)
            i.garmentId,
      ];
      return needed.isNotEmpty && needed.every(ids.contains);
    }).firstOrNull;
    SavedOutfitNote? savedNote = saved == null ? null : SavedOutfitNote(saved);
    if (savedNote == null && variant != null) {
      final (outfit, removed) = variant;
      final byId = {for (final g in snapshot.garments) g.id: g};
      savedNote = SavedOutfitNote(
        outfit,
        swaps: [
          for (final MapEntry(key: role, value: id) in removed.entries)
            for (final (e, r) in items)
              if (r == role) OutfitSwap(role, byId[id], e.garment),
        ],
      );
    }
    if (savedNote != null) notes.add(savedNote);

    final suggested = [
      for (final (e, role) in items) SuggestedItem(e.garment, role, e.notes),
    ];
    return _Draft(
      OutfitCandidate(
        items: suggested,
        optionalLayer: optional == null
            ? null
            : SuggestedItem(optional.garment, OutfitRole.outerLayer, [
                const OptionalLayerNote(),
                ...optional.notes,
              ]),
        notes: notes,
      ),
      entries: [for (final (e, _) in items) e],
      seed: request.seed,
      comboPreference: comboPreference + (savedNote == null ? 0 : 1),
      load: load,
    );
  }

  static int _layer(OutfitRole r) => switch (r) {
    OutfitRole.mainTop || OutfitRole.onePiece => 0,
    OutfitRole.midLayer => 1,
    OutfitRole.outerLayer => 2,
    OutfitRole.bottom => 3,
    OutfitRole.footwear => 4,
    OutfitRole.accessory => 5,
  };
}

final class _Draft {
  _Draft(
    this.candidate, {
    required List<_Entry> entries,
    required int seed,
    required int comboPreference,
    required this.load,
  }) : key = (entries.map((e) => e.garment.id.value).toList()..sort()).join(
         ',',
       ),
       missing = candidate.notes.whereType<MissingRole>().length,
       warnings = candidate.items.fold(0, (sum, i) => sum + i.warnings.length),
       preference =
           entries.fold(0, (sum, e) => sum + e.preference) + comboPreference,
       positions = entries.fold(0, (sum, e) => sum + e.position) {
    tiebreak = _seedKey(seed, key);
  }

  final OutfitCandidate candidate;

  /// Peças do conjunto, para não repetir o mesmo conjunto.
  final String key;
  final int missing;
  final int warnings;
  final int preference;

  /// Padrões e texturas fortes a competir ([OutfitHarmony.load]).
  final int load;

  /// Soma das posições de cada peça na ordem do seu papel.
  final int positions;
  late final int tiebreak;

  /// Completos primeiro, menos avisos, mais preferências (das peças e do
  /// conjunto), menos padrões/texturas a competir, peças mais bem
  /// ordenadas, seed.
  static int compare(_Draft a, _Draft b) {
    var c = a.missing.compareTo(b.missing);
    if (c != 0) return c;
    c = a.warnings.compareTo(b.warnings);
    if (c != 0) return c;
    c = b.preference.compareTo(a.preference);
    if (c != 0) return c;
    c = a.load.compareTo(b.load);
    if (c != 0) return c;
    c = a.positions.compareTo(b.positions);
    if (c != 0) return c;
    c = a.tiebreak.compareTo(b.tiebreak);
    if (c != 0) return c;
    return a.key.compareTo(b.key);
  }
}

/// FNV-1a de 32 bits: igual em todas as plataformas (ao contrário de
/// `hashCode`), para que a mesma seed dê o mesmo resultado na Web e no
/// Android.
int _seedKey(int seed, String text) {
  var h = 0x811c9dc5;
  for (final unit in '$seed|$text'.codeUnits) {
    h ^= unit;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h;
}
