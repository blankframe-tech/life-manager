# The canvas: an app that takes the user's shape

Branch `refresh`. Code in `lib/canvas/`, tests in `test/canvas/`.

## Why

Most life apps ship a philosophy: learn their way of doing things, or leave.
People try one, use it hard for a few days, and drift back to whatever has
the least friction: a pinned Google Keep note, a WhatsApp chat with
themselves, a budget sheet. That fallback *is* their system. They know where
everything is in it.

So the app does not ask people to adopt a system. It reads the one they
already have and becomes that:

- their headings become sections, **in the order they wrote them**;
- a list with prices stays a list, with a total;
- "Rahim owes me 500" becomes a who-owes-whom ledger;
- a long paragraph stays a paragraph;
- a small note becomes one page with **no bottom nav at all**; a lot of
  material splits into 2–6 tabs.

Everything runs on the phone. No model, no network.

## How it works

```
 pasted text / .txt / .md / .csv
              │
              ▼
   Shaper.compile  (lib/canvas/shaper.dart)     ← runs once per source
     • headings, bullets, checkboxes
     • amounts, dates, debts, people
     • CSV columns
              │
     sections (SectionSpec)  +  rows (Item)
              │                    │
              │                    └─► Isar, via SyncService (once; insert-if-absent)
              ▼
   layout(sections, overrides)  (lib/canvas/blueprint.dart)
              │
           Blueprint  ──► shape in SharedPreferences, words in Isar ──► CanvasShell draws it
```

### Memory instead of computation

| Work | When it runs | What is saved |
|---|---|---|
| Parse + classify a source | Once, when it is added | Its sections, under its content hash |
| Arrange sections into tabs | When a source is added or the user renames / hides / moves | The blueprint |
| Draw | Every launch | Nothing new: the blueprint is decoded and drawn |
| Section summaries (left, totals, net owed) | On render, from the live rows | Nothing (it is a fold over a few dozen rows) |

- Adding a second note never re-reads the first.
- Adding the same note again is recognised by its hash and skipped.
- A re-import writes only rows the database does not have, so edits, ticks
  and deletes made since are kept (uuids are v5 over section id + line).
- The raw text is **not** stored. Its rows are already in Isar (so in the
  encrypted vault).
- SharedPreferences (plaintext NSUserDefaults, which iOS backs up) gets only
  the shape: section ids, types, kinds, order and domains, under
  `canvas_state_v1`. The user's own words (file names, headings and
  renames) are a single `CanvasText` row in Isar, which is excluded from
  backups (`lib/models/canvas_text.dart`). A launch joins the two; a state
  saved by an older build is split on its first load.

### Rows are ordinary items

A section is a filtered view: `Item.kind == section.kind` and
`Item.section == section.id`. Kinds are the existing ones (`task`, `buy`,
`budget`, `txn`, `deal`, `note`, `dream`), so the classic module screens
(reachable from ⋯ → Modules, history & settings) show the same rows, Budget
math still works, and backup / vault / history need no change.

## The rules (deterministic)

**Blocks.** A heading is a markdown `#` line, a `**bold**` line, a short
line ending in `:`, an ALL-CAPS line, a line over `===`/`---`, or a short
plain line after a blank line that is either a known keyword ("Bazaar",
"Dreams") or followed by a list line. Lines before the first heading form a
block named after the source.

**Lines.** Bullets (`-`, `•`, `1.`), checkboxes (`[ ]`, `[x]`, `✓`, `~~done~~`),
amounts (`৳1,500`, `Tk 500`, `10k`, `1.5 lakh`, `Eggs 120`; Bangla digits;
a lone year like `2027` is not a price), dates (day-first `15/12`, `15 Dec`,
`Dec 15`, ISO, `today`, `tomorrow`, `by Friday`; whole words only, so
"wedding" is not Wednesday), debts (`owes me`, `lent`, `pabo` → owed to me;
`I owe`, `borrowed from`, `dibo` → I owe) and the person's name.

