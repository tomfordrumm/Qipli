---
id: S016
title: Надёжная навигация и закрытие History
status: needs_verification
depends_on:
  - S003
covers:
  - FR-003
  - FR-004
  - FR-005
  - FR-026
  - NFR-005
  - NFR-006
  - NFR-008
---

# S016: Надёжная навигация и закрытие History

## Результат

History одинаково реагирует на клавиатуру независимо от SwiftUI first responder, не запускает повторную вставку во время незавершённого focus handoff, показывает самую свежую доступную clipboard change и закрывается при переходе пользователя в любое другое окно без возврата фокуса назад.

## В scope

- оконная маршрутизация Up, Down, Enter и Escape для key History panel;
- восстановление search focus при получении panel key status;
- ровно одна history paste transaction до success/failure/cancel;
- activation notification с bounded fallback перед synthetic `Command-V`;
- passive dismiss при потере History key status без активации сохранённого target;
- согласованный pasteboard flush перед fresh History presentation;
- capture без полного storage reload после каждой новой external copy;
- deterministic tests для admission, transaction, dismissal и fresh capture ordering.

## Вне scope

- подтверждение того, что конкретное target field приняло текст;
- восстановление прежнего system pasteboard после history paste;
- изменение обычного `Command-V`, Paste Stack traversal или его nonactivating panel;
- новый persistence backend или фоновая сеть.

## Поведение и контракты

- Key History panel обрабатывает точные unmodified Up, Down, Enter и Escape независимо от текущего first responder. Up/Down синхронно меняют selection, а Enter передаёт в отложенную paste transaction exact-entry snapshot. Остальные клавиши остаются у native control.
- Fresh show выбирает первый результат, получает search focus после фактического key-window transition и перед reload захватывает последнюю доступную внешнюю pasteboard change.
- Первый допустимый Enter создаёт одну transaction. Повторные Enter и double-click до её завершения не переписывают pasteboard и не отправляют второй synthetic `Command-V`.
- Target activation остаётся обязательным условием dispatch. Системное activation notification завершает ожидание сразу, timer остаётся bounded fallback.
- Потеря History key status скрывает panel без вызова focus restorer. Escape сохраняет прежний явный cancel contract и возвращает captured target.
- Successful external capture добавляет exact occurrence в текущую in-memory History без полного повторного fetch. Storage failure остаётся видимым.

## Acceptance criteria

- [ ] Up/Down меняют selection, а Enter/Escape работают после fresh show, повторной активации и клика по History row, пока panel остаётся key.
- [ ] Если initial activation заняла больше прежних трёх main-run-loop turns, получение key status всё равно фокусирует Search и включает keyboard navigation.
- [x] Rapid repeated Enter/double-click во время target activation приводит максимум к одной pasteboard write и одной tagged paste command.
- [x] Successful target activation не ждёт следующего 50 ms polling tick; exhausted deadline оставляет retryable failure без dispatch.
- [ ] Click, Command-Tab или переход в другое окно скрывает History и не активирует ранее captured app поверх нового user target.
- [x] Escape по-прежнему закрывает History, возвращает captured target и не меняет pasteboard.
- [x] Copy непосредственно перед History show доступен в первой presentation, если pasteboard уже опубликовал change.
- [x] Обычный external capture не выполняет полный storage fetch; duplicates, Unicode, multiline, retention и self-write suppression сохраняются.

## Verification

- [x] Unit tests window-key admission, exact key routing, `Down → Enter` exact-entry snapshot и modified-key pass-through.
- [x] Unit tests single in-flight paste transaction, success/failure reset и repeated input suppression.
- [x] Unit tests passive dismiss не вызывает focus restoration, а explicit Escape вызывает.
- [x] Integration test fresh pasteboard flush completes capture before History reload/presentation.
- [x] Full SwiftPM suite и unsigned Xcode Debug build.
- [ ] Manual macOS matrix: hotkey focus, row click plus arrows, delayed target activation, rapid Enter, click outside to same/other app, Command-Tab, Escape and retry failure.

## Implementation report

### Реализовано

- Перенесены Up/Down/Enter/Escape в History-only AppKit keyboard monitor; modified input остаётся native responder chain.
- Добавлены single in-flight paste transaction, activation notification и bounded polling fallback.
- History получает fresh pasteboard poll перед показом, а successful capture обновляет in-memory список без полного storage fetch.
- Passive click-away/Command-Tab скрывают только History без focus restoration. Paste Stack не получает ни mouse monitor, ни dismiss-on-resign behavior.

### Проверено

- SwiftPM: 150 тестов, 0 failures.
- Unsigned universal Xcode Debug build (`arm64`, `x86_64`): пройден.
- Manual macOS interaction matrix остаётся открытой.

### Отклонения и остаточные риски

- Реальный responder/focus path и клики по другим приложениям требуют ручной проверки в запущенном menu bar app.
- Успешный synthetic `Command-V` означает доставку события после активации target, но не подтверждает принятие текста конкретным target field.
