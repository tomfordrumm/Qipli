---
id: S031
title: Форматированный текст в History
status: needs_verification
depends_on:
  - S023
  - S026
  - S027
covers:
  - FR-005
  - FR-037
  - FR-038
  - FR-039
  - BR-019
  - BR-022
  - BR-024
  - BR-029
  - BR-030
  - BR-031
  - NFR-005
  - NFR-006
  - NFR-008
  - NFR-016
  - NFR-021
  - NFR-023
  - NFR-024
  - NFR-030
---

# S031: Форматированный текст в History

## Пользовательский результат

Текст, скопированный из приложения с форматированием, остаётся доступным в 30-дневной History вместе с исходными стандартными RTF/HTML representations. `Enter` и double-click вставляют наиболее совместимое сохранённое представление вместе с plain-text fallback, а `⇧Enter` намеренно вставляет только plain text. Default `⌘⇧V` по-прежнему открывает History, а Paste Stack остаётся text-only.

## В scope

- capture одного pasteboard change как одной occurrence с canonical plain text и source-provided `public.rtf`/`public.html` representations того же ordered item;
- raw byte preservation стандартных RTF/HTML без преобразования всей History в `NSAttributedString` и без нормализации markup;
- Qipli-managed opaque storage для admitted rich payload вне page/search/UI descriptors;
- default rich History paste по `Enter` и double-click с plain-text representation в том же pasteboard item;
- explicit plain History paste по exact `⇧Enter`, сохраняющий существующий target activation, conceal, self-write и single-transaction contracts;
- видимая и VoiceOver-доступная подсказка `Enter — Paste` / `⇧Enter — Paste as Plain Text` без нового configurable global shortcut;
- plain-only fallback при превышении rich payload limits и non-payload notice, не блокирующий сохранение допустимого текста;
- lightweight schema migration с сохранением legacy/plain, URL, image и file/video occurrences;
- Delete, 30-day expiry, Clear All, orphan cleanup и release/update data-preservation для managed rich payload;
- active Paste Stack получает только immutable canonical plain text, хотя соответствующая History occurrence может сохранить rich representations.

## Вне scope

- `public.rtfd`, WebArchive, Office/private/dynamic pasteboard types, arbitrary MIME passthrough и lazy data providers;
- визуальный rich-text renderer внутри History, HTML preview, font installation или pixel-perfect preview source app;
- sanitization, rewriting, semantic comparison или conversion RTF ↔ HTML;
- загрузка external resources, указанных внутри HTML, и любой новый network owner;
- rich text внутри Paste Stack или изменение ordinary `⌘V` вне active Stack;
- пользовательская настройка allowlist/limits и отдельный global shortcut для plain paste;
- гарантия одинакового результата во всех target apps: target выбирает поддерживаемую representation по системному pasteboard contract.

## Данные и системные контракты

- Existing `HistoryEntry.text` остаётся canonical exact plain string для validation, search, preview и Stack. Richness не определяется через текущий `isTypedEntry == !isTextOnly`; materialization должен использовать явное наличие rich manifest/representations.
- Rich manifest хранит occurrence ID, ordered item position, per-item canonical plain text, allowlisted UTType identifier, opaque relative asset path, byte count и integrity digest. Raw RTF/HTML bytes не входят в Core Data page object, descriptor или UI state.
- Reader snapshots advertised types одного observed `changeCount`, читает canonical `.string` и затем allowlisted `.rtf`/`.html` того же item последовательно. Каждый type запрашивается не более одного раза, одновременно удерживается не более одного rich candidate сверх уже принятого payload, private/dynamic types не materialize-ятся.
- Production safety default: максимум 16 MiB на одну RTF/HTML representation, 32 MiB суммарно на rich representations одной occurrence и 512 MiB на все durable rich-text assets. Policy инъецируется в тесты. `NSPasteboardItem.data(forType:)` может вернуть уже полностью materialized `Data`, поэтому cap ограничивает admission/persistence, но не обещает streaming или pre-read rejection. Controlled TextEdit/browser probe до реализации измеряет обычные и oversized samples; изменение чисел обновляет D-039 и этот slice до продолжения.
- Если rich representation отсутствует, превышает per-representation/occurrence/total limit или не может быть durably записана, но canonical text допустим, occurrence атомарно сохраняется как plain-only. UI показывает bounded non-payload notice; descriptor и логи не раскрывают содержимое, размер или source metadata.
- Если уже сохранённый rich asset отсутствует или повреждён, default rich paste fail closed до conceal/target activation и предлагает повторить через `⇧Enter`. Автоматическая тихая деградация при paste не подменяет выбранное пользователем действие.
- Default rich payload записывает `.string`, `.rtf` и/или `.html` в один `NSPasteboardItem` в source order. Plain mode строит новый payload только с `.string`; derived preview/search text никогда не становится paste payload.
- Exact final `changeCount`, prepared manifest identity и reserved occurrence сверяются непосредственно перед tagged `⌘V`; внешняя смена pasteboard отменяет transaction с retryable non-payload error.

## Acceptance criteria

