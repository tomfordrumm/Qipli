---
id: S030
title: Paste Stack в Top Notch
status: done
depends_on:
  - S007
  - S012
  - S021
  - S027
covers:
  - FR-007
  - FR-008
  - FR-009
  - FR-010
  - FR-011
  - FR-012
  - FR-013
  - FR-014
  - FR-015
  - FR-017
  - FR-036
  - BR-024
  - BR-027
  - BR-028
  - NFR-004
  - NFR-006
  - NFR-009
  - NFR-019
  - NFR-026
  - NFR-027
  - NFR-028
  - NFR-029
---

# S030: Paste Stack в Top Notch

## Пользовательский результат

Пользователь запускает и использует Paste Stack в той же верхней оболочке, что и History. Stack остаётся поверх текущего приложения, не забирает у него фокус, показывает порядок и прогресс серии и схлопывается обратно в область чёлки после Cancel или последней вставки. Отдельное перемещаемое окно Paste Stack больше не появляется.

## В scope

- отдельная reusable nonactivating Top Notch panel для Paste Stack, использующая общую с History safe-area geometry, чёрную форму, mask transition и Reduce Motion fallback;
- top-center fallback на дисплеях без camera housing и пересчёт frame при изменении screen parameters;
- Start/Collect по existing shortcut и status menu без активации Qipli, включая tagged source Copy и empty menu-start;
- горизонтальная ordered presentation text occurrences с bounded previews, явными position, Next, Processing, Used и reactivation-priority states;
- reorder ожидающих occurrences, direct/reverse direction и существующая блокировка порядка после начала traversal;
- Reactivate action, exact `⌘⇧Z`, retryable copy/capture/paste/input errors и text-only media notice;
- ordinary `⌘V`, self-write suppression, auto-finish, global Escape и explicit Cancel без изменения StackSession contracts;
- удаление standalone floating Paste Stack presentation из активного user path; сохранённая позиция старого окна больше не влияет на новый Top Notch frame.

## Вне scope

- специальное переключение или handoff между активным Paste Stack и History;
- compact always-visible indicator, hover expansion или idle auto-collapse незавершённого Stack;
- отдельное полноценное окно History, `Развернуть` и Favorites;
- media occurrences внутри Paste Stack, templates завершённых стеков или восстановление session после relaunch/crash;
- правое, левое или нижнее положение Top Notch;
- изменение ordinary `⌘V` вне active Stack, capture/persistence schema, retention, network или telemetry contracts.

## Системные и UI-контракты

- Общая оболочка означает общий shape/geometry/motion contract, а не один оконный lifecycle. History остаётся activating/key presentation с Search и History-only click-away. Stack использует отдельную `.nonactivatingPanel`, не вызывает `NSApp.activate`, `makeKey` или Search focus и не получает resign-key/outside-click dismissal hooks.
- Stack screen выбирается из текущего source/target context с bounded mouse/main/first-screen fallback. Геометрия использует фактические `safeAreaInsets`, auxiliary areas и `visibleFrame`; сохранённые координаты прежней floating panel не читаются для placement.
- Верхний anchor не двигается во время reveal/dismiss. Hidden state не оставляет Qipli surface или hit area; active незавершённый Stack остаётся раскрытым до Cancel/Escape/auto-finish.
- Ordered UI не создаёт второй long-lived occurrence array и не выполняет скрытый O(N²) next traversal. Preview остаётся bounded, exact full text используется только existing capture/paste paths.
- Mouse reorder, direction, Cancel и Reactivate не активируют Qipli и не переводят keyboard focus из внешнего приложения. Modified keys и text editing продолжают принадлежать target app.
- Finish сначала публикует консистентный all-used state, затем выполняет обратное схлопывание и `orderOut`; после этого menu возвращается в Start, а ordinary `⌘V` снова полностью системный.

## Acceptance criteria

