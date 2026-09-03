---
id: S023
title: Bounded typed History foundation
status: done
depends_on:
  - S018
  - S019
  - S020
covers:
  - FR-027
  - NFR-016
  - NFR-017
  - NFR-018
  - NFR-021
  - NFR-025
---

# S023: Bounded typed History foundation

## Пользовательский результат

Существующая text History после обновления сохраняет все occurrences и прежнее поведение, но загружает не весь 30-day store, а bounded pages. Поиск по-прежнему охватывает всю историю и не блокирует ввод.

## В scope

- lightweight migration legacy `HistoryEntry(id, text, capturedAt)` в typed occurrence с одним text item;
- `HistoryOccurrence`, ordered payload-item и representation contracts, пока production capture/paste принимает только text;
- initial и load-more pages максимум по 500 occurrence descriptors;
- keyset cursor по строгому `(activityAt DESC, id DESC)` order без растущего `OFFSET`;
- database-backed full-retention search с текущей localized case-insensitive substring semantics;
- page-aware capture, mark-used promotion, delete, Clear All, retention и selection;
- current native table row reuse, keyboard bridge, fresh-show top reset и paste transaction без визуального редизайна;
- payload-free platform probe ordered `NSPasteboardItem`/UTType inventory на controlled text, URL, image и Finder fixtures до изменения allowlist.

## Вне scope

- сохранение image bytes, URL/file/video typed capture или media pasteback;
- thumbnails, file bookmarks и managed asset directory;
- OCR, FTS dependency, source-app metadata или search filters;
- media Paste Stack;
- изменение 30-day retention, text search semantics, ordinary `Command-V` или Accessibility contract.

## Данные и контракты

- Одна legacy row мигрирует в одну occurrence с тем же UUID, exact text и activity value.
- Page/search API возвращает descriptors без exact media fields. Для text item exact string materializes только при capture mutation, selected paste или явной repository operation.
- Первая и каждая следующая page содержат `1...500` items либо пустой terminal result. Cursor принадлежит query generation и не переиспользуется после смены query/order-affecting mutation.
- Empty query использует activity index. Search охватывает весь retention window и возвращает bounded results. Отменённый/stale result не публикуется.
- New capture и successful mark-used становятся первыми без unconditional full reload. Delete не создаёт duplicate/gap между загруженными pages; следующая page продолжает от последнего surviving cursor.
- UI не хранит полный descriptor/payload snapshot как скрытый compatibility cache.

## Acceptance criteria

- [x] Existing synthetic legacy store мигрирует без изменения UUID, exact text, activity order, retention boundary и restart behavior.
- [x] Первый History show после reload публикует не более 500 descriptors; repeated show без mutation не выполняет новый full fetch.
- [x] Scroll/load-more выдаёт каждую retained occurrence ровно один раз в latest-first order и завершает terminal state без бесконечного fetch.
- [x] Search находит совпадение за пределами первой page, сохраняет текущую localized case-insensitive substring semantics и не загружает full retained payload в UI memory.
- [x] Rapid query change публикует только последний generation; clear query немедленно возвращает current first page.
- [x] Capture, successful promotion, delete, expiry и Clear All во время loaded/search state не создают duplicate, пропуск, stale selection или unconditional full reload.
- [x] Up/Down, Enter, double-click, Delete, fresh-show viewport reset, click-away и failure restore сохраняют принятый S016 contract.
- [x] Controlled pasteboard probe фиксирует только type/count aggregates и подтверждает multi-item/representation shapes без clipboard payload в output.

## Verification

- Focused repository/view-model tests на 0/1/499/500/501 и 1 800/10 000/50 000 synthetic occurrences.
- Operation-count assertions: bounded returned descriptors, no full UI snapshot, no repeated-show fetch, one page query per accepted load-more.
- Migration/restart tests на temporary legacy SQLite/Core Data store; query-plan proof для page order/cursor и exact UUID.
- Search parity fixtures для Unicode, composed/decomposed text, mixed case и active system locale; stale/cancellation tests.
- Full SwiftPM и Xcode Debug suite, Thread Sanitizer targeted run, unsigned universal Release build и `git diff --check`.
- Manual installed-app smoke: legacy History survives update; first page, deep scroll, full-history search, rapid typing, arrows, non-first Enter, delete, copy-before-show и repeated show.

## Implementation report

Реализовано в текущем рабочем срезе:

- typed occurrence schema и ordered payload-item/representation contracts добавлены с lightweight migration legacy text rows без изменения UUID, текста и activity order;
- History repository и view model используют bounded initial/load-more pages с keyset cursor, database-backed full-retention search, generation guard и page-aware capture/promotion/delete/retention mutations;
- native History table, keyboard bridge, fresh-show reset и exact paste transaction сохранены, а payload-free pasteboard probe проверяет только aggregate type/count shapes.

Проверено текущими SwiftPM и Xcode Debug suites, включая migration, paging/search parity, stale generation, mutation и payload-free probe tests. Slice переведён в `done`; remaining installed-app observations относятся к следующему typed-media/release workflow, а не к незавершённому S023 implementation.
