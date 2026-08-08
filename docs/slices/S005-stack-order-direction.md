---
id: S005
title: Порядок и направление обхода
status: needs_verification
depends_on:
  - S004
covers:
  - FR-009
  - FR-010
  - BR-005
  - NFR-005
  - NFR-008
---

# S005 — Порядок и направление обхода

## Пользовательский результат

До начала вставки пользователь видит будущую последовательность, может переставить элементы и выбрать прямой или обратный обход без изменения их текста.

## В scope

- drag-and-drop либо эквивалентная нативная перестановка pending occurrences;
- direct/reverse control, direct по умолчанию;
- явная маркировка следующего элемента и визуальное объяснение обхода;
- чистые state-machine transitions и accessibility/keyboard fallback для reorder;
- блокировка изменения базового порядка после первого обработанного paste event как согласованное предположение MVP.

## Вне scope

- фактический перехват `⌘V` и used-state;
- reactivation;
- сохранённые пользовательские настройки направления;
- произвольное редактирование текста элемента.

## Предусловия

- S004 завершён и occurrence identity стабилен.
- Предположение BR-005 не отклонено по результатам UX-проверки S004.

## Ожидаемое поведение

- Видимый список — базовый порядок, а маркер направления объясняет traversal.
- Direct выбирает первый pending сверху, reverse — последний pending снизу.
- Перестановка и смена направления мгновенно пересчитывают next, но не создают/удаляют записи истории.
- Одинаковые элементы переставляются по occurrence ID, а не по text.

## Состояния интерфейса

- direct/reverse selected;
- drag/reorder active;
- next marker;
- single item;
- controls locked после начала вставки (используется с S006).

## Данные и контракты

- `position` описывает базовый видимый порядок и уникален внутри текущей сессии.
- Направление — session-level enum, default `.direct`.
- State machine возвращает deterministic next occurrence для любого списка и направления.
- Reorder API принимает occurrence IDs и отклоняет отсутствующие/повторяющиеся ID без частичной мутации.

## Acceptance criteria

- [x] При двух и более элементах пользователь может изменить базовый порядок; после операции каждый occurrence присутствует ровно один раз, а full text и history records не меняются.
- [x] Direct выбран по умолчанию и маркирует верхний pending occurrence следующим; reverse маркирует нижний pending occurrence следующим.
- [x] После перестановки в direct/reverse next и визуальная последовательность соответствуют BR-005, включая несколько одинаковых текстов.
- [x] Один элемент корректно показывается следующим в обоих направлениях; пустой стек не предлагает reorder.
- [x] Есть keyboard/accessibility fallback для перемещения элемента без обязательного drag gesture, а направление имеет понятные label/state.
- [x] Reorder с некорректным occurrence ID отклоняется атомарно и не портит session state.
- [x] После сигнала «вставка началась» controls порядка/направления становятся недоступными и не меняют уже выбранный traversal; до S006 это проверяется state-machine contract test.

## Verification

- [x] Property/unit tests: reorder сохраняет набор ID и уникальность positions.
- [x] Unit tests direct/reverse для 0/1/N элементов и одинаковых текстов.
- [x] Unit test invalid reorder не выполняет частичную мутацию.
- [x] Deterministic UI intent/model seam покрывает native drag reorder, accessible move up/down fallback, direction toggle, next marker labels и disabled control state; XCUI gesture loop не добавлялся.
- [ ] Ручная проверка длинных/multiline previews и VoiceOver labels основных controls.

## Definition of Done

- [x] Все acceptance criteria выполнены автоматической проверкой; ожидается ручная macOS matrix.
- [ ] Автоматические и ручные проверки пройдены.
- [x] Приложение собирается без новой регрессии.
- [x] `STATE.md` и frontmatter синхронно обновлены.
- [x] Новые значимые решения не требуются: контракт следует BR-005 и существующему in-memory lifecycle.
- [x] Implementation report заполнен.

## Implementation report

### Реализовано

- `StackSession` хранит только in-memory base visible order, `.direct`/`.reverse` и deterministic next occurrence. `reorder(occurrenceIDs:)` принимает exact-ID permutation целиком, перенумеровывает position в `0...N-1` и отвергает invalid/missing/duplicate/non-permutation input до мутации.
- Reorder безопасен для duplicate text; text/historyEntryID не меняются. Внешний copy append после reorder добавляется в конец base order.
- `markTraversalStarted()` — узкая граница для S006: она блокирует direction/reorder, но не добавляет перехват `⌘V`, used-state, actual paste, reactivation или persistence.
- Compact nonactivating panel показывает segmented direct/reverse state, текстовое объяснение top/bottom next и явный Next marker. Native macOS `List.onMove` даёт drag reorder; accessible Move Up/Down controls с ясными labels используют те же occurrence-ID intents. Locked/single-item rows остаются читаемыми, а movement controls отключаются.

### Изменённые файлы

- `Sources/Qipli/PasteStack/StackSession.swift`
- `Sources/Qipli/UI/PlaceholderViews.swift`
- `Sources/Qipli/UI/PanelController.swift`
- `Tests/QipliTests/PasteStackTests.swift`
- `docs/TECHNICAL.md`, `docs/STATE.md`, этот slice

### Выполненная проверка

- SwiftPM `swift test`: 65 tests, 0 failures.
- Xcode Debug XCTest (`Qipli`, macOS): 65 tests, 0 failures; native macOS `List.onMove` compiles in the app target.
- Xcode Release universal `arm64+x86_64` build: successful with `CODE_SIGNING_ALLOWED=NO`.
- Остаются ручные проверки: real drag, visible direct/reverse/next for empty/single/multiple and duplicate/multiline values, VoiceOver labels and Move Up/Down behavior, plus source-focus preservation while Stack collects.

### Отклонения от плана

Нет.

### Оставшиеся проблемы

Нет; S006/S007 behavior намеренно не добавлялся.
