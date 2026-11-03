import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/account_sync/presentation/settings_screen.dart';
import '../features/inspirations/presentation/style_screen.dart';
import '../features/outfits/presentation/outfits_screen.dart';
import '../features/planner/presentation/planner_screen.dart';
import '../features/wardrobe/presentation/wardrobe_screen.dart';
import 'app_shell.dart';

abstract final class AppRoutes {
  static const planner = '/planeador';
  static const wardrobe = '/guarda-roupa';
  static const outfits = '/conjuntos';
  static const style = '/estilo';
  static const settings = '/definicoes';
}

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: AppRoutes.planner,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(navigationShell: shell),
        branches: [
          _branch(AppRoutes.planner, const PlannerScreen()),
          _branch(AppRoutes.wardrobe, const WardrobeScreen()),
          _branch(AppRoutes.outfits, const OutfitsScreen()),
          _branch(AppRoutes.style, const StyleScreen()),
        ],
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

StatefulShellBranch _branch(String path, Widget screen) => StatefulShellBranch(
  routes: [GoRoute(path: path, builder: (context, state) => screen)],
);
