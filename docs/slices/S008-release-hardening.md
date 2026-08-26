---
id: S008
title: Приватность и релиз через GitHub
status: blocked
depends_on:
  - S003
  - S007
  - S010
  - S011
covers:
  - FR-006
  - FR-018
  - FR-019
  - FR-020
  - FR-021
  - NFR-001
  - NFR-002
  - NFR-003
  - NFR-004
  - NFR-007
---

# S008 — Приватность и релиз через GitHub

## Пользовательский результат

Пользователь загружает с GitHub подписанный и notarized Qipli, устанавливает его на чистую macOS 14, понимает разрешения и локальное хранение и завершает оба основных сценария без внешней передачи содержимого.

## В scope

- финальный privacy/entitlements/logging audit;
- release configuration, Developer ID signing, Hardened Runtime;
- archive, notarization, stapling, packaging и checksum;
- clean-machine install/upgrade/uninstall notes;
- GitHub release notes с системными требованиями, onboarding, Accessibility, Settings, shortcuts и Launch at Login;
- проверка delete-one/delete-all, retention и отсутствия продуктовой сети;
- подтверждение архитектур бинарника и supported matrix.

## Вне scope

- Mac App Store, auto-update service и installer daemon;
- telemetry/remote crash reports;
- новое Settings/onboarding поведение сверх контрактов S010/S011;
- новые функции истории или Paste Stack.

## Предусловия

- S003, S007, S010 и S011 завершены; core MVP и setup flows доступны.
- Есть Apple Developer Program membership, Developer ID Application certificate и notarization credentials. Если нет — срез остаётся `planned`/становится `blocked`, но локальная разработка не откатывается.
- Apple platform sources из `TECHNICAL.md` перепроверены на дату релиза.

## Ожидаемое поведение

- Gatekeeper принимает artifact без обходных инструкций.
- Первый запуск до чтения pasteboard показывает onboarding S011 с понятным локальным privacy explanation, permission path, hotkeys и explicit Launch at Login choice.
- Приложение не делает runtime network requests и не имеет неиспользуемых entitlements.
- Обновление не теряет допустимую history и корректно перепроверяет Accessibility после изменения подписи/пути.

## Состояния интерфейса

- first run privacy notice;
- permission not granted/granted;
- Settings/custom shortcuts и Launch at Login off/enabled/requires approval;
- normal upgrade with existing store;
- incompatible/corrupt store error with безопасным recovery;
- release about/version information.

## Данные и контракты

- Public artifact содержит только необходимые executable/resources.
- Signing secrets не хранятся в repository, artifact или logs.
- Checksum и версия однозначно соответствуют release artifact.
- Uninstall notes честно описывают расположение локальных данных и способ их удаления; приложение не удаляет данные без user action.

## Acceptance criteria

- [ ] Release build использует deployment target macOS 14, Hardened Runtime, ожидаемые architectures и минимальный набор entitlements; App Sandbox и network client/server entitlement отсутствуют.
- [ ] Все executables внутри artifact подписаны Developer ID, archive успешно проходит Apple notarization, ticket stapled, а Gatekeeper проверка проходит на загруженной копии.
- [ ] На чистом профиле macOS 14 пользователь устанавливает приложение, понимает локальное хранение/риск секретов, выдаёт или отклоняет Accessibility и видит честное degraded state при отказе.
- [ ] На чистом профиле onboarding появляется до первого pasteboard read, допускает Skip/deny, не включает Launch at Login без явного действия и позднее повторно открывается из Settings без сброса preferences.
- [ ] На чистой системе выполняются PJ-001 и PJ-002; отказ разрешения, повторная выдача, sleep/wake и повторный запуск не приводят к потере управляемости.
- [ ] Custom History/Stack/Reactivate shortcuts переживают restart и reset; обычный `⌘V`/`Esc` сохраняют контракты. Launch at Login проходит enable → logout/login → disable и external-disable/requires-approval paths на подписанном artifact.
- [ ] Network inspection основной сессии не показывает runtime requests Qipli; clipboard text, search queries и previews отсутствуют в logs и release diagnostics.
- [ ] Delete one, clear all и auto-retention сохраняются после перезапуска; clear-all удаляет управляемый store/sidecars, но UI/docs не обещают secure erase и не заявляют очистку system pasteboard.
- [ ] Upgrade поверх предыдущей test build сохраняет записи моложе 30 дней или выполняет документированное безопасное migration/recovery без молчаливой частичной потери.
- [ ] GitHub Release содержит artifact, checksum, системные требования, changelog, инструкции установки/Accessibility, privacy summary и ссылку на исходный код/license; signing credentials нигде не опубликованы.

