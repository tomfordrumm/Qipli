# Qipli — текущее состояние проекта

Последняя актуализация: 2026-09-15

Источник operational-статусов: этот файл. Исторические переходы и прежние verification snapshots находятся в [`STATE-HISTORY.md`](STATE-HISTORY.md).

## Текущее положение

### Qipli Dev identity

Статус: `needs_verification`. D-045 реализован: Debug `Qipli Dev.app` / `com.qipli.app.dev`, Apple Development, отдельные настройки, общий History store/assets и отключённый Sparkle. Подписанный universal `build-for-testing` прошёл; существующие `SecureUpdaterSettingsTests` 3/3; Release settings сохраняют `Qipli.app` / `com.qipli.app`. Strict codesign verification прошёл на копии в `/private/tmp/qipli-dev-identity-check/Qipli Dev.app` без Finder xattrs: Documents file provider повторно добавляет недопустимый FinderInfo к build test bundle. Проверка Accessibility остаётся за пользователем: обычный Cmd+R из Xcode, выдать Dev доступ, пересобрать и проверить сохранение доступа обеих версий. Версии запускать по очереди.


- Основная ветка работы: `release/1.0.10`, версия `1.0.10`, build `11`. Release notes подготовлены; следующий delivery gate — push ветки, pull request в защищённый `main`, unsigned CI, merge и protected release workflow.
- Последняя опубликованная версия по GitHub Releases — `v1.0.9` от 2026-09-07; наличие публикации перепроверено 2026-09-11, бинарные artifacts в этой проверке не проверялись. Публикация DMG/ZIP, appcast и реальный Sparkle update для `v1.0.10` ещё не выполнены.
- Milestones M1–M3 и M6–M9 завершены. M4/M5 сохраняют release gates S014/S008; M10 и M11 активны из-за оставшихся gates S031 и S032.
- S001–S007, S009–S013, S015–S016, S017–S027 и S030 имеют статус `done`.
- S028 остаётся в backlog по D-038. S029 возвращён в активный план по D-042; M12 описывает избранное в Top Notch.
- S014 имеет статус `needs_verification`: публичный `v1.0.8` подтверждён, остаётся operational immutable-rerun proof и clean-machine macOS 14 install/launch.
- S008 остаётся `blocked` до закрытия release verification matrix, связанной с S014.

## Новая запланированная работа

S033 реализован и принят по D-043: Stack начинает в compact presentation с bounded side previews, pending/status/direction indicators, раскрытием без задержки, explicit accessibility expansion и geometry-aware hit testing. Synthetic geometry, focused/full SwiftPM suites, unsigned universal Xcode Debug build и ручная установленная matrix подтверждены пользователем. После S033 запланирован S034: rich text/images, typed paste и session ownership по D-044. Предыдущий release snapshot ниже не перепроверялся этой задачей.

S035 добавлен как план вырезания файлов с индикацией в компактном окне. Предложен Finder-only сценарий ⌘X → ⌘V; scope и platform probe остаются открыты по D-046. Реализация не начата, приоритет относительно S034 не назначен.

## Текущая работа

### Избранное в Top Notch

S029 реализован по D-042: header/card stars, search внутри режима, migration и защита от automatic expiry для favorite occurrences и owned assets. SwiftPM и universal Release Xcode build пройдены; установленная accessibility/display matrix и signed-update сохранение favorite остаются отдельными gates.


### Password-field History shortcut

Статус: `needs_verification`.

History opener переведён на Carbon `RegisterEventHotKey` с обновлением binding из Settings и event-tap fallback при ошибке регистрации. SwiftPM build и 12 focused input tests прошли; duplicate History dispatch и fallback без регистрации покрыты. Публичный релиз этого исправления не выполнен.

History использует native `.nonactivatingPanel` с прямым key-window/Search focus. 2026-09-08 пользователь подтвердил, что вызов из Chrome password field теперь работает; временная диагностика удалена по его запросу. Переход прошёл 47 focused tests и development-signed Xcode Debug build. Отдельные custom shortcut/reset и release gates не закрывались этим подтверждением.

### Сброс History к первому элементу

По запросу пользователя каждый явный show теперь сбрасывает native scroll origin к началу после layout и до reveal, даже при неизменной selection. Snapshot/thumbnail updates сохраняют ручную прокрутку. 50 focused History/model/panel tests и development-signed Xcode Debug build прошли, включая native scroll regression; диагностические markers отсутствуют в собранном executable. Требуется пользовательская проверка повторного открытия после прокрутки.

