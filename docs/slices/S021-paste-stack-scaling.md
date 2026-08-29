---
id: S021
title: Масштабируемый Paste Stack
status: needs_verification
depends_on:
  - S020
covers:
  - FR-009
  - FR-010
  - FR-011
  - FR-012
  - NFR-019
---

# S021: Масштабируемый Paste Stack

## Результат

Paste Stack определяет следующий occurrence одним линейным проходом и готовит next-state один раз на UI snapshot, поэтому большой список не создаёт скрытый O(N²) render path.

## В scope

- direct/reverse next lookup без промежуточного `filter` array;
- вычисление exact next occurrence/ID один раз на render snapshot вместо повторения для каждой row;
- устранение повторных linear lookup/update там, где это безопасно без усложнения state machine;
- operation-count и large-stack regression tests;
- сохранение reorder, direction lock, reactivation priority, processing/used и duplicates.

## Вне scope

- новый durable Stack store;
- virtualization/custom collection UI без доказанной необходимости;
- изменение paste sequence или panel lifecycle;
- ограничение размера Stack.

## Контракты

- Direct выбирает первый eligible occurrence, reverse — последний; reactivation priority сохраняет прежний exact-ID precedence.
- Render preparation вызывает next traversal не более одного раза для одного snapshot независимо от row count.
- Duplicate text остаётся разными occurrences по UUID; reorder validation и contiguous positions не меняются.
- Оптимизация не добавляет stale cache, способный пережить mutation.

## Acceptance criteria

- [x] `nextOccurrence` не аллоцирует полный filtered array и выполняет не более одного прохода.
- [x] UI snapshot вычисляет next ID один раз, а строки сравнивают готовый ID без session traversal.
- [x] 0/1/N direct/reverse, reorder, append, used, processing и reactivation tests сохраняются.
- [x] Large-stack operation-count растёт линейно, а не квадратично.
- [x] Exact full text и bounded preview contract S020 сохраняются.

## Verification

- [x] Focused Stack state-machine and render-preparation tests.
- [x] S017 Stack baselines/operation counts до/после.
- [x] Full SwiftPM/Xcode suite и unsigned universal Release build.
- [ ] Manual reorder/direction/reactivate/paste smoke.

## Implementation report

### Реализовано

- `StackNextOccurrenceResolver` выбирает direct/reverse pending fallback и exact reactivation priority за один traversal без промежуточного filtered array.
- Paste reservation повторно использует найденный index для перехода в `.processing`, исключая дополнительные lookup после выбора next occurrence.
- `StackSessionController` готовит `nextOccurrenceID` вместе с каждым опубликованным session snapshot. SwiftUI rows сравнивают UUID за O(1) и больше не вызывают traversal для каждой строки.
- Derived next ID обновляется до существующей Combine publication и сам не создаёт дополнительный render signal.

### Проверено

- Focused Stack state-machine suite: 44 tests, 0 failures; direct/reverse, reorder, append, reservation, used/processing, failures и reactivation semantics сохранены.
- Performance suite: 9 tests, 0 failures. Worst-case 10 000-element resolver посетил ровно 10 000 occurrences, включая priority fallback; 10 000 UI rows использовали один traversal visit после snapshot preparation.
- Полный SwiftPM suite из clean copy: 172 tests, 0 failures. Полный unsigned Xcode Debug suite: 172 tests, 0 failures.
- Unsigned universal Release build прошёл с `arm64` и `x86_64`; bounded Stack preview и exact occurrence text tests остались зелёными.

### Отклонения и остаточные риски

- Ручной reorder/direction/reactivate/paste smoke в реальной panel не выполнялся; до него срез остаётся `needs_verification`.
- Reorder validation и UUID-based updates остаются линейными, но больше не умножаются на число UI rows. Custom virtualization не добавлялась без доказанной необходимости.
