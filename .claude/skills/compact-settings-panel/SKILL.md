---
name: compact-settings-panel
description: Interface conventions for the settings panel on the right of the X1 Scan window (app/X1Scan/Panel, app/X1ScanCore/Sources/X1ScanCore/UI). Use whenever adding, changing or reviewing a control, row or section of that panel, so that it stays dense, aligned, translated, accessible and correct in light and dark mode.
---

# Compact settings panel

The panel on the right of the main window holds the scan and export
settings. It is a working tool used for hours: dense, quiet and aligned, with
every number readable and editable in one place. These rules apply to every
section of the panel. Sections not converted yet still use
`PanelSectionView` / `PanelRow` in `SettingsPanelView.swift`; convert them
with the components below when they are touched.

## Components (X1ScanCore, `Sources/X1ScanCore/UI/CompactPanel.swift`)

- `CompactSection(title, foldTexts:, isExpanded:) { … }`: a foldable
  section. `foldTexts` is `Strings.foldTexts` (VoiceOver "expanded" /
  "collapsed"); `isExpanded` is `model.panel.expansion(of: section)`.
- `CompactDisclosureStyle(texts:isHeader:)`: the disclosure style of the
  panel (one button for chevron and title, content not indented).
  `CompactSection` uses it with the header trait, and gives its content the
  same style without it.
- `CompactSliderRow(value:format:texts:)`: a number on one row. `texts`
  comes from `Strings.sliderRow(label:unit:format:)`; for an `Int` setting,
  `value` is `Binding(rounding: $model.…)`.
- `CompactInfoRow(label, value:)`: a read-only value on one row.
- `CompactPanelMetrics`: the grid (label column, field and unit widths,
  column, row and group spacings, content inset, section insets). Use these
  constants; do not hard-code sizes.
- In `Panel/` (no interface, tested in `CompactPanelTests.swift`; extend the
  tests when they change):
  - `CompactValueFormat`: range, default, step, digits, formatting and
    parsing of a number;
  - `CompactFieldState`: the text of a numeric field; only typed text is
    applied;
  - `PanelController.expansion(of:)` (in `UI/`): the folded state of a
    section or sub-group, saved with the panel layout.

These views hold no setting and produce no interface text: the application
passes every string, already translated (see Text and languages).

## Type and spacing

- System font only. Rows in `.callout`; notes, warnings and secondary
  information in `.caption`; section titles in `.callout` semibold. No other
  sizes, no custom fonts.
- Small controls: the panel sets `.controlSize(.small)`; do not override it
  inside a section.
- Tight spacing: `CompactPanelMetrics.rowSpacing` between rows, section
  insets from `CompactPanelMetrics.sectionInsets`. No blank lines made of
  spacers or extra padding.
- Numbers use `.monospacedDigit()` so that they do not jump while they
  change.
- Notes stay short and wrap (`.fixedSize(horizontal: false, vertical: true)`);
  long explanations belong in tooltips or the documentation, not the panel.

## Sections

- One `CompactSection` per group of settings, with a short title (one or two
  words) that fits on one line in both languages.
- Folded state is remembered between launches: bind `isExpanded` to the
  panel layout (`model.panel.expansion(of: section)`); add a `PanelSection`
  case for a new section. All sections are open at first launch.
- A sub-group inside a section (for example a histogram) is a
  `DisclosureGroup` bound with `model.panel.expansion(of:)`, without its own
  separator. Inside a `CompactSection` it gets `CompactDisclosureStyle`
  without the header trait; outside one, apply
  `.disclosureGroupStyle(CompactDisclosureStyle(texts: Strings.foldTexts))`.
- Clicking the title folds and unfolds, not only the chevron. The title is
  marked as a header for VoiceOver.

## Rows and the grid

- Every row starts with a label column of `CompactPanelMetrics.labelWidth`,
  secondary colour, one line, leading aligned. Controls of all rows start at
  the same x.
