# Recolly — Figma → Flutter design system rules

Use these rules when turning Figma frames (via the Figma MCP `get_design_context`) into Flutter code.
The MCP output (React/Tailwind) is a **reference only** — always re-express it with the tokens and widgets below.

## 1. Frameworks & build
- Flutter (Dart SDK ^3.13), Material 3 (`useMaterial3: true`), target Android. Build: `flutter pub get && flutter run`.
- No CSS/web stack, no codegen, no token pipeline. Tokens are hand-written Dart constants.
- Charts: `fl_chart`. Images: `image_picker`. Lints: `flutter_lints`.
- Do not add new packages (e.g. `flutter_svg`, `google_fonts`) without asking — `pubspec.yaml` is a foundation file.

## 2. Design tokens — `client/lib/core/theme/` (foundation, ask before editing)
Import everything with one line: `import 'package:client/core/theme/app_theme.dart';` (re-exports colors + typography).

| Figma concept | Dart token | File |
|---|---|---|
| Color styles / variables | `AppColors.cream, teal, green, coral, yellow, white, ink, inkMuted, slate, deepSlate, disabled, skeleton, danger` | `app_colors.dart` |
| Text styles | `AppTypography.display(40/800), title(28/800), subtitle(18/800), body(15/400), label(13/600), caption(12/400), button(15/800)` | `app_typography.dart` |
| Spacing | `AppSpacing.xxs 4, xs 8, sm 12, md 16, lg 24, xl 32, xxl 48, whitespace 100` | `app_theme.dart` |
| Corner radius | `AppRadii.card 16, input 12, pill 999` (+ `cardAll`, `inputAll`, `pillAll`) | `app_theme.dart` |
| Stroke | `AppBorders.width 2.5`, `AppBorders.side` (ink) | `app_theme.dart` |
| Drop shadow | `AppShadows.hard` (ink, offset `0,4`, blur 0), `AppShadows.none` | `app_theme.dart` |
| Box style | `AppTheme.brutalBox(color:, borderRadius:, hasBorder:, hasShadow:)` | `app_theme.dart` |

Rules:
- Map every Figma hex to the nearest `AppColors` token. Never write `Color(0x…)` in feature code. If a Figma color has no token, stop and ask Member 3 (owner of the theme) to add it.
- Font is **Be Vietnam Pro** (bundled in `assets/fonts/`, weights 400/600/800 only). Snap other Figma weights to these three.
- Snap Figma spacing to the `AppSpacing` scale; snap strokes of 2–3px to `AppBorders.width`.
- Shadows have **zero blur**. Note: the code uses offset `(0, 4)`, while `.claude/CLAUDE.md` says ~`4px 4px` — follow the code; flag the mismatch if a design uses `4,4`.
- `AppTheme.light()` already themes Material widgets (buttons, inputs, chips, dialogs, switches, snackbar, dividers). Prefer theme-driven Material widgets over re-styling them per screen.

```dart
Container(
  padding: const EdgeInsets.all(AppSpacing.md),
  decoration: AppTheme.brutalBox(color: AppColors.yellow),
  child: Text('Hôm nay', style: AppTypography.subtitle),
);
```

## 3. Component library — `client/lib/widgets/` (barrel: `widgets.dart`)
Reuse before building. Figma component → Dart widget:

| Figma component | Widget | Key params |
|---|---|---|
| Card | `BrutalCard` | `color`, `borderStyle: solid/dashed`, `hasShadow`, `padding` |
| Primary/secondary button | `BrutalButton` | `label`, `onPressed` (null = disabled), `color`, `icon`, `leadingIcon`, `leading`, `expanded` |
| Icon button | `BrutalIconButton` | `icon`, `shape: circle/square`, `size 48`, `iconSize 20` |
| Badge / tag | `BrutalBadge`, `ChronotypeBadge` | `label`, `color`, `icon` |
| Progress bar | `BrutalProgressBar` | — |
| Bottom nav | `BrutalBottomNavBar` | — |