- [x] `⌘⇧C` из приложения-источника показывает Paste Stack Top Notch на соответствующем display, не активирует Qipli и отправляет tagged ordinary Copy в ещё активное приложение; menu Start показывает тот же shell без Copy.
- [x] Empty, collecting и repeated collect сохраняют одну session; каждое внешнее text-copy создаёт отдельную ordered card, включая duplicates, Unicode и multiline text, без раскрытия полного payload в preview.
- [x] Pending cards можно переставлять до traversal lock; direct/reverse control, position и exact Next визуально и через VoiceOver соответствуют StackSession state.
- [x] Каждое accepted ordinary `⌘V` резервирует и отправляет ровно один exact occurrence; Processing, Used и следующий item публикуются без пропуска, duplicate или возврата self-write в History/Stack.
- [x] Reactivate и exact `⌘⇧Z` сохраняют существующий one-shot priority и traversal resume; retryable permission/write/dispatch/input failure не теряет occurrence и показывает non-payload error.
- [x] Click-away, Command-Tab и работа во внешнем приложении не скрывают Stack и не забирают focus. Global Escape и explicit Cancel отменяют session, скрывают shell после reverse transition и сохраняют History occurrences.
- [x] После последнего successful dispatch пользователь видит консистентный all-used state, затем shell схлопывается и полностью исчезает; последующий `⌘V` проходит системе.
- [x] Standalone movable Paste Stack window не показывается, не существует второй interactive Stack surface, а legacy saved origin не влияет на Top Notch placement.
- [x] Camera-housing и notchless placement, second display, full-screen Space, Light/Dark, Reduce Motion/Transparency, Increase Contrast и VoiceOver сохраняют читаемость, screen bounds и nonactivating behavior.
- [x] Existing History `⌘⇧V`, Search, arrow/Enter paste, Delete, click-away и captured-target contracts не регрессируют; отдельный active-Stack-to-History flow не является acceptance path.

## Verification

- pure presentation tests: Stack nonactivation, отсутствие History dismissal hooks, shared safe-area geometry, hidden/appearing/visible/dismissing transitions, screen change и legacy-position independence;
- focused Stack UI/state tests: empty/collecting, reorder/direction lock, Next/Processing/Used, reactivation priority, error states, duplicate/Unicode/multiline bounded previews и accessibility labels;
- existing S004–S007/S021 input/session/executor regression suites без изменения ordinary `⌘V`, self-write или auto-finish semantics;
- focused S027 geometry/mask/Reduce Motion tests и History keyboard/paste/click-away regression suite;
- full SwiftPM/Xcode test suite, signed Debug and unsigned universal Release builds, payload/log/network scan и `git diff --check`;
- manual camera-housing MacBook + notchless external display matrix: source Copy, menu-empty Start, reorder/direction, sequential paste, Reactivate/`⌘⇧Z`, cancel/Escape, auto-finish, two target apps, second display, full-screen Space и accessibility appearances. Setup: открыть source и target apps на проверяемом display. Expected: Stack всегда остаётся в Top Notch, target focus не теряется, exact sequence совпадает, после finish/cancel Qipli surface отсутствует.

## Implementation report

Реализовано в текущем рабочем срезе:

- обычная floating Paste Stack panel заменена на отдельную borderless nonactivating Top Notch panel с теми же safe-area geometry, `mainMenu + 3` level, чёрной поверхностью и `TopNotchHistorySurfaceView` mask contract, что и History;
- `⌘⇧C` и Start из status menu продолжают использовать существующие `StackCollectionStarter` и tagged Copy paths. Stack panel не активирует Qipli, не становится key и не устанавливает History keyboard/outside-click monitors;
- Stack UI переведён из вертикального `List` в горизонтальные bounded text cards. Карточки показывают exact position, bounded preview, Next/Processing/Used, Reactivate и deferred UUID-based reorder controls с VoiceOver actions;
- В Stack убраны нижние progress/direction подписи. Header теперь стоит у верхней границы панели, safe-area учитывается только при её placement и не съедает внутреннюю высоту, а карточки получили меньшую высоту и ограниченный трёхстрочный preview;
- screen parameter changes пересчитывают Stack frame и safe-area inset, повторно разрешая сохранённый display ID только среди подключённых экранов и используя fallback при отключении монитора. Legacy saved floating origin, drag region и move persistence удалены, поэтому старое положение не участвует в Top Notch placement;
- Cancel, global Escape и auto-finish используют отдельный generation-guarded reverse mask transition. `orderOut` выполняется после схлопывания; при Reduce Motion остаётся короткий opacity transition. Existing StackSession, input interception, self-write suppression, retry и ordinary `⌘V` contracts не менялись.

Focused SwiftPM UI/geometry/material suite после финальных изменений: `20/20`; полный SwiftPM suite прошёл `231/231`; unsigned Xcode Debug build завершился с exit code `0`; `git diff --check` прошёл.

После review исправлены два края: Stack теперь захватывает `preferredScreen` внешнего frontmost приложения перед показом, а повторный Start перед новой анимацией сбрасывает `ignoresMouseEvents` и отменяет stale transition через generation guard.

Manual MacBook camera-housing + external notchless display matrix подтверждена пользователем: nonactivation/focus, source Copy, menu Start, reorder/direction, sequential paste, Reactivate/`⌘⇧Z`, Escape/Cancel, auto-finish, second display, full-screen Space и accessibility appearances.

Известное принятое ограничение вынесено в BL-006: отключение внешнего дисплея именно во время reveal может оставить panel на прежнем экране до завершения перехода. Это не блокирует принятую пользовательскую матрицу S030.
