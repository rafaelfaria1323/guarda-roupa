import 'package:supabase_flutter/supabase_flutter.dart';

import 'restore_plan.dart';

/// Pergunta ao Supabase que ids do backup esta conta já apagou ou desfez
/// (essas linhas saem do stream do PowerSync, por isso o dispositivo não
/// as vê). A RLS só deixa ver as linhas do próprio utilizador.
Future<Set<String>> Function(RemovableTable, List<String>)
supabaseRemovedLookup(SupabaseClient client) => (table, ids) async {
  // Ids que não são UUID (backups feitos à mão) não existem no servidor.
  final uuids = ids.where(_uuid.hasMatch).toList();
  final found = <String>{};
  for (var i = 0; i < uuids.length; i += _chunk) {
    final chunk = uuids.sublist(i, (i + _chunk).clamp(0, uuids.length));
    final rows = await client
        .from(table.table)
        .select('id')
        .inFilter('id', chunk)
        .not(table.column, 'is', null);
    for (final row in rows) {
      found.add(row['id']! as String);
    }
  }
  return found;
};

const _chunk = 100;
final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);
