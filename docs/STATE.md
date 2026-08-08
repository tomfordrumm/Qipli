# Qipli — текущее состояние проекта

Последняя актуализация: 2026-08-08

Источник истины для статусов: этот файл

## Текущее положение

- S001 и S002 завершены: автоматические и ручные проверки пройдены.
- Текущий milestone: M1 — рабочая локальная история.
- Активный срез: [`S003 — Поиск и повторная вставка из истории`](slices/S003-history-search-paste.md), статус `needs_verification`.
- Завершённые срезы: [`S001 — Скелет приложения и системное разрешение`](slices/S001-foundation-permissions.md) и [`S002 — Захват, хранение и удаление истории`](slices/S002-history-capture-retention.md).
- Точный следующий шаг: вручную проверить S003: `⌘⇧V` не выполняет command target app до открытия History, force-activates Qipli и делает History key/Search focused. Каждый fresh hotkey/menu show должен вернуть reused long list к first selected row с top anchor, while Up/Down keeps selection visible без jump/recenter; paste-failure reopen сохраняет retry row/viewport. Проверить Up/Down/Enter/Esc без SwiftUI console warning, read-only entries, single-click selection, exact double-click paste и Delete without selection/paste. Successful `Enter` paste должен реально отправляться в TextEdit/browser/editor (без ручного `⌘V`) и поднимать exact occurrence наверх after reopen/restart without duplicate, while selection/pasteboard write/rejected activation/dispatch failure do not promote. Также проверить retryable target failures, `Esc` и permission-denied paths; затем принять или исправить slice.

## Статусы срезов

| Срез | Название | Статус | Зависимости |
|---|---|---|---|
| S001 | Скелет приложения и системное разрешение | `done` | — |
| S002 | Захват, хранение и удаление истории | `done` | S001 |
| S003 | Поиск и повторная вставка из истории | `needs_verification` | S002 |
| S004 | Сбор и визуальная панель Paste Stack | `planned` | S002 |
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
- S003 реализован: keyboard-active History panel с локализованной strong user-initiated activation, read-only entries/single-select/double-click paste, local search/ID selection, non-animated selection auto-scroll и fresh-show top viewport reset, durable exact-occurrence activity recency, safe history paste executor с target activation before close и bounded main-run-loop wait, active exact-hotkey filtering, deferred keyboard state/window actions и retryable failures. SwiftPM и Xcode XCTest прошли по 45 тестов; Xcode Debug/Release builds прошли. Реальные focus/paste/failure/recency/viewport paths и clean-console keyboard navigation ожидают ручной проверки.
- S001 и S002 имеют статус `done`; S003 — `needs_verification`; остальные срезы остаются `planned`.

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
