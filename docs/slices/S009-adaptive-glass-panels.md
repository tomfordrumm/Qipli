---
id: S009
title: Адаптивные стеклянные панели
status: done
depends_on:
  - S001
  - S003
  - S007
covers:
  - FR-017
  - NFR-001
  - NFR-005
  - NFR-009
---

# S009 — Адаптивные стеклянные панели

## Пользовательский результат

History, Paste Stack и Permission выглядят как единая нативная стеклянная система: на новых macOS используется настоящий Liquid Glass, а на macOS 14–25 — близкий системный material fallback без потери читаемости, focus или привычного window chrome.

## В scope

- общий AppKit material boundary для всех временных панелей;
- один `NSGlassEffectView` style `regular` на panel в macOS 26+;
- один `NSVisualEffectView` с семантическим material `.popover`, `.behindWindow` blending и системным active/follows-window state на macOS 14–25;
- прозрачный window background и визуально единая title bar при сохранённых native close/drag semantics;
- системные label/control colors без appearance-specific hardcode;
- компактная in-panel IA-polish для History, Paste Stack и Permission при сохранении existing intent/state boundaries;
- Light/Dark Mode, Reduce Transparency и Increase Contrast;
- сохранение размеров, multi-display placement, Spaces/full-screen behavior и keyboard/nonactivating contracts существующих панелей.

## Вне scope

- повышение deployment target выше macOS 14;
- Liquid Glass style `clear`, custom tint или отдельный glass effect на каждой строке/кнопке;
- borderless panel, custom traffic lights, custom window dragging или новая анимационная система;
- широкий редизайн информационной архитектуры History/Paste Stack/Permission за пределами явно описанного компактного panel polish;
- app icon, menu bar icon, release signing/notarization и S008;
- изменение clipboard, history, stack, focus или global-input business logic.

## Предусловия

- S001, S003 и S007 завершены; их panel lifecycle/focus contracts являются regression boundary.
- Сборка использует SDK, содержащий `NSGlassEffectView`, но deployment target остаётся macOS 14.
- S008 может оставаться `blocked`: paid Developer ID не нужен для локальной реализации и проверки S009.

## Ожидаемое поведение

- На macOS 26+ panel content помещается в один regular Liquid Glass surface; system chrome и стандартные controls получают актуальное системное оформление.
- На macOS 14–25 тот же content помещается в один semantic standard-material surface без ссылки на недоступный runtime symbol.
- History по-прежнему активируется, получает Search focus и восстанавливает target при paste/cancel.
- Paste Stack по-прежнему остаётся nonactivating и не забирает focus у source/target app.
- Permission сохраняет существующие injected request/settings actions и native keyboard/accessibility behavior: native title — единственный heading, state даёт один concise sentence и ровно одну кнопку (`Allow Access` для `notRequested`, `Open System Settings` для `denied`/`granted`). Compact 360×150 content area вмещает двухстрочный текст и action без изменения title/close/material/nonactivation/Spaces contracts.
- History использует native window title как единственный заголовок: Search и Clear All находятся в одной верхней строке; отдельной нижней кнопки Paste нет, но Enter и double-click exact selected entry сохраняют paste. Search — compact neutral system shell с VoiceOver hint для filter/Up/Down, без меняющегося blue focus outline, но с реальными native caret/focus semantics. Delete — нативная SF Symbol `trash` button с accessibility label/help; при пустом Search локальный `⌫`/Delete удаляет exact selected occurrence через тот же deferred delete path, но при непустом Search всегда остаётся обычным text editing. Selected row имеет subtle rounded surface и outline системного accent color, не отдельный material layer.
- Paste Stack использует native title как единственный заголовок и даёт List занять primary content area. Единственная верхняя compact control — icon toggle направления: `arrow.down` означает direct/top-to-bottom, `arrow.up` — reverse/bottom-to-top; она вызывает existing deferred direction intent, disabled after traversal lock и сообщает accessibility label/value/hint. Visible row arrows, explanatory lines и Cancel Stack button отсутствуют, но native drag и accessible Move Up/Move Down UUID intents остаются. Exact next row использует icon и subtle rounded system-accent surface, а reactivation/processing/used/error semantics сохраняются.
- При Reduce Transparency система может сделать surface существенно более непрозрачной; это корректная адаптация, а не ошибка дизайна.

