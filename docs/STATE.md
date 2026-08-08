# Qipli — текущее состояние проекта

Последняя актуализация: 2026-08-08

Источник истины для статусов: этот файл

## Текущее положение

- S001–S007 завершены: автоматические и ручные проверки пройдены.
- Milestone M1 — рабочая локальная история — завершён.
- Milestone M2 — Paste Stack — завершён.
- Завершённые срезы: [`S001 — Скелет приложения и системное разрешение`](slices/S001-foundation-permissions.md), [`S002 — Захват, хранение и удаление истории`](slices/S002-history-capture-retention.md), [`S003 — Поиск и повторная вставка из истории`](slices/S003-history-search-paste.md), [`S004 — Сбор и визуальная панель Paste Stack`](slices/S004-stack-collection.md), [`S005 — Порядок и направление обхода`](slices/S005-stack-order-direction.md), [`S006 — Последовательная вставка и прогресс`](slices/S006-stack-sequential-paste.md) и [`S007 — Повторная активация и отмена`](slices/S007-stack-recovery-cancel.md).
- Точный следующий шаг: перед реализацией перепроверить prerequisites, Apple platform/release contracts и S008 coverage для [`S008 — Приватность и релиз через GitHub`](slices/S008-release-hardening.md).

## Статусы срезов

| Срез | Название | Статус | Зависимости |
|---|---|---|---|
| S001 | Скелет приложения и системное разрешение | `done` | — |
| S002 | Захват, хранение и удаление истории | `done` | S001 |
| S003 | Поиск и повторная вставка из истории | `done` | S002 |
| S004 | Сбор и визуальная панель Paste Stack | `done` | S002 |
| S005 | Порядок и направление обхода | `done` | S004 |
| S006 | Последовательная вставка и прогресс | `done` | S001, S005 |
| S007 | Повторная активация и отмена | `done` | S006 |
| S008 | Приватность и релиз через GitHub | `planned` | S003, S007 |

## Блокеры и recheck points

Активных блокеров для S001–S007 нет.

- Перед S008 подтвердить доступ к Apple Developer Program, Developer ID Application certificate и notarization credentials.
- В S008 повторить подтверждённый в S001 Accessibility/event-tap flow на чистой минимально поддерживаемой macOS 14 с подписанным release artifact.
- Перед S008 подтвердить возможность собрать universal binary; если доступна только Apple Silicon сборка, отразить это в продуктовой совместимости и release notes.

## Последнее проверенное состояние

