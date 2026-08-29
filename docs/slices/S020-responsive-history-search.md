---
id: S020
title: Отзывчивый поиск и ограниченные previews
status: planned
depends_on:
  - S019
covers:
  - FR-004
  - FR-005
  - NFR-018
  - NFR-019
---

# S020: Отзывчивый поиск и ограниченные previews

## Результат

Ввод в History остаётся отзывчивым на большом snapshot, старый search result не заменяет новый, а UI не обходит целиком длинный текст ради короткого preview; поиск и вставка продолжают использовать full exact text.

## В scope

- cancellable/debounced search вне main actor над immutable snapshot;
- generation/cancellation guard от stale results;
- прежняя localized case-insensitive substring semantics;
- единый bounded preview helper для History и Paste Stack;
- tests с большими синтетическими snapshots и длинным Unicode/multiline text.

## Вне scope

- FTS, новая database search dependency или изменение search semantics;
- truncation storage/search/paste payload;
- изменение History navigation/paste transaction;
- Stack traversal optimization — S021.

## Контракты

- Empty query немедленно возвращает текущий ordered snapshot.
- Непустой query вычисляется вне main actor; отмена или новый generation запрещают публикацию устаревшего результата.
- Preview читает максимум display limit плюс один Character для ellipsis и не вызывает полный `.count` большого String.
- Selected entry всегда хранит exact full text; pasteboard write не использует preview.

## Acceptance criteria

- [ ] Быстрый ввод нескольких query публикует только результат последнего generation.
- [ ] Search не выполняет линейный full-snapshot filter на main actor и сохраняет localized case-insensitive substring behavior.
- [ ] Empty/no-results/selection/navigation остаются корректными при async completion.
- [ ] Preview traversal ограничен `limit + 1`, корректен для Unicode grapheme clusters/multiline и не раскрывает лишний текст.
- [ ] Full long text находится по фрагменту за preview boundary и вставляется без усечения.

## Verification

- [ ] Focused cancellation/stale-result/search-semantics tests.
- [ ] Preview operation-count и long-text exact-paste tests.
- [ ] S017 search/preview baselines на 1 800/10 000/50 000 synthetic entries.
- [ ] Full SwiftPM/Xcode suite и unsigned universal Release build.
- [ ] Manual rapid typing/clear/retype smoke в History.

## Implementation report

### Реализовано

Не заполнено.

### Проверено

Не заполнено.

### Отклонения и остаточные риски

Не заполнено.