**Block → section.** The heading's keywords decide (Dena paona / owe /
loan → people; expense / spent → money log; budget / bills / monthly →
budget; bazaar / grocery / buy → shopping list; dream / goal → someday;
todo / tasks → checklist; notes / ideas → note), unless the lines clearly
disagree (a "Financial plan" written in sentences is a note). With no
heading keyword, the lines decide by majority. A headingless block that
mixes debts, prices and plain lines (a chat with yourself) is sorted line by
line into People / Money / Shopping / To-do / Notes sections.

**CSV.** Picks the amount, date, title, category and done columns by header
name or by content; keeps any other column in the row's note. A date column
makes it a money log (`txn`), no date makes it a budget, no numbers makes it
a checklist. Signed amounts read as money in / out.

**Layout.** Up to 5 visible sections, or one domain only → one page, no nav.
Otherwise one tab per domain (Money, People, To-do, Shopping, Dreams, Notes)
in the order they first appear; a domain with one section joins its family
(People → Money, Shopping → To-do, Dreams → Notes) unless the user moved it
there. Never more than 6 tabs.

**Hand edits** (section ⋯ → Rename / Move to tab / Hide) are overrides kept
apart from the compiled sections, so they survive every later re-shape.

## The blueprint JSON (the contract for a model later)

The layout is data, so the shaper can later be swapped for (or checked
against) a model with structured output that reads the same sources and emits
the same JSON. `Blueprint.fromJson` already treats input as untrusted: wrong
`format` or a newer `version` is refused, unknown section types and bad ids
are dropped, titles are clipped to 80 characters, tabs are capped at 6.

```json
{
  "format": "life-manager-canvas",
  "version": 1,
  "tabs": [
    {
      "id": "money",
      "title": "Money",
      "domain": "money",
      "sections": [
        { "id": "cv-1a2b3c4d-0", "title": "Monthly budget", "type": "ledger",
          "kind": "budget", "domain": "money", "order": 0 }
      ]
    }
  ]
}
```

`type` ∈ `checklist | ledger | people | notes | goals`;
`domain` ∈ `money | people | todo | shopping | goals | notes`;
`kind` is an `Item.kind`. A model would also have to emit the rows (as
`Item.toMap()` objects with `section` set); that half is not built.

## Where things are

| File | What |
|---|---|
| `lib/canvas/blueprint.dart` | `SectionSpec`, `CanvasTab`, `Blueprint`, `SectionOverride`, `layout()`. Pure Dart. |
| `lib/canvas/shaper.dart` | `Shaper.compile`, `quickItem` (the inline add field), `route` (the "Jot anything" field). |
| `lib/canvas/canvas_store.dart` | `CanvasNotifier` (preview / commit / rename / hide / move / reset), `writeNewItems`. |
| `lib/canvas/canvas_shell.dart` | `CanvasShell`, `CanvasPage`, `CanvasSectionView`. |
| `lib/canvas/morph_screen.dart` | "Shape it your way": paste, file, example, preview, apply. |
| `lib/canvas/samples.dart` | The example sources. Tests assert on this exact text. |

Entry points: onboarding page "Bring your own system", Settings → Layout,
and the wand button on every canvas page. `RootScaffold` draws the canvas
whenever one is saved; Settings → Layout → "Use the standard layout" forgets
the shape and keeps every row.

## Known limits / next

- The blueprint lives in SharedPreferences and Isar, not in the vault or
  backup file. Restoring a vault on a new phone brings the rows back (into the
  classic screens) but not the shape.
- `Shaper.version` is saved but nothing re-shapes old imports when the rules
  change (the raw text is gone by design). A re-import of the same text after
  a rules change is skipped as already present; Settings → Layout → standard,
  then shape again, re-reads it.
- English and Banglish keywords only; Bangla script headings fall back to
  content rules.
- Behaviour-driven adaptation (promote sections you open most, suggest a
  split when a section grows) is not built; the overrides map is where it
  would land.
