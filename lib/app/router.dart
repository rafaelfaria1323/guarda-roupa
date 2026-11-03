import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/account_sync/application/providers.dart';
import '../features/account_sync/domain/auth_service.dart';
import '../features/account_sync/presentation/settings_screen.dart';
import '../features/account_sync/presentation/sign_in_screen.dart';
import '../features/inspirations/presentation/style_screen.dart';
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
  static const style = '/estilo';
  static const settings = '/definicoes';
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
