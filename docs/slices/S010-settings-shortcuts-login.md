---
id: S010
title: Settings, пользовательские сочетания и запуск при входе
status: done
depends_on:
  - S001
  - S007
  - S009
covers:
  - FR-018
  - FR-019
  - FR-020
  - BR-011
  - BR-012
  - BR-013
  - NFR-004
  - NFR-010
  - NFR-011
---

# S010 — Settings, пользовательские сочетания и запуск при входе

## Пользовательский результат

Пользователь открывает одно понятное окно Settings, проверяет Accessibility, управляет запуском Qipli при входе и безопасно меняет три Qipli shortcuts без перезапуска приложения и без риска потерять последнее рабочее состояние.

## В scope

- singleton active Settings window из status menu;
- раздел General с Accessibility status/action, Launch at Login и повторным запуском onboarding;
- раздел Shortcuts для History, Start/Collect Paste Stack и Reactivate Previous;
- локальное сохранение настроек и Reset to Defaults;
- системный `SMAppService.mainApp` adapter без helper process;
- runtime refresh shortcut и login-item state;
- честные validation, requires-approval и retryable error states;
- keyboard/VoiceOver accessibility и автоматические тесты через injected adapters.

## Вне scope

- изменение обычного `⌘V`, `Esc`, направления Stack или поведения synthetic events;
- гарантированное обнаружение shortcut conflicts во всех сторонних приложениях;
- sync настроек между устройствами;
- отдельный background helper, LaunchAgent, daemon или новая persistence dependency;
- сам first-run flow: его использует S011.

## Предусловия

- S001, S007 и S009 завершены; действующие input, permission и adaptive material contracts подтверждены.
- Default shortcuts остаются `⌘⇧V`, `⌘⇧C` и `⌘⇧Z`.
- Обычный `⌘V` вне active Stack и `Esc` вне active Stack должны продолжать проходить без изменения.
- `ServiceManagement`/`SMAppService` contract для macOS 14+ перепроверен 2026-08-12 по Apple Developer Documentation.

## Ожидаемое поведение

- Пункт `Settings…` открывает одну активируемую window и повторно поднимает уже открытую копию.
- General показывает фактический Accessibility state через существующий service и маршрутизирует те же `Allow Access`/`Open System Settings` actions без второго permission source of truth.
- Launch at Login изначально выключен, если system service не зарегистрирован. Включение вызывает регистрацию `SMAppService.mainApp`, отключение — unregister.
- Settings различает not registered, enabled, requires approval и error. Внешнее изменение в System Settings отражается при открытии окна и повторной активации Qipli.
- Shortcut recorder принимает одно сочетание для каждой из трёх команд, показывает человекочитаемое значение и применяет только валидный полный snapshot без перезапуска event tap или приложения.
- Modifier-only input, сочетание без Command/Control/Option, внутренний duplicate и защищённые ordinary editing/input contracts отклоняются с объяснением. Последнее рабочее значение не меняется.
- Повреждённые или несовместимые сохранённые shortcuts fail closed к defaults; восстановление видно пользователю и не затрагивает clipboard/history.
- Reset to Defaults меняет только три shortcuts. Accessibility, login item и onboarding completion остаются прежними.

## Состояния интерфейса

- singleton Settings window inactive/active/reopened;
- Accessibility: not requested, denied, granted, input unavailable;
- Launch at Login: off, enabled, requires approval, register/unregister error;
- Shortcut: idle, recording, accepted, internal/protected conflict, recovered default;
- Reset to Defaults available/disabled;
- onboarding action available независимо от completion state.

## Данные и контракты

