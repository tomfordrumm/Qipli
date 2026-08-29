---
id: S014
title: Публичный репозиторий и подписанные GitHub-релизы
status: needs_verification
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

Пользователь нажимает Download на лендинге, получает `Qipli.dmg`, открывает оформленный образ и перетаскивает Qipli в Applications. Gatekeeper принимает DMG и приложение без обходных инструкций; immutable ZIP остаётся отдельным update artifact для Sparkle.

## Блокеры

Hosted signing/notarization blocker снят: protected Environment содержит exportable Developer ID Application `.p12` и App Store Connect API credentials, а real tag run создал публичный notarized release. До `done` остаются clean-machine launch на macOS 14 и реальный immutable rerun уже опубликованного tag.

Лицензия MIT, copyright `Sviatoslav Zhilichev`, сохранение безопасной Git-истории, approver `tomfordrumm` и public visibility после финального audit подтверждены 2026-08-28. S013 завершён.

## В scope

- README, выбранная LICENSE, SECURITY policy, install/privacy/update notes;
- final current-tree/history audit до смены visibility;
- перевод текущего repository в public после успешного audit;
- branch protection и protected GitHub Environment `release`;
- tag-triggered workflow на exact commit с ephemeral Keychain;
- Developer ID signing, universal archive, Hardened Runtime, notarization, stapling и existing strict verifier;
- собственный AppIcon и branded DMG layout с `Qipli.app`, `/Applications` и понятной стрелкой;
- draft GitHub Release, versioned DMG/ZIP, оба SHA-256, stable `Qipli.dmg` alias и generated release notes;
- прямая ссылка лендинга через `releases/latest/download/Qipli.dmg`;
- повторное скачивание candidate asset и проверка до stable publication;
- idempotent rerun без второго release или mutable replacement уже опубликованного asset.

## Вне scope

- Sparkle dependency, appcast и in-app update UI;
- beta/prerelease channel, nightly signing и release на каждый push;
- Mac App Store, PKG installer и silent install;
- автоматическая history rewrite при найденном secret без отдельного согласованного remediation plan.

## Поведение и контракты

- Release workflow работает только с exact tag commit и protected Environment. Fork/PR code не исполняется после выдачи secrets.
- `.p12` и `.p8` декодируются во временный каталог, certificate импортируется во временный Keychain и удаляется unconditional cleanup step.
- `scripts/package-release.sh` остаётся одной fail-closed packaging boundary для local и CI paths; он создаёт проверенный ZIP для Sparkle и отдельно подписанный/notarized/stapled DMG для ручной установки. CI authentication может отличаться, verification criteria нет.
- Tag/version/build mismatch, test failure, certificate error, rejected notarization, missing staple, Gatekeeper failure или checksum mismatch запрещает публикацию.
- Workflow создаёт draft release. Stable publication происходит только после повторной проверки candidate, скачанного через authenticated draft-asset API.
- Published versioned release assets immutable по имени и содержимому. `Qipli.dmg` внутри каждого release обязан byte-for-byte совпадать с versioned DMG; исправление требует новой версии, а не замены asset под прежним URL.

## Acceptance criteria

- [x] Пользователь выбрал MIT; repository содержит README, LICENSE и SECURITY с корректными install, privacy и vulnerability-reporting instructions.
- [x] Current tree и доступная Git history не содержат real secrets, private signing material или пользовательский clipboard payload; пять старых `dist/*` paths проверены и по решению пользователя остаются без history rewrite.
- [x] Repository публичный, `main` защищён обязательным S013 CI, а release Environment требует `tomfordrumm` approval перед secrets и publication и принимает только tags `v*.*.*`.
- [x] Stable tag `vX.Y.Z` совпадает с built short version, использует strictly increasing numeric build и указывает на разрешённый commit.
- [x] Hosted runner импортирует Developer ID identity в ephemeral Keychain, собирает universal `arm64+x86_64`, выполняет strict pre-notarization verification и не ослабляет entitlements checks.
- [x] `notarytool` использует App Store Connect API credential, submission получает `Accepted`, ticket stapled, а `spctl`/verifier принимают app и повторно распакованный ZIP.
- [x] Draft GitHub Release содержит versioned ZIP, SHA-256, requirements, changelog, onboarding/Accessibility/Settings/shortcuts/Launch at Login notes и privacy summary.
- [x] Локальный unsigned layout smoke подтверждает AppIcon, branded background, `Qipli.app`, `/Applications`, сохранённый размер окна и читаемый drag-to-install path.
- [ ] Protected release создаёт Developer ID-signed, notarized и stapled versioned DMG, checksum и identical `Qipli.dmg`; public latest URL скачивает тот же DMG.
- [x] Workflow скачивает candidate asset через authenticated draft-asset API, проверяет checksum, archive contents, code signature, staple и Gatekeeper до stable publication.
- [x] Logs и artifacts не содержат `.p12`, `.p8`, passwords, private Sparkle key или decoded Keychain data; cleanup выполняется и при failure/cancel.
- [ ] Повторный run для того же tag не создаёт второй release и не заменяет уже опубликованный immutable asset.

## Verification