```dart
import 'package:client/widgets/widgets.dart';

BrutalButton(label: 'Lưu', onPressed: _save, color: AppColors.green);
```

- Architecture: plain `StatelessWidget`/`StatefulWidget`, constructor params with token defaults. Pressed state = shift by `AppShadows.offset` and drop the shadow (see `brutal_button.dart`).
- Widgets used by one feature only go in `features/<feature>/widgets/`. Promote to `lib/widgets/` only when 2+ features need it.
- No Storybook. The living catalog is `features/theme_gallery/theme_gallery_page.dart` (palette, type scale, cards, buttons, badges, Material samples). Add new shared widgets there.
- Code Connect: none set up yet. If added, map Figma components to the widgets in the table above.

## 4. Project structure
```
client/lib/
  main.dart, app.dart        # entry + MaterialApp(theme: AppTheme.light()) — foundation
  core/                      # theme/, di/repository_scope.dart, api_client, storage — foundation
  data/                      # models/, repositories/, api/, mock/ (see data/README.md)
  widgets/                   # shared Brutal* widgets
  features/<feature>/        # *_page.dart / *_screen.dart, widgets/, <feature>_data.dart
```
Features: `auth, calendar, personal, sleep, sync, theme_gallery, timetable, today, todo, welcome_screens`.
Data comes through `RepositoryScope` (from `core/di/`), never by calling HTTP from a widget.

## 5. Assets & icons
- Raster assets live flat in `client/assets/` and **must be listed one by one** in `pubspec.yaml` (`assets/splashLogo.png`, `phones.png`, `trophy.png`, `google_logo.png`, …). Reference by path: `Image.asset('assets/trophy.png')` / `AssetImage(...)`.
- Export Figma images as PNG (2x–3x) into `assets/`, camelCase or snake names as existing; no CDN, no build-time optimization. `precacheImage` for images shown in dialogs (see `motivation_dialog.dart`).
- Icons: Material `Icons.*` only, prefer the `_outlined` / `_rounded` variants (e.g. `Icons.bedtime_outlined`, `Icons.edit_outlined`). No SVG support is installed — map Figma icons to the closest Material icon; brand logos use a PNG (see `features/auth/widgets/google_logo.dart`).

## 6. Styling & layout
- No CSS: style via `ThemeData` (global) + tokens (local). Background is `AppColors.cream` (scaffold default).
- Phone-first, single column. Responsiveness is minimal (`MediaQuery`/`LayoutBuilder` used in only a few places). Use `Flexible`/`Expanded` + `TextOverflow.ellipsis` instead of fixed Figma widths; keep Figma frame width (~360–412dp) as guidance, not hard sizes.
- Accessibility: wrap custom tappables in `Semantics(button: true, …)` like `BrutalButton`/`QuoteCard`.
- UI strings are Vietnamese; code and comments English.

## 7. Workflow for a Figma frame
1. `get_design_context` + `get_screenshot` for the node.
2. Map colors/text/spacing/radius/stroke/shadow to tokens (section 2).
3. Map components to `lib/widgets/` (section 3); build feature-local widgets for the rest.
4. Place the screen in `features/<feature>/`, data via repositories.
5. Check against the screenshot; add a widget test in `client/test/` (golden tests exist in `test/goldens/`).

## Known drift (report to owner, do not fix outside your area)
- `features/today/widgets/barchat.dart:252,259` hardcodes `Color(0xFFE88B73)` — should be a token (coral?). Owner: Member 3.
- `features/calendar/week_calendar_page.dart:20` defines `skeletonColor = Color(0xFFE4DFD2)` ≈ `AppColors.skeleton (0xFFE5DFD2)`. Owner: Member 2.
- Shadow offset `(0,4)` vs CLAUDE.md `4px 4px`.
