import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/module_nav.dart';
import 'history_screen.dart';
import 'settings_screen.dart';

/// Every module, plus Settings and History.
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modules = ref.watch(appConfigProvider).modules;
    Widget chevron() => Icon(
      CupertinoIcons.chevron_right,
      size: 18,
      color: context.colors.inkSub,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          if (modules.isNotEmpty) ...[
            groupHeader(context, 'Modules'),
            cardGroup(context, [
              for (var i = 0; i < modules.length; i++) ...[
                ListTile(
                  leading: IconTile(
                    icon: modules[i].icon,
                    accent: modules[i].accent,
                    size: 40,
                  ),
                  title: Text(modules[i].title),
                  subtitle: Text(modules[i].intro.tagline),
                  trailing: chevron(),
                  onTap: () => openModule(context, ref, modules[i]),
                ),
                if (i != modules.length - 1) rowDivider(context),
              ],
            ]),
          ],
          groupHeader(context, 'App'),
          cardGroup(context, [
            ListTile(
              leading: const IconTile(
                icon: CupertinoIcons.clock,
                accent: Accents.forest,
                size: 40,
              ),
              title: const Text('Activity History'),
              subtitle: const Text('Every add, edit and delete'),
              trailing: chevron(),
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const HistoryScreen())),
            ),
            rowDivider(context),
            ListTile(
              leading: const IconTile(
                icon: CupertinoIcons.gear,
                accent: Accents.forest,
                size: 40,
              ),
              title: const Text('Settings'),
              subtitle: const Text('Appearance, backup, vault, app lock'),
              trailing: chevron(),
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
            ),
          ]),
        ],
      ),
    );
  }
}
