---
id: S021
title: Масштабируемый Paste Stack
status: planned
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

- [ ] `nextOccurrence` не аллоцирует полный filtered array и выполняет не более одного прохода.
- [ ] UI snapshot вычисляет next ID один раз, а строки сравнивают готовый ID без session traversal.
- [ ] 0/1/N direct/reverse, reorder, append, used, processing и reactivation tests сохраняются.
- [ ] Large-stack operation-count растёт линейно, а не квадратично.
- [ ] Exact full text и bounded preview contract S020 сохраняются.

## Verification

- [ ] Focused Stack state-machine and render-preparation tests.
- [ ] S017 Stack baselines/operation counts до/после.
- [ ] Full SwiftPM/Xcode suite и unsigned universal Release build.
- [ ] Manual reorder/direction/reactivate/paste smoke.

## Implementation report

### Реализовано

Не заполнено.

### Проверено

Не заполнено.

### Отклонения и остаточные риски

Не заполнено.