- [x] Focused workflow tests/static checks для tag/version admission, missing secrets, failed notarization status и cleanup trap.
- [x] Полный SwiftPM/Xcode test and build gate перед release job.
- [x] Реальный protected tag run на GitHub-hosted macOS runner.
- [x] До публикации ZIP, повторно скачанный из draft через API, проходит SHA-256, archive inventory, strict verifier, `stapler validate` и Gatekeeper; после публикации та же проверка повторяется через публичный URL без GitHub authentication.
- [ ] До и после публикации DMG проходит SHA-256, inventory/layout, Developer ID signature, stapler и Gatekeeper; `releases/latest/download/Qipli.dmg` совпадает с versioned asset.
- [ ] Clean-machine launch на минимальной поддерживаемой macOS 14 показывает ожидаемый Developer ID/Gatekeeper path.
- [x] Repository public-view smoke подтверждает README/LICENSE/SECURITY, release notes и доступность ZIP без GitHub authentication.

## Implementation report

### Реализовано

- Добавлены MIT `LICENSE`, публичный README, SECURITY policy и release notes template с install, Accessibility, Settings, shortcuts, Launch at Login и privacy notes.
- `.github/workflows/release.yml` принимает только stable version tag или reviewed recovery input, использует protected Environment `release`, pinned checkout и минимальный `contents: write` только для same-repository Release.
- `scripts/package-hosted-release.sh` валидирует protected values, декодирует `.p12`/`.p8` в runner temp, импортирует certificate во временный Keychain, временно добавляет его в user search list, проверяет exact Developer ID identity и восстанавливает исходный search list через cleanup trap.
- `scripts/package-release.sh` сохраняет локальный Keychain-profile path и добавляет hosted App Store Connect API authentication без изменения strict signing/notarization verifier.
- `scripts/package-release.sh` теперь после app/ZIP boundary создаёт оформленный DMG, подписывает и отдельно notarize-ит финальный образ, stapled и проверяет его до помещения результатов в `dist`.
- `scripts/publish-github-release.sh` загружает versioned DMG/ZIP, checksums и identical `Qipli.dmg`, повторно скачивает candidates через authenticated API, проверяет checksum/signature/staple/Gatekeeper, публикует stable release и повторяет проверки через публичные URLs. Уже опубликованный tag immutable и fail closed отклоняет rerun.
- Добавлены AppIcon asset catalog, deterministic DMG background/layout, builder/verifier, latest-download contract и negative layout tests.

### Проверено

- `scripts/tests/release-contract-tests.sh`: 13 positive/negative cases для workflow contract, missing/malformed secrets, accepted/rejected notarization, tag admission и DMG inputs прошли.
- Локальный universal Release app успешно скомпилировал AppIcon; реальный DMG mount/layout smoke и визуальный Finder smoke прошли. Подпись/notarization финального DMG остаются protected release gate.
- Shell syntax, release/CI static contracts, workflow YAML parse и `git diff --check` прошли.
- Полный SwiftPM suite: 150 tests, 0 failures. Unsigned Xcode Debug и Release builds прошли; built metadata соответствует `1.0.0 (1)`, Release executable universal `x86_64 arm64` с deployment target macOS 14.
- Public-readiness audit проверил 87 current paths и 43 revisions без вывода payload values; blocking paths и credential-shaped values не найдены. Пять старых ignored `dist/*` paths сохранены по D-028.
- Commit `7dbd37dc117305f6b3c695f0505c079e7572fee0` прошёл hosted unsigned CI run `33162629048`: version, CI/release contract, audit, 150 tests, Debug/Release builds и built metadata завершились успешно.
- `tomfordrumm/Qipli` переведён в public после audit. `main` требует strict `test-and-build`, linear history, conversation resolution и запрещает force-push/delete с enforce-admins. Environment `release` требует `tomfordrumm` approval и custom tag policy `v*.*.*`.
- Unauthenticated public-view smoke получил HTTP 200 для repository, README, LICENSE и SECURITY. Включены private vulnerability reporting, Dependabot security updates, secret scanning и push protection.
- Первый tag run `33164714425` fail closed остановился до notarization и publication: import `.p12` прошёл, но Xcode не видел временный Keychain вне user search list. PR `#4` добавил search-list setup, exact identity preflight и restoration; обязательный CI прошёл.
- Protected tag run `33165198739` на commit `0681078f8a38154aca52981d2f5185bd4c69c58b` прошёл 150 SwiftPM tests, unsigned build gate, universal Developer ID archive, App Store Connect API notarization, stapling, cleanup, draft verification и stable publication.
- Публичный release [`v1.0.0`](https://github.com/tomfordrumm/Qipli/releases/tag/v1.0.0) содержит `Qipli-1.0.0.zip` и checksum. Независимое unauthenticated скачивание подтвердило SHA-256 `b7edd1d56322de6487ea2563a2200185fa430dcca74355e1a052744725d9804e`, version `1.0.0 (1)`, Developer ID signature, stapled ticket и Gatekeeper `source=Notarized Developer ID`.

### Отклонения и остаточные риски

- Реальный rerun опубликованного `v1.0.0` ещё не выполнен; contract fail closed запрещает второй release или замену immutable assets, но operational proof остаётся открытым.
- Clean-machine launch на macOS 14 остаётся отдельным release gate S008 и незакрытым verification step S014.
- Текущий публичный `v1.0.3` был выпущен до D-030 и содержит только ZIP. Stable latest DMG URL начнёт работать после следующего protected release; старые release assets не изменяются.
