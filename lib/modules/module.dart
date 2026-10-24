import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_theme.dart';
import '../widgets/item_editor.dart';

/// A named group inside a list ("Priority 0", "Wishlist"). Stored in
/// `Item.section` as [id].
class ListSection {
  const ListSection(this.id, this.label, {this.icon});
  final String id;
  final String label;
  final IconData? icon;
}

/// One kind of record a module owns, and the fields its editor shows.
///
/// [kind] is the value stored in `Item.kind` (and the Supabase `kind` column).
/// Keep it stable once data exists — renaming it orphans old rows.
class ItemSpec {
  const ItemSpec({
    required this.kind,
    required this.singular,
    this.sections = const [],
    this.amount = false,
    this.dueDate = false,
    this.noteHint = 'Notes (optional)',
    this.noteLines = 3,
  });

  final String kind;

  /// "Task", "Note" — used in "New Task" / "Edit Task".
  final String singular;

  /// Editor shows a section picker when non-empty; the first is the default.
  final List<ListSection> sections;

  /// Editor shows an optional amount (৳) field.
  final bool amount;

  /// Editor shows an optional due-date row.
  final bool dueDate;

  final String noteHint;
  final int noteLines;
}

/// One bullet on a module's intro page.
class IntroFeature {
  const IntroFeature(this.icon, this.title, this.subtitle);
  final IconData icon;
  final String title;
  final String subtitle;
}

/// The content of a module's intro / onboarding page.
class ModuleIntro {
  const ModuleIntro({
    required this.tagline,
    required this.description,
    this.features = const [],
  });
  final String tagline;
  final String description;
  final List<IntroFeature> features;
}

/// The contract every feature implements. A module is self-contained in
/// `lib/modules/<name>/`; the app learns about it only through
/// `lib/app_modules.dart`. See docs/MODULES.md.
abstract class LifeModule {
  const LifeModule();

  /// Stable id ("budget"). Used for nav config, intro-seen flags and hero tags.
  String get id;
  String get title;
  IconData get icon;
  ModuleAccent get accent;

  /// Record kinds this module owns. The first is what the + button adds.
  /// Empty for modules that don't store items.
  List<ItemSpec> get items => const [];

  ModuleIntro get intro;

  /// The module's main screen body (no Scaffold — the shell supplies the app
  /// bar, search and + button).
  Widget buildScreen(BuildContext context);

  /// Optional summary card on Home.
  Widget? buildHomeCard(BuildContext context) => null;

  /// Optional block in Settings (a header + card is supplied around it).
  Widget? buildSettings(BuildContext context) => null;

  /// Whether the shell shows a search button for this module.
  bool get searchable => items.isNotEmpty;

  /// What the + button does. Default: open the editor for the first kind.
  void onAdd(BuildContext context, WidgetRef ref) {
    if (items.isEmpty) return;
    showItemEditor(context, ref, items.first.kind);
  }
}

/// The app's module configuration. The real one lives in
/// `lib/app_modules.dart`; tests build their own.
class AppConfig {
  const AppConfig({required this.modules, this.navIds = const []});

  /// Enabled modules, in display order.
  final List<LifeModule> modules;

  /// Module ids shown in the bottom nav between Home and More (max 3 used).
  /// Ids that aren't in [modules] are ignored.
  final List<String> navIds;

  List<LifeModule> get navModules => [
    for (final id in navIds) ...modules.where((m) => m.id == id),
  ].take(3).toList();

  LifeModule? byId(String id) {
    for (final m in modules) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// The module that owns records of [kind], if it's enabled.
  LifeModule? moduleForKind(String kind) {
    for (final m in modules) {
      if (m.items.any((s) => s.kind == kind)) return m;
    }
    return null;
  }

  ItemSpec? specFor(String kind) {
    for (final m in modules) {
      for (final s in m.items) {
        if (s.kind == kind) return s;
      }
    }
    return null;
  }
}
