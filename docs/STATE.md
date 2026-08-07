# Qipli — текущее состояние проекта

Последняя актуализация: 2026-08-07

Источник истины для статусов: этот файл

## Текущее положение

- Foundation S001 реализован и прошёл автоматическую Xcode-проверку, но ожидает ручной проверки системного поведения macOS.
- Текущий milestone: M1 — рабочая локальная история.
- Активный срез: S001 — `needs_verification`.
- Первый готовый срез: [`S001 — Скелет приложения и системное разрешение`](slices/S001-foundation-permissions.md).
- Точный следующий шаг: перезапустить Qipli из Xcode, подтвердить появление status item и onboarding, затем пройти ручную Accessibility/event-tap матрицу; не начинать историю или Paste Stack до её результата.

## Статусы срезов

| Срез | Название | Статус | Зависимости |
|---|---|---|---|
| S001 | Скелет приложения и системное разрешение | `needs_verification` | — |
| S002 | Захват, хранение и удаление истории | `planned` | S001 |
| S003 | Поиск и повторная вставка из истории | `planned` | S002 |
| S004 | Сбор и визуальная панель Paste Stack | `planned` | S002 |
| S005 | Порядок и направление обхода | `planned` | S004 |
| S006 | Последовательная вставка и прогресс | `planned` | S001, S005 |
| S007 | Повторная активация и отмена | `planned` | S006 |
| S008 | Приватность и релиз через GitHub | `planned` | S003, S007 |

## Блокеры и recheck points

Для завершения S001 требуется ручная проверка menu bar, Accessibility и глобального ввода на поддерживаемой/чистой macOS-сессии.

- Перед S008 подтвердить доступ к Apple Developer Program, Developer ID Application certificate и notarization credentials.
- В S001 на чистом профиле macOS 14 проверить, что Accessibility trust покрывает event tap и synthetic paste; если macOS требует дополнительное разрешение, обновить onboarding, `TECHNICAL.md` и решение до S002.
- Перед S008 подтвердить возможность собрать universal binary; если доступна только Apple Silicon сборка, отразить это в продуктовой совместимости и release notes.

## Последнее проверенное состояние

- `PROJECT_BRIEF.md` сохранён без изменений.
- S001 добавил нативную menu bar foundation, Xcode project, Swift Package build configuration и XCTest с fake adapters. История, persistence, clipboard capture и бизнес-логика Paste Stack ещё отсутствуют.
- Swift Package Debug и Release build прошли; plist, entitlements и project syntax прошли статическую проверку.
- Xcode Debug и Release builds для macOS 14 target прошли с `CODE_SIGNING_ALLOWED=NO`.
- Xcode XCTest прошли: 9 тестов, 0 ошибок. Явный programmatic AppKit bootstrap исправил отсутствие запуска app delegate; пользователю осталось подтвердить status item после перезапуска.
- Ручные системные проверки menu bar, Accessibility и event tap ещё не завершены.
- S001 имеет статус `needs_verification`; остальные срезы остаются `planned`.

## Журнал переходов

| Дата | Изменение | Основание |
|---|---|---|
| 2026-08-06 | Создан план; S001 переведён в `ready`, остальные срезы — `planned`. | Easy PRD по подтверждённому брифу и ответам пользователя |
| 2026-08-07 | Реализован S001 и переведён в `needs_verification`. | Swift Package Debug/Release builds и статическая проверка успешны; Xcode/XCTest и ручная macOS verification недоступны на машине только с Command Line Tools. |
| 2026-08-07 | Исправлен programmatic AppKit lifecycle и конфигурация Xcode test target. | Xcode Debug/Release builds и 9 XCTest прошли; остаётся ручная системная проверка. |
