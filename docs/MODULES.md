# Modules

Every feature (Budget, Dealings, Tasks, Notes, Transactions, Buy, Dreams…) is a
**module**: a folder under `lib/modules/<name>/` that implements the
`LifeModule` contract in `lib/modules/module.dart`.

One file decides which modules exist and in what order:
**`lib/app_modules.dart`**.

## The contract

| Member | Required | What it is |
|---|---|---|
| `id` | yes | Stable id (`'budget'`). Used for nav slots, intro-seen flags, hero tags. |
| `title`, `icon`, `accent` | yes | Name, icon, and a `ModuleAccent` from `Accents` (light + dark colours). |
| `items` | no | The `ItemSpec`s it owns: `kind` stored in `Item.kind`, `singular`, and editor fields (`sections`, `amount`, `dueDate`, note hint/lines). The first is what **+** adds. |
| `intro` | yes | `ModuleIntro`: tagline, description, feature bullets. Shown the first time the module opens and from its ⓘ button. |
| `buildScreen` | yes | The module's main body. No `Scaffold`: the shell adds the app bar, search and **+**. |
| `buildHomeCard` | no | A summary card on Home. |
| `buildSettings` | no | A block in Settings, under the module's title. |
| `searchable`, `onAdd` | no | Override the search button and the **+** behaviour. |

## Remove a module

Delete its line in `kAppConfig.modules`. It disappears from the Home tiles and
cards, the bottom nav, More, onboarding, intro screens and Settings. Nothing
else needs editing. Its rows stay in the database (and in backups), so putting
the line back brings them back. Activity History still lists them, labelled by
their raw kind.

## Reorder

Move lines in `kAppConfig.modules`. Home tiles (the first four), Home cards,
More and onboarding follow that order.

## Bottom nav

`navIds` lists up to three module ids shown between **Home** and **More**.
Ids of modules that aren't enabled are skipped.

```dart
navIds: ['budget', 'tasks', 'notes'],
```

## Add a simple category (one config entry)

A list with sections, optional amounts and due dates needs no new code.
Add a `CategoryModule` to `kAppConfig.modules`:

```dart
CategoryModule(
  id: 'books',                  // also the stored Item.kind (pass kind: to override)
  title: 'Reading',
  singular: 'Book',
  icon: CupertinoIcons.book,
  accent: Accents.sky,
  sections: [ListSection('now', 'Reading now'), ListSection('next', 'Up next')],
  tagline: 'One page at a time.',
  description: 'Books you are reading and the ones you want next.',
),
```

Optional: `amount: true`, `dueDate: true`, `features:`, `emptyTitle:`,
`emptySubtitle:`. `test/modules_test.dart` renders exactly this example.

`kind` is free text from end to end (Isar, backup JSON, Supabase), so a new
kind needs no migration. Don't rename a kind after you have data in it: the
old rows would be orphaned.

## Add a custom module (one folder + one line)

1. Create `lib/modules/habits/habits_module.dart`:

   ```dart
   class HabitsModule extends LifeModule {
     const HabitsModule();
     @override String get id => 'habits';
     @override String get title => 'Habits';
     @override IconData get icon => CupertinoIcons.repeat;
     @override ModuleAccent get accent => Accents.peach;
     @override List<ItemSpec> get items =>
         const [ItemSpec(kind: 'habit', singular: 'Habit')];
     @override ModuleIntro get intro => const ModuleIntro(
         tagline: 'Small things, every day.', description: '…');
     @override Widget buildScreen(BuildContext context) => const HabitsScreen();
   }
   ```

2. Add `HabitsModule(),` to `kAppConfig.modules`.

Read items with `ref.watch(itemsProvider('habit'))`, save with
`ref.read(syncServiceProvider).save(item)`, and open the shared editor with
`showItemEditor(context, ref, 'habit')`. The editor reads its fields from
your `ItemSpec`.

## Cloud sync

`kCloudSyncEnabled` in the same file is `false`: data stays on the device even
when a build has Supabase keys. Set it to `true` to bring back sign-in and sync
(see README → Supabase setup).
