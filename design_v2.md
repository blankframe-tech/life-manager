# Design v2 — usability upgrade spec

For devs building v2. Builds on `design.md` (v1 as-is) and the
`ui-ux-pro-max` skill's flutter/finance/product guidance. Keep v1's iOS
grouped-list identity, offline-first Isar+Supabase architecture, unified
`Item` model, and Riverpod — this is a usability pass, not a rewrite.

## What stays
- Unified `Item` model, one Supabase table, Riverpod state, Isar local-first.
- iOS grouped-list visual language (rounded cards, hairline dividers,
  bottom nav + FAB + bottom-sheet editor).
- Per-section accent color identity (indigo/teal/orange/violet/pink).

## What changes and why

### 1. Dark mode (new requirement)
v1 is light-only (`AppColors.bg = #F2F2F7` hardcoded). Ship a dark
variant — this app holds financial data people check at night/in bed.
- Convert `AppColors` to semantic tokens resolved per `Brightness`, not
  raw hex used directly in widgets: `background`, `surface`, `onSurface`,
  `onSurfaceMuted`, `divider`, `primary`, `destructive`. Reference
  `ThemeData.colorScheme` + `Theme.of(context)` instead of static
  `AppColors.x` constants sprinkled across `lib/screens/*.dart`.
- Dark background: deep navy/near-black (`#0F172A` family), not inverted
  light-mode colors — desaturate accents slightly so they don't vibrate on
  black (per finance-app color research: trust blue `#1E40AF` / profit
  green `#059669` / alert red `#DC2626` read well on `#0F172A`).
- Keep the 5 section accents but verify each hits 4.5:1 on both the light
  card (`#FFFFFF`) and dark card (`#192134`) backgrounds independently —
  don't assume light-mode contrast carries over.
- Respect system `Brightness` by default; add a manual override in a new
  Settings screen (see §6).

### 2. Typography
Current: single `.SF Pro Text` family, hardcoded sizes (13/14/15/17/18px)
scattered per-widget. For v2:
- Adopt a real type-scale as named `TextTheme` roles (`titleLarge`,
  `titleMedium`, `bodyLarge`, `bodyMedium`, `labelSmall` ...) instead of
  inline `TextStyle(fontSize: 15)` in every row builder — one change point
  when the scale needs adjusting.
- Support Dynamic Type / `MediaQuery.textScaler`: nothing in v1 disables
  scaling, but no screen has been tested at largest accessibility text
  size — verify `budget_screen.dart`'s money rows and `checklist_screen.dart`
  due-date badges don't clip or overlap at 200% scale; wrap with
  `FittedBox` or allow wrapping instead of fixed-height rows.
  (`web` domain guideline: `dynamic-type`, severity High.)
- Money/amount columns (`money()`, `moneyK()` in `lib/util/format.dart`):
  use tabular figures so amounts don't jitter column alignment as digits
  change — Flutter: `FontFeature.tabularFigures()` in the amount
  `TextStyle`.

### 3. Data visualization (currently zero charts — text + progress bars only)
Budget screen only has 3 linear progress bars; Dealings has plain stat
numbers. Add real charts using **`fl_chart`** (pure-Dart, no native
deps — fits offline-first/no-extra-permissions constraint):

