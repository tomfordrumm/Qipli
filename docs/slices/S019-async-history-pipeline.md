---
id: S019
title: Асинхронный History pipeline
status: done
depends_on:
  - S018
covers:
  - FR-001
  - FR-002
  - FR-006
  - NFR-006
  - NFR-016
  - NFR-017
  - NFR-020
---

# S019: Асинхронный History pipeline

## Результат

Core Data work выполняется последовательно вне main actor, быстрые capture сохраняют порядок и History-first semantics, а повторный показ панели использует актуальный snapshot без безусловного полного reload.

## В scope

- serialized background repository/service execution boundary;
- async create/fetch/mark-used/delete/clear/retention API и immutable UI snapshots;
- строгая capture queue: durable History save → matching Stack append → main-actor publish;
- drain/flush перед user-triggered fresh History show;
- startup/hourly refresh без reload на каждый panel presentation;
- visible loading/error states и tests на thread/order/failure contracts.

## Вне scope

- изменение search algorithm/debounce — S020;
- новый persistence backend или parallel writes;
- изменение paste target handoff, ordinary `Command-V` или Stack traversal;
- потеря capture ради UI responsiveness.

## Контракты

- Ни один persistent fetch/save/delete/retention operation не исполняется на main thread.
- Capture operations сериализованы в observed pasteboard order. Stack occurrence появляется только после успешного durable History save и только для исходной matching session/watermark.
- Fresh show выполняет explicit poll и ждёт уже поставленную capture pipeline; затем показывает snapshot без второго full fetch.
- Repeated show при отсутствии storage/capture change не увеличивает full-fetch counter.
- UI публикуется только на main actor, managed objects не пересекают context boundary.

## Acceptance criteria

- [x] Injected store доказывает, что create/fetch/mark-used/delete/clear/retention вызываются не на main thread.
- [x] Rapid capture сохраняет порядок, duplicates и History-first Stack append; failure не создаёт Stack-only occurrence.
- [x] Copy непосредственно перед History shortcut появляется первым до presentation.
- [x] Два последовательных show без изменений выполняют не более одного initial/required fetch и не запускают unconditional reload.
- [x] Startup, hourly retention, delete-one, clear-all, mark-used promotion и error/retry states сохраняются.
- [x] Main actor остаётся доступен во время искусственно медленного store operation.

## Verification

- [x] Focused concurrency/order/failure tests с controlled fake store.
- [x] S017 fetch counters и capture baseline.
- [x] Full SwiftPM/Xcode tests; Thread Sanitizer или эквивалентный targeted run, если доступен стабильно.
- [x] Unsigned universal Release build.
- [x] Manual rapid-copy → immediate History show smoke без пропущенных entries.

## Implementation report

### Реализовано

- `SerializedHistoryService` изолирует synchronous policy/store API за последовательным actor boundary; `HistoryViewModel` получил async fetch/create/mark-used/delete/clear и публикует только value snapshots на main actor.
- `CoreDataHistoryStore` использует private-queue context для всех fetch/save/delete/retention operations; managed objects не покидают store boundary.
- Pasteboard events ставятся в ordered capture queue. Каждая операция сначала сохраняет History, затем добавляет matching Stack occurrence. При вызове History pasteboard опрашивается первым, cached panel показывается синхронно, а `drainPendingCaptures()` заканчивается в фоне и публикует свежий occurrence уже в открытую panel.
- Startup и hourly refresh остались явными lifecycle operations. `prepareForPresentation()` сбрасывает presentation state поверх загруженного snapshot и больше не делает unconditional fetch.
- Retry, delete, promotion и Settings Clear History переведены на async UI actions без блокировки main actor.
- Corrective fix 2026-08-29 возвращает обновлённый `activityAt` из serialized mark-used operation и сразу перестраивает cached order без fetch. Публикация происходит только после синхронного visual conceal, поэтому closing History не показывает reorder. Перед каждым presentation cached snapshot также применяет тот же строгий 30-day cutoff, поэтому recency и retention не зависят от следующего hourly reload.

### Проверено

- Controlled store подтвердил off-main выполнение fetch/create/mark-used/delete/clear и доступность main actor, пока fetch удерживается test semaphore.
- Ordered queue test подтвердил rapid duplicate captures, exact order, distinct occurrences и History-first failure contract; presentation-order test фиксирует `poll → cached panel → async drain start`.
- Repeated presentation test подтвердил неизменный fetch counter после initial load.
- Corrective focused tests подтвердили promotion использованного occurrence на первое место, cached presentation без повторной list publication и удаление истёкшего cached occurrence без увеличения fetch counter. `HistoryViewModelSearchTests`: 17 tests, 0 failures.
- Текущий corrective HEAD: полные Xcode и clean-copy SwiftPM suites по 189 tests, 0 failures; unsigned Xcode Release собран для `arm64` и `x86_64`.
- Полный SwiftPM suite из clean copy: 166 tests, 0 failures. Полный Xcode Debug suite: 166 tests, 0 failures. Targeted Thread Sanitizer run: пройден.
- Unsigned universal Release build: пройден, executable содержит `arm64` и `x86_64`.

### Отклонения и остаточные риски

- 2026-08-30 пользователь подтвердил rapid-copy → immediate History show smoke на двух машинах без пропущенных entries. Срез переведён в `done`.
- Очередь намеренно сериализует persistence: при очень медленном/недоступном store backlog сохраняет данные и порядок ценой задержки presentation, а не теряет capture.
