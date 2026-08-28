---
id: S015
title: Безопасные обновления через Sparkle
status: in_progress
depends_on:
  - S014
covers:
  - FR-024
  - FR-025
  - BR-017
  - BR-018
  - NFR-002
  - NFR-003
  - NFR-008
  - NFR-014
  - NFR-015
---

# S015: Безопасные обновления через Sparkle

## Результат

Пользователь установленной Sparkle-enabled версии Qipli вручную или после явного opt-in обнаруживает новый stable release, подтверждает установку и возвращается в обновлённое приложение с сохранённой History и Settings. Повреждённое или неподписанное обновление не заменяет рабочую версию. `v1.0.1` впервые добавляет Sparkle и устанавливается вручную; `v1.0.2` доказывает реальный update path.

## В scope

- Sparkle `2.9.6` через exact Swift Package Manager dependency;
- изолированный updater adapter и `SPUStandardUpdaterController` lifecycle;
- `Check for Updates…` в status menu и Settings General;
- выключенный по умолчанию toggle автоматической проверки;
- публичный GitHub Pages appcast для одного stable channel;
- изолированный verification appcast для подготовки old-to-new test до публикации первого production Sparkle feed;
- `SUPublicEDKey`, release-side private EdDSA key и `generate_appcast`;
- manual check, up-to-date, available, download/install/relaunch и retryable failure states;
- публикация feed только после готового immutable GitHub Release asset;
- реальный update между двумя Developer ID-signed и notarized builds;
- сохранение History, shortcuts, onboarding completion и Launch at Login; Accessibility recheck после relaunch.

## Вне scope

- beta/nightly channels, phased rollout и delta updates;
- silent install без подтверждения пользователя;
- собственный update server, account, telemetry или device identifier;
- автоматическое обновление уже опубликованного `v1.0.0`, который не содержит Sparkle;
- Mac App Store update mechanism.

## Поведение и контракты

- Manual check доступен независимо от automatic-check preference.
- Automatic checks default `false` и меняются только явным действием пользователя; disabling прекращает будущие background checks.
- Updater получает только public feed/archive URL и version metadata. Он не имеет доступа к HistoryService, StackSession, search query или clipboard preview.
- `CFBundleVersion` определяет ordering; short version показывается пользователю. Feed item с неувеличенным build игнорируется.
- Update archive должен пройти Sparkle EdDSA и ожидаемую Apple code-signing identity. Redirect или host change не обходят verification.
- Feed публикуется последним. `v1.0.1` создаёт первый production stable appcast только после immutable release asset; `v1.0.2` доказывает old-to-new path. Failed release не меняет current stable appcast.
- Offline, invalid XML, incompatible minimum OS, invalid signature, interrupted download или install failure оставляет текущую версию запускаемой и показывает retryable state только в update UI.

## Acceptance criteria

- [x] Production Xcode target и Swift Package tests используют exact Sparkle `2.9.6` без ослабления deployment target macOS 14.
- [x] Built app содержит корректные `SUFeedURL` и `SUPublicEDKey`; private EdDSA key отсутствует в app, repository, GitHub Release assets и logs.
- [ ] Status menu и Settings предлагают manual `Check for Updates…`; action доступно с клавиатуры и VoiceOver и не включает background checks.
- [ ] Automatic-check toggle по умолчанию выключен, сохраняет explicit opt-in и может быть отключён без изменения History/Paste Stack behavior.
- [x] Appcast использует HTTPS, immutable versioned GitHub Release URL, increasing numeric build, short version, minimum macOS и EdDSA signature.
- [ ] Release workflow готовит stable appcast только после успешного S014 asset verification; failed/draft release не становится update candidate. `v1.0.1` устанавливается вручную и создаёт первый production feed, `v1.0.2` подтверждает update через этот feed.
- [ ] Manual check различает checking, up-to-date, available, progress, relaunch и retryable error; invalid signature не предлагает или не устанавливает update.
- [x] Update request и updater logs не содержат clipboard text, history, search query, previews или локальный Qipli identifier.
- [ ] Реальный update с предыдущего production-signed build на следующий сохраняет Core Data history, shortcut preferences, onboarding completion и фактический Launch at Login state.
- [ ] После relaunch Qipli перепроверяет Accessibility и event tap; сохранённое системное разрешение продолжает работать либо UI честно ведёт пользователя через восстановление без ложного granted state.
- [ ] Interrupted/tampered/offline update оставляет старую app version запускаемой и не повреждает user store.

## Verification

- [ ] Unit tests updater preferences, manual/automatic admission, version ordering и failure mapping через injected adapter.
- [x] Static privacy check подтверждает отсутствие product payload access и private EdDSA material.
- [x] Generated appcast проходит XML/signature validation и указывает на существующий immutable GitHub Release asset; production feed не меняется до завершения release verification.
- [ ] Tampered archive и wrong EdDSA key отклоняются production-signed old build.
- [ ] Offline, invalid feed, interrupted download и install failure regression сохраняет текущую версию и локальные данные.
- [x] Full SwiftPM/Xcode suite, universal Release и S014 signing/notarization gate.
- [ ] Manual clean-machine matrix: install old build, capture History, change shortcuts/login item, opt in, discover new build, install, relaunch and verify data/Settings/Accessibility.
- [ ] Manual accessibility matrix: status menu/Settings update controls, VoiceOver, keyboard, Light/Dark and Reduce Motion.

