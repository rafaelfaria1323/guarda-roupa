import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'app/config.dart';
import 'features/account_sync/application/providers.dart';
import 'features/account_sync/data/supabase_auth_service.dart';
import 'features/account_sync/data/supabase_connector.dart';
import 'features/account_sync/data/supabase_photo_storage.dart';
import 'features/import/application/import_providers.dart';
import 'features/import/data/supabase_product_importer.dart';
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
