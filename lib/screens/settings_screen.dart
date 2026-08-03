import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../providers/providers.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final _salary = TextEditingController(
      text: ref.read(monthlySalaryProvider).toStringAsFixed(0));

  @override
  void dispose() {
    _salary.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final themeMode = ref.watch(themeModeProvider);
    final sync = ref.watch(syncServiceProvider);
    final online = ref.watch(syncOnlineProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          groupHeader(context, 'Appearance'),
          cardGroup(context, [
            Padding(
              padding: const EdgeInsets.all(16),
              child: CupertinoSlidingSegmentedControl<ThemeMode>(
                groupValue: themeMode,
                children: const {
                  ThemeMode.system: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text('System')),
                  ThemeMode.light: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text('Light')),
                  ThemeMode.dark: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text('Dark')),
                },
                onValueChanged: (mode) {
                  if (mode != null) {
                    ref.read(themeModeProvider.notifier).set(mode);
                  }
                },
              ),
            ),
          ]),
          groupHeader(context, 'Budget'),
          cardGroup(context, [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                controller: _salary,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Monthly salary (৳)',
                  helperText: 'Used for the 65 / 20 / 15 budget split',
                ),
                onSubmitted: _saveSalary,
                onEditingComplete: () => _saveSalary(_salary.text),
              ),
            ),
          ]),
          groupHeader(context, 'Sync'),
          cardGroup(context, [
            ListTile(
              leading: Icon(
                online ? CupertinoIcons.cloud : CupertinoIcons.cloud_bolt,
                color: online ? AppColors.green : c.inkSub,
              ),
              title: Text(online ? 'Online' : 'Offline (local only)'),
              subtitle: ValueListenableBuilder<DateTime?>(
                valueListenable: sync.lastSyncedAt,
                builder: (context, value, _) => Text(
                  value == null
                      ? 'Not synced yet'
                      : 'Last synced ${DateFormat('d MMM, HH:mm').format(value)}',
                ),
              ),
              trailing: TextButton(
                onPressed: online ? () => sync.forceResync() : null,
                child: const Text('Sync now'),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  void _saveSalary(String text) {
    final v = double.tryParse(text.trim());
    if (v != null && v > 0) {
      ref.read(monthlySalaryProvider.notifier).set(v);
    }
  }
}
