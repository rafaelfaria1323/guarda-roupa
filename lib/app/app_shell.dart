import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/account_sync/application/providers.dart';
import '../features/account_sync/presentation/sync_status.dart';
import '../l10n/app_localizations.dart';
import 'router.dart';

/// Largura a partir da qual a navegação inferior passa a lateral.
const wideLayoutBreakpoint = 840.0;

class AppShell extends ConsumerWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  void _select(int index) => navigationShell.goBranch(
    index,
    initialLocation: index == navigationShell.currentIndex,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final destinations = [
      (Icons.calendar_today_outlined, Icons.calendar_today, l10n.navPlanner),
      (Icons.checkroom_outlined, Icons.checkroom, l10n.navWardrobe),
      (Icons.style_outlined, Icons.style, l10n.navOutfits),
      (Icons.auto_awesome_outlined, Icons.auto_awesome, l10n.navStyle),
    ];
    final title = destinations[navigationShell.currentIndex].$3;
    final appBar = AppBar(
      title: Text(title),
      actions: [
        SyncStatusIcon(
          sync: ref.watch(syncSummaryProvider),
          onPressed: () => context.push(AppRoutes.settings),
        ),
        IconButton(
          tooltip: l10n.settings,
          icon: const Icon(Icons.settings_outlined),
          onPressed: () => context.push(AppRoutes.settings),
        ),
      ],
    );

    final isWide = MediaQuery.sizeOf(context).width >= wideLayoutBreakpoint;
    if (isWide) {
      return Scaffold(
        appBar: appBar,
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: navigationShell.currentIndex,
              onDestinationSelected: _select,
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final (icon, selected, label) in destinations)
                  NavigationRailDestination(
                    icon: Icon(icon),
                    selectedIcon: Icon(selected),
                    label: Text(label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: navigationShell),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: appBar,
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: _select,
        destinations: [
          for (final (icon, selected, label) in destinations)
            NavigationDestination(
              icon: Icon(icon),
              selectedIcon: Icon(selected),
              label: label,
            ),
        ],
      ),
    );
  }
}
