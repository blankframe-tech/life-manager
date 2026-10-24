import 'package:flutter/cupertino.dart';

import '../../theme/app_theme.dart';
import '../module.dart';
import 'category_screen.dart';

/// A generic, configurable checklist module: a titled list of items grouped
/// into sections, with optional amounts and due dates. Buy, Dreams and Tasks
/// are all instances of this — a new simple category is one entry in
/// `lib/app_modules.dart`, no new code.
class CategoryModule extends LifeModule {
  const CategoryModule({
    required this.id,
    required this.title,
    required this.singular,
    required this.icon,
    required this.accent,
    String? kind,
    this.sections = const [],
    this.amount = false,
    this.dueDate = false,
    this.tagline = 'Keep it all in one list.',
    this.description =
        'Add anything, tick it off when it is done, and swipe to remove.',
    this.features,
    this.emptyTitle,
    this.emptySubtitle,
  }) : _kind = kind; // ignore: prefer_initializing_formals

  @override
  final String id;
  @override
  final String title;
  final String singular;
  @override
  final IconData icon;
  @override
  final ModuleAccent accent;

  /// Stored `Item.kind`. Defaults to [id].
  final String? _kind;
  String get kind => _kind ?? id;

  final List<ListSection> sections;
  final bool amount;
  final bool dueDate;
  final String tagline;
  final String description;
  final List<IntroFeature>? features;
  final String? emptyTitle;
  final String? emptySubtitle;

  @override
  List<ItemSpec> get items => [
    ItemSpec(
      kind: kind,
      singular: singular,
      sections: sections,
      amount: amount,
      dueDate: dueDate,
    ),
  ];

  @override
  ModuleIntro get intro => ModuleIntro(
    tagline: tagline,
    description: description,
    features:
        features ??
        [
          if (sections.isNotEmpty)
            IntroFeature(
              CupertinoIcons.square_stack_3d_up,
              'Sections',
              sections.map((s) => s.label).join(' · '),
            ),
          const IntroFeature(
            CupertinoIcons.check_mark_circled,
            'Tick things off',
            'Done items sink to the bottom.',
          ),
          if (amount)
            const IntroFeature(
              CupertinoIcons.money_dollar_circle,
              'Amounts in ৳',
              'Note what each one costs.',
            ),
          if (dueDate)
            const IntroFeature(
              CupertinoIcons.calendar,
              'Due dates',
              'See what is coming up first.',
            ),
          const IntroFeature(
            CupertinoIcons.lock_shield,
            'Private',
            'Stored on this device only.',
          ),
        ],
  );

  @override
  Widget buildScreen(BuildContext context) => CategoryScreen(module: this);
}