- `ShortcutPreferences` хранит только command identifiers, key representation и semantic modifiers в локальных preferences; clipboard payload, search query и preview туда не попадают.
- Три shortcuts загружаются и валидируются как единый snapshot. Частично повреждённый snapshot не должен создавать collision или оставлять одну команду без binding.
- Event adapter получает immutable current bindings через injected provider/snapshot и сохраняет существующие exact keyDown, synthetic marker и narrow Stack admission rules.
- `LaunchAtLoginServicing` изолирует `SMAppService.mainApp.status`, `register()`, `unregister()` и переход в Login Items Settings; тесты не меняют реальный system login item.
- `requiresApproval` не считается enabled. UI предлагает открыть Login Items Settings, а не повторяет регистрацию бесконечно.
- Ошибки не содержат пользовательский clipboard text, search query, shortcut keystroke sequence beyond its visible setting или signing secrets.

## Acceptance criteria

- [x] Status menu открывает единственное native Settings window с доступными General и Shortcuts, а повторное действие не создаёт duplicate.
- [x] Accessibility state/action в Settings использует существующий permission service и обновляется после System Settings. Отдельные Permission item и panel удалены; permission-required Stack path открывает Settings на General.
- [x] Launch at Login через `SMAppService.mainApp` корректно показывает off/enabled/requires-approval/error, поддерживает register/unregister, оставляет `notFound` retryable и отражает внешнее отключение без ложного успеха.
- [x] History, Start/Collect Paste Stack и Reactivate Previous переназначаются, применяются без relaunch и сохраняются после штатного restart; defaults точно равны `⌘⇧V`, `⌘⇧C`, `⌘⇧Z`.
- [x] Invalid, modifier-only, internally duplicated и protected combinations не заменяют последний рабочий snapshot; UI не обещает обнаружить все сторонние conflicts.
- [x] Обычный `⌘V` и `Esc` сохраняют существующие active/inactive Stack contracts при default и custom shortcuts; tagged synthetic events и keyUp проходят как раньше.
- [x] Reset to Defaults и recovery повреждённых preferences детерминированны и не меняют Accessibility, login item, onboarding completion, history или pasteboard.
- [x] Settings полностью управляется с клавиатуры и VoiceOver; status, error и selection не передаются только цветом.

## Verification

- [x] Unit tests shortcut codec/validation/snapshot fallback, internal collision, defaults и runtime matching без реального event tap.
- [x] Unit tests injected launch-at-login adapter для notRegistered/enabled/requiresApproval/notFound, register/unregister success/failure и external status refresh.
- [x] AppKit tests singleton activation, window lifecycle и сохранение accessory/menu-bar application behavior.
- [x] Полный SwiftPM/Xcode XCTest suite, Debug и universal Release builds с deployment target macOS 14.
- [x] Пользовательская ручная приёмка основного Settings, shortcuts, permission и Launch at Login пути выполнена 2026-08-26; проверенные сценарии работают.

Расширенная logout/login, VoiceOver, display modes, clean-console и clean-machine matrix не выдаётся за выполненную. По явному решению пользователя она перенесена в общий предрелизный прогон S008 и не блокирует приёмку S010.

## Definition of Done

- [x] Все acceptance criteria приняты пользователем.
- [x] Автоматические проверки и достаточная для приёмки ручная проверка пройдены; полный системный регресс перенесён в S008.
- [x] Приложение собирается без новой регрессии.
- [x] `STATE.md` и frontmatter синхронно обновлены.
- [x] Новые значимые решения записаны в `DECISIONS.md`; реализация следует D-019 и D-020, новых решений не потребовалось.
- [x] Implementation report заполнен.

## Implementation report

### Реализовано

