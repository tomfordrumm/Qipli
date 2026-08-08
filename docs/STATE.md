# Qipli — текущее состояние проекта

Последняя актуализация: 2026-08-08

Источник истины для статусов: этот файл

## Текущее положение

- S001–S003 завершены: автоматические и ручные проверки пройдены.
- Milestone M1 — рабочая локальная история — завершён.
- S004 реализован и ожидает ручной проверки Paste Stack collection/focus/display scenarios.
- Завершённые срезы: [`S001 — Скелет приложения и системное разрешение`](slices/S001-foundation-permissions.md), [`S002 — Захват, хранение и удаление истории`](slices/S002-history-capture-retention.md) и [`S003 — Поиск и повторная вставка из истории`](slices/S003-history-search-paste.md).
- Точный следующий шаг: вручную проверить S004 из source apps, включая exact Escape, close/cancel, multiple displays и full-screen/Space; после подтверждения пользователя можно перевести S004 в `done`.

## Статусы срезов

| Срез | Название | Статус | Зависимости |
|---|---|---|---|
| S001 | Скелет приложения и системное разрешение | `done` | — |
| S002 | Захват, хранение и удаление истории | `done` | S001 |
| S003 | Поиск и повторная вставка из истории | `done` | S002 |
| S004 | Сбор и визуальная панель Paste Stack | `needs_verification` | S002 |
| S005 | Порядок и направление обхода | `planned` | S004 |
| S006 | Последовательная вставка и прогресс | `planned` | S001, S005 |
| S007 | Повторная активация и отмена | `planned` | S006 |
| S008 | Приватность и релиз через GitHub | `planned` | S003, S007 |

## Блокеры и recheck points

Активных блокеров для S001–S003 нет.

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
- S001–S003 имеют статус `done`; S004 имеет статус `needs_verification`; S005–S008 остаются `planned`.
- S004 добавил временную in-memory StackSession: exact `⌘⇧C` начинает одну пустую collection session, append происходит только после durable History capture и сохраняет duplicate/Unicode occurrences. Nonactivating floating Stack panel показывается на display под курсором, Cancel/close/exact global Escape очищают только session. Ordinary `⌘V` остаётся не перехваченным. SwiftPM и Xcode Debug XCTest: 55 tests, 0 errors; universal Release arm64+x86_64 собран. Требуется ручная macOS matrix focus/Space/full-screen/multi-display.

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
| 2026-08-08 | S004 реализован и переведён в `needs_verification`. | Автоматические Stack/session/capture/input/placement тесты, SwiftPM и Xcode Debug XCTest (55 tests) прошли; universal Release arm64+x86_64 собран. Требуется ручная проверка nonactivating focus, cancel/Escape, displays и full-screen/Space. |