- `PROJECT_BRIEF.md` сохранён без изменений.
- S001 добавил нативную menu bar foundation, Xcode project, Swift Package build configuration и XCTest с fake adapters. История, persistence, clipboard capture и бизнес-логика Paste Stack ещё отсутствуют.
- Swift Package Debug и Release build прошли; plist, entitlements и project syntax прошли статическую проверку.
- Xcode Debug и Release builds для macOS 14 target прошли с `CODE_SIGNING_ALLOWED=NO`.
- Xcode XCTest прошли: 11 тестов, 0 ошибок, включая детерминированную симуляцию успешного и исчерпанного восстановления event tap. Явный programmatic AppKit bootstrap исправил отсутствие запуска app delegate.
- Пользователь вручную подтвердил menu bar, permission onboarding и выдачу Accessibility, оба глобальных сочетания, singleton panels, неизменность обычного `⌘V` и штатный Quit.
- S002 добавил локальную Core Data/SQLite history, changeCount monitor, retention и базовую панель; SwiftPM и Xcode XCTest прошли по 20 тестов, Xcode Release build прошёл.
- Пользователь вручную подтвердил exact text/Unicode/multiline capture, duplicates, игнорирование non-text, restart persistence, durable delete, clear-all confirmation, неизменность system pasteboard и отсутствие clipboard payload в логах.
- S003 реализован: keyboard-active History panel с локализованной strong user-initiated activation, read-only entries/single-select/double-click paste, local search/ID selection, non-animated selection auto-scroll и fresh-show top viewport reset, durable exact-occurrence activity recency, safe history paste executor с target activation before close и bounded main-run-loop wait, active exact-hotkey filtering, deferred keyboard state/window actions и retryable failures. SwiftPM и Xcode XCTest прошли по 45 тестов; Xcode Debug/Release builds прошли. Пользователь подтвердил реальные focus/paste/failure/recency/viewport paths и clean-console keyboard navigation.
- S001–S007 имеют статус `done`; S008 остаётся `planned`.
- S006 добавил UUID reservation/rollback state machine и deferred sequential paste executor: exact ordinary untagged `⌘V` прерывается только для active Stack with pending/reserved occurrence; tagged events/keyUp/modifiers pass stack path. Used означает successful tagged command dispatch, not target-field confirmation; last all-used snapshot publishes before deferred close. Native `List` processing/used/auto-finish states разделены common-mode run-loop boundaries и unchanged state не публикуется повторно. SwiftPM: 80 tests, 0 failures; Xcode Debug XCTest и universal Release (`arm64+x86_64`) прошли. User подтвердил complete post-fix manual macOS matrix и clean console без layout-recursion warning.
- S004 добавил временную in-memory StackSession: exact `⌘⇧C` начинает либо сохраняет collection session, показывает nonactivating panel и dispatch-ит tagged ordinary `⌘C` в остающееся active source app; resulting source-owned copy попадает в Stack только после durable History capture и сохраняет duplicate/Unicode occurrences. Menu Start остаётся пустым. Cancel/close/exact global Escape очищают только session; ordinary `⌘V` остаётся не перехваченным. SwiftPM и Xcode Debug XCTest: 59 tests, 0 errors; universal Release arm64+x86_64 собран. Пользователь подтвердил полную ручную matrix: source focus, copies/duplicates/Unicode/multiline, repeat hotkey, Escape/Cancel/red close, History retention, new empty Stack, second display и full-screen/Space.
- S005 добавил in-memory base-order/direction state machine: UUID-only atomic reorder, direct/reverse next, append-at-end after reorder и narrow traversal lock for S006. Compact nonactivating panel показывает direction/Next и native drag plus accessible Move Up/Down intents without changing ordinary `⌘V`. После ручной regression report direction/drag mutations перенесены за common-mode RunLoop boundary с exact-ID snapshot; SwiftPM и Xcode Debug XCTest: 68 tests, 0 errors; universal Release arm64+x86_64 собран. Пользователь подтвердил полную manual matrix, включая clean console и full-width separators.
- S007 добавил UUID reactivation priority и Reactivate Previous (`⌘⇧Z`) with direct/reverse cursor preservation, origin-aware retry rollback, deferred auto-finish race safety, exact self-write suppression и immediate idempotent cancel. SwiftPM/Xcode Debug XCTest: 91 tests, 0 failures; universal Release `arm64+x86_64` прошёл. Пользователь подтвердил полную manual macOS matrix: source focus, Reactivate/Reactivate Previous and system Redo pass-through, recovery/retry, Escape/red-close/Cancel/menu cancellation, post-cancel ordinary `⌘V`, auto-finish boundary и clean console без List layout recursion.

## Журнал переходов

