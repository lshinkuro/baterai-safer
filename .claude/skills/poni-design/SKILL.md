---
name: poni-design
description: Poni's design system (monochrome + mint, "premium" look) and UI conventions. Use before adding or changing any view so new screens match: tokens, components, color meaning, type scale, motion, accessibility.
---

# Poni design system

Look: **monochrome base + one mint accent**, hairline cards, quiet type. Color is used only where it
carries meaning. Tokens and shared components live in `Sources/baterai-safer/UI.swift` (popover) and
the "Island building blocks" section of `Notch.swift` (notch, always dark).

## Color

| Use | Token |
|---|---|
| Brand accent: active tab, primary button, toggles, selected chip/day | `Palette.accent` (mint `#34D399`) |
| Text/icons on an accent fill | `Palette.onAccent` (black 85%), never white |
| Card border | `Palette.hairline` (popover) / `.white.opacity(0.07)` (notch) |
| Success / good | `Palette.green` (or accent when it's "healthy") |
| Warning / needs attention | `Palette.amber`, only amber |
| Error / danger / destructive | `Palette.red` |
| Secondary text | `.secondary` (popover), `.gray` (notch) |

- No per-feature colors, no colored glows or shadows, no system `.red/.green/...`; use `Palette`.
- Status colors come from flags in the model (`failed`, `ok`), never from matching message text.
- **Data may be colored by its value** (Battery tab): hero glyph and glow, tile icon and bar, chart line
  by value (mint → amber → red). Thresholds: battery >40% or charging mint, 21–40% amber, ≤20% red;
  temp <35° mint, <40° amber; health ≥80% mint, ≥60% amber; cycles <800 mint.
- Content-driven color is fine: album-art glow, calendar colors, app icons.

## Components (reuse; don't hand-roll)

Popover: `Card(title:icon:)` (title renders as small caps), `Hero(theme:)` (near-black card; `theme.a` is
only a faint glow: `.mint`, or `.rose` for danger), `Tile(icon:title:value:tone:fraction:)`,
`Switch`, `IconBadge(icon:tint:)` (neutral; tinted only when "on"), `Action`, `ToggleTile`,
`StatusPill`, `Ring`, `Meter`, `TabBar`.
Notch: `NCard`, `NButton(icon:title:tint:prominent:)` (prominent = mint fill + dark text), `Chip`,
`Placeholder` (every empty state), `Equalizer`.
Segmented pills: selected = `Palette.accent` fill + `Palette.onAccent` text, others gray.

## Type, shape, motion

- SF Pro, not `.rounded`. Weights up to `.semibold`/`.bold`; no `.heavy`/`.black`.
- Sizes are whole points: 9 · 10 · 11 · 12 · 13 · 15 for text; 20+ for numbers and heroes.
- Corner radius: 4 (chart bars) · 6 (rows, chips) · 10 (inputs, small cards) · 16 (tiles) · 18 (cards) · 22 (hero).
- Motion: `Motion.snap` (taps, open/close) and `Motion.ease` (fades, value changes). Both return nil under
  Reduce Motion. Don't add new curves; animated `TimelineView`s pause with `paused: Motion.reduced`.

## Behavior

- Icon-only buttons use `.tip("…")`: tooltip **and** VoiceOver name.
- Destructive actions ask first with `confirm(title, info, button)` (quit, delete event, uninstall, clean).
- Per-row actions are visible (a `⋯` menu) and mirrored in `.contextMenu`; don't hide them behind a bare click.
- Text the user sees goes through localization (see the poni-localize skill).
- The notch is 720×300 and closes when the pointer leaves it in hover mode: keep pickers and choosers
  inline inside the card, not in popovers.
- Check the result with the poni-ui-check skill.