- Status menu получил `Settings…`; `SettingsWindowController` создаёт одно активируемое native window, переиспользует его при повторном открытии и обновляет system state при каждом show и возврате приложения в active state.
- General использует существующий `AccessibilityPermissionService`, различает permission и global-input unavailable, вызывает те же request/System Settings actions и не создаёт второй источник permission state.
- `SystemLaunchAtLoginService` изолирует `SMAppService.mainApp`. View model читает фактические `notRegistered`, `enabled`, `requiresApproval` и `notFound`, выполняет register/unregister только по явному toggle, показывает retryable error и ведёт `requiresApproval` в Login Items Settings. Исправление 2026-08-27 оставило toggle доступным при `notFound`: signed canary подтвердил реальный переход `notFound → enabled → notRegistered` через register/unregister.
- `ShortcutPreferences` хранит versioned atomic snapshot трёх bindings в `UserDefaults`. Полный snapshot валидируется до публикации: нужен Command/Control/Option, запрещены внутренние physical-key collisions и защищённые standard editing combinations. Повреждённые данные целиком заменяются defaults с видимым recovery state.
- Recorder применяет History, Start/Collect Paste Stack и Reactivate Previous сразу. Event tap получает текущий immutable snapshot через thread-safe provider; ordinary `⌘V`, active-Stack `Esc`, synthetic marker и keyDown admission остаются отдельными неизменяемыми контрактами.
- Shortcuts UI сообщает recording, validation, recovery и errors текстом и SF Symbols, имеет accessibility label/value/help и Reset to Defaults, который меняет только shortcut preferences.
- После пользовательской проверки удалены дублирующие `Permission: …` из status menu и отдельная Permission panel. Попытка запустить Paste Stack без Accessibility или при недоступном input listener открывает singleton Settings на General.

### Изменённые файлы

- `Sources/Qipli/App/ApplicationShell.swift`
- `Sources/Qipli/Input/CGEventTapAdapter.swift`
- `Sources/Qipli/Settings/ShortcutPreferences.swift`
- `Sources/Qipli/Settings/LaunchAtLoginService.swift`
- `Sources/Qipli/Settings/SettingsViewModel.swift`
- `Sources/Qipli/UI/SettingsWindowController.swift`
- `Sources/Qipli/UI/PanelController.swift`
- `Sources/Qipli/UI/PanelMaterialProvider.swift`
- `Sources/Qipli/UI/PlaceholderViews.swift`
- `Tests/QipliTests/SettingsTests.swift`
- `Tests/QipliTests/PanelMaterialProviderTests.swift`
- `Qipli.xcodeproj/project.pbxproj`
- `docs/PLAN.md`
- `docs/STATE.md`
- `docs/slices/S010-settings-shortcuts-login.md`

### Выполненная проверка

- Focused SwiftPM S010 suite: 12 tests, 0 failures.
- Полный SwiftPM suite после удаления Permission panel: 120 tests, 0 failures. Xcode Debug XCTest прошёл; Xcode project wiring, AppKit window lifecycle и оба target architectures проверены.
- После исправления retry из `notFound`: 6 focused `SettingsViewModelTests` и полный SwiftPM suite из 135 тестов прошли без ошибок; Developer ID-signed canary с отдельным bundle ID в `/Applications` подтвердил реальный register/unregister path на macOS 26.6.
- Universal Release с deployment target macOS 14 и `CODE_SIGNING_ALLOWED=NO` собран; `lipo -archs` подтвердил `x86_64 arm64`.
- `plutil -lint Qipli.xcodeproj/project.pbxproj` и `git diff --check` прошли.
- 2026-08-26 пользователь проверил большую часть переданной ручной матрицы, подтвердил корректную работу проверенных сценариев и явно принял S010 как `done`.
- Полный logout/login, VoiceOver/keyboard, appearance/accessibility display modes, clean console и clean-machine прогон остаётся частью предрелизной проверки S008.

### Отклонения от плана

Фактический first-run onboarding и действие `Show Onboarding Again` реализует S011. S010 предоставляет общие permission, shortcut и launch-at-login services, но не добавляет временный no-op action в Settings.

### Оставшиеся проблемы

Product-code blockers отсутствуют. S010 принят и завершён. Непройденные пункты расширенной системной матрицы сохранены как предрелизная проверка S008 и не отмечены как фактически выполненные.