| Дата | Изменение | Основание |
|---|---|---|
| 2026-08-06 | Создан план; S001 переведён в `ready`, остальные срезы — `planned`. | Easy PRD по подтверждённому брифу и ответам пользователя |
| 2026-08-07 | Реализован S001 и переведён в `needs_verification`. | Swift Package Debug/Release builds и статическая проверка успешны; Xcode/XCTest и ручная macOS verification недоступны на машине только с Command Line Tools. |
| 2026-08-07 | Исправлен programmatic AppKit lifecycle и конфигурация Xcode test target. | Xcode Debug/Release builds и 9 XCTest прошли; остаётся ручная системная проверка. |
| 2026-08-07 | S001 переведён в `done`. | Пользователь подтвердил полную ручную матрицу; автоматическая проверка adapter recovery завершена тестом с инъецируемым hook. |
| 2026-08-07 | D-006 принят, S002 переведён в `ready`. | S001 завершён; Core Data/SQLite остаётся самым простым системным persistence решением без сторонней зависимости. |
| 2026-08-07 | S002 реализован и переведён в `needs_verification`. | SwiftPM и Xcode XCTest: 20 тестов без ошибок; требуется ручная проверка real NSPasteboard, persistence и UI. |
| 2026-08-07 | S002 переведён в `done`. | Пользователь подтвердил полную ручную clipboard/UI/restart/privacy матрицу; автоматические проверки ранее прошли. |
| 2026-08-07 | D-004 и D-007 приняты, S003 переведён в `ready`. | S001 подтвердил AppKit/Core Graphics input и menu-bar shell на macOS 14; S002 завершён, границы search/paste и Apple platform contracts перепроверены. |
| 2026-08-07 | S003 реализован и переведён в `needs_verification`. | SwiftPM и Xcode XCTest: 35 тестов без ошибок; Debug и Release builds прошли. Остаётся ручная матрица real paste/focus/permission/failure, включая отсутствие target-app action до History и autofocus без click. |
| 2026-08-08 | S003 переведён в `done`; milestone M1 завершён. | Пользователь подтвердил полную ручную матрицу History UI, keyboard focus/navigation, cross-app paste, recency и viewport; финальная автоматическая матрица содержит 45 тестов без ошибок. |
| 2026-08-08 | S004 реализован и переведён в `needs_verification`. | Автоматические Stack/session/capture/input/placement тесты, включая hotkey source-Copy и menu-empty Start, SwiftPM и Xcode Debug XCTest (59 tests) прошли; universal Release arm64+x86_64 собран. Требуется ручная проверка source-copy/focus, cancel/Escape, displays и full-screen/Space. |
| 2026-08-08 | S004 переведён в `done`; M2 начат. | Пользователь подтвердил полную ручную Paste Stack matrix: source-copy/focus, duplicates/Unicode/multiline, repeated hotkey, ordinary `⌘V`, Escape/Cancel/red close, History retention, new empty Stack, second display и full-screen/Space; автоматическая matrix остаётся 59 tests без ошибок. |
| 2026-08-08 | S005 переведён из `planned` в `ready`. | S004 завершён; подтверждены prerequisite occurrence identity, collection/session ownership и nonactivating panel contracts. |
| 2026-08-08 | S005 реализован и переведён в `needs_verification`. | SwiftPM и Xcode Debug XCTest: 65 tests, 0 errors; universal Release `arm64+x86_64` собран. Требуется ручная macOS проверка drag/direction/Next/VoiceOver/source focus; S006–S007 behavior не добавлялся. |
| 2026-08-08 | Исправлена S005 SwiftUI layout/publication regression. | Direction, drag и accessible reorder intents deferred через common-mode RunLoop с exact candidate UUID snapshot и execution-time domain validation; SwiftPM/Xcode XCTest: 68 tests, 0 errors; universal Release собран. Manual paths passed, требуется только повтор чистой консоли/layout warning проверки. |
| 2026-08-08 | Исправлено выравнивание separators S005 List. | Native separator guides закреплены к full-width row HStack, чтобы conditional Next/multiline/disabled controls не сужали separator. SwiftPM и Xcode Debug XCTest: 68 tests, 0 errors; остаётся final clean-console + visual separator retest. |
| 2026-08-08 | S005 переведён в `done`. | Пользователь подтвердил финальную manual matrix: clean console и full-width separators вместе с ранее пройденными drag/direction/Next/accessibility/source-focus checks; автоматическая матрица остаётся 68 tests без ошибок. |
| 2026-08-08 | S006 переведён из `planned` в `ready`. | S001 и S005 завершены; повторно подтверждены active event-tap, marker и pasteboard self-write contracts для последовательной вставки. |
| 2026-08-08 | S006 реализован и переведён в `needs_verification`. | UUID reservation, exact self-write suppression, tagged dispatch rollback and deferred auto-finish покрыты SwiftPM (78 tests), Xcode Debug XCTest и universal Release `arm64+x86_64`; остаётся ручная real-app/Accessibility matrix. |
| 2026-08-08 | Исправлена S006 native Stack `List` layout recursion. | Processing row, used row and auto-finish теперь разделены common-mode run-loop boundaries; unchanged state does not emit extra publications. SwiftPM: 80 tests, Xcode Debug XCTest и universal Release `arm64+x86_64` прошли; S006 остаётся `needs_verification` до user clean-console retest. |
| 2026-08-08 | S006 переведён в `done`; D-011 принят. | User подтвердил full post-fix macOS matrix: sequential paste, direct/reverse, duplicates/Unicode/multiline, repeat, recovery, Used/Next/auto-finish, ordinary `⌘V`, history preservation и clean console без layout-recursion warning. |
| 2026-08-08 | S007 переведён из `planned` в `ready`; D-015 принят. | S006 завершён; повторно подтверждены active event-tap consume/pass-through и `NSWindowDelegate.windowShouldClose`/`orderOut` contracts. Пользователь уточнил Reactivate Previous: exact `⌘⇧Z` назначает last successfully dispatched occurrence one-shot priority и не является immediate paste или target undo. |
| 2026-08-08 | S007 реализован и переведён в `needs_verification`. | SwiftPM и Xcode Debug XCTest: 91 tests, 0 failures; universal Release `arm64+x86_64`, plist/project lint, diff check и production privacy/network scan прошли. Требуется user manual macOS matrix: recovery/Reactivate Previous, source focus, cancel and clean-console/List layout. |
| 2026-08-08 | S007 переведён в `done`; M2 завершён. | Пользователь подтвердил полную manual macOS matrix, включая recovery/Reactivate Previous, system Redo pass-through, source focus, cancellation, post-cancel `⌘V`, auto-finish и clean console без List layout recursion. |