### Performance review D-041

Реализация, automated checks и пользовательский smoke test завершены. Изменения включают ranked search, indexed keyset range, persisted display projection, bounded image/rich quotas, ordered capture admission и bounded thumbnail cache. Подробные benchmark numbers и implementation evidence остаются в связанных slices и архивной записи состояния.

Smoke test подтвердил migration, search, text/image/rich-text paste и Paste Stack. Он не заменяет S032 visual/accessibility matrix и signed update verification.

## Подготовка v1.0.10

- Ветка: `release/1.0.10`; версия `1.0.10`, build `11`.
- Release notes: [`release-notes-template.md`](release-notes-template.md).
- Следующий delivery path: push → pull request в защищённый `main` → unsigned CI → merge → tag `v1.0.10` на commit `main` → protected signing/notarization workflow.
- Перед публикацией требуется отдельная проверка, что installed History shortcut, S031 update path и S032 visual/search/accessibility gates не выданы за пройденные.

## Статусы срезов

| Срез | Название | Статус | Зависимости или оставшийся gate |
|---|---|---|---|
| S001 | Скелет приложения и системное разрешение | `done` | — |
| S002 | Захват, хранение и удаление истории | `done` | S001 |
| S003 | Поиск и повторная вставка из истории | `done` | S002 |
| S004 | Сбор и визуальная панель Paste Stack | `done` | S002 |
| S005 | Порядок и направление обхода | `done` | S004 |
| S006 | Последовательная вставка и прогресс | `done` | S001, S005 |
| S007 | Повторная активация и отмена | `done` | S006 |
| S008 | Приватность и первый стабильный релиз через GitHub | `blocked` | release verification matrix; зависит от S014–S016 |
| S009 | Адаптивные стеклянные панели | `done` | S001, S003, S007 |
| S010 | Settings, пользовательские сочетания и запуск при входе | `done` | — |
| S011 | Опциональный first-run onboarding | `done` | — |
| S012 | Edge-to-edge Paste Stack с кастомным header | `done` | — |
| S013 | Версии и безопасный public CI | `done` | — |
| S014 | Публичный репозиторий и подписанные GitHub-релизы | `needs_verification` | immutable rerun; clean-machine macOS 14 install/launch |
| S015 | Безопасные обновления через Sparkle | `done` | — |
| S016 | Надёжная навигация и закрытие History | `done` | — |
| S017 | Performance baselines и instrumentation | `done` | — |
| S018 | Эффективное History storage | `done` | S017 |
| S019 | Асинхронный History pipeline | `done` | — |
| S020 | Отзывчивый поиск и ограниченные previews | `done` | — |
| S021 | Масштабируемый Paste Stack | `done` | — |
| S022 | Энергоэффективный pasteboard polling | `done` | — |
| S023 | Bounded typed History foundation | `done` | — |
| S024 | Managed image History | `done` | — |
| S025 | Referenced URL, file and video History | `done` | automated и browser/Finder matrix подтверждены |
| S026 | Typed History migration and release hardening | `done` | — |
| S027 | Top Notch History shelf | `done` | display/focus/paste/accessibility matrix подтверждена |
| S028 | Полноценная карточная History | `backlog` | BL-004; вне активного плана |
| S029 | Избранное в Top Notch History | `needs_verification` | automated checks passed; installed-app matrix и signed-update persistence |
| S030 | Paste Stack в Top Notch | `done` | S007, S012, S021, S027 |
| S031 | Форматированный текст в History | `needs_verification` | installed Sparkle update с сохранением History |
| S032 | Полировка карточек и релевантный поиск History | `needs_verification` | installed-app visual/search/accessibility matrix |
| S033 | Компактный Paste Stack по центру | `done` | S030; automated checks и ручная установленная matrix подтверждены пользователем |
| S034 | Rich text и изображения в Paste Stack | `planned` | S033, S024, S031; signed-update gate S031 сохраняется перед delivery |
| S035 | Вырезание файлов с индикацией в чёлке | `planned` | S033, S025; подтверждение scope и Finder platform probe D-046 |

## Блокеры и recheck points

- S033: закрыт после пользовательского подтверждения ручной установленной matrix. Release signing/update gates ведутся отдельно и не блокируют этот срез.

