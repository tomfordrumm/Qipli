---
id: S014
title: Публичный репозиторий и подписанные GitHub-релизы
status: blocked
depends_on:
  - S013
covers:
  - FR-022
  - FR-023
  - BR-015
  - BR-016
  - BR-017
  - NFR-007
  - NFR-008
  - NFR-012
  - NFR-013
  - NFR-014
---

# S014: Публичный репозиторий и подписанные GitHub-релизы

## Результат

Пользователь открывает публичный GitHub Release, скачивает один однозначно версионированный Qipli ZIP и checksum, а Gatekeeper принимает распакованное приложение без обходных инструкций. Новый stable tag воспроизводит тот же fail-closed путь.

## Блокеры

- Пользователь должен выбрать open-source лицензию.
- Для hosted runner нужен exportable Developer ID Application `.p12` с private key и пароль.
- В protected GitHub Environment нужен App Store Connect API `.p8`, Key ID и Issuer ID с правом notarization.
- S013 должен завершить version contract и unsigned CI.

## В scope

- README, выбранная LICENSE, SECURITY policy, install/privacy/update notes;
- final current-tree/history audit до смены visibility;
- перевод текущего repository в public после успешного audit;
- branch protection и protected GitHub Environment `release`;
- tag-triggered workflow на exact commit с ephemeral Keychain;
- Developer ID signing, universal archive, Hardened Runtime, notarization, stapling и existing strict verifier;
- draft GitHub Release, versioned ZIP, SHA-256 и generated release notes;
- повторное скачивание candidate asset и проверка до stable publication;
- idempotent rerun без второго release или mutable replacement уже опубликованного asset.

## Вне scope

- Sparkle dependency, appcast и in-app update UI;
- beta/prerelease channel, nightly signing и release на каждый push;
- Mac App Store, DMG/PKG installer и silent install;
- автоматическая history rewrite при найденном secret без отдельного согласованного remediation plan.

## Поведение и контракты

- Release workflow работает только с exact tag commit и protected Environment. Fork/PR code не исполняется после выдачи secrets.
- `.p12` и `.p8` декодируются во временный каталог, certificate импортируется во временный Keychain и удаляется unconditional cleanup step.
- `scripts/package-release.sh` остаётся одной fail-closed packaging boundary для local и CI paths; CI authentication может отличаться, verification criteria нет.
- Tag/version/build mismatch, test failure, certificate error, rejected notarization, missing staple, Gatekeeper failure или checksum mismatch запрещает публикацию.
- Workflow создаёт draft release. Stable publication происходит только после повторной проверки candidate, скачанного через authenticated draft-asset API.
- Published release assets immutable по имени и содержимому. Исправление требует новой версии, а не замены ZIP под прежним URL.

## Acceptance criteria

- [ ] Пользователь выбрал лицензию; repository содержит README, LICENSE и SECURITY с корректными install, privacy и vulnerability-reporting instructions.
- [ ] Current tree и доступная Git history не содержат real secrets, private signing material или пользовательский clipboard payload; найденные credentials удалены по согласованному plan и ротированы до public visibility.
- [ ] Repository публичный, `main` защищён обязательным S013 CI, а release Environment требует разрешённый gate перед secrets и publication.
- [ ] Stable tag `vX.Y.Z` совпадает с built short version, использует strictly increasing numeric build и указывает на разрешённый commit.
- [ ] Hosted runner импортирует Developer ID identity в ephemeral Keychain, собирает universal `arm64+x86_64`, выполняет strict pre-notarization verification и не ослабляет entitlements checks.
- [ ] `notarytool` использует App Store Connect API credential, submission получает `Accepted`, ticket stapled, а `spctl`/verifier принимают app и повторно распакованный ZIP.
- [ ] Draft GitHub Release содержит versioned ZIP, SHA-256, requirements, changelog, onboarding/Accessibility/Settings/shortcuts/Launch at Login notes и privacy summary.
- [ ] Workflow скачивает candidate asset через authenticated draft-asset API, проверяет checksum, archive contents, code signature, staple и Gatekeeper до stable publication.
- [ ] Logs и artifacts не содержат `.p12`, `.p8`, passwords, private Sparkle key или decoded Keychain data; cleanup выполняется и при failure/cancel.
- [ ] Повторный run для того же tag не создаёт второй release и не заменяет уже опубликованный immutable asset.

## Verification

- [ ] Focused workflow tests/static checks для tag/version admission, missing secrets, failed notarization status и cleanup trap.
- [ ] Полный SwiftPM/Xcode test and build gate перед release job.
- [ ] Реальный protected tag run на GitHub-hosted macOS runner.
- [ ] До публикации ZIP, повторно скачанный из draft через API, проходит SHA-256, archive inventory, strict verifier, `stapler validate` и Gatekeeper; после публикации та же проверка повторяется через публичный URL без GitHub authentication.
- [ ] Clean-machine launch на минимальной поддерживаемой macOS 14 показывает ожидаемый Developer ID/Gatekeeper path.
- [ ] Repository public-view smoke подтверждает README/LICENSE/SECURITY, release notes и доступность ZIP без GitHub authentication.

## Implementation report

### Реализовано

Не заполнено.

### Проверено

Не заполнено.

### Отклонения и остаточные риски

Не заполнено.
