---
id: S013
title: Версии и безопасный public CI
status: ready
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

- [ ] Built `Info.plist` получает short version и build из Xcode build settings, а source plist больше не содержит независимый hard-coded release number.
- [ ] Pure version check принимает согласованные `vX.Y.Z`, `MARKETING_VERSION` и numeric `CURRENT_PROJECT_VERSION` и отклоняет mismatch, prerelease input для stable channel и нечисловой build.
- [ ] Pull request и push в `main` запускают SwiftPM suite и unsigned Xcode Debug/Release build на поддерживаемом GitHub-hosted macOS runner.
- [ ] CI workflow имеет явный `permissions: contents: read`, не использует `pull_request_target`, не импортирует Keychain material и не ссылается на release secrets.
- [ ] Сторонние Actions ограничены официальными GitHub Actions и фиксированы reviewable version/commit reference; shell steps не печатают environment.
- [ ] Повторный push в тот же ref отменяет устаревший незавершённый CI run, не затрагивая run другого ref.
- [ ] Repository audit проверяет tracked tree, ignored release outputs и Git history на private keys, known token forms, signing archives и запрещённые clipboard fixtures без вывода найденного secret value.
- [ ] `dist/` остаётся ignored, `git ls-files dist` пуст, а CI artifacts имеют ограниченный retention и не становятся Git-tracked files.

## Verification

- [ ] Focused unit/shell tests version validator: valid stable, tag mismatch, invalid build, prerelease rejection.
- [ ] `swift test` и unsigned Xcode Debug/Release build локально.
- [ ] Workflow syntax/static permission check и `git diff --check`.
- [ ] Реальный GitHub pull request run и push-to-main run завершаются успешно без release secrets.
- [ ] Fork-style PR proof подтверждает отсутствие protected secrets и write permissions.
- [ ] Public-readiness audit сохранён как непayload summary; любой реальный credential блокирует S014 до rotation/remediation.

## Implementation report

### Реализовано

Не заполнено.

### Проверено

Не заполнено.

### Отклонения и остаточные риски

Не заполнено.
