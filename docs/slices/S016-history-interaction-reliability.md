---
id: S016
title: Надёжная навигация и закрытие History
status: done
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

- Key History panel обрабатывает точные unmodified Up, Down, Enter и Escape независимо от текущего first responder. Up/Down синхронно меняют model и native table selection/viewport, а Enter начинает paste transaction с exact-entry snapshot в том же handler. Остальные клавиши остаются у native control.
- Fresh show синхронно показывает уже загруженный cached snapshot, выбирает первый результат и получает search focus после фактического key-window transition. Последняя доступная внешняя pasteboard change опрашивается первой, но её durable capture заканчивается и публикуется уже после показа панели.
- Первый допустимый Enter создаёт одну transaction. Повторные Enter и double-click до её завершения не переписывают pasteboard и не отправляют второй synthetic `Command-V`.
- Target activation остаётся обязательным условием dispatch. После successful pasteboard write History сразу скрывается визуально, сохраняя ordered/key window только для cooperative handoff; системное activation notification завершает невидимое ожидание сразу, timer остаётся bounded fallback. Любая failure восстанавливает panel для retry.
- Потеря History key status скрывает panel без вызова focus restorer. Escape сохраняет прежний явный cancel contract и возвращает captured target.
- Successful external capture добавляет exact occurrence в текущую in-memory History без полного повторного fetch. Storage failure остаётся видимым.

## Acceptance criteria

- [x] Up/Down меняют selection, а Enter/Escape работают после fresh show, повторной активации и клика по History row, пока panel остаётся key.
- [x] Если initial activation заняла больше прежних трёх main-run-loop turns, получение key status всё равно фокусирует Search и включает keyboard navigation.
- [x] Rapid repeated Enter/double-click во время target activation приводит максимум к одной pasteboard write и одной tagged paste command.
- [x] Successful target activation не ждёт следующего 50 ms polling tick; exhausted deadline оставляет retryable failure без dispatch.
- [x] Каждый Up/Down синхронно применяет exact native row selection; `scrollRowToVisible` не позволяет highlight уйти за viewport и не использует deferred/coalesced SwiftUI `scrollTo`.
- [x] `Enter` визуально скрывает History без `Pasting…`, selection jump или видимого activation wait; failure возвращает ту же panel с retryable error.
- [x] Click, Command-Tab или переход в другое окно скрывает History и не активирует ранее captured app поверх нового user target.
- [x] Escape по-прежнему закрывает History, возвращает captured target и не меняет pasteboard.
- [x] Copy непосредственно перед History show доступен в первой presentation, если pasteboard уже опубликовал change.
- [x] Обычный external capture не выполняет полный storage fetch; duplicates, Unicode, multiline, retention и self-write suppression сохраняются.

## Verification

- [x] Unit tests window-key admission, exact key routing, `Down → Enter` exact-entry snapshot и modified-key pass-through.
- [x] Unit tests single in-flight paste transaction, success/failure reset и repeated input suppression.
- [x] Unit tests passive dismiss не вызывает focus restoration, а explicit Escape вызывает.
- [x] Integration test fresh pasteboard flush completes capture before History reload/presentation.
- [x] Full SwiftPM suite и unsigned Xcode Debug build.
- [x] Manual macOS matrix: hotkey focus, row click plus arrows, instant visual hide on Enter, delayed target activation, rapid Enter, click outside to same/other app, Command-Tab, Escape and retry failure.

## Implementation report

### Реализовано

- Перенесены Up/Down/Enter/Escape в History-only AppKit keyboard monitor; modified input остаётся native responder chain.
- Добавлены single in-flight paste transaction, activation notification и bounded polling fallback. После успешной pasteboard write panel становится прозрачной до завершения handoff; отдельный progress row удалён, а failure path восстанавливает presentation.
- History получает fresh pasteboard poll, сразу показывает cached snapshot и только затем асинхронно дожидается ordered capture queue; successful capture обновляет уже видимый in-memory список без полного storage fetch.
- SwiftUI `List` заменён на view-based `NSTableView`. AppKit keyboard monitor через weak bridge в том же вызове применяет highlight и `scrollRowToVisible`; `onAppear`/prefetch больше не используется как эвристика видимости.
- Enter больше не ждёт следующего main-run-loop turn: single transaction создаётся непосредственно в key handler. Mark-used обновляет durable/cache recency, но видимый порядок публикуется только при следующем fresh show.
- Reusable History panel prewarm-ится после startup reload, чтобы первый пользовательский show не оплачивал создание SwiftUI/AppKit hierarchy.
- Временная payload-free unified trace локализовала SwiftUI render bottleneck и после принятого ручного smoke полностью удалена вместе с call sites и тестом.
- Passive click-away/Command-Tab скрывают только History без focus restoration. Paste Stack не получает ни mouse monitor, ни dismiss-on-resign behavior.

### Проверено

- После native-table rewrite focused History ViewModel/intent Xcode tests: 35 tests, 0 failures. Финальные Xcode и clean-copy SwiftPM suites: по 189 tests, 0 failures.
- Xcode Debug app собран для `arm64` и `x86_64`.
- Пользователь принял Xcode smoke cold/warm open, rapid Up/Down, non-first Enter без видимого jump и адаптивные одно-/многострочные rows. Trace показала среднюю реакцию стрелок `1.93 ms`, maximum `8.3 ms`, visual conceal на Enter `4.3–8.4 ms`.
- 2026-08-30 пользователь подтвердил полную manual macOS matrix, включая failure restore, VoiceOver/Delete/double-click и click-away/Command-Tab regression, на двух машинах.

### Отклонения и остаточные риски

- Реальный responder/focus path и клики по другим приложениям подтверждены пользователем на двух машинах.
- Успешный synthetic `Command-V` означает доставку события после активации target, но не подтверждает принятие текста конкретным target field.