## Implementation report

### Реализовано

- 2026-08-28 пользователь подтвердил параллельный старт при открытых manual gates S014, последовательность `v1.0.1 → v1.0.2`, генерацию отдельного EdDSA key и настройку GitHub Pages.
- Exact Sparkle `2.9.6` подключён к Swift Package и production Xcode target; `SparkleSecureUpdater` владеет `SPUStandardUpdaterController` и не получает product payload services.
- Status menu и Settings General получили manual `Check for Updates…`; automatic checks выключены plist-контрактом и меняются только explicit toggle. Automatic install выключен.
- `v1.0.1 (2)` зафиксирован как первая Sparkle-enabled версия. В app встроены HTTPS `SUFeedURL` и public EdDSA key; private key создан в Keychain и добавлен только как protected `release` Environment secret.
- Release workflow до signing сверяет private key с встроенным public key, после packaging генерирует и проверяет signed appcast, публикует GitHub Release и только затем передаёт feed в pinned official GitHub Pages deployment. GitHub Pages включён в workflow mode с enforced HTTPS.
- Добавлены fail-closed проверки exact tag/version/build/minimum macOS/immutable asset URL/archive length/EdDSA, public asset availability, update privacy boundary и ordering release-before-feed.
- Первый protected `v1.0.1` recovery run дошёл до Apple notarization и выявил ad-hoc signatures без timestamp у вложенных Sparkle helpers. Release packaging теперь повторно подписывает их в обязательном inside-out порядке и fail closed проверяет Developer ID, Team ID, Hardened Runtime и secure timestamp каждого компонента до отправки Apple.

### Проверено

- Focused updater tests: 3/3. Full SwiftPM: 153/153. Full Xcode XCTest: 153/153.
- Unsigned Xcode Release `1.0.1 (2)` собран universal `arm64+x86_64`; app содержит universal Sparkle.framework, `SUFeedURL` и `SUPublicEDKey`.
- Public key из Info.plist совпадает с generated Keychain keypair; test appcast для production-shaped ZIP прошёл XML, version/build, minimum macOS, immutable URL, length и EdDSA verification.
- `scripts/check-update-privacy.sh`, release contract tests, plist/project lint и `git diff --check` прошли.
- Nested signing regression fixture подтвердил шесть вызовов в exact inside-out порядке, preservation entitlements только для Downloader и отказ при отсутствующем helper; обновлённый release contract содержит 11/11 passing cases.
- PR `#6` hosted CI run `33171371342` прошёл полный read-only version/public-readiness/SwiftPM/unsigned Debug+Release/built metadata gate без release secrets.
- PR `#7` и push-to-main run `33173641626` проверили nested-signing regression contract на hosted runner. Protected tag run `33174121960` attempt 2 прошёл exact-tag admission, 153 tests, EdDSA key preflight, universal build, inside-out Developer ID signing, nested Team ID/runtime/timestamp verification, Apple notarization, stapling, Gatekeeper, credential cleanup и immutable public release verification.
- Публичный `Qipli-1.0.1.zip` имеет SHA-256 `a5f5ff23857adee6b7821377316ee0f2fe514065c29fc4d1f7f59e7ffe2bc882`. Независимое unauthenticated скачивание подтвердило checksum, version `1.0.1 (2)`, все пять nested Sparkle signatures, stapler и Gatekeeper `source=Notarized Developer ID`.
- Production `https://tomfordrumm.github.io/Qipli/appcast.xml` опубликован после release asset и независимо прошёл XML, immutable URL, build/version, minimum macOS, length и public availability checks. Для `github-pages` сохранён `main` и добавлена отдельная deployment policy только для stable tags `v*.*.*`.

### Отклонения и остаточные риски

- Публичный `v1.0.0` выпущен без Sparkle и требует ручной установки следующей версии. Первый реальный updater proof возможен только между `v1.0.1` и `v1.0.2`.
- Первый submission `f0b52e36-f273-4dd5-9b63-5a306c53074f` ожидаемо отклонён до публикации artifact/feed из-за nested Sparkle signing gap; исправленный protected run прошёл и заменил этот release candidate.
- `v1.0.1` и production feed опубликованы. Остаются ручная установка первой Sparkle-enabled версии, UI/accessibility/failure matrix и реальный signed/notarized update `v1.0.1 → v1.0.2` с проверкой сохранности данных.
- Standard checking/up-to-date/available/download/install/relaunch/error presentation и version admission принадлежат Sparkle; Qipli unit tests покрывают только собственный adapter/settings contract. Tampered/offline/interrupted path остаётся обязательной manual integration проверкой.
