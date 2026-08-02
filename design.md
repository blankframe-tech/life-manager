# Design — Life Manager UI/UX reference

Read this to know the feel and capability without running the app.

## Look and feel
iOS-native grouped-list style (Cupertino icons + Material widgets, SF Pro
Text font). Soft grey background, white rounded cards with subtle shadow,
thin hairline dividers. Bottom tab bar, floating add button, bottom-sheet
editor. Cupertino page transitions on both iOS and Android.

## Screen hierarchy
```
RootScaffold (Scaffold, IndexedStack keeps all 5 mounted)
├── AppBar — section title (center), cloud icon (sync status) top-right
├── Body — one of 5 screens, swapped by bottom nav, state preserved
│   ├── BudgetScreen
│   ├── DealingsScreen
│   ├── ChecklistScreen (kind=task)
│   ├── ChecklistScreen (kind=buy)
│   └── DreamsScreen
├── FloatingActionButton — opens item editor sheet, colored per section
└── NavigationBar (bottom, 5 destinations, height 64)
```

Each list screen shares the same skeleton:
`summary/balance card → groupHeader (uppercase, small caps label + trailing
stat) → cardGroup (rounded white card, rows separated by rowDivider) →
"add" row → swipe-to-delete on every row (DeletableRow, red background,
trash icon, endToStart swipe)`.

### Budget
- Summary card: salary total (large, bold) + 3 progress rows (Needs 65% /
  Savings 20% / Wants 15%), each a thin progress bar, red when over ideal.
- One card group per category, rows show title + amount, trailing "Add to
  X" row with a colored plus icon.

### Dealings ("Dena Paona" ledger)
- Balance card: two stat columns (I owe / red, Owed to me / teal) split by
  a vertical hairline, plus a pill banner below showing net position
  (teal if positive, rose if negative).
- Three optional groups: "I owe", "Owed to me", "Notes & assets" — each a
  card group of rows (title, optional note line, signed amount in
  compact-K format, colored by direction).

### Tasks / Buy (ChecklistScreen, shared component)
- Grouped by fixed sections (Tasks: time-sensitive / admin & tech /
  declutter — Buy: Priority 0 / Wishlist), plus a catch-all "Other" group.
- Group header shows "$n left" count.
- Each row: tappable circle checkbox (fills with section color +
  checkmark when done), title (strikethrough + grey when done), optional
  note, optional due-date badge (pill, calendar icon, red if due ≤3 days).

### Dreams
- No groups — one card per dream, full-bleed pink→violet gradient tile,
  sparkle icon + title in white. No amounts, no dates.

### Empty states (any screen with 0 items)
Centered: large hairline-grey icon, bold title, grey subtitle.

## Item editor (bottom sheet, all 5 kinds share one component)
Rounded-top sheet, drag handle, title "New/Edit {Section}":
1. Title field (required, autofocus on add)
2. Kind-specific segmented control (pill buttons, selected = filled with
   section color, white text):
   - Deal: "I owe" / "They owe me"
   - Budget: "Needs" / "Wants" / "Savings"
   - Task: "Time-sensitive" / "Admin" / "Declutter" + due-date row (Pick
     date / Clear buttons)
   - Buy: "Priority 0" / "Wishlist"
3. Amount field (deal/budget/buy only, numeric, ৳ optional)
4. Notes field (multiline, all kinds)
5. Full-width filled "Add" / "Save changes" button, background = section
   color.

## Capabilities
- Add / edit / delete (swipe) any item across 5 kinds.
- Toggle task/buy done state inline (tap checkbox).
- Due dates on tasks with a "due soon" (≤3 days) visual warning.
- Live budget math: planned vs ideal 65/20/15 split against a fixed
  monthly salary constant, over-budget rows flip red.
- Live dealings math: sums debts/credits, shows net position.
- Offline-first: every screen reads/writes Isar instantly; a background
  SyncService pushes to Supabase and pulls realtime changes across
  devices. Cloud icon in the app bar shows online/offline (grey =
  offline/syncing, green = online).
- Soft delete: swiping a row marks it a tombstone (propagates the delete
  to other devices) rather than hard-deleting locally.

## Color scheme
| Token | Hex | Use |
|---|---|---|
| `bg` | `#F2F2F7` | screen background (iOS grouped) |
| `card` | `#FFFFFF` | card / row surface |
| `ink` | `#1C1C1E` | primary text |
| `inkSub` | `#8E8E93` | secondary text |
| `hair` | `#E5E5EA` | dividers, empty-state icons |
| `indigo` | `#5B5BD6` | Budget / brand / app seed color |
| `teal` | `#14B8A6` | credit, "they owe me", online |
| `rose` | `#F43F5E` | debt, "I owe", over-budget, delete, due-soon |
| `orange` | `#F97316` | Tasks |
| `violet` | `#8B5CF6` | Buy |
| `pink` | `#EC4899` | Dreams |
| `green` | `#22C55E` | synced/online indicator |

Each of the 5 sections owns one accent color, used consistently for: its
nav icon (filled when active), its FAB, its checklist checkbox fill, its
editor's selected segment and save button. Dreams additionally uses a
pink→violet gradient tile instead of a flat color.

## Buttons / controls inventory
- **FAB** (circle, section-colored, white plus icon) — per-screen add.
- **NavigationBar** (5 destinations, white bg, active icon tinted +
  14%-alpha color pill indicator, 11px bold label).
- **Segmented pill selector** (custom `Wrap` of tap targets, not native
  Cupertino segment) — filled/colored when selected, white bg + ink text
  otherwise.
- **FilledButton** — full-width, rounded 12px, section color — the
  editor's primary save/add action.
- **TextButton** — "Pick date" / "Clear" in the task due-date row.
- **Swipe-to-delete** (Dismissible, end-to-start, rose background + trash
  icon reveal).
- **Inline tap targets** — "Add to {category}" row (plus icon + indigo
  text), checkbox circle (task/buy done toggle).
- Text inputs: filled rounded rect (12px radius), no visible border,
  card-white fill, placeholder-only labels (no floating labels).
