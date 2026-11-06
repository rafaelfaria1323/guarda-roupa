import '../../../core/domain/result.dart';
import '../../engine/domain/daily_engine.dart';
import '../../engine/domain/suggestion.dart';
import '../../inspirations/domain/style_preference.dart';
import '../../outfits/domain/outfit.dart';
import '../../photo_ai/domain/photo_reader.dart';
import '../../wardrobe/domain/garment.dart';
import '../../wardrobe/domain/garment_attributes.dart';
import '../../wardrobe/domain/garment_category.dart';
import '../../wardrobe/domain/reference_color.dart';
import '../../wear/domain/calendar_day.dart';

/// "Pedir ao stylist" (docs/features/ia-gemini.md): o Gemini escolhe um
/// conjunto entre as peças disponíveis, só pelo texto delas.
abstract interface class Stylist {
  Future<Result<StylistReply, PhotoReadFailure>> suggest(
    Map<String, Object?> brief,
  );
}

/// Resposta do servidor, ainda com os ids curtos ("p1", "p2", …).
final class StylistReply {
  const StylistReply({required this.items, this.name, this.why});

  factory StylistReply.fromJson(Map<String, Object?> json) => StylistReply(
    name: json['name'] is String ? json['name']! as String : null,
    why: json['why'] is String ? json['why']! as String : null,
    items: [
      for (final i in json['items'] is List ? json['items']! as List : [])
        if (i case {'id': final String id, 'role': final String role})
          (id, role),
    ],
  );

  final List<(String id, String role)> items;
  final String? name;
  final String? why;
}

/// O que se manda: só peças candidatas (não arquivadas e disponíveis), em
/// texto, com ids curtos. Nunca fotos, marcas nem notas.
final class StylistBrief {
  StylistBrief._(this.json, this.ids);

  /// Até [maxGarments] peças: as menos usadas primeiro, se houver mais.
  factory StylistBrief.build(
    WardrobeSnapshot snapshot,
    SuggestionRequest request, {
    String? ask,
    List<GarmentId> previous = const [],
  }) {
    final day = request.day;
    final last = <GarmentId, CalendarDay>{};
    final recent = <GarmentId, int>{};
    for (final w in snapshot.wears) {
      final ago = w.wornOn.daysUntil(day);
      if (ago < 0) continue;
      for (final id in w.garmentIds) {
        if (last[id] == null || last[id]!.compareTo(w.wornOn) < 0) {
          last[id] = w.wornOn;
        }
        if (ago < 30) recent[id] = (recent[id] ?? 0) + 1;
      }
    }
    final garments = [
      for (final g in snapshot.garments)
        if (g.isCandidate) g,
    ]..sort((a, b) => (recent[a.id] ?? 0).compareTo(recent[b.id] ?? 0));
    final chosen = garments.take(maxGarments).toList();
    final ids = <String, GarmentId>{};
    final back = <GarmentId, String>{};
    for (final (i, g) in chosen.indexed) {
      ids['p${i + 1}'] = g.id;
      back[g.id] = 'p${i + 1}';
    }
    GarmentAttributes a(Garment g) => g.attributes;
    final weather = request.weather;
    String pref(StylePreference p) => switch (p.subject) {
      PreferenceSubject.color => 'color ${_color(int.tryParse(p.value) ?? 0)}',
      _ => '${p.subject.id} ${p.value}',
    };
    return StylistBrief._({
      'occasion': request.occasion?.id,
      'weather': weather == null
          ? null
          : {
              'feels_like_c': weather.feelsLikeC.round(),
              'rain': weather.rain,
              'wind_kmh': weather.windKmh.round(),
              'sunny': weather.sunny,
            },
      'likes': [
        for (final p in snapshot.preferences)
          if (p.stance == PreferenceStance.like) pref(p),
      ],
      'avoids': [
        for (final p in snapshot.preferences)
          if (p.stance == PreferenceStance.avoid) pref(p),
      ],
      'previous': [for (final id in previous) ?back[id]],
      'ask': (ask == null || ask.trim().isEmpty) ? null : ask.trim(),
      'garments': [
        for (final g in chosen)
          {
            'id': back[g.id],
            'category': g.category.id,
            'name': ?g.name,
            'colors': [for (final c in g.colors.take(3)) _color(c.rgb)],
            'pattern': ?a(g).pattern?.id,
            'texture': ?a(g).texture?.id,
            'warmth': ?a(g).warmth?.id,
            'formality': ?a(g).formality?.id,
            'fit': ?a(g).fit?.id,
            'length': ?a(g).length?.id,
            'rain_ok': ?a(g).rainOk,
            'wind_ok': ?a(g).windOk,
            'occasions': [for (final o in a(g).occasions) o.id],
            'wears_30d': recent[g.id] ?? 0,
            'last_worn_days': switch (last[g.id]) {
              final d? => d.daysUntil(day),
              null => null,
            },
          },
      ],
    }, ids);
  }

