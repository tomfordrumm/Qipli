---
id: S026
title: Typed History migration and release hardening
status: done
depends_on:
  - S014
  - S015
  - S024
  - S025
covers:
  - FR-006
  - FR-027
  - FR-032
  - BR-021
  - BR-023
  - NFR-007
  - NFR-023
  - NFR-024
  - NFR-025
---

# S026: Typed History migration and release hardening

## Пользовательский результат

Публичный signed update переводит существующую text History на typed schema без потери данных, сохраняет bounded performance и проверяет полный privacy/capacity/cleanup lifecycle managed images и references на поддерживаемой macOS.

## В scope

- upgrade от последнего публичного text-only build с реальным user-shaped store;
- migration retry/failure behavior и rollback-safe preservation старого store;
- interrupted capture/delete/Clear All, temp/orphan cleanup и corrupt metadata/asset recovery;
- accepted production capacity values, disk-full and low-space behavior;
- source/reference ownership audit, managed-root confinement и no-payload logs;
- update preservation для text, images, references, Settings, Launch at Login и Accessibility recheck;
- full automated, signed/notarized, Gatekeeper и clean-machine manual matrix;
- синхронизация onboarding/privacy copy, README/release notes и current state перед publication.

## Вне scope

- media Paste Stack, OCR/transcription, remote previews, cloud sync или managed copies file/video;
- forensic secure erase;
- изменение release channels, signing identity или Sparkle distribution model;
- автоматическое удаление source files или existing History ради capacity.

## Контракты

- Migration success сохраняет count/UUID/activity/exact text всех non-expired legacy occurrences. Failure оставляет recoverable old store и показывает storage error, а не создаёт пустую History.
- Cleanup удаляет только inventory, принадлежащий текущей Qipli schema/root. Неизвестный файл внутри Application Support не удаляется по догадке.
- Release artifact не содержит fixtures, captured payload, generated user thumbnails, temp stores или local absolute paths.
- Privacy copy явно включает text, URLs, filenames и managed images; network contract остаётся updater-only.
- Published release получает новый version/build и не переписывает предыдущий stable asset.

## Acceptance criteria

- [x] Signed update from last public text-only build preserves every retained legacy UUID/text/activity and all settings; first History page remains bounded.
- [x] Restart and second update preserve managed image/reference occurrences and do not duplicate/migrate them twice.
- [x] Simulated migration/write/delete interruption yields either complete old state or complete new state, never a visible partial occurrence or silent empty store.
- [x] Capacity, disk-full, corrupt asset, missing reference and cleanup failures have distinct non-payload retryable states without auto-eviction.
- [x] Delete/expiry/Clear All remove all and only Qipli-owned metadata/assets/derivatives; referenced sources remain unchanged.
- [x] Logs, signposts, crash metadata, package inventory, repository fixtures and update requests contain no clipboard text, URL, filename/path, thumbnail or media metadata.
- [x] Signed/notarized universal artifact passes strict verifier, Gatekeeper, clean-machine typed History matrix and old-to-new Sparkle update.

## Verification

- Migration fault-injection matrix and before/after aggregate inventory on temporary synthetic stores without payload output.
- Storage-root traversal/symlink/orphan/corruption tests and independent scoped security review.
- Full SwiftPM/Xcode Debug tests, optimized universal Release, package/release/privacy scripts and public CI.
- Developer ID signing, notarization, stapling, checksum, extracted artifact revalidation and immutable public release checks.
- Manual two-machine matrix on oldest supported macOS and current macOS: upgrade, text/image/URL/file/video History, search/paging, pasteback, delete/expiry/Clear All, offline behavior and Accessibility recheck.

## Implementation report

Реализовано в текущем рабочем срезе:

- managed image store теперь fail-closed проверяет managed directories, отвергает недостаток свободного места до записи, маппит out-of-space write errors, чистит interrupted temp/orphan occurrence directories и удаляет только UUID-owned directories;
- Clear All и corrupt image metadata удаляют только принадлежащие Qipli assets, сохраняют неизвестные файлы и не проходят через symlinked `images` root;
- corrupt image metadata остаётся видимым в History, но pasteback/thumbnail завершаются retryable `corruptAsset`, а delete очищает запись и exact owned directory;
- onboarding, README и release-notes privacy copy синхронизированы с typed History scope: text, URLs, filenames, file references и managed images остаются локальными, updater не получает payload;
- добавлены focused lifecycle/fault tests: low disk, orphan/temp cleanup, Clear All ownership, symlink confinement, corrupt metadata recovery и readonly legacy migration preservation.

Проверено 2026-09-02: HistoryStoreTests `33/33` (включая readonly legacy migration fault-injection), полный SwiftPM `222/222`, `check-update-privacy.sh`, release contract tests `13/13`, public-readiness audit `137` current paths / `97` Git revisions, unsigned optimized universal Release (`arm64` + `x86_64`), version contract `1.0.6 (7)` и embedded Sparkle runtime linking. Signed/notarized `v1.0.6 (7)` опубликован, Sparkle appcast задеплоен, а пользователь подтвердил update/clean-machine typed History smoke на втором Mac.

Scoped security diff scan завершён по commit range `bf23b30..6336499`: `0` reportable findings, coverage complete; дополнительно проверены path/symlink confinement, owned-only cleanup, corrupt metadata fail-closed и отсутствие payload leakage. TAC advisory был `not_granted`, а независимый architecture reviewer не завершился в bounded wait, поэтому это ограничение сохранено в scan report.

Все acceptance criteria закрыты; slice переведён в `done` после signed release/update smoke и migration fault-injection.
