---
id: S004
title: Сбор и визуальная панель Paste Stack
status: needs_verification
depends_on:
  - S002
covers:
  - FR-007
  - FR-008
  - FR-015
  - BR-001
  - BR-002
  - BR-004
  - NFR-005
  - NFR-006
  - NFR-008
---

# S004 — Сбор и визуальная панель Paste Stack

## Пользовательский результат

Пользователь включает Paste Stack, видит компактную панель поверх источника и собирает в ней точную последовательность копирований, включая одинаковые значения.

## В scope

- начало/единственность stack session по `⌘⇧C` и status menu; hotkey дополнительно отправляет обычный `⌘C` в source selection, menu Start остаётся empty;
- in-memory `StackSession` и occurrence identity;
- empty/collecting panel поверх других приложений без перехвата `⌘V`;
- добавление истории-события в стек после успешного сохранения;
- duplicate display, безопасное preview и отмена пустой/collecting сессии;
- panel placement на текущем display и базовое поведение в Spaces/full screen.

## Вне scope

- drag reorder и выбор направления;
- последовательная вставка, used-state и reactivation;
- сохранение/восстановление сессии после перезапуска.

## Предусловия

- S002 завершён: каждое capture event имеет стабильную history identity.
- Поведение menu bar/panels из S001 не имеет незакрытых platform blockers.

## Ожидаемое поведение

- `⌘⇧C` сначала начинает session (либо сохраняет существующую), показывает nonactivating panel и отправляет tagged synthetic ordinary `⌘C` в остающееся active source app; target-owned pasteboard event затем проходит History-first capture pipeline.
- Menu Start всегда начинает пустым и не отправляет `⌘C`.
- Повторный `⌘⇧C` не создаёт/reset session, но повторно отправляет обычную Copy-команду для текущего source selection.
- Только копирования, произошедшие после старта, добавляются в session.
- Добавление в стек происходит после успешной записи в историю.
- Панель остаётся видимой, но не крадёт фокус у приложения-источника при обычном копировании.
- Закрытие до вставки уничтожает только session state.

## Состояния интерфейса

- empty collecting;
- one/many pending occurrences;
- duplicate previews как отдельные строки;
- transient storage/capture error;
- canceled/closed.

## Данные и контракты

- `StackOccurrence` соответствует `TECHNICAL.md`, живёт только в памяти.
- Preview может визуально сокращать длинную строку, но occurrence хранит полный неизменённый text.
- ID occurrence уникален даже при одинаковых `historyEntryID`/text; в нормальном capture flow каждая запись истории также уникальна.
- Активна не более чем одна StackSession.

## Acceptance criteria

- [ ] `⌘⇧C` из другого приложения начинает/сохраняет одну stack session, показывает panel и отправляет обычный `⌘C` в source selection; resulting external copy сначала появляется в History, затем как первый/очередной Stack occurrence. Повторное сочетание не создаёт/reset session, но копирует очередное selection. Status menu Start начинает пустой Stack без Copy. Автоматическое coordinator coverage пройдено; требуется ручная macOS проверка.
- [ ] Каждое следующее текстовое копирование добавляется один раз в конец видимого списка и уже присутствует в общей истории. Автоматическое capture coverage пройдено; требуется ручная macOS проверка.
- [ ] Два одинаковых копирования показываются как два независимо идентифицируемых occurrence; Unicode и многострочный текст в модели не меняются. Автоматическое model coverage пройдено; требуется ручная macOS проверка.
- [x] Изменения без текстового представления и self-writes Qipli не добавляются; ошибка сохранения истории не создаёт «осиротевший» элемент только в стеке.
- [ ] Панель остаётся поверх обычных окон и позволяет продолжать `⌘C` в источнике без постоянной потери фокуса; на нескольких displays появляется рядом с активным экраном и не оказывается за его видимой рамкой. Требуется ручная macOS проверка.
- [x] До реализации S006 обычный `⌘V` не перехватывается и не меняет occurrence state.
- [ ] Глобальный `Esc` из приложения-источника при активной панели или её close control завершает сессию и скрывает панель; собранные тексты остаются в истории. Требуется ручная macOS проверка.
- [ ] Новый запуск стека после отмены начинает пустую сессию; прежний список не восстанавливается после перезапуска Qipli. Требуется ручная macOS проверка.

