---
id: S019
title: Асинхронный History pipeline
status: planned
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

- [ ] Injected store доказывает, что create/fetch/mark-used/delete/clear/retention вызываются не на main thread.
- [ ] Rapid capture сохраняет порядок, duplicates и History-first Stack append; failure не создаёт Stack-only occurrence.
- [ ] Copy непосредственно перед History shortcut появляется первым до presentation.
- [ ] Два последовательных show без изменений выполняют не более одного initial/required fetch и не запускают unconditional reload.
- [ ] Startup, hourly retention, delete-one, clear-all, mark-used promotion и error/retry states сохраняются.
- [ ] Main actor остаётся доступен во время искусственно медленного store operation.

## Verification

- [ ] Focused concurrency/order/failure tests с controlled fake store.
- [ ] S017 fetch counters и capture baseline.
- [ ] Full SwiftPM/Xcode tests; Thread Sanitizer или эквивалентный targeted run, если доступен стабильно.
- [ ] Unsigned universal Release build.
- [ ] Manual rapid-copy → immediate History show smoke без пропущенных entries.

## Implementation report

### Реализовано

Не заполнено.

### Проверено

Не заполнено.

### Отклонения и остаточные риски

Не заполнено.
