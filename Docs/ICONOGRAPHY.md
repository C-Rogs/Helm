# Helm iconography

Normative icon catalog for the `DesignSystem` package. All in-app symbols route through `HelmIcon` and `HelmIconView` so weight and size stay consistent per context.

## Contexts

| Context | Size | Weight | Use |
|---|---|---|---|
| `tab` | 22pt | medium | Tab bar items |
| `section` | 20pt | regular | Empty states, section headers |
| `inline` | 15pt | regular | Row adornments, banners, chips |
| `action` | 28pt | semibold | Composer send, primary icon actions |

## Arc-trace motif

Dashboard and section eyebrows use the arc gauge symbol (`gauge.with.dots.needle.67percent`) or the `HelmArcTraceMark` ornament. Tab Dashboard uses the gauge symbol; other tabs use their domain glyph at tab weight.

`HelmSectionEyebrow` prepends `HelmArcTraceMark` by default. Pass `showsArcMark: false` for error or system labels.

## Catalog

| `HelmIcon` | SF Symbol | Context | Notes |
|---|---|---|---|
| `dashboard` | `gauge.with.dots.needle.67percent` | tab, section | Arc motif; readiness and home |
| `train` | `dumbbell` | tab, section | Workout logging |
| `nutrition` | `fork.knife` | tab, section | Macro targets and logging |
| `chat` | `bubble.left.and.bubble.right` | tab, section | Coach thread |
| `settings` | `gearshape` | tab | App configuration |
| `health` | `heart.text.square` | section | HealthKit and onboarding |
| `trends` | `chart.xyaxis.line` | section | Trends and charts |
| `chevronRight` | `chevron.right` | inline | Navigation affordance |
| `info` | `info.circle` | inline | Explain affordance |
| `checkmark` | `checkmark.circle` | inline | Set completion (outline) |
| `checkmarkFilled` | `checkmark.circle.fill` | inline | Completed set |
| `circle` | `circle` | inline | Incomplete set |
| `scale` | `scalemass` | inline | Volume readout |
| `trash` | `trash` | inline | Destructive row action |
| `plus` | `plus.circle.fill` | inline | Add exercise |
| `send` | `arrow.up.circle.fill` | action | Chat composer |
| `mic` | `mic.fill` | action | Chat food dictation |
| `refresh` | `arrow.clockwise` | inline | Pull to refresh toolbar |
| `photo` | `photo.on.rectangle` | inline | Photo meal picker |
| `camera` | `camera.fill` | inline | Camera meal capture |
| `search` | `magnifyingglass` | inline | Food search |
| `barcode` | `barcode.viewfinder` | inline | Barcode scanner |
| `offline` | `wifi.slash` | inline | Coach degraded banner |
| `swap` | `arrow.triangle.swap` | inline | Adjustment banner |
| `arrowRight` | `arrow.right` | inline | Adjustment from-to |
| `empty` | `tray` | section | Generic empty state |
| `error` | `exclamationmark.triangle` | inline | Error state |
| `coach` | `bubble.left.and.bubble.right.fill` | tab | Filled coach variant (legacy tab) |

## Rules

- Do not call `Image(systemName:)` in feature views; use `HelmIconView` or `Label(_, helmIcon:)`.
- Tab icons use outline glyphs except where iOS tab bar expects fill; Dashboard keeps the arc gauge in all appearances.
- Inline icons inherit `fgMuted` unless state-colored (depleted for errors, accent for active send).
- No decorative icons without a semantic role.
