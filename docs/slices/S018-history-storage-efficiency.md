---
id: S018
title: Эффективное History storage
status: done
depends_on:
  - S017
covers:
  - FR-002
  - FR-006
  - NFR-016
---

# S018: Эффективное History storage

## Результат

Exact History lookup и retention не сканируют или материализуют весь store без необходимости, а выбранные Core Data indices подтверждены query-plan и regression tests.

## В scope

- persistent index для exact `id` lookup;
- измерение sort `capturedAt DESC, id DESC` и добавление sort/composite index только при доказанном выигрыше;
- batch delete для expired entries с корректным merge/reset context state;
- lightweight migration существующего SQLite store;
- repository tests для duplicates, retention boundary, delete, restart и query plan.

## Вне scope

- замена Core Data/SQLite;
- hard cap количества entries или длины текста;
- asynchronous UI/service pipeline — S019;
- изменение 30-дневного retention или capture-or-use activity semantics.

## Контракты

- Existing store открывается после schema change без потери полных текстов и duplicate occurrences.
- Exact UUID fetch использует индекс; retention выполняется store-level batch operation, не создавая managed object для каждой удаляемой записи.
- User-visible ordering остаётся `capturedAt DESC, id DESC`.
- Batch delete не оставляет stale objects/results в используемом context.

## Acceptance criteria

- [x] Persistent model объявляет и реально создаёт UUID index; SQLite query plan перестаёт делать full table scan для exact ID.
- [x] Expired cleanup использует batch delete и сохраняет boundary `age >= 30 days`.
- [x] Existing SQLite store проходит lightweight migration и durable restart test.
- [x] Duplicate text/UUID uniqueness, mark-used promotion, delete-one и clear-all сохраняют поведение.
- [x] Composite activity/order index принят после query-plan доказательства устранения temporary B-tree.

## Verification

- [x] Repository and migration focused tests на temporary stores.
- [x] Query-plan/index inspection без чтения production payload.
- [x] S017 storage baseline сравнён по стабильному query-plan до/после.
- [x] Full SwiftPM/Xcode suite и unsigned universal Release build.

## Implementation report

### Реализовано

- Persistent model получил exact `idIndex` и composite `activityOrderIndex(capturedAt, id)`.
- `versionHashModifier` явно запускает lightweight migration, потому что fetch-index changes сами по себе не меняют compatibility hash существующего store.
- Expired entries удаляются одним `NSBatchDeleteRequest` с object-ID merge вместо fetch/materialization каждого managed object.
- Migration/query-plan tests используют только temporary synthetic store; production payload не читается.

### Проверено

- Legacy capturedAt-only store мигрирован без потери exact text/UUID/activity. Exact ID plan изменился с full scan на `SEARCH ... USING COVERING INDEX ... idIndex`.
- Ordered plan больше не содержит `USE TEMP B-TREE`; SQLite использует composite activity/order index. Поэтому composite index принят, несмотря на дополнительную небольшую стоимость записи.
- Focused HistoryStore suite: 10 tests, 0 failures, включая batch cleanup 1 000 expired entries.
- Полный SwiftPM suite из clean copy: 162 tests, 0 failures. Full Xcode Debug tests и unsigned universal Release `x86_64 arm64`: пройдены.

### Отклонения и остаточные риски

- Индексы ускоряют lookup/order, но не устраняют synchronous main-thread Core Data boundary; это изолированно решает S019.
- Model migration проверена с существующей схемой S002. Clean-machine launch реального пользовательского store остаётся smoke gate при следующем установленном build.