- A number is a `CompactSliderRow`, on one line:
  - label on the left;
  - slider in the middle, taking the remaining width;
  - editable field on the right, fixed width (`fieldWidth`), digits trailing
    aligned;
  - unit after the field, in its own fixed column (`unitWidth`), secondary
    colour (`ppi`, `%`, …). Empty unit: an empty column, the grid stays.
- The field accepts what people type: comma or full stop as decimal
  separator, spaces and apostrophes ignored. Return or leaving the field
  applies the value, and so does folding the section or changing tab while
  typing; a text that is not a number shows the current value again.
  Clicking into the field without typing never changes the value. Values are clamped to the range and the step. The field shows the
  locale's decimal separator, without grouping.
- A double-click on the label restores the default value. The label's
  tooltip says what that default is (value and unit). VoiceOver gets the same
  action as a named accessibility action.
- Choices are pickers with hidden labels (`.labelsHidden()`), placed in the
  control column after the label. Read-only values are `CompactInfoRow`.

## No decoration

- No boxes, cards, backgrounds, shadows or rounded containers around rows or
  sections. Structure comes from alignment, spacing and one thin `Divider`
  under each section.
- No icons in labels unless the icon is the control (a menu or a tool).
- Colour only for meaning: secondary for labels and units, the system
  warning and error colours for warnings and errors. Never a fixed colour
  for text or backgrounds.

## Text and languages

- The interface is in English and French, following the system language
  (Settings can force one). Every visible string, tooltip and VoiceOver text
  goes through the application's String Catalog
  (`app/X1Scan/Localization/Localizable.xcstrings`): `String(localized:
  comment:)` or `Text(_:comment:)` in the application target, typed helpers
  in `Strings.swift` for composed texts.
- Every new key gets its French translation in the catalogue, state
  `translated`, and a `comment` that tells a translator where it appears.
  `Text(verbatim:)` only for text that is the same in every language
  (a unit symbol such as `%`, a file name).
- Check that the French text fits the label column; shorten the wording
  rather than widening the column.
- X1ScanCore has no catalogue: its components receive translated strings
  (for example `CompactSliderRow.Texts`, built by `Strings.sliderRow`).

## Light and dark mode

- Semantic colours and materials only (`.primary`, `.secondary`,
  `Divider`, system control styles), so that light and dark mode follow the
  system and the app's Appearance setting with no extra code.
- Images drawn by the app (histogram, previews) must stay readable on both
  backgrounds.

## Accessibility

- Every control has a label for VoiceOver, even when its visible label is
  hidden or drawn separately: pass the label to the control and hide the
  duplicate text (`.accessibilityHidden(true)` on the separate label).
- Sliders speak their value with the unit (`accessibilityValue`).
- Anything reachable only by a gesture (double-click on a label) also exists
  as a named accessibility action.
- Read-only rows combine label and value into one element.
- Keyboard: every field and control is reachable with Tab; Return applies a
  field.

## Width and scrolling

- The panel content is laid out for a fixed width: rows do not stretch or
  reflow when the window changes. Content that does not fit vertically
  scrolls in the panel's `ScrollView`; the Preview and Scan buttons stay
  fixed below it.
- Note: the panel is resizable today (260-640 pt, docs/decisions.md, step
  3). Until that decision changes, a row must look right at 260 pt and not
  spread out at 640 pt: fixed columns, the slider takes the free space.

## Checking a change

- `swift test` in `app/X1ScanCore`.
- Build the app and take a debug snapshot (`-X1ScanSnapshot`, see
  `DebugSnapshot.swift`) with `-StartupSource virtual`, in light/English and
  dark/French (`-Appearance dark -AppleLanguages "(fr)"`). Save your
  preferences first (`defaults export org.x1scanarm.X1Scan`) and import them
  back after; write the images outside the repository.
- The offscreen snapshot does not draw native controls correctly in dark
  mode (they come out as white blocks): judge dark mode on screen.
- Run the `x1-ui` subagent on the change before committing, as well as
  `x1-reviewer`.
