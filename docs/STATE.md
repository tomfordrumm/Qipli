# Qipli — текущее состояние проекта

Последняя актуализация: 2026-08-07

Источник истины для статусов: этот файл

## Текущее положение

- Foundation S001 завершён: автоматические и ручные проверки пройдены.
- Текущий milestone: M1 — рабочая локальная история.
- Активный срез: S002 — `needs_verification`.
- Первый завершённый срез: [`S001 — Скелет приложения и системное разрешение`](slices/S001-foundation-permissions.md).
- Точный следующий шаг: вручную проверить real NSPasteboard, restart persistence, delete и clear-all в запущенном приложении; после успешного результата перевести S002 в `done`.

## Статусы срезов

| Срез | Название | Статус | Зависимости |
|---|---|---|---|
| S001 | Скелет приложения и системное разрешение | `done` | — |
| S002 | Захват, хранение и удаление истории | `needs_verification` | S001 |
| S003 | Поиск и повторная вставка из истории | `planned` | S002 |
| S004 | Сбор и визуальная панель Paste Stack | `planned` | S002 |
| S005 | Порядок и направление обхода | `planned` | S004 |
| S006 | Последовательная вставка и прогресс | `planned` | S001, S005 |
| S007 | Повторная активация и отмена | `planned` | S006 |
| S008 | Приватность и релиз через GitHub | `planned` | S003, S007 |

## Блокеры и recheck points

Реализация S002 не заблокирована; до `done` остаётся пользовательская проверка real NSPasteboard, persistence и destructive UI actions.

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
- S002 добавил локальную Core Data/SQLite history, changeCount monitor, retention и базовую панель; SwiftPM и Xcode XCTest прошли по 20 тестов, Xcode Release build прошёл. Ручная проверка системного pasteboard и UI остаётся обязательной.
- S001 имеет статус `done`; S002 реализован и ожидает ручной проверки; остальные срезы остаются `planned`.

## Журнал переходов

| Дата | Изменение | Основание |
|---|---|---|
| 2026-08-06 | Создан план; S001 переведён в `ready`, остальные срезы — `planned`. | Easy PRD по подтверждённому брифу и ответам пользователя |
| 2026-08-07 | Реализован S001 и переведён в `needs_verification`. | Swift Package Debug/Release builds и статическая проверка успешны; Xcode/XCTest и ручная macOS verification недоступны на машине только с Command Line Tools. |
| 2026-08-07 | Исправлен programmatic AppKit lifecycle и конфигурация Xcode test target. | Xcode Debug/Release builds и 9 XCTest прошли; остаётся ручная системная проверка. |
| 2026-08-07 | S001 переведён в `done`. | Пользователь подтвердил полную ручную матрицу; автоматическая проверка adapter recovery завершена тестом с инъецируемым hook. |
| 2026-08-07 | D-006 принят, S002 переведён в `ready`. | S001 завершён; Core Data/SQLite остаётся самым простым системным persistence решением без сторонней зависимости. |
| 2026-08-07 | S002 реализован и переведён в `needs_verification`. | SwiftPM и Xcode XCTest: 20 тестов без ошибок; требуется ручная проверка real NSPasteboard, persistence и UI. |
