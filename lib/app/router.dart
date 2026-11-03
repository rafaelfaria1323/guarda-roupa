import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/weather/presentation/weather_location_screen.dart';
import '../features/account_sync/application/providers.dart';
import '../features/account_sync/domain/auth_service.dart';
import '../features/account_sync/presentation/settings_screen.dart';
import '../features/account_sync/presentation/sign_in_screen.dart';
import '../features/care/presentation/care_settings_screen.dart';
import '../features/inspirations/presentation/style_screen.dart';
import '../features/inspirations/presentation/inspiration_editor_screen.dart';
import '../features/inspirations/presentation/preference_editor_screen.dart';
import '../features/outfits/presentation/outfit_editor_screen.dart';
import '../features/outfits/presentation/outfits_screen.dart';
import '../features/planner/presentation/planner_screen.dart';
import '../features/wardrobe/domain/garment.dart';
import '../features/wardrobe/presentation/garment_form_screen.dart';
import '../features/wardrobe/presentation/wardrobe_screen.dart';
import '../features/wear/presentation/wear_picker_screen.dart';
import 'app_shell.dart';

abstract final class AppRoutes {
  static const signIn = '/entrar';
  static const planner = '/planeador';
  static const wardrobe = '/guarda-roupa';
  static const newGarment = '/guarda-roupa/nova';
  static String garment(GarmentId id) => '/guarda-roupa/peca/${id.value}';
  static const outfits = '/conjuntos';
  static const newOutfit = '/conjuntos/novo';
  static String outfit(String id) => '/conjuntos/conjunto/$id';
  static const style = '/estilo';
  static const newInspiration = '/estilo/inspiracao/nova';
  static String inspiration(String id) => '/estilo/inspiracao/$id';
  static const newPreference = '/estilo/preferencia/nova';
  static String preference(String id) => '/estilo/preferencia/$id';
  static const settings = '/definicoes';
  static const careSettings = '/definicoes/lavagem';
  static const weatherLocation = '/definicoes/localizacao';
  static const wear = '/vesti';
  static String correctWear(String eventId) => '/vesti/$eventId';
}

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authServiceProvider);
  final refresh = _AuthRefresh(auth);
  final router = GoRouter(
    initialLocation: AppRoutes.planner,
    refreshListenable: refresh,
    redirect: (context, state) {
      final signedIn = auth.currentUser != null;
      final atSignIn = state.matchedLocation == AppRoutes.signIn;
      if (!signedIn) return atSignIn ? null : AppRoutes.signIn;
      if (atSignIn) return AppRoutes.planner;
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.signIn,
        builder: (context, state) => const SignInScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(navigationShell: shell),
        branches: [
          _branch(AppRoutes.planner, const PlannerScreen()),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.wardrobe,
                builder: (context, state) => const WardrobeScreen(),
              ),
            ],
          ),
          _branch(AppRoutes.outfits, const OutfitsScreen()),
          _branch(AppRoutes.style, const StyleScreen()),
        ],
      ),
      // Formulários fora do shell: ocupam o ecrã inteiro, com botão de voltar.
      GoRoute(
        path: AppRoutes.newGarment,
        builder: (context, state) => const GarmentFormScreen(),
      ),
      GoRoute(
        path: '/guarda-roupa/peca/:id',
        builder: (context, state) =>
            GarmentFormScreen(id: GarmentId(state.pathParameters['id']!)),
      ),
      GoRoute(
        path: AppRoutes.newOutfit,
        builder: (context, state) => const OutfitEditorScreen(),
      ),
      GoRoute(
        path: '/conjuntos/conjunto/:id',
        builder: (context, state) =>
            OutfitEditorScreen(id: state.pathParameters['id']),
      ),
      GoRoute(
        path: AppRoutes.newInspiration,
        builder: (context, state) => const InspirationEditorScreen(),
      ),
      GoRoute(
        path: '/estilo/inspiracao/:id',
        builder: (context, state) =>
            InspirationEditorScreen(id: state.pathParameters['id']),
      ),
      GoRoute(
        path: AppRoutes.newPreference,
        builder: (context, state) => const PreferenceEditorScreen(),
      ),
      GoRoute(
        path: '/estilo/preferencia/:id',
        builder: (context, state) =>
            PreferenceEditorScreen(id: state.pathParameters['id']),
      ),
      GoRoute(
        path: AppRoutes.careSettings,
        builder: (context, state) => const CareSettingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.weatherLocation,
        builder: (context, state) => const WeatherLocationScreen(),
      ),
      GoRoute(
        path: AppRoutes.wear,
        builder: (context, state) => const WearPickerScreen(),
      ),
      GoRoute(
        path: '/vesti/:id',
        builder: (context, state) =>
            WearPickerScreen(eventId: state.pathParameters['id']),
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
  );
  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});

StatefulShellBranch _branch(String path, Widget screen) => StatefulShellBranch(
  routes: [GoRoute(path: path, builder: (context, state) => screen)],
);

/// Reavalia o redirect sempre que a sessão muda.
final class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(AuthService auth) {
    _subscription = auth.userChanges.listen((_) => notifyListeners());
  }

  late final StreamSubscription<AuthUser?> _subscription;

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