## Verification

- [ ] Полный automated test suite и чистые Debug/Release builds.
- [ ] Проверка entitlements/signatures всех executables, Gatekeeper assessment и notarization log без warnings, требующих исключений.
- [ ] Clean-machine/manual matrix из `TECHNICAL.md`, включая macOS 14 и доступные более новые версии.
- [ ] Clean-profile onboarding/Settings/custom-shortcut/Launch-at-Login matrix из S010/S011 на подписанном artifact.
- [ ] Network/log audit во время capture, history paste, stack paste и delete flows.
- [ ] Install → data capture → upgrade → verify → delete-all → restart сценарий.
- [ ] Скачать опубликованный artifact заново, проверить checksum и запуск, а не тестировать только локальный archive.

## Definition of Done

- [ ] Все acceptance criteria выполнены.
- [ ] Автоматические и ручные проверки пройдены.
- [ ] Приложение собирается без новой регрессии.
- [ ] `STATE.md` и frontmatter синхронно обновлены.
- [ ] Новые значимые решения записаны в `DECISIONS.md`.
- [ ] Implementation report заполнен.

## Implementation report

### Реализовано

- Подготовлены два fail-closed command-line workflow: local `Apple Development` package и public Developer ID/notarized release.
- Общий verifier проверяет signer/Team ID/designated requirement, Hardened Runtime, entitlements, bundle/minimum OS, universal architectures, forbidden xattrs и strict code signature; release после notarization дополнительно проверяет stapled ticket и Gatekeeper.
- Оба workflow очищают только `FinderInfo`/resource-fork metadata в изолированном temporary archive, создают ZIP без resource/xattr/quarantine/ACL metadata, распаковывают его и повторяют verification до checksum.
- Notary credentials читаются только из named Keychain profile; certificate names и Team ID передаются явными release environment values, secrets в repository не добавлены.
- Certificate availability подтверждается фактической подписью Xcode archive и строгим verifier, а не `security find-identity`, который не перечисляет identities из Data Protection Keychain.

### Изменённые файлы

- `scripts/package-local.sh`
- `scripts/package-release.sh`
- `scripts/verify-signed-app.sh`
- `docs/TECHNICAL.md`, `docs/DECISIONS.md`, `docs/STATE.md` и этот slice

### Выполненная проверка

- `bash -n` для всех трёх scripts — успешно.
- Verifier отклонил существующий `/Applications/Qipli.app` как ad-hoc/no-Team-ID artifact — ожидаемый fail-closed результат.
- Полный SwiftPM suite (106 тестов) и unsigned Xcode Debug/Release builds — успешно.
- 2026-08-26 universal `arm64+x86_64` Release archive подписан `Developer ID Application: Sviatoslav Zhilichev (3N2R5K4J63)` с Hardened Runtime и secure timestamp.
- Apple submission `82224766-5606-47a2-939a-9d423ab477b9` получила `Accepted`, `Ready for distribution`, `issues: null`; ticket stapled, Gatekeeper вернул `source=Notarized Developer ID` для app и повторно распакованного ZIP.
- `dist/Qipli-1.0.zip` и SHA-256 созданы; `shasum -a 256 -c` прошёл.

### Отклонения от плана

- Первый artifact создан до завершения S010/S011 и рассматривается как signing/notarization test, а не публичный релиз или выполнение всех acceptance criteria.

### Оставшиеся проблемы

Credential blocker снят, S010 завершён. S011, clean-machine install/upgrade, Accessibility/TCC, Settings/onboarding, network/log, data lifecycle и downloaded GitHub artifact matrices ещё не завершены. Поэтому S008 остаётся `blocked`.
