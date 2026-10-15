---
id: S038
name: Opt-in локальные журналы
depends_on: [S010, S037]
covers: [FR-055, BR-041, NFR-038]
---

# S038: Локальная диагностика

D-054. Settings General, toggle выключен по умолчанию, Show Logs и Clear Logs. Durable preference отдельно для Dev/Release. Локальные JSONL files без payload, source/app/window identities, keyboard stream и arbitrary strings. Bounded serial writer, fixed schema, random session/operation correlation, correction stages/reasons и durations. До 10 MiB/7 дней, без сети.

## Acceptance criteria

- [x] Fresh profile выключен, diagnostic directory не создаётся от событий. Opt-in сохраняется после relaunch.
- [ ] Show/Clear Logs работают с выключенным toggle; error state доступен и не раскрывает paths/errors. Clear инвалидирует старые queued events.
- [x] Size/age retention и bounded queue, private permissions и отказ на symlinks проверены. Disable не принимает новые события.
- [x] Correction success/denied/failure имеют operation correlation, stages, fixed reasons и timing без пользовательских данных.
- [x] Полный SwiftPM, Debug/Release builds и privacy/version/release checks пройдены.
- [ ] Installed signed Settings keyboard/VoiceOver/Light-Dark и реальный correction smoke проверены отдельно.

## Verification

Injected temporary directories/preferences/clock, synthetic inputs only. Unit tests для privacy schema, default/relaunch/disable/clear, bounded storage, expiration и unsafe filesystem. Coordinator fake adapters проверяют корреляцию и причины. Полный существующий suite и universal builds. Установленная Settings matrix не подменяется автоматическими проверками.

## Implementation report

Реализовано 2026-10-15 в текущей feature ветке, без commit/push/publication. `LocalDiagnostics` принимает только typed enums, UTC timestamp, случайные session/operation UUIDs, numeric-only version/build и monotonic duration. UI не получает raw payload. Correction trace включает trigger type, admission/capture, selected/word/cycle proof, mapping/replacement, native-paste vs Unicode fallback, postcondition и layout switch. Word refusal checks имеют отдельные reason codes; completion correlation проверена fake AX adapter.

Writer: utility queue, максимум 256 admitted pending records, generation invalidation при disable/clear, opt-in UserDefaults, ten 1 MiB JSONL files, seven-day mtime cleanup на startup/write/hourly timer. Directory 0700/files 0600, symlink/non-regular/hardlink/foreign-owner rejection, managed names only. Existing oversized managed files удаляются при cleanup. Никаких OSLog/network/telemetry/dependencies. Update privacy boundary не меняется.

Проверки:

- Новые `LocalDiagnosticsTests` 10/10: fresh default-off/no-directory, preference relaunch/disable, exact record schema и permissions, size rotation, expiry while disabled, clear/continued logging/unmanaged preservation, file/directory symlink refusal, oversized event failure, deterministic backlog bound и disable race.
- Coordinator integration: success stages/correlation, busy refusal и missing fresh-word reason, без payload. Settings integration: default-off, async enable/disable, clear и filesystem failure UI. Существующие regression tests сохранены.
- Полный SwiftPM 345 tests, 0 failures, 0 skips. Финальный rerun после trigger-type instrumentation также 345/345.
- Universal unsigned Debug и Release PASS. Development-signed universal Dev 1.0.14/build15 PASS; strict/deep codesign PASS. Candidate source snapshot отличается от рабочего кода только version/notes; build inputs сохранены в `dist/1.0.14-preparation/candidate-inputs.sha256.json`.
- Version validator 8/8, release contract 13/13, CI contract, project/built-version, runtime linking, update privacy, public-readiness audit и diff checks PASS. Readiness audit отмечает уже существующие пять ignored release-output paths в Git history; текущие dist files не tracked.
- Native AppKit/SwiftUI Light/Dark renders на synthetic preferences, enlarged inspection height. Scoped finish review: `ship`, actionable defects нет. Documenter подтвердил соответствие incumbent grouped Form без новых design tokens. Эти renders не заменяют production-size/installed accessibility checks.

Открыто: реальный Show Logs в Finder, scrolling при обычном размере Settings, keyboard/VoiceOver, installed correction reproduction с журналом и новые D-053 gesture/long-selection/error-panel smoke. S038 остаётся needs_verification. Подписанный public ZIP/DMG и Sparkle не создавались и не проверялись для кандидата.