| Screen | Add | Chart type | Notes |
|---|---|---|---|
| Budget | Needs/Wants/Savings breakdown | **Stacked 100% bar** (not pie — 3 categories is borderline but stacked bar reads faster than pie and scales if a 4th category is added later) | Keep the existing linear ideal-vs-actual bars per category (they're the more actionable view); add the stacked bar as a single at-a-glance summary above them |
| Budget | Spend trend over months | **Line chart**, once >1 month of history exists | Skip entirely until multi-month data exists — don't build it for a single data point |
| Dealings | Net position over time | **Waterfall chart** (i-owe entries negative, they-owe entries positive, running total) | Matches the "who owes whom" mental model better than two separate stat numbers; keep the stat card too, add waterfall as detail view on tap |
| Tasks/Buy | Completion ratio per group | **Waffle/percentage chip** in `groupHeader` trailing (already shows "$n left" — add a small filled-percentage ring or waffle next to it) | Cheap addition, reuses existing header slot |

Rules for all of the above (from the skill's chart guidelines):
- Never rely on color alone — waterfall bars get a ↑/↓ glyph, stacked bar
  segments get direct % labels.
- Provide the existing plain-number/list view as the accessible fallback
  — charts are additive, not a replacement for the row list.
- Debug/entrance animation must respect `MediaQuery.disableAnimations`
  (reduced motion) — data must be legible immediately, not only after a
  1s draw-in.
- ≤5 categories for any pie/donut if one is ever used; this app's data
  (3 budget categories, 2 deal directions) stays safely under that, so
  stacked bar/waterfall over pie is a style choice for scannability, not
  a hard limit workaround.

### 4. Empty / loading / error states
v1 already has `emptyState()` (good) but no loading-skeleton or
error-retry pattern — `async.when(loading: ..., error: ...)` in every
screen just shows a spinner or raw exception text (`Text('$e')` in
`budget_screen.dart:29`, `dealings_screen.dart`, etc).
- Replace the bare `CupertinoActivityIndicator()` loading branch with a
  skeleton matching the target screen's card shape (shimmer rows in
  `cardGroup` shape) — only for the first load; local Isar reads are
  near-instant so this mostly matters for the initial Supabase pull on a
  fresh install.
- Replace `Text('$e')` error branches with a real error state: icon +
  one-line human message + a "Retry" button that re-invokes the provider.
  Never show a raw exception string to the user.
- `emptyState()` already has icon/title/subtitle — add a CTA button
  (e.g. "Add your first task") wired to `showItemEditor`, since a screen
  with zero items is exactly the moment a user needs the add-flow most
  discoverable.

### 5. Interaction & motion
- **Undo delete.** Swipe-to-delete (`DeletableRow`) currently deletes
  immediately with no recovery. Add a `SnackBar` with an "Undo" action
  (4-5s) before the tombstone write actually commits, or commit
  immediately but keep a short-lived undo buffer in `SyncService`. This
  is the single highest-value change in this doc — irreversible swipe
  deletes on financial/task data is the classic mobile UX trap.
- **Confirm destructive, not routine, actions.** Don't add a confirm
  dialog to every delete (that defeats swipe's speed) — but do confirm
  before bulk/irreversible actions if v2 adds any (e.g. "clear all done
  tasks").
- **Haptics.** Add light haptic feedback on: swipe-delete commit, task
  checkbox toggle, save button tap. iOS-first app, users expect it
  (`HapticFeedback.lightImpact()` / `.mediumImpact()` for delete).
- **Press feedback timing.** Verify all custom tap targets (`_segmented`
  pills in `item_editor.dart`, checklist checkbox `GestureDetector`) show
  visual feedback within ~100ms — currently plain `GestureDetector` with
  no press-state styling at all. Wrap in `InkWell`/`Material` (already
  done for row taps) so pills and checkboxes get the same tactile
  response as list rows.
- **Segmented control → native widget.** `_segmented()` in
  `item_editor.dart` is a hand-rolled `Wrap` of `GestureDetector`s. Prefer
  `CupertinoSlidingSegmentedControl` — animated selection, correct
  accessibility semantics, no reinvented tap-state logic.

### 6. New screen: Settings (currently none exists)
Nothing to manage app-level preferences today. Add one, reachable from a
gear icon in the app bar (next to the sync-status cloud icon):
- Appearance: System / Light / Dark.
- Sync status detail (last synced time, force-resync button) — currently
  the cloud icon is the *only* sync affordance; users have no way to see
  *when* it last synced or force a retry after being offline.
- Monthly salary value — currently `kMonthlySalary = 40000.0` is a
  hardcoded constant in `budget_screen.dart:13`. Make it user-editable;
  the 65/20/15 split should recompute from a stored value, not a
  compile-time constant.

### 7. Search & filter (currently none — every screen is view-everything)
With 71+ items already and growth expected, add:
- A search field reachable from each screen's app bar (icon → expands to
  a text field, filters the current `itemsProvider` list client-side by
  title/note). Cheap since data is already local in Isar.
- Buy/Task screens: a "hide completed" toggle in the group header row —
  done items currently just sink to the bottom and stay visible forever,
  which will get noisy.

### 8. Accessibility checklist (gaps found in current code)
- **Icon-only tap targets need labels.** The checklist checkbox
  (`GestureDetector` wrapping an `Icon` in `checklist_screen.dart`), the
  cloud sync icon in `root_scaffold.dart`, and the delete-swipe icon all
  lack `Semantics`/`tooltip`. Add `Semantics(label: 'Mark done', ...)` or
  a `Tooltip` to each.
- **Touch target size.** The checklist checkbox icon is 24px with
  `right: 12` padding only on one side — verify the full tappable area is
  ≥44×44 (wrap in a fixed-size `SizedBox` + `InkResponse`, not just the
  bare icon's bounding box).
- **Color-only signal.** Over-budget rows in `budget_screen.dart` turn
  text/bar rose-colored with no icon/text change; dealings direction is
  color-only (rose/teal) too. Add a small ↑ (over) glyph next to
  over-budget amounts, and keep the existing +/− text prefix on dealings
  (already present — good, don't remove it).
- **Focus order / screen reader.** No `Semantics` grouping currently on
  card rows — a screen reader hits title, note, amount, badge as separate
  unlabeled nodes. Wrap each row's content in one `Semantics` node with a
  composed label ("Rent, 10,000 taka, due in 3 days").

### 9. List performance (forward-looking, not urgent at current data volume)
All 4 list screens use `ListView(children: [...])` (eager build), fine at
tens of items. If a user's Buy/Task lists grow past ~200 rows, switch the
`cardGroup`/row-building path to `ListView.builder` or a `SliverList` so
off-screen rows aren't built. Not a v2-launch blocker — flag as a known
scaling ceiling.

## Color tokens for v2 (add to `app_theme.dart`, don't replace v1 accents)

| Token | Light | Dark | Use |
|---|---|---|---|
| `background` | `#F2F2F7` | `#0F172A` | screen bg |
| `surface` | `#FFFFFF` | `#192134` | cards |
| `surfaceMuted` | `#F2F2F7` | `#101A34` | skeleton/disabled fill |
| `onSurface` | `#1C1C1E` | `#F8FAFC` | primary text |
| `onSurfaceMuted` | `#8E8E93` | `#94A3B8` | secondary text |
| `divider` | `#E5E5EA` | `rgba(255,255,255,0.08)` | hairlines |
| `destructive` | `#F43F5E` (existing rose) | `#EF4444` | delete/over-budget |
| `success` | `#22C55E` (existing green) | `#059669` | done/synced/credit |

Section accents (indigo/teal/orange/violet/pink) stay the same hex in
both modes — just re-check contrast against `surface` dark value above.

## Typography option (if moving off system font)
If the team wants a named type system instead of `.SF Pro Text`: **Plus
Jakarta Sans** (single-family, geometric sans, reads well for
finance/productivity mobile, supports the full weight range this app
already uses — 400/500/600/700/800). Optional, not required — system
font is a legitimate zero-dependency choice for an iOS-first app.

## Priority order for implementation
1. Undo-delete (safety net for irreversible action — highest risk today).
2. Dark mode + semantic color tokens (biggest visible v2 differentiator).
3. Empty/loading/error state upgrade (cheap, high polish-per-effort).
4. Accessibility labels + touch target fixes (compliance, low effort).
5. Settings screen (unlocks configurable salary + appearance).
6. Charts (budget stacked bar, dealings waterfall).
7. Search/filter + hide-completed.
8. Segmented control → Cupertino native widget swap.
9. ListView.builder migration — only once list sizes justify it.