## Состояния интерфейса

- regular Liquid Glass, macOS 26+;
- semantic material fallback, macOS 14–25;
- Light/Dark appearance;
- Reduce Transparency enabled;
- Increase Contrast enabled;
- active/inactive History и nonactivating Paste Stack;
- длинный multiline/Unicode content и большие списки без потери contrast/layout.

## Данные и контракты

- Новый код не читает и не сохраняет clipboard payload; он только выбирает и конфигурирует presentation view.
- Runtime selection изолирован в одном AppKit factory/provider с инъецируемым capability seam для deterministic tests.
- Каждая panel получает ровно один outer material surface; rows, Lists и controls не создают отдельные custom glass layers.
- Existing `NSPanel` ownership, delegate, level, collection behavior, activation и close contracts не меняются.
- Manual regression обнаружил, что `TextField` потребляет editing Delete до SwiftUI `.onKeyPress`; прежняя pure admission seam не доказывает фактическую delivery key event. S009 заменяет этот ineffective handler lifecycle-owned local AppKit key-down monitor в background Search: он принимает только non-repeat physical Backspace/forward Delete без ⌘/⌃/⌥/⇧ при focused Search в key/event History window, empty query, list state и exact selected occurrence, snapshots entry и запускает existing deferred delete intent. Во всех остальных случаях возвращает исходный event в normal text editing/app behavior. Никакой global event tap или другой input contract не меняется.
- History Search shell использует только system fill/label separator colors и один neutral outline, не добавляет material/effect view или focus animation. Focus state остаётся feature-owned для real first responder/caret/autofocus; static VoiceOver hint заменяет только визуальный blue focus indicator, не keyboard semantics.
- Paste Stack direction toggle и accessible row actions используют existing deferred `PasteStackPanelIntent` UUID/direction paths и `PasteStackPanelControlState` bounds. Drag handle не несёт VoiceOver semantic; новый decorative row styling не создаёт material/effect view.
- Permission presentation выбирается pure state-to-copy/action mapping seam; он не меняет `AccessibilityPermissionService`, injected closures или вызовы системных API. В каждый момент отображается ровно одна доступная action.
- SwiftUI content остаётся feature-owned; AppKit material wrapper владеет только visual hosting boundary.

## Acceptance criteria

- [x] History, Paste Stack и Permission используют один общий material factory/provider без трёх расходящихся реализаций.
- [x] На macOS 26+ factory создаёт `NSGlassEffectView` style `regular`; на macOS 14–25 создаёт semantic `NSVisualEffectView` fallback, при этом deployment target остаётся 14.
- [x] Smoke check на macOS 26 подтвердил визуально корректный нативный Liquid Glass surface и unified title bar.
- [x] Window background/title bar визуально объединены во всех поддерживаемых состояниях, а native close control, dragging, title, resizing policy и accessibility window semantics сохранены.
- [x] History сохраняет strong user-initiated activation, Search autofocus, keyboard navigation, paste target restoration и fresh viewport reset.
- [x] Paste Stack сохраняет nonactivating focus behavior, floating/multi-display/full-screen placement, drag reorder и global `⌘V`/`Esc` contracts.
- [x] Permission сохраняет все действия и честные permission states.
- [x] Light/Dark, Reduce Transparency и Increase Contrast остаются читаемыми; selection/Next/Used/error не различаются только прозрачностью или цветом.
- [x] Большой список, Unicode/multiline content и быстрые state changes не создают layout recursion, rendering artifacts или заметные interaction hitches.

## Verification

- [x] Unit tests capability selection и semantic surface configuration через injected provider.
- [x] AppKit contract tests подтверждают неизменность style masks, activation, close delegate, level и collection behavior для трёх панелей.
- [x] Полный SwiftPM/Xcode XCTest suite, Debug и universal Release builds с deployment target macOS 14.
- [x] Manual macOS 26 smoke: granted-state compact Permission layout, copy и один Open System Settings button визуально подтверждены пользователем.
- [x] Manual macOS 26 History retest: autofocus/input, arrow selection, Enter, Backspace и neutral Search/selected-row presentation подтверждены пользователем.
- [x] Manual macOS 26+ matrix принята пользователем: отдельно подтверждены Light/Dark и обновлённый Paste Stack; остальные оставшиеся пункты macOS 26+ матрицы пользователь явно принял как пройденные.
- [x] Manual fallback matrix на macOS 14–25 принята пользователем как verification deviation: отдельный hardware run не выполнялся. Приёмка основана на deterministic tests fallback configuration, build с deployment target macOS 14 и universal Release; это не утверждение о фактическом запуске на macOS 14–25.
- [x] Console/accessibility/display portions remaining matrix приняты пользователем как пройденные; отдельные наблюдения VoiceOver, display modes и console не были заново задокументированы.

