---
id: S015
title: Безопасные обновления через Sparkle
status: planned
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

Пользователь установленной предыдущей версии Qipli вручную или после явного opt-in обнаруживает новый stable release, подтверждает установку и возвращается в обновлённое приложение с сохранённой History и Settings. Повреждённое или неподписанное обновление не заменяет рабочую версию.

## В scope

- Sparkle 2 через фиксированную Swift Package Manager dependency;
- изолированный updater adapter и `SPUStandardUpdaterController` lifecycle;
- `Check for Updates…` в status menu и Settings General;
- выключенный по умолчанию toggle автоматической проверки;
- публичный GitHub Pages appcast для одного stable channel;
- изолированный verification appcast для real old-to-new test до первого stable release;
- `SUPublicEDKey`, release-side private EdDSA key и `generate_appcast`;
- manual check, up-to-date, available, download/install/relaunch и retryable failure states;
- публикация feed только после готового immutable GitHub Release asset;
- реальный update между двумя Developer ID-signed и notarized builds;
- сохранение History, shortcuts, onboarding completion и Launch at Login; Accessibility recheck после relaunch.

## Вне scope

- beta/nightly channels, phased rollout и delta updates;
- silent install без подтверждения пользователя;
- собственный update server, account, telemetry или device identifier;
- обновление версии, которая была публично выпущена без Sparkle;
- Mac App Store update mechanism.

## Поведение и контракты

- Manual check доступен независимо от automatic-check preference.
- Automatic checks default `false` и меняются только явным действием пользователя; disabling прекращает будущие background checks.
- Updater получает только public feed/archive URL и version metadata. Он не имеет доступа к HistoryService, StackSession, search query или clipboard preview.
- `CFBundleVersion` определяет ordering; short version показывается пользователю. Feed item с неувеличенным build игнорируется.
- Update archive должен пройти Sparkle EdDSA и ожидаемую Apple code-signing identity. Redirect или host change не обходят verification.
- Feed публикуется последним. S015 проверяет этот порядок на isolated verification path; первый production stable appcast публикуется только через S008. Failed release не меняет current stable appcast.
- Offline, invalid XML, incompatible minimum OS, invalid signature, interrupted download или install failure оставляет текущую версию запускаемой и показывает retryable state только в update UI.

## Acceptance criteria

- [ ] Production Xcode target и Swift Package tests используют одну зафиксированную совместимую Sparkle 2 dependency без ослабления deployment target macOS 14.
- [ ] Built app содержит корректные `SUFeedURL` и `SUPublicEDKey`; private EdDSA key отсутствует в app, repository, GitHub Release assets и logs.
- [ ] Status menu и Settings предлагают manual `Check for Updates…`; action доступно с клавиатуры и VoiceOver и не включает background checks.
- [ ] Automatic-check toggle по умолчанию выключен, сохраняет explicit opt-in и может быть отключён без изменения History/Paste Stack behavior.
- [ ] Appcast использует HTTPS, immutable versioned GitHub Release URL, increasing numeric build, short version, minimum macOS и EdDSA signature.
- [ ] Release workflow готовит stable appcast только после успешного S014 asset verification; failed/draft release не становится update candidate. До S008 реальный old-to-new proof использует отдельный verification URL, который не является production `SUFeedURL`.
- [ ] Manual check различает checking, up-to-date, available, progress, relaunch и retryable error; invalid signature не предлагает или не устанавливает update.
- [ ] Update request и updater logs не содержат clipboard text, history, search query, previews или локальный Qipli identifier.
- [ ] Реальный update с предыдущего production-signed build на следующий сохраняет Core Data history, shortcut preferences, onboarding completion и фактический Launch at Login state.
- [ ] После relaunch Qipli перепроверяет Accessibility и event tap; сохранённое системное разрешение продолжает работать либо UI честно ведёт пользователя через восстановление без ложного granted state.
- [ ] Interrupted/tampered/offline update оставляет старую app version запускаемой и не повреждает user store.

## Verification

- [ ] Unit tests updater preferences, manual/automatic admission, version ordering и failure mapping через injected adapter.
- [ ] Static privacy check подтверждает отсутствие product payload access и private EdDSA material.
- [ ] Generated verification appcast проходит XML/signature validation и указывает на существующий immutable GitHub Release asset; production stable path остаётся под gate S008.
- [ ] Tampered archive и wrong EdDSA key отклоняются production-signed old build.
- [ ] Offline, invalid feed, interrupted download и install failure regression сохраняет текущую версию и локальные данные.
- [ ] Full SwiftPM/Xcode suite, universal Release и S014 signing/notarization gate.
- [ ] Manual clean-machine matrix: install old build, capture History, change shortcuts/login item, opt in, discover new build, install, relaunch and verify data/Settings/Accessibility.
- [ ] Manual accessibility matrix: status menu/Settings update controls, VoiceOver, keyboard, Light/Dark and Reduce Motion.

## Implementation report

### Реализовано

Не заполнено.

### Проверено

Не заполнено.

### Отклонения и остаточные риски

Не заполнено.