  /// O servidor aceita até 200.
  static const maxGarments = 150;

  final Map<String, Object?> json;

  /// Id curto → peça.
  final Map<String, GarmentId> ids;

  /// Peças suficientes para pedir (o servidor quer pelo menos duas).
  bool get isEnough => ids.length >= 2;

  static String _color(int rgb) =>
      ReferenceColor.fromRgb(rgb)?.id ??
      '#${rgb.toRadixString(16).padLeft(6, '0')}';
}

/// A resposta, verificada pela app.
final class StylistPick {
  const StylistPick(this.candidate, {this.name, this.why});

  final OutfitCandidate candidate;
  final String? name;
  final String? why;
}

/// Volta a verificar o que o Gemini escolheu: só peças mandadas, cada uma
/// num papel que a categoria permite, sem repetir papéis únicos, e um
/// conjunto com parte de cima e de baixo (ou peça única). As notas são as
/// do motor para hoje ([DailyEngine.assess]). `null` = não serve.
StylistPick? reviewStylistReply(
  StylistReply reply,
  StylistBrief brief,
  WardrobeSnapshot snapshot,
  SuggestionRequest request,
) {
  final byId = {for (final g in snapshot.garments) g.id: g};
  final items = <OutfitItem>[];
  for (final (short, roleId) in reply.items) {
    final g = byId[brief.ids[short]];
    if (g == null || !g.isCandidate || items.any((i) => i.garmentId == g.id)) {
      continue;
    }
    final taken = [for (final i in items) i.role];
    final asked = OutfitRole.fromId(roleId);
    var role = asked != null && _fits(asked, g)
        ? asked
        : OutfitRole.suggestFor(g.category, taken);
    if (role.single && taken.contains(role)) {
      // Um segundo top passa a camada; o resto fica de fora.
      if (role == OutfitRole.mainTop && _fits(OutfitRole.midLayer, g)) {
        role = OutfitRole.midLayer;
      } else {
        continue;
      }
    }
    items.add(OutfitItem(g.id, role));
  }
  final roles = {for (final i in items) i.role};
  // Uma camada sem nada por baixo é o top.
  if (roles.contains(OutfitRole.midLayer) &&
      !roles.contains(OutfitRole.mainTop)) {
    final i = items.indexWhere((i) => i.role == OutfitRole.midLayer);
    items[i] = OutfitItem(items[i].garmentId, OutfitRole.mainTop);
    roles
      ..remove(OutfitRole.midLayer)
      ..add(OutfitRole.mainTop);
  }
  final onePiece = roles.contains(OutfitRole.onePiece);
  if (onePiece &&
      (roles.contains(OutfitRole.mainTop) ||
          roles.contains(OutfitRole.bottom))) {
    return null;
  }
  if (!onePiece &&
      !(roles.contains(OutfitRole.mainTop) &&
          roles.contains(OutfitRole.bottom))) {
    return null;
  }
  items.sort((a, b) => _layer(a.role).compareTo(_layer(b.role)));
  final assessed = [
    for (final s in DailyEngine.assess(snapshot, request, items)) ?s,
  ];
  return StylistPick(
    OutfitCandidate(
      items: [
        for (final s in assessed)
          if (s.role != OutfitRole.accessory) s,
      ],
      accessories: [
        for (final s in assessed)
          if (s.role == OutfitRole.accessory) s,
      ],
      notes: [
        if (!roles.contains(OutfitRole.footwear))
          const MissingRole(OutfitRole.footwear),
      ],
    ),
    name: reply.name,
    why: reply.why,
  );
}

bool _fits(OutfitRole role, Garment g) => switch (role) {
  OutfitRole.mainTop => g.category.group == CategoryGroup.top,
  OutfitRole.midLayer => DailyEngine.overLayers.contains(g.category),
  OutfitRole.outerLayer => g.category.group == CategoryGroup.outerwear,
  OutfitRole.bottom => g.category.group == CategoryGroup.bottom,
  OutfitRole.onePiece => g.category.group == CategoryGroup.onePiece,
  OutfitRole.footwear => g.category.group == CategoryGroup.footwear,
  OutfitRole.accessory =>
    g.category.group == CategoryGroup.accessory ||
        g.category.group == CategoryGroup.other,
};

int _layer(OutfitRole r) => switch (r) {
  OutfitRole.mainTop || OutfitRole.onePiece => 0,
  OutfitRole.midLayer => 1,
  OutfitRole.outerLayer => 2,
  OutfitRole.bottom => 3,
  OutfitRole.footwear => 4,
  OutfitRole.accessory => 5,
};