## Definition of Done

- [x] Все acceptance criteria выполнены.
- [x] Автоматические и ручные проверки пройдены или явно приняты пользователем как verification deviation.
- [x] Приложение собирается без новой регрессии.
- [x] `STATE.md` и frontmatter синхронно обновлены.
- [x] Новые значимые решения записаны в `DECISIONS.md` (D-016); новых архитектурных решений в финальной verification нет.
- [x] Implementation report заполнен.

## Implementation report

### Реализовано

- Один `PanelMaterialProvider` теперь является единственной AppKit boundary для History, Paste Stack и Permission. Через инъецируемый capability provider он создаёт один `NSGlassEffectView` со style `regular` на macOS 26+ или один `NSVisualEffectView` fallback с `.popover`, `.behindWindow` и `.followsWindowActiveState` на macOS 14–25.
- `PanelWindowConfiguration` сохраняет исходные title, floating level, Spaces/full-screen, hides-on-deactivate и nonactivation contracts. Он добавляет `.fullSizeContentView`, transparent nonopaque background и native transparent title bar; material покрывает title bar, а `NSHostingView` constraint’ится к `contentLayoutGuide`, поэтому не перекрывает traffic lights. Высота native title bar вычисляется и компенсируется до установки content constraints, сохраняя feature-owned History 460×340, Stack 400×360 и компактную Permission 360×150 без clipping.
- History и Paste Stack сохраняют один outer material layer: их `List` scroll backgrounds скрыты, но строки, controls, selection/Next/Used/error states остаются системными SwiftUI/AppKit controls без дополнительного glass layer.
- History polish убирает дублирующий in-content заголовок и нижнюю кнопку Paste: title остаётся в native chrome, Search/Clear All собраны в одну строку, Enter/double-click остаются paste actions. Row deletion — SF Symbol `trash` с label/help «Delete»; selected row рисуется одной subtle rounded accent surface, а не full-row rectangle и не отдельным effect layer. Focused Search также admits local `⌫`/Delete only when query is empty and an exact list occurrence is selected; it snapshots that occurrence and reuses the deferred delete-only intent, otherwise returns the key to normal text editing.
- Paste Stack polish оставляет native title единственным заголовком и отдаёт основное место `List`: in-content collecting/processing status, segmented direction picker, explanatory text, visible row arrows и Cancel Stack button удалены. Один compact icon toggle использует existing deferred `.setTraversalDirection`, отображает `arrow.down`/`arrow.up` и сообщает VoiceOver текущую direction и результат toggle. Pending rows сохраняют native drag; decorative VoiceOver-hidden handle показан только когда reorder доступен. UUID-based Move Up/Move Down остаются как bounded row accessibility actions. Exact next и reactivation-priority rows имеют semantic icon и subtle rounded system-accent surface, а Processing, Used, Reactivate и error states сохранены.
- Permission polish убирает in-content heading и повтор menu description. Pure `PermissionPanelPresentation` сопоставляет каждое permission state с одним кратким sentence и ровно одной action: `Allow Access` вызывает существующий injected request closure только для `notRequested`, а `Open System Settings` вызывает существующий settings closure для `denied` и `granted`. Переходы permission service и системные API не менялись.
- Автоматические tests покрывают injected backend selection, фактическую fallback configuration, macOS 26 regular glass, full-size titlebar/content-layout geometry и window contracts всех трёх panels.

### Изменённые файлы

- `Sources/Qipli/UI/PanelMaterialProvider.swift`
- `Sources/Qipli/UI/PanelController.swift`
- `Sources/Qipli/UI/PlaceholderViews.swift`
- `Tests/QipliTests/HistorySearchPasteTests.swift`
- `Tests/QipliTests/PanelMaterialProviderTests.swift`
- `Qipli.xcodeproj/project.pbxproj`
- `docs/PRODUCT.md`
- `docs/STATE.md`
- `docs/slices/S009-adaptive-glass-panels.md`

