---
name: poni-localize
description: Keep Poni translated. Indonesian is the source language and en.lproj/Localizable.strings maps it to English; use whenever adding or changing user-visible text, and to find strings that slipped through untranslated.
---

# Localizing Poni

The app follows the macOS language: Indonesian, or English for anything else.
`Resources/en.lproj/Localizable.strings` uses the **Indonesian text as keys**; `Resources/id.lproj`
only marks Indonesian as supported. `scripts/bundle.sh` copies both into `Poni.app/Contents/Resources`,
and `Info.plist` declares `CFBundleDevelopmentRegion = id` and `CFBundleLocalizations = [id, en]`.
Permission prompts are in `Resources/en.lproj/InfoPlist.strings`.

## Writing text in code

- **Literal in a view translates itself**: `Text("Simpan")`, `Button("Batal")`, `.help("…")`, `Label("…", systemImage:)`.
  With values: `Text("Skor \(score)")` → key `Skor %lld`; `Text("\(name) disalin")` → key `%@ disalin`.
- **A `String` variable does not**: `Text(title)` shows it verbatim. Shared components already wrap
  their titles in `tr()` (Card, Switch, Tile, Action, ToggleTile, StatusPill, NButton, Chip, Placeholder,
  FeatureChip, tab titles, `.tip()`, `confirm()`, toasts). Elsewhere use `Text(tr(value))`.
- **Don't interpolate a `String` into a literal for a word that needs translating**: in
  `Text("\(h)j \(m)m \(charging ? "sampai penuh" : "tersisa")")` the inner words never translate.
  Split it: `Text(charging ? "\(h)j \(m)m sampai penuh" : "\(h)j \(m)m tersisa")`.
- **Messages built in models** (`"Gagal: \(err)"`) can't be looked up after the fact. When one matters,
  build it with `String(format: tr("Gagal: %@"), err)`.
- **Dates**: format with `.locale(appLocale)` (the app's language), never a hard-coded `id_ID`.
  For calendars set `cal.locale = appLocale` but keep `cal.firstWeekday = Calendar.current.firstWeekday`
  so weekday headers line up with the grid.
- **Leave alone**: Belajar Bahasa content (meanings are for Indonesian learners), AI prompts, AppleScript,
  data such as branch names or file names.

## Adding translations

```sh
python3 .claude/skills/poni-localize/add_strings.py '{"Putar di %@": "Play in %@", "Hapus semua": "Clear all"}'
plutil -lint Resources/en.lproj/Localizable.strings
```

Write every interpolation as `%@`; the script writes the `%@`/`%lld`/`%%` variants SwiftUI asks for.
Words that are the same in both languages ("Git", "Clipboard") don't need an entry; a missing key just
shows the original text.

## Finding untranslated text

Render in English with the poni-ui-check skill:
`.claude/skills/poni-ui-check/snap.sh <scratchpad>/shots-en en`.
`NSShowNonLocalizedStrings` turns every missing string into **CAPITALS**, so anything Indonesian or
upper-cased in the PNGs needs a key (or is a `String` that needs `tr()`).

To try the real app in English without changing the system:
`defaults write io.github.lshinkuro.BateraiSafer AppleLanguages -array en`, launch,
then `defaults delete io.github.lshinkuro.BateraiSafer AppleLanguages`.