- [ ] Rich text из TextEdit и browser/contenteditable создаёт одну History occurrence: canonical text остаётся exact, а присутствующие allowlisted RTF/HTML bytes переживают restart без попадания в descriptor/search snapshot.
- [ ] `Enter` и double-click пишут один ordered pasteboard item со всеми сохранёнными standard rich representations и exact plain fallback; compatible target сохраняет bold/italic/underline, link, list и paragraph structure в пределах source/target capabilities.
- [ ] Exact `⇧Enter` по выбранной rich occurrence пишет только `.string`, закрывает Top Notch и вставляет plain text в captured target; `⌘⇧V` продолжает только открывать History.
- [ ] Для plain/legacy occurrence `Enter`, double-click и `⇧Enter` дают прежний exact plain result без duplicate History occurrence или изменения activity semantics.
- [ ] Rich payload больше 16 MiB на representation, 32 MiB на occurrence либо выходящий за 512 MiB total quota не сохраняется как managed asset; допустимый canonical text сохраняется plain-only, existing History не удаляется, а пользователь получает bounded non-payload notice. Test не заявляет pre-read rejection, которого не предоставляет AppKit.
- [ ] Missing/corrupt rich asset не запускает synthetic paste и оставляет History открытой с retryable state; последующий `⇧Enter` вставляет сохранённый canonical plain text.
- [ ] Delete, expiry и Clear All сначала делают occurrence недоступной, затем удаляют rich manifest/assets; interrupted write/delete оставляет только распознаваемый Qipli orphan для startup maintenance.
- [ ] Active Paste Stack при rich copy сохраняет rich occurrence в History, но добавляет/вставляет только canonical plain text и не меняет ordinary `⌘V`, traversal или self-write contracts.
- [ ] RTFD, WebArchive, private/dynamic types и remote resources не читаются и не добавляют сеть, dependency, source path или payload в logs/telemetry.
- [ ] Existing URL/image/file/video capture, bounded paging/search, Top Notch keyboard selection, target activation, double-click, click-away and failed-paste reopen не регрессируют.

## Verification

- reader/classifier contract tests с synthetic `NSPasteboardItem`: `.string` only, `.string + .rtf`, `.string + .html`, all three, two ordered items, empty/whitespace string, unsupported/private types и one-read counters;
- storage tests: raw byte equality after restart, lightweight schema migration from current store, no rich bytes in descriptors, atomic commit, delete/expiry/Clear All, corrupt/missing asset и orphan maintenance;
- capacity tests с injected small per-representation/per-occurrence/total limits плюс boundary cases `limit - 1`, `limit`, `limit + 1`; доказывают sequential one-read admission, немедленный discard oversized candidate, plain-only fallback и отсутствие auto-eviction;
- paste writer/executor tests: default multi-representation payload, explicit plain-only payload, exact `changeCount`, external-mutation fail closed, single transaction, repeat suppression и mark-used only after tagged dispatch;
- focused History input tests для Return/keypad Enter, exact Shift-only modifier, double-click, repeat и прочих modifiers; shortcut settings и global event-tap mappings не меняются;
- regression suites S023–S027 и S030, полный SwiftPM/Xcode suite, optimized universal Release, payload/log/network scan и `git diff --check`;
- manual macOS matrix: TextEdit rich source/target, Safari или Chrome contenteditable source/target, Notes и один установленный office editor; bold/italic/underline, font/color, hyperlink, list, paragraphs, Unicode/multiline, rich default paste, `⇧Enter` plain paste, relaunch, delete/Clear All и active Stack. IDE/plain target должен получить canonical text без заявления, что Qipli сохранил styling в несовместимом поле.

## Implementation report

Реализовано в текущем рабочем срезе:

- `PasteboardMonitor` сохраняет canonical `.string` и только source-provided `public.rtf`/`public.html` для одного observed change; rich capture остаётся одной text-primary History occurrence, сохраняет canonical text каждого ordered item и не добавляет private/dynamic representations;
- typed pasteboard reads сериализованы как one-in-flight operation: overtaken snapshot не публикует уже изменившееся live pasteboard содержимое, а следующий poll обрабатывает newest change;
- rich capture не перехватывает mixed image/reference changes: такие clipboard changes остаются на существующем typed image/reference path;
- text, rich text, images, references и mixed content проходят через единый `HistoryCapture`; общий capture result владеет публикацией descriptor и bounded notice;
- добавлены `HistoryRichTextAssetStore` и общий `ManagedAssetDirectory` с opaque UUID paths, root/symlink containment, SHA-256 integrity, atomic temp-to-managed writes, injected 16/32/512 MiB limits, plain-only fallback и orphan/temp cleanup;
- Core Data получил optional `richTextManifest` с lightweight model version bump. Restart, selected default paste, corruption fail-closed, Delete, expiry, Clear All и startup cleanup обслуживают rich assets вместе с существующими typed assets;
- production History view state хранит только bounded descriptors; exact payload materializes по UUID только перед paste. Legacy table presentation удалена, History и Paste Stack используют общий interruption-safe Top Notch lifecycle;
- `Enter`/double-click используют сохранённые rich representations с exact plain fallback в каждом ordered pasteboard item, `⇧Enter` использует только canonical plain text. Existing `⌘⇧V`, ordinary `⌘V` и text-only Paste Stack paths не менялись;
- History UI показывает bounded non-payload fallback notice и VoiceOver/keyboard hint для plain paste. Focused storage, paste, keyboard и reader contract tests добавлены.

Verification:

- focused SwiftPM S031 storage/paste/input checks: `30/30` passed, including mixed routing, per-item fallback and oversized-candidate rejection. The separate named-pasteboard reader contract test is skipped because named pasteboards are unavailable in the headless test environment;
- full SwiftPM run: `223` current tests executed, `5` named-pasteboard environment skips, `0` failures. Ten tests coupled only to the removed legacy History presentation were deleted with that implementation; the remaining suite includes overtaken-read ordering, rich/image/reference storage, paging, Stack and Top Notch regressions;
- `git diff --check` passed. Unsigned universal Xcode Debug build succeeded for arm64 and x86_64 with a clean redirected DerivedData directory;
- user confirmed completion of the manual S031 macOS checks; signed Release/update verification remains open.
