---
id: S032
title: Полировка карточек и релевантный поиск History
status: needs_verification
depends_on:
  - S023
  - S024
  - S025
  - S027
covers:
  - FR-004
  - FR-006
  - FR-027
  - FR-031
  - FR-033
  - FR-040
  - FR-041
  - FR-042
  - FR-043
  - FR-044
  - BR-022
  - BR-023
  - BR-027
  - BR-032
  - BR-033
  - NFR-005
  - NFR-008
  - NFR-018
  - NFR-021
  - NFR-023
  - NFR-027
  - NFR-028
  - NFR-031
  - NFR-032
---

# S032: Полировка карточек и релевантный поиск History

## Пользовательский результат

Top Notch History показывает более спокойные карточки без дублирующих type labels. Изображение заполняет карточку, подпись остаётся читаемой на затемнённой подложке, а основной текст занимает меньше места. Клик меняет только selection без перезагрузки ленты. Обычный Backspace больше не удаляет History. Exact `⇧Backspace` удаляет выбранную occurrence, а запрос вроде `localhost` показывает сохранённые typed URL раньше incidental совпадений внутри text cards.

## В scope

- удаление видимых `Text`/`URL`/`Image`/`File`/`Video` labels при сохранении type icon и полного accessibility label;
- системный card text 13 pt и сохранение bounded multiline preview;
- full-bleed aspect-fill local thumbnail для image card, icon overlay, нижняя затемнённая подложка под bounded dimensions/status и accent selection border;
- честный image fallback до готовности thumbnail и полный reset thumbnail/overlay/constraints при переиспользовании card view другим типом;
- exact `⇧Backspace` как единственный keyboard delete shortcut для selected History occurrence при пустом или непустом Search;
- обычный Backspace, modified shortcuts, repeat и отсутствие selection проходят без History delete;
- pure relevance classification для existing localized case-insensitive substring matches;
- full-retention URL-first search order и stable ranked continuation без перестановки только уже загруженной chronological page;
- selection-only reconciliation для mouse click без `reloadData()`, повторного search/storage read или viewport jump;
- targeted visible-card update после готовности thumbnail без full-collection reload;
- сохранение existing Search debounce, generation cancellation, selected exact UUID, load-more, durable delete и typed paste contracts.

## Вне scope

- изменение capture classification: URL-подобный plain text не становится typed URL;
- remote URL title, favicon, website preview, OCR, image analysis или новый network owner;
- изменение card size, Top Notch geometry/motion, Search field layout, footer или Paste Stack cards;
- undo, confirmation dialog, Trash или новый retention/delete lifecycle;
- schema migration, FTS dependency, source-app metadata и пользовательские search filters;
- изменение `Enter`, `⇧Enter`, double-click, ordinary `⌘V`, History shortcut или target activation.

## UI и системные контракты

- Type label удаляется только из визуального layout. `TopNotchHistoryCardKind`, symbol и accessibility label продолжают сообщать тип, unavailable state и bounded detail.
- Text, URL, file и video cards используют icon плюс bounded 13-pt detail. Image card закрепляет существующий local thumbnail по четырём границам и рисует его с aspect fill внутри card mask. Thumbnail не меняет exact paste payload.
- Image metadata/state находится на нижней затемнённой подложке с достаточным contrast. Selection видима через accent border и дополнительный non-color signal; reuse из image в text и обратно не оставляет stale image, scrim или constraints.
- Native mouse selection уже применена `NSCollectionView` до публикации selected UUID. Следующий SwiftUI/AppKit reconciliation не снимает и не устанавливает её повторно, если target index path совпадает; повторный click по выбранной карточке не публикует новый selection state. Keyboard navigation сохраняет явный horizontal scroll для offscreen target.
- Snapshot revision отражает только изменение identity/order карточек. Готовность thumbnail имеет отдельные per-entry revisions и targeted update path только для соответствующего visible item, не вызывая `reloadData()` всей коллекции.
- Delete monitor принимает только non-repeat key-down для Backspace, exact Shift-only device-independent modifiers, focused History Search и существующего selected UUID. Query может быть пустым или непустым. Событие consume-ится только после принятого delete intent; обычный Backspace остаётся у `NSTextField`.
- Match semantics не меняются: entry остаётся результатом только когда existing searchable metadata содержит query по системным localized case-insensitive substring rules.
- Ranked order имеет три устойчивые группы: exact/prefix URL domain или address match; остальные typed URL metadata matches; остальные matches. Внутри группы используется `activityAt DESC, id DESC`.
- Unfiltered History продолжает использовать `(activityAt, id)` cursor. Search continuation использует `(rank, activityAt, id)`, принадлежит текущей query generation и сбрасывается после смены query или order-affecting mutation.
- Каждая page содержит не более 500 descriptors. Repository может последовательно сканировать fixed rank groups вне main actor, но UI не получает full-retention snapshot, exact media payload, bookmarks или thumbnail bytes в search descriptors.
- Search query, URL, card text, filenames, metadata и thumbnail content не попадают в logs, signposts, fixtures с пользовательскими данными или network requests.

## Acceptance criteria

