---
id: S018
title: Эффективное History storage
status: planned
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

- [ ] Persistent model объявляет и реально создаёт UUID index; SQLite query plan перестаёт делать full table scan для exact ID.
- [ ] Expired cleanup использует batch delete и сохраняет boundary `age >= 30 days`.
- [ ] Existing SQLite store проходит lightweight migration и durable restart test.
- [ ] Duplicate text/UUID uniqueness, mark-used promotion, delete-one и clear-all сохраняют поведение.
- [ ] Sort index принимается только с измерением; при отсутствии доказанного выигрыша решение явно записано в Implementation report.

## Verification

- [ ] Repository and migration focused tests на temporary stores.
- [ ] Query-plan/index inspection без чтения production payload.
- [ ] S017 storage baselines до/после.
- [ ] Full SwiftPM/Xcode suite и unsigned universal Release build.

## Implementation report

### Реализовано

Не заполнено.

### Проверено

Не заполнено.

### Отклонения и остаточные риски

Не заполнено.
