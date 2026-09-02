---
id: S025
title: Referenced URL, file and video History
status: done
depends_on:
  - S023
  - S024
covers:
  - FR-028
  - FR-030
  - FR-031
  - BR-019
  - BR-020
  - BR-022
  - BR-023
  - BR-024
  - NFR-022
  - NFR-023
  - NFR-024
---

# S025: Referenced URL, file and video History

## Пользовательский результат

URL и локальные file/video selections появляются в общей History, ищутся по локальной metadata и повторно вставляются без копирования source bytes. Перемещённый или удалённый source получает проверяемое available/unavailable поведение, а Qipli никогда не удаляет исходный объект.

## В scope

- typed web URL occurrence без network fetch, favicon или remote title;
- Finder single и multi-file pasteboard changes с сохранением ordered items одной occurrence;
- UTType-based file/video classification и локальная filename/extension/type/item-count metadata;
- URL bookmark/reference create, resolve, stale refresh и unavailable state;
- lightweight file/video row presentation без чтения source contents и без mandatory generated media thumbnail;
- full-retention metadata search и bounded paging;
- multi-item typed pasteboard writeObjects/pasteback;
- moved, renamed, deleted, unmounted и permission-denied source states;
- Delete/expiry/Clear All только для reference metadata/derived cache;
- active text-only Stack explanation без media append.

## Вне scope

- managed copies file/video bytes, file-content indexing, OCR, transcription, codecs или playback;
- remote URL metadata/preview и любой новый network request;
- media Paste Stack;
- гарантированное восстановление source после удаления или недоступного volume;
- изменение source file, permissions или extended attributes.

## Данные и контракты

- Web URL хранит exact supported URL/string representations и derived local domain/title fallback. Parsing failure не превращает arbitrary string в URL kind.
- File/video item хранит bookmark/reference и last-known display metadata. Source byte size может отображаться как metadata, но не считается Qipli-owned storage.
- Bookmark resolution выполняется вне main actor только для availability refresh или selected paste. Successful stale resolution обновляет reference metadata durably.
- Multi-file occurrence остаётся одной row и одной paste transaction; item order соответствует source pasteboard.
- Missing/unavailable reference не удаляется автоматически и не считается успешным paste. Delete/Clear All reference не затрагивает source URL.

## Acceptance criteria

- [x] Web URL из browser сохраняет URL semantics, находится по URL/domain и повторно вставляется без network request.
- [x] Finder single/multi-file selection создаёт одну occurrence с правильным item count/order и повторно вставляется совместимому target.
- [x] Video file классифицируется по UTType/metadata и не читается целиком для capture, list, search или pasteboard preparation.
- [x] Rename/move на том же доступном storage проходит documented bookmark resolution path; stale bookmark обновляется без duplicate occurrence.
- [x] Deleted/unmounted/permission-denied source показывает unavailable state, не скрывает occurrence и не выполняет false successful paste.
- [x] Delete, expiry и Clear All удаляют только Qipli metadata/derivatives и byte-for-byte не меняют существующие source files.
- [x] Search находит occurrences за пределами первой page по filename, extension, domain и content type без OCR/file-content scan.
- [x] Media copy при active Stack не меняет Stack state и сохраняет ordinary `Command-V` text contract.

## Verification

- URL/classifier tests на web URL, file URL, plain text that resembles URL, image+URL representation mix и unsupported schemes.
- Bookmark adapter tests на create/resolve/stale/error с temporary files; real Finder behavior остаётся manual platform gate.
- Multi-item order/paste writer tests и bounded descriptor/search operation counts.
- File-ownership tests доказывают отсутствие source write/delete/copy, включая Clear All and expiry.
- Full SwiftPM/Xcode suite, universal Release, privacy/network scan и `git diff --check`.
- Manual browser URL, Finder single/multi-file, video, rename/move/delete/unmount, search, pasteback, active Stack и relaunch matrix.

## Implementation report

Реализовано:

- typed pasteboard classifier распознаёт web URL и Finder file URL, отличает video по UTType/расширению и сохраняет item order без чтения source bytes;
- Core Data получил reference manifest с bookmarkData для локальных файлов/video и exact URL string для web URL;
- History rows/search используют локальные filename/extension/domain/type metadata, а selected paste разрешает bookmark вне main actor, обновляет stale bookmark и fail-closed помечает unavailable;
- typed pasteback публикует `public.url` и `public.file-url`, Delete/Clear All/retention не удаляют source, а media copy при active Stack остаётся History-only;
- mixed pasteboard items сохраняют image и URL/file representations в одной History occurrence и восстанавливают их в одном ordered pasteboard item;
- добавлены regression tests для URL semantics, plain-text URL rejection, Finder multi-file/video classification, writer payload, stale move, unavailable source, search и source ownership.

Автоматические проверки: focused URL/reference/pasteboard suite — 44 теста; полный SwiftPM suite — 217 тестов, exit 0; Xcode Debug test — 217/217; Xcode Release universal build (`arm64` + `x86_64`) — `BUILD SUCCEEDED`; security-diff scan — 0 findings.

Пользователь подтвердил ручную матрицу: реальный browser URL, Finder single/multi-file и video, rename/move, deleted/unmounted/permission-denied source, search/pasteback в совместимые приложения, active Stack, relaunch и clean-console behavior. Срез закрыт как `done` на основании этого scoped user acceptance.
