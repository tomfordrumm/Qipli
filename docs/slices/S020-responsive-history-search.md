---
id: S020
title: Отзывчивый поиск и ограниченные previews
status: needs_verification
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

- [x] Быстрый ввод нескольких query публикует только результат последнего generation.
- [x] Search не выполняет линейный full-snapshot filter на main actor и сохраняет localized case-insensitive substring behavior.
- [x] Empty/no-results/selection/navigation остаются корректными при async completion.
- [x] Preview traversal ограничен `limit + 1`, корректен для Unicode grapheme clusters/multiline и не раскрывает лишний текст.
- [x] Full long text находится по фрагменту за preview boundary и вставляется без усечения.

## Verification

- [x] Focused cancellation/stale-result/search-semantics tests.
- [x] Preview operation-count и long-text exact-paste tests.
- [x] S017 search/preview baselines на 1 800/10 000/50 000 synthetic entries.
- [x] Full SwiftPM/Xcode suite и unsigned universal Release build.
- [ ] Manual rapid typing/clear/retype smoke в History.

## Implementation report

### Реализовано

- `BackgroundHistorySearcher` выполняет localized case-insensitive substring filter за actor boundary над immutable value snapshot; каждое обновление query отменяет прежнюю task и увеличивает generation.
- Общий `HistorySearchMatcher` является production implementation и test seam: на каждом незавершённом поиске он инспектирует каждую запись ровно один раз, исключая скрытый вложенный full-snapshot traversal.
- Непустой query получает debounce 100 ms, состояние `Searching…` и stale-result guard; empty query синхронно возвращает текущий ordered snapshot.
- Async reload/capture/delete дожидаются актуального background filter перед возвратом, поэтому storage mutation не оставляет промежуточный пустой result.
- Общий `BoundedTextPreview` для History и Paste Stack обходит максимум `limit + 1` Unicode grapheme clusters. Stored/search/paste text остаётся полным и точным.

### Проверено

- Focused History search suite: 14 tests, 0 failures, включая управляемое завершение stale generation и подтверждение off-main search.
- Long Unicode/multiline preview test подтвердил ровно `limit + 1` traversal; exact-paste test нашёл marker за preview boundary и записал полный text.
- S017 performance baseline suite остаётся зелёным на snapshots 1 800/10 000/50 000 и long-text fixture.
- Corrective operation-count gate 2026-08-29 подтвердил inspection counts `1 800/10 000/50 000`; совместный Xcode performance/search run прошёл 25/25.
- Полный SwiftPM suite из clean copy: 170 tests, 0 failures. Полный unsigned Xcode Debug suite: 170 tests, 0 failures.
- Unsigned universal Release build прошёл с `arm64` и `x86_64`.

### Отклонения и остаточные риски

- Ручной rapid typing/clear/retype smoke в реальной History panel не выполнялся; до него срез остаётся `needs_verification`.
- Search по-прежнему линейный по полному snapshot; срез устраняет main-thread stall и stale publication, но сознательно не вводит FTS и не меняет substring semantics.
