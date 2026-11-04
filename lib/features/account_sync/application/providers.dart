import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:powersync/powersync.dart';

import '../../../app/config.dart';
import '../../local_ai/data/photo_embeddings.dart';
import '../../wardrobe/data/photo_files.dart';
import '../../wardrobe/data/powersync_wardrobe_repository.dart';
import '../../wardrobe/domain/wardrobe_repository.dart';
import '../data/local_database.dart';
import '../domain/auth_service.dart';

final appConfigProvider = Provider<AppConfig>(
  (ref) => AppConfig.fromEnvironment(),
);

/// Substituído em `main` (Supabase) e nos testes.
final authServiceProvider = Provider<AuthService>(
  (ref) => const UnconfiguredAuthService(),
);

/// Cria o conector de sincronização; `null` = só local (sem PowerSync).
final syncConnectorFactoryProvider =
    Provider<PowerSyncBackendConnector Function()?>((ref) => null);

/// Abre a base local de uma conta. Substituído nos testes.
final databaseOpenerProvider =
    Provider<Future<PowerSyncDatabase> Function(String userId)>(
      (ref) => openUserDatabase,
    );

final currentUserProvider = StreamProvider<AuthUser?>((ref) async* {
  final auth = ref.watch(authServiceProvider);
  yield auth.currentUser;
  yield* auth.userChanges;
});

final _currentUserIdProvider = Provider<String?>(
  (ref) => ref.watch(currentUserProvider).value?.id,
);

/// Base local da conta atual. Muda de conta = fecha a base anterior e abre
/// outra (ADR-008: dados de A nunca aparecem em B).
final userDatabaseProvider = FutureProvider<PowerSyncDatabase?>((ref) async {
  final userId = ref.watch(_currentUserIdProvider);
  if (userId == null) return null;
  final db = await ref.watch(databaseOpenerProvider)(userId);
  ref.onDispose(db.close);
  final connector = ref.watch(syncConnectorFactoryProvider);
  if (connector != null) {
    await db.connect(connector: connector());
  }
  return db;
});

final wardrobeRepositoryProvider = Provider<WardrobeRepository?>((ref) {
  final userId = ref.watch(_currentUserIdProvider);
  final db = ref.watch(userDatabaseProvider).value;
  if (userId == null || db == null) return null;
  return PowerSyncWardrobeRepository(db: db, ownerId: userId);
});

/// Estado de sincronização visível ao utilizador.
final class SyncSummary {
  const SyncSummary({
    required this.configured,
    required this.connected,
    required this.uploading,
    required this.pendingOperations,
    required this.conflicts,
    this.lastSyncedAt,
    this.error,
  });

  /// `false` quando o PowerSync não está configurado: dados só locais.
  final bool configured;
  final bool connected;
  final bool uploading;
  final int pendingOperations;
  final int conflicts;
  final DateTime? lastSyncedAt;
  final Object? error;
}

final _syncStatusProvider = StreamProvider<SyncStatus?>((ref) async* {
  final db = ref.watch(userDatabaseProvider).value;
  if (db == null) {
    yield null;
    return;
  }
  yield db.currentStatus;
  yield* db.statusStream;
});

final _pendingOperationsProvider = StreamProvider<int>((ref) {
  final db = ref.watch(userDatabaseProvider).value;
  if (db == null) return Stream.value(0);
  return db
      .watch(
        // Só as operações contam: as escritas na vista `garments` também
        // entram em ps_crud, mas não são enviadas (ver OperationUploadQueue).
        'SELECT count(*) AS n FROM ps_crud '
        r"WHERE json_extract(data, '$.type') IN "
        "('garment_operations', 'wear_operations', 'outfit_operations', 'style_operations', 'plan_operations')",
        triggerOnTables: const {'ps_crud'},
      )
      .map((rows) => rows.first['n']! as int);
});

final _conflictsProvider = StreamProvider<int>((ref) {
  final db = ref.watch(userDatabaseProvider).value;
  if (db == null) return Stream.value(0);
  return db
      .watch(
        'SELECT count(*) AS n FROM sync_conflicts',
        triggerOnTables: const {'sync_conflicts'},
      )
      .map((rows) => rows.first['n']! as int);
});

final syncSummaryProvider = Provider<SyncSummary>((ref) {
  final status = ref.watch(_syncStatusProvider).value;
  return SyncSummary(
    configured: ref.watch(syncConnectorFactoryProvider) != null,
    connected: status?.connected ?? false,
    uploading: status?.uploading ?? false,
    pendingOperations: ref.watch(_pendingOperationsProvider).value ?? 0,
    conflicts: ref.watch(_conflictsProvider).value ?? 0,
    lastSyncedAt: status?.lastSyncedAt,
    error: status?.uploadError ?? status?.downloadError,
  );
});

/// Termina a sessão e apaga a base local desta conta neste dispositivo,
/// incluindo alterações por enviar (ADR-008). O ecrã pede confirmação antes
/// e bloqueia quando há pendências.
Future<void> signOut(WidgetRef ref) async {
  final db = ref.read(userDatabaseProvider).value;
  if (db != null) await clearAccountData(db);
  await ref.read(authServiceProvider).signOut();
}

/// Apaga tudo o que a conta deixou neste dispositivo.
Future<void> clearAccountData(PowerSyncDatabase db) async {
  await db.disconnectAndClear();
  // Fora do schema do PowerSync: o clear acima não lhe toca.
  await db.writeTransaction(PhotoFiles.clear);
  await db.writeTransaction(PhotoEmbeddings.clear);
}