- S014/S008: нужен operational immutable rerun опубликованного release tag и clean-machine macOS 14 verification.
- S031: implementation, automated checks, manual acceptance и signed public release подтверждены; остаётся реальный installed Sparkle update smoke.
- S032: implementation, focused/full automated checks, universal builds и signed public `v1.0.8` подтверждены; остаётся visual/search/accessibility matrix в установленном приложении.
- S029: implementation, full SwiftPM и universal Release Xcode build подтверждены; остаются installed-app behavior/accessibility/display matrix и signed update с сохранением favorite после relaunch.
- Password-field History shortcut: исправление keyboard focus подтверждено пользователем; custom shortcut/reset и release gates остаются отдельно.
- Ограничение BL-006, отключение дисплея во время Top Notch reveal, принято и не блокирует S030.

## Последняя проверка

- 2026-09-15: пользователь подтвердил полную ручную приёмку S033 и несколько дней использования compact Paste Stack. Hover/collapse работают без задержки; runtime, display и accessibility gates считаются закрытыми как user-reported acceptance. Свежий полный SwiftPM suite: 255 tests, 0 failures, 5 skipped; focused S033: 29/29.

- 2026-09-14: S033 implementation: compact/expanded Stack presentation, bounded camera-band geometry, bounded hit regions, hover/accessibility lifecycle и screen-parameter repositioning. Subagent review findings по ширине regions, collapse re-entry, interaction hold и stale geometry timers исправлены; финальный review actionable findings не выявил. Focused `TopNotchHistoryShelfTests`: 29 tests, 0 failures; full SwiftPM: 255 tests, 0 failures, 5 skipped; unsigned universal Xcode Debug build passed. Реальный installed-app MacBook/menu-band/accessibility matrix на тот момент ещё не выполнялся.

- 2026-09-11: release candidate `1.0.10` / build `11`: 248 SwiftPM tests, 0 failures; universal unsigned Release build; version и runtime linking для arm64/x86_64; release-contract tests 13/13, version-validator tests 8/8, CI contract, public-readiness audit и `git diff --check` прошли. Signing, notarization и installed Sparkle update этим прогоном не проверялись.

- 2026-09-11: пользователь подтвердил, что текущие изменения в целом прошли тестирование, и запросил release PR. Это общее подтверждение не закрывает отдельные verification matrix автоматически.

- 2026-09-08: удаление focus diagnostics и reset History scroll получили 50 focused tests, development-signed Xcode Debug build и `git diff --check`; debug markers отсутствуют в executable. Пользовательский reopen-scroll smoke новой сборки остаётся следующим шагом.
- 2026-09-08: после live Chrome trace выполнен переход History на native nonactivating key panel; 47 focused tests, development-signed Xcode Debug build и `git diff --check` прошли. Пользователь затем подтвердил исправление Chrome password-field focus.
- 2026-09-08: password-field focus follow-up прошёл 37 focused SwiftPM tests, universal unsigned Xcode Debug build и `git diff --check`. Пользователь подтвердил открытие History в прежней сборке; Search/keyboard selection/paste требуют live проверки новой.
- 2026-09-07: D-041 performance changes прошли focused/full automated checks, universal builds, migration/process smoke и пользовательский product smoke.
- 2026-09-07: password-field shortcut получил 12 focused input tests и `git diff --check`; live installed-app behavior не проверен.
- 2026-09-08: S029 implementation прошёл full SwiftPM (`249` tests, `0` failures, `5` skipped из-за test-environment pasteboard), universal Release Xcode build и `git diff --check`; installed-app matrix и signed update не проверены.
- 2026-09-04: `v1.0.8` signed/notarized public release независимо проверен; installed update остаётся отдельным gate S031.

## Следующее действие

S033 закрыт. Следующий срез по зависимости — S034; отдельные release gates S014/S008, S031 и S032 остаются в общем порядке ниже.


1. Проверить сброс History к первому элементу после прокрутки и повторного открытия; отдельно проверить custom shortcut/reset и обычное text field.
2. Выполнить S032 installed-app visual/search/accessibility matrix, включая card reuse, selection-only update, URL-first search и exact `⇧Backspace`.
3. Выполнить реальный Sparkle update для S031 с сохранением History.
4. Подготовить и провести protected `v1.0.10` release после закрытия необходимых gates. Immutable-rerun gate S014 остаётся отдельным незавершённым требованием.

Подробные исторические записи не являются обязательным operational-контекстом. Открывайте [`STATE-HISTORY.md`](STATE-HISTORY.md) только если нужно восстановить происхождение решения, старый verification result или release evidence.