- [ ] Ни одна History card не показывает отдельную type label; icon остаётся видимой, а VoiceOver сообщает type, bounded detail/state и selection.
- [ ] Основной card text использует системный шрифт 13 pt, сохраняет bounded multiline truncation и остаётся читаемым в Light/Dark и Increase Contrast.
- [ ] Готовый local image thumbnail заполняет карточку через aspect fill без внутренних полей; dimensions/status читаются на нижней затемнённой подложке, а selected card имеет различимую accent border.
- [ ] До готовности или при ошибке thumbnail image card показывает локальный fallback без network request; после reuse image card как text card старое изображение и overlay не остаются.
- [ ] Click по другой карточке меняет только прежний и новый highlight, сохраняет horizontal viewport и не вызывает `reloadData()`, повторный search/storage read или повторное применение уже установленного native selection. Повторный click по выбранной карточке является no-op.
- [ ] Готовность thumbnail обновляет только соответствующую видимую image card; остальные item views не reconfigure-ятся и full collection reload не выполняется.
- [ ] Обычный Backspace при пустом и непустом Search не вызывает delete. Exact `⇧Backspace` удаляет ровно selected occurrence через existing durable delete path и выбирает ближайший surviving result.
- [ ] Repeat, forward Delete, `Command`/`Control`/`Option` combinations, другое окно, потерянный Search focus и отсутствие selection не вызывают History delete.
- [ ] Для query `localhost` более старая typed URL occurrence с matching domain/address появляется раньше более свежих text occurrences, содержащих тот же substring.
- [ ] Exact/prefix URL match идёт раньше другого typed URL substring match, затем идут остальные matches; внутри каждой группы сохраняется strict activity/UUID order.
- [ ] Typed URL, находящаяся глубже первой chronological page, попадает на первую ranked search page. Load-more через границы rank groups возвращает каждую match occurrence ровно один раз без gap или duplicate.
- [ ] Unicode/composed/decomposed case-insensitive matching, rapid query cancellation, empty-query latest-first order, capture/promotion/delete mutations, selected paste и formatted/plain paste contracts не регрессируют.
- [ ] Search и thumbnail work остаются вне main actor, page содержит максимум 500 descriptors, а repository/UI не создают full payload snapshot или новый network path.

## Verification

- pure relevance tests: exact domain, domain prefix, full-URL prefix, URL substring, text substring, URL-like plain text, Unicode case variants и deterministic activity/UUID tie-break;
- Core Data paging tests на 0/1/499/500/501 matches, deep URL beyond the first chronological page, page ending внутри rank group, переход между группами, terminal cursor и отсутствие duplicate/gap;
- HistoryViewModel tests для stale generation, query reset, capture/promotion/delete во время ranked results и nearest surviving selection;
- pure keyboard admission tests для ordinary Backspace, exact Shift-only Backspace, non-empty query, repeat, forward Delete, extra modifiers, wrong window/focus и missing selection;
- card descriptor/reuse tests для отсутствия visible type label, сохранения accessibility type, 13-pt style contract, image/text state reset, lazy visible-card thumbnail request и fallback;
- collection reconciliation tests со spy/counter seam: different/same mouse selection дают zero reload, unchanged snapshot сохраняет viewport, keyboard offscreen selection сохраняет controlled scroll, actual IDs/order change даёт один reload, а thumbnail completion reconfigure-ит только целевой visible item;
- focused S023/S024/S025/S027/S031 regressions, затем полный SwiftPM/Xcode Debug suite, optimized universal Release build, payload/log/network scan и `git diff --check`;
- manual installed-app smoke: открыть Top Notch, несколько раз выбрать разные и уже выбранную карточку и подтвердить отсутствие flash/reload/viewport jump; найти `localhost` при более старой typed URL и новых text matches; проверить обычный Backspace и `⇧Backspace` в empty/filtered state; затем проверить targeted появление native/browser image thumbnails, horizontal reuse, selection, Light/Dark, Increase Contrast и VoiceOver.

## Implementation report

Реализовано 2026-09-04. History descriptors получили rank-aware continuation для трёх групп совпадений: exact/prefix typed URL, прочие typed URL и остальные matches. Core Data и fallback search сканируют retention window пакетами не более `limit + 1`, сохраняют `(rank, activityAt, id)` cursor и не передают payload snapshot. Добавлены regression tests для deep URL, перехода между группами и отсутствия duplicate/gap.

Top Notch cards больше не показывают отдельные type labels, используют 13-pt bounded detail и full-bleed aspect-fill для local image thumbnail с fallback/scrim/overlay и reset при reuse. Thumbnail completion остаётся targeted. Локальный delete monitor принимает только exact non-repeat `⇧Backspace` в History window с выбранной occurrence; обычный Backspace, forward Delete и прочие модификаторы проходят дальше. Существующие paste, capture, selection и formatted/plain contracts сохранены.

Уточнение FR-044/NFR-032 доведено до фактического coordinator path: повторный click и уже применённый native selection не вызывают повторный `deselect/select`, а изменение selection не вызывает `reloadData()`. Thumbnail completion передаёт отдельный bounded update token и reconfigures только соответствующий visible item; snapshot reload остаётся только за изменением identity/order. Reuse text card после image card очищает thumbnail, fallback и scrim.

После read-only ревью исправлены четыре дефекта: rank сохраняется в cursor после promotion, удаления и pruning; selection accessibility value обновляется вместе с native selection; coalesced thumbnail callback сохраняет per-entry revisions и обновляет только изменившиеся видимые cards; корневой card layer клиппит full-bleed image по continuous rounded corners. Добавлен regression test ranked load-more после удаления occurrence.

Автоматическая проверка: focused S032 suite `61 tests, 0 failures`; полный SwiftPM suite `236 tests, 0 failures` (headless named-pasteboard skips); unsigned Xcode Debug и Release universal builds (`arm64+x86_64`) прошли; Release version contract и embedded Sparkle runtime linking прошли; `git diff --check` прошёл. Остаётся manual installed-app matrix: visual card reuse, mouse selection/no reload, empty/filtered Backspace, URL-first search, thumbnail appearance, Light/Dark, Increase Contrast и VoiceOver.