## Verification

- [x] Unit tests session start/uniqueness, append, duplicates, cancel и deallocation.
- [x] Integration test: history save succeeds before occurrence append; store failure leaves stack unchanged.
- [x] Coordinator tests: hotkey start/show/copy ordering, repeated hotkey, menu-empty start, dispatch failure и tagged `⌘C` pass-through.
- [x] UI model seam: empty/collecting/duplicate state feeds the panel without XCUI; native nonactivating focus и close action требуют ручной проверки.
- [ ] Ручной сбор из TextEdit, браузера и редактора кода без потери `⌘C` focus.
- [ ] Ручная проверка двух displays и одного full-screen/Space сценария.
- [ ] Проверка, что cancel не удаляет записи из history panel после повторного открытия.

## Definition of Done

- [ ] Все acceptance criteria выполнены.
- [ ] Автоматические и ручные проверки пройдены.
- [x] Приложение собирается без новой регрессии.
- [x] `STATE.md` и frontmatter синхронно обновлены.
- [x] `DECISIONS.md` синхронизирован: принято D-014 для изменённой семантики `⌘⇧C`; применяется D-010.
- [x] Implementation report заполнен.

## Implementation report

### Реализовано

- `StackSession`/`StackOccurrence` и `StackSessionController`: единственная in-memory session, UUID token/occurrence, append-only duplicate-preserving collection и release on cancel.
- Capture coordinator сохраняет History до Stack append и сверяет snapshot session token plus pasteboard start watermark, поэтому delayed event до Start или после cancel не попадает в новую session.
- `⌘⇧C` coordinator создаёт/сохраняет session с watermark до tagged ordinary `⌘C`, показывает panel без activation и оставляет target app владельцем resulting pasteboard write; menu Start не dispatch-ит Copy.
- Nonactivating floating Paste Stack panel с empty/collecting/error state, read-only truncated previews, Cancel и native close handling; Start/Cancel menu state и exact global Escape.
- Stack panel выбирает screen под курсором и pure placement clamp к `visibleFrame`; history/permission panels сохранили прежний center behavior.

### Изменённые файлы

- `Sources/Qipli/PasteStack/StackSession.swift`
- `Sources/Qipli/PasteStack/StackCollectionCaptureCoordinator.swift`
- `Sources/Qipli/PasteStack/StackCollectionStarter.swift`
- `Sources/Qipli/App/ApplicationShell.swift`
- `Sources/Qipli/History/HistoryViewModel.swift`
- `Sources/Qipli/Input/GlobalInput.swift`
- `Sources/Qipli/Input/CGEventTapAdapter.swift`
- `Sources/Qipli/UI/PanelController.swift`
- `Sources/Qipli/UI/PlaceholderViews.swift`
- `Tests/QipliTests/PasteStackTests.swift`, `Tests/QipliTests/InputCoordinatorTests.swift`, `Qipli.xcodeproj/project.pbxproj`
- `docs/TECHNICAL.md`, `docs/STATE.md`, этот slice

### Выполненная проверка

- SwiftPM и Xcode Debug XCTest: 59 tests, 0 errors; universal Release `arm64+x86_64` build прошёл.
- Deterministic checks: duplicates/Unicode, start uniqueness, hotkey start/show/copy ordering and repeat, menu-empty start, copy dispatch failure, cancel release/new empty session, history-before-stack, store failure, stale deferred token/start watermark, Escape active filter, tagged/ordinary `⌘C`, ordinary `⌘V` pass-through и panel placement math.
- Требуется ручная macOS matrix перед `done`.

### Отклонения от плана

Нет.

### Оставшиеся проблемы

- Manual verification: hotkey Copy of source selection and repeat behavior, source-app focus during `⌘C`, global Escape/cancel, panel close, multiple displays и full-screen/Space behavior.
