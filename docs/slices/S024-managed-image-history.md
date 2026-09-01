---
id: S024
title: Managed image History
status: needs_verification
depends_on:
  - S023
covers:
  - FR-028
  - FR-029
  - FR-031
  - FR-032
  - BR-019
  - BR-020
  - BR-021
  - BR-022
  - BR-023
  - BR-024
  - NFR-022
  - NFR-023
  - NFR-024
---

# S024: Managed image History

## Пользовательский результат

Пользователь копирует inline image, видит её в History после restart, находит по локальной metadata и повторно вставляет. Qipli ограничивает managed storage, не удаляет старую историю скрыто и полностью очищает owned image data по Delete, expiry или Clear All.

## Статус и prerequisite

S023 завершён, а D-035 принят с production defaults: 32 MiB на image item, 64 MiB на occurrence, 1 GiB на durable original image bytes, 128 MiB на thumbnail cache и 512 px на длинную сторону thumbnail. Лимиты пока не выносятся в UI.

## В scope

- allowlist стандартных image UTTypes и controlled source-app contract probe;
- одна occurrence с одним или несколькими ordered inline image items и retained supported representations;
- atomic temporary-to-managed asset commit в Application Support;
- injected per-item/total capacity policy, oversize/storage-full notification и no-auto-eviction behavior;
- bounded descriptor и placeholder/thumbnail states в native History table;
- visible-row-only asynchronous thumbnail generation/cache;
- metadata-only search по local type/format/dimensions, если они доступны без OCR;
- exact selected image materialization и typed pasteboard writer с self-write suppression;
- delete, 30-day expiry, Clear All, restart, corrupt/missing asset и orphan-temp cleanup;
- active text-only Stack explanation без append/state mutation.

## Вне scope

- file/video references, Finder multi-file collections и remote URL preview;
- OCR, object recognition, image editing или format conversion ради search;
- media Paste Stack;
- automatic eviction существующей History, user-configurable capacity UI или cloud backup;
- arbitrary/custom pasteboard provider types вне принятого allowlist.

## Данные и контракты

- Asset filename/path состоит только из Qipli-owned opaque IDs и валидируется относительно managed root.
- Size admission завершается до durable publication. Rejected capture не создаёт occurrence/placeholder и не меняет Stack.
- Stored representation manifest фиксирует item order, UTType, expected byte count и integrity metadata. Thumbnail не входит в manifest и никогда не используется для paste.
- Main actor получает descriptor/thumbnail result, но не full image `Data`.
- Paste reservation materializes только selected occurrence. Ошибка чтения/integrity останавливает transaction до conceal/target activation.
- Delete/expiry/Clear All не завершаются как успешные, пока occurrence недоступна UI; оставшийся owned cleanup debt безопасно повторяется maintenance.

## Acceptance criteria

- [ ] Supported image из native app и browser создаёт одну durable occurrence с правильным ordered item/representation manifest.
- [ ] Restart показывает occurrence и thumbnail, а pasteback передаёт сохранённое image content совместимому target без text substitution.
- [ ] History page/search snapshot не содержит full image bytes; offscreen rows не запускают unbounded decode.
- [ ] Per-item и total limit отклоняют новую image целиком с понятным уведомлением, не создают placeholder и не удаляют старые occurrences.
- [ ] Partial write, disk-full, corrupt/missing asset и failed metadata commit не публикуют успешную occurrence и не оставляют unsafe path cleanup.
- [ ] Delete, expiry и Clear All удаляют metadata, managed asset, thumbnails и temp artifacts только внутри Qipli roots.
- [ ] Image copy при active Stack появляется в History, не меняет Stack session/order/next и получает понятное text-only limitation state.
- [ ] Pasteback регистрирует exact final `changeCount`, не recaptures Qipli write и сохраняет target/failure behavior S016.

## Verification

- Pure classifier/allowlist tests на standard image/text/URL combinations и unsupported custom types.
- Temporary asset-store tests на atomic commit/rollback, capacity boundaries, invalid relative path, symlink/path traversal, restart, corruption и cleanup inventory.
- Thumbnail operation-count/memory tests на visible/offscreen rows и большие synthetic dimensions без реальных пользовательских images.
- Typed writer tests на item/representation order, payload manifest, external mutation before dispatch и self-write suppression.
- Full SwiftPM/Xcode suite, optimized universal Release, scoped security diff scan и payload-free log/source scan.
- Manual native-app/browser copy, restart, scroll, metadata search, paste, oversize notification, Delete/Clear All и active Stack behavior.

## Implementation report

### Реализовано

- Добавлены typed inline-image contracts, allowlist PNG/TIFF/JPEG/HEIC/HEIF/GIF и managed Application Support storage с opaque UUID paths.
- Реализованы per-item 32 MiB, per-occurrence 64 MiB и durable-originals 1 GiB fail-closed quotas без auto-eviction; rejected capture не публикует occurrence и показывает non-payload notice.
- Сохранены ordered items и все поддержанные representations; Core Data хранит только manifest/metadata, а exact paste materializes выбранную occurrence через typed pasteboard writer.
- Добавлены atomic temporary writes, integrity/hash/size checks, path/symlink validation, pending-delete recovery, expiry/Clear All cleanup и bounded 512 px thumbnails с byte-capped 128 MiB UI cache.
- Pasteboard materialization и image metadata parsing вынесены из main actor; active text-only Stack сохраняет image в History без изменения Stack order/state и показывает ограничение.
- Новый `ManagedImageStore.swift` добавлен и в SwiftPM, и в native `Qipli.xcodeproj` target.

### Проверено

- Focused S024/store/pasteboard/paste tests: 46/46.
- Полный SwiftPM suite: 207/207, 0 failures.
- Native unsigned Xcode Debug XCTest: exit 0 после включения managed-image source в project.
- `git diff --check` и payload-free source scan прошли.
- Независимый read-only review: исходные 3 P1 замечания исправлены; новых P0/P1 не осталось. P2 про bounded read также закрыт предварительной file-size проверкой.

### Остаточные gates

- Требуется ручная native/browser matrix: image copy из native app и browser, restart, visible/offscreen thumbnail behavior, metadata search, exact paste, oversize/storage-full notice, Delete/Clear All и copy при active Stack.
- Release/optimized universal build и scoped security diff scan остаются задачами S026/release pipeline.
