---
id: S013
title: Версии и безопасный public CI
status: needs_verification
depends_on: []
covers:
  - BR-015
  - BR-016
  - NFR-008
  - NFR-012
  - NFR-013
---

# S013: Версии и безопасный public CI

## Результат

Каждый pull request и push в `main` получает одинаковую unsigned проверку проекта, а version metadata имеет один контракт, пригодный для будущего tag release. CI не видит и не имитирует release credentials.

## В scope

- `CFBundleShortVersionString` через `MARKETING_VERSION` и числовой возрастающий `CFBundleVersion` через `CURRENT_PROJECT_VERSION`;
- единая проверка формата stable tag, short version и build number без подписи;
- GitHub Actions workflow для pull request и push в `main` на hosted macOS runner;
- SwiftPM tests и unsigned Xcode build для deployment target macOS 14;
- минимальные token permissions, concurrency и отсутствие release secrets/actions в PR workflow;
- повторяемый public-readiness audit current tree и Git history без печати secret values;
- подтверждение, что generated `dist/` остаётся ignored и не входит в commits.

## Вне scope

- Developer ID import, notarization и GitHub Release;
- выбор лицензии и смена repository visibility;
- Sparkle, appcast и сетевые запросы приложения;
- автоматическое изменение версии или создание tag самим workflow.

## Поведение и контракты

- CI запускается для fork pull request без доступа к protected Environment и repository signing secrets.
- Workflow использует `contents: read`; write permissions отсутствуют.
- Неуспешный test/build/version check делает job красным и не создаёт artifact, release или tag.
- Stable release version меняется reviewable commit. Будущий tag только подтверждает уже записанную версию.
- Audit выводит только тип проверки и затронутый path. Реальные credential values не попадают в log или fixture.

## Acceptance criteria

- [x] Built `Info.plist` получает short version и build из Xcode build settings, а source plist больше не содержит независимый hard-coded release number.
- [x] Pure version check принимает согласованные `vX.Y.Z`, `MARKETING_VERSION` и numeric `CURRENT_PROJECT_VERSION` и отклоняет mismatch, prerelease input для stable channel и нечисловой build.
- [ ] Pull request и push в `main` запускают SwiftPM suite и unsigned Xcode Debug/Release build на поддерживаемом GitHub-hosted macOS runner.
- [x] CI workflow имеет явный `permissions: contents: read`, не использует `pull_request_target`, не импортирует Keychain material и не ссылается на release secrets.
- [x] Сторонние Actions ограничены официальными GitHub Actions и фиксированы reviewable version/commit reference; shell steps не печатают environment.
- [x] Повторный push в тот же ref отменяет устаревший незавершённый CI run, не затрагивая run другого ref.
- [x] Repository audit проверяет tracked tree, ignored release outputs и Git history на private keys, known token forms, signing archives и запрещённые clipboard fixtures без вывода найденного secret value.
- [x] `dist/` остаётся ignored, `git ls-files dist` пуст, а CI artifacts имеют ограниченный retention и не становятся Git-tracked files.

## Verification

- [x] Focused unit/shell tests version validator: valid stable, tag mismatch, invalid build, prerelease rejection.
- [x] `swift test` и unsigned Xcode Debug/Release build локально.
- [x] Workflow syntax/static permission check и `git diff --check`.
- [ ] Реальный GitHub pull request run и push-to-main run завершаются успешно без release secrets.
- [ ] Fork-style PR proof подтверждает отсутствие protected secrets и write permissions.
- [x] Public-readiness audit сохранён как непayload summary; любой реальный credential блокирует S014 до rotation/remediation.

## Implementation report

### Реализовано

- `Config/Version.xcconfig` стал одной точкой изменения `MARKETING_VERSION` и `CURRENT_PROJECT_VERSION` для Debug и Release.
- Source `Info.plist` использует build-setting substitutions; release version больше не продублирована literal values.
- `scripts/validate-version.sh` проверяет stable `X.Y.Z`, положительный numeric build и точное соответствие `vX.Y.Z`.
- `scripts/check-project-version.sh` сверяет xcconfig, Debug/Release settings, source plist и опциональный built plist.
- `.github/workflows/ci.yml` запускает read-only unsigned CI для pull request и push в `main` на `macos-15`, отменяет только устаревший run того же ref и не создаёт artifacts.
- `scripts/check-ci-contract.sh` статически запрещает `pull_request_target`, release/signing команды, secret references, write permissions, unpinned Actions и artifact upload.
- `scripts/audit-public-readiness.sh` проверяет текущие tracked/untracked paths и доступную Git history на private-key/archive paths, credential-shaped values и запрещённые clipboard fixtures, не печатая найденные значения.

### Проверено

- `scripts/tests/validate-version-tests.sh`: 8 positive/negative cases прошли.
- Project version check подтвердил `1.0.0`, build `1` и tag `v1.0.0` для Debug/Release и built Release plist.
- SwiftPM: 150 tests, 0 failures.
- Unsigned Xcode Debug и Release builds прошли; Release app universal `arm64+x86_64`, deployment target macOS 14.
- Static CI contract, shell syntax, plist/project syntax и `git diff --check` прошли.
- Public-readiness audit проверил 75 current paths и 34 Git revisions. Credential-shaped values, private signing material и запрещённые clipboard fixtures не найдены.

### Отклонения и остаточные риски

- Реальный GitHub pull request, push-to-main и fork-style run ещё не выполнялись. До этих трёх hosted checks срез остаётся `needs_verification`.
- Audit сообщил о пяти старых `dist/*` paths в Git history. Они не содержат обнаруженного private signing material, сейчас `dist/` ignored и `git ls-files dist` пуст. Решение о возможной очистке history относится к public-readiness gate S014.
- Workflow фиксирует официальный `actions/checkout` v7.0.1 по commit SHA и использует поддерживаемый GitHub-hosted label `macos-15`, сверенные 2026-08-28.
