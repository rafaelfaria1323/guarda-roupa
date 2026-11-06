import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'app/config.dart';
import 'features/photo_ai/application/photo_ai_providers.dart';
import 'features/photo_ai/data/supabase_photo_reader.dart';
import 'features/account_sync/application/providers.dart';
import 'features/account_sync/data/supabase_auth_service.dart';
import 'features/account_sync/data/supabase_connector.dart';
import 'features/account_sync/data/supabase_photo_storage.dart';
import 'features/backup/application/backup_providers.dart';
import 'features/backup/data/supabase_removed_lookup.dart';
import 'features/import/application/import_providers.dart';
import 'features/import/data/supabase_product_importer.dart';
import 'features/reminders/application/reminder_providers.dart';
import 'features/reminders/data/supabase_reminder_backend.dart';
import 'features/shopping/application/shopping_providers.dart';
import 'features/stylist/application/stylist_providers.dart';
import 'features/stylist/data/supabase_stylist.dart';
import 'features/wardrobe/application/photo_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = AppConfig.fromEnvironment();

  final overrides = [appConfigProvider.overrideWithValue(config)];
  if (config.hasSupabase) {
    await Supabase.initialize(
      url: config.supabaseUrl,
      publishableKey: config.supabasePublishableKey,
    );
    final client = Supabase.instance.client;
    final stylist = SupabaseStylist(
      supabaseUrl: config.supabaseUrl,
      apiKey: config.supabasePublishableKey,
      accessToken: () => client.auth.currentSession?.accessToken,
    );
    overrides
      ..add(authServiceProvider.overrideWithValue(SupabaseAuthService(client)))
      ..add(
        photoStorageProvider.overrideWithValue(SupabasePhotoStorage(client)),
      )
      ..add(
        productImporterProvider.overrideWithValue(
          SupabaseProductImporter(
            supabaseUrl: config.supabaseUrl,
            apiKey: config.supabasePublishableKey,
            accessToken: () => client.auth.currentSession?.accessToken,
          ),
        ),
      )
      ..add(
        photoReaderProvider.overrideWithValue(
          SupabasePhotoReader(
            supabaseUrl: config.supabaseUrl,
            apiKey: config.supabasePublishableKey,
            accessToken: () => client.auth.currentSession?.accessToken,
          ),
        ),
      )
      ..addAll([
        stylistProvider.overrideWithValue(stylist),
        shoppingAdvisorProvider.overrideWithValue(stylist),
      ])
      ..add(
        reminderBackendProvider.overrideWithValue(
          SupabaseReminderBackend(
            client: client,
            supabaseUrl: config.supabaseUrl,
            apiKey: config.supabasePublishableKey,
          ),
        ),
      )
      ..add(
        remoteRemovedLookupProvider.overrideWithValue(
          supabaseRemovedLookup(client),
        ),
      )
      ..add(
        syncConnectorFactoryProvider.overrideWithValue(
          config.hasPowerSync
              ? () => SupabasePowerSyncConnector(
                  client: client,
                  powerSyncUrl: config.powerSyncUrl,
                )
              : null,
        ),
      );
  }

  runApp(ProviderScope(overrides: overrides, child: const GuardaRoupaApp()));
}