### Выполненная проверка

- SwiftPM Debug XCTest: 103 tests, 0 failures; focused `HistoryPanelIntentTests`: 8 tests, 0 failures.
- Xcode Debug XCTest с `CODE_SIGNING_ALLOWED=NO`, explicit macOS arm64 destination и isolated DerivedData: 103 tests, 0 failures; Universal Xcode Release (`arm64+x86_64`) собран.
- Universal Xcode Release (`arm64+x86_64`, deployment target macOS 14, `CODE_SIGNING_ALLOWED=NO`) собран; `lipo -archs` подтвердил обе архитектуры.
- `plutil -lint` для Info.plist и entitlements, Xcode project listing, `git diff --check` и scoped source logging/network scan прошли.
- Пользователь вручную подтвердил на macOS 26, что нативный Liquid Glass визуально выглядит корректно; отдельно подтверждены Light/Dark и обновлённый Paste Stack. Затем пользователь явно принял все остальные оставшиеся пункты manual matrix как пройденные.
- History получил user-requested presentation polish без изменения intent boundary: native title bar теперь единственный заголовок; Search и Clear All в одной строке; нижняя Paste button удалена, а Enter и double-click exact selected entry остались paste actions. Search заменён compact neutral system shell (`magnifyingglass`, system control fill и separator outline), который не меняет outline при focus, но сохраняет native caret/focus/autofocus и добавляет VoiceOver hint для filter/Up/Down. Delete использует SF Symbol `trash` с accessibility label, hint и help «Delete»; current selection сообщает VoiceOver value и имеет subtle rounded system-accent surface plus outline. Новые визуальные assertions не добавлялись, чтобы не закреплять тестами SwiftUI implementation detail; существующие `HistoryPanelIntentTests` в полном suite подтверждают keyboard, exact double-click и delete-only contracts.
- Manual History keyboard regression выявил, что SwiftUI `TextField` consumed editing Delete до `.onKeyPress`; ineffective SwiftUI delete handlers заменены lifecycle-owned local AppKit monitor’ом. Он normalizes physical backward/forward Delete, требует focused Search и matching key/event History window, rejects repeats и ⌘/⌃/⌥/⇧ (но не Caps Lock/Fn/numeric pad), snapshots exact entry и routes только admitted action в existing deferred delete intent. Deterministic tests покрывают physical keyCode, modifiers, repeat, focus и window gates. Пользователь подтвердил macOS 26 combined History retest: autofocus/input, arrows, Enter и Backspace теперь работают, neutral Search и selected row выглядят корректно; остальные пункты ручной matrix затем явно приняты пользователем.
- Direction toggle и row-accessibility admission покрыты deterministic pure seams: direct/reverse отображают требуемые SF Symbol, next direction и VoiceOver value/hint; доступные Move Up/Move Down actions точно следуют position bounds и traversal lock. Визуальные SwiftUI assertions не добавлялись.
- Permission mapping tests доказывают exact copy, accessible button label и routing action для `notRequested`, `denied` и `granted`; AppKit geometry test подтверждает 360×150 `contentLayoutRect` внутри native title bar.
- Пользователь вручную подтвердил на macOS 26 granted-state Permission presentation: compact layout, copy и единственная `Open System Settings` button визуально корректны. Остальные Permission/accessibility checks затем явно приняты пользователем как пройденные.

### Отклонения от плана

- Xcode XCTest/Release intentionally использовали отдельные `/private/tmp` DerivedData directories, чтобы unsigned XCTest bundle не попал в обычный signed Debug DerivedData пользователя.
- Отдельный ручной hardware run fallback-панелей на macOS 14–25 не выполнялся. Пользователь явно принял это как verification deviation при завершении S009, опираясь на deterministic fallback configuration tests, deployment build macOS 14 и universal Release. Это не заменяет фактическую будущую проверку на старой ОС и не означает, что она была выполнена.

### Оставшиеся проблемы

Нет открытых blockers для S009. Пользователь явно принял оставшуюся manual matrix; единственное сохранённое ограничение — документированное выше отсутствие отдельного hardware run на macOS 14–25.
