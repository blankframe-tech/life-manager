// ─────────────────────────────────────────────────────────────────────────────
//  THE MODULE LIST. Edit this file to add, remove or reorder features.
//
//  • Remove a module: delete its line. It disappears from Home, the bottom nav,
//    More, onboarding, intro screens and Settings. Its data stays in the
//    database untouched (put the line back and it reappears).
//  • Reorder: move lines. Home tiles, cards and More follow this order.
//  • Bottom nav: list up to 3 module ids in [kNavIds] (Home and More are fixed).
//  • New simple list: add a CategoryModule(...) entry. See docs/MODULES.md.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/cupertino.dart';

import 'models/item.dart';
import 'modules/budget/budget_module.dart';
import 'modules/category/category_module.dart';
import 'modules/dealings/dealings_module.dart';
import 'modules/module.dart';
import 'modules/notes/notes_module.dart';
import 'modules/tasks/tasks_module.dart';
import 'modules/transactions/transactions_module.dart';
import 'theme/app_theme.dart';

const kAppConfig = AppConfig(
  modules: [
    BudgetModule(),
    DealingsModule(),
    TasksModule(),
    NotesModule(),
    TransactionsModule(),
    CategoryModule(
      id: 'buy',
      kind: ItemKind.buy,
      title: 'Buy',
      singular: 'Item',
      icon: CupertinoIcons.cart,
      accent: Accents.rose,
      amount: true,
      sections: [
        ListSection('p0', 'Priority 0 · must asap', icon: CupertinoIcons.flame),
        ListSection('wishlist', 'Wishlist', icon: CupertinoIcons.heart),
      ],
      tagline: 'Buy what matters first.',
      description: 'A shopping list split into must-haves and someday-wants.',
      emptyTitle: 'Nothing to buy',
      emptySubtitle: 'Your cart is calm. Add what you need when you need it.',
    ),
    CategoryModule(
      id: 'dreams',
      kind: ItemKind.dream,
      title: 'Dreams',
      singular: 'Dream',
      icon: CupertinoIcons.sparkles,
      accent: Accents.lavender,
      tagline: 'Big things, no pressure.',
      description:
          'Long-term wishes and someday plans. No dates, no deadlines — just direction.',
      emptyTitle: 'Dream a little',
      emptySubtitle: 'Write down one big thing you want for your future.',
    ),
  ],
  navIds: ['budget', 'tasks', 'notes'],
);

/// Supabase cloud sync. OFF in V2: everything stays on this device, even when
/// a build has Supabase keys. Set to true to bring back sign-in and sync
/// (see README → "Supabase setup").
const kCloudSyncEnabled = false;
