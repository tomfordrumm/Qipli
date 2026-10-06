# Qipli — текущее состояние проекта

Последняя актуализация: 2026-10-06, опубликован и проверен v1.0.13/build14 без временной диагностики S037. Установленное Sparkle обновление остаётся отдельной проверкой.

Источник operational-статусов: этот файл. Исторические переходы и прежние verification snapshots находятся в [`STATE-HISTORY.md`](STATE-HISTORY.md).

## Текущее положение

### Qipli Dev identity

Статус: `needs_verification`. D-045 реализован: Debug `Qipli Dev.app` / `com.qipli.app.dev`, Apple Development, отдельные настройки, общий History store/assets и отключённый Sparkle. Подписанный universal `build-for-testing` прошёл; существующие `SecureUpdaterSettingsTests` 3/3; Release settings сохраняют `Qipli.app` / `com.qipli.app`. Strict codesign verification прошёл на копии в `/private/tmp/qipli-dev-identity-check/Qipli Dev.app` без Finder xattrs: Documents file provider повторно добавляет недопустимый FinderInfo к build test bundle. Проверка Accessibility остаётся за пользователем: обычный Cmd+R из Xcode, выдать Dev доступ, пересобрать и проверить сохранение доступа обеих версий. Версии запускать по очереди.


- Удаление логирования [PR #31](https://github.com/tomfordrumm/Qipli/pull/31) и [Release PR #32](https://github.com/tomfordrumm/Qipli/pull/32) слиты в `main`. Release source SHA `8be2a4c076896f08338b15e1d470b8e04fb4d5df`, версия `1.0.13`, build `14`.
- Последняя опубликованная версия [v1.0.13](https://github.com/tomfordrumm/Qipli/releases/tag/v1.0.13), от 2026-10-06. Signed/notarized ZIP/DMG и Sparkle feed проверены. В публичном executable нет временных диагностических logger markers. Installed update этим не подтверждён.
- Milestones M1–M3 и M6–M9 завершены. M4/M5 сохраняют release gates S014/S008; M10 и M11 активны из-за оставшихся gates S031 и S032.
- S001–S007, S009–S013, S015–S016, S017–S027 и S030 имеют статус `done`.
- S028 остаётся в backlog по D-038. S029 возвращён в активный план по D-042; M12 описывает избранное в Top Notch.
- S014 имеет статус `needs_verification`: публичный `v1.0.8` подтверждён, остаётся operational immutable-rerun proof и clean-machine macOS 14 install/launch.
- S008 остаётся `blocked` до закрытия release verification matrix, связанной с S014.

## Новая запланированная работа

S037 `needs_verification`: реализация on-demand bounded capture по D-052 доставлена в v1.0.12. Полный SwiftPM 325/325, signed universal Debug/unsigned Release и owned NSTextView word+0/3 spaces/selection/native Undo PASS. Пользователь подтвердил новую Dev в ChatGPT: исправление слова без выделения без пробела и после пробелов, один ⌘Z и сохранение clipboard. Дополнительные sources, permission/focus races, VoiceOver/macOS14 и установленное Sparkle обновление остаются открыты. Подробности в Implementation report S037.

S033 реализован и принят по D-043: Stack начинает в compact presentation с bounded side previews, pending/status/direction indicators, раскрытием без задержки, explicit accessibility expansion и geometry-aware hit testing. Synthetic geometry, focused/full SwiftPM suites, unsigned universal Xcode Debug build и ручная установленная matrix подтверждены пользователем. S034 реализован и закрыт пользователем 2026-09-16 по D-044: typed capture/paste для rich text и images, session leases, revocation/unavailable states и bounded previews. Установленная source/target matrix, Accessibility/VoiceOver и signed-update gate остаются delivery gates и не меняют статус закрытого implementation slice. Предыдущий release snapshot ниже не перепроверялся этой задачей.

S035 реализован локально по предложенному Finder-only сценарию ⌘X → ⌘V. Synthetic platform probe подтвердил рабочую связку tagged Finder ⌘C → ⌥⌘V, но прямой Finder ⌘X и наблюдение результата не подтверждены; поэтому UI остаётся dispatch-only, а установленная Finder/accessibility/display matrix и окончательное подтверждение scope по D-046 открыты. Статус `needs_verification`; включён в опубликованный `v1.0.11`, что не закрывает установленную matrix.

S036 реализован по D-047: до пяти последних записей под History, bounded native menu previews, immutable UUID snapshot, захват target при открытии и общий typed paste coordinator. Статус `needs_verification`: автоматические проверки проходят, installed-app target/keyboard/VoiceOver/appearance matrix ещё открыта. При active Stack выбор отключён с пояснением.

## Текущая работа

### Упрощение кода по D-048

Локальная реализация проверена: обязательные History capabilities и lease forwarding, единый storage actor, общий Stack write/validation path, удаление неиспользуемых APIs, общий first-page loader с сохранением selection и stale-result guard, shared panel mechanics и разделение PlaceholderViews на именованные UI файлы. SwiftPM: 286 tests, 0 failures, 5 sandbox skips; отдельный запуск PasteboardMonitorTests вне sandbox: 23/23, без skips. Unsigned universal Debug Xcode build и `git diff --check` прошли. Independent review: найденный selection regression исправлен и покрыт тестом, оставшихся actionable findings нет. Net production Swift: −361 строк.

Следующая проверка: установленная подписанная Dev сборка, History search/selection → paste в исходное приложение, plain/rich/image Stack с Cancel/Delete/Reactivate, Finder Cut compact panel и multi-display placement. Эти interactive gates не подтверждены автоматическими тестами. Рефакторинг входит в опубликованный `v1.0.11`; нынешняя проверка publication metadata не заменяет этот interactive gate.


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

## Последний выпуск

`v1.0.13`, build `14`, tag/main SHA `8be2a4c076896f08338b15e1d470b8e04fb4d5df`. [PR #31](https://github.com/tomfordrumm/Qipli/pull/31) удаляет временный logger, его вызовы и coordinator stage tracking; proof state и safety checks сохранены. [PR #32](https://github.com/tomfordrumm/Qipli/pull/32) содержит только version/build и release notes. Exact-SHA [main CI](https://github.com/tomfordrumm/Qipli/actions/runs/37460793779) и protected [release workflow](https://github.com/tomfordrumm/Qipli/actions/runs/37461443223) SUCCESS; Environment approval выполнил пользователь.

Публичные ZIP/DMG SHA-256 PASS; стабильный и latest `Qipli.dmg` идентичны версионному DMG. Workflow проверил codesign, notarization/stapling и Gatekeeper; скачанное приложение независимо прошло strict/deep codesign, stapler и Gatekeeper. [Sparkle appcast](https://tomfordrumm.github.io/Qipli/appcast.xml): 1.0.13/build14, minimum macOS14.0, immutable ZIP URL и длина совпадают; Ed25519 подпись ZIP независимо проверена публичным ключом из приложения. Public executable logging marker scan PASS.

Локальные gates patch: SwiftPM 325/325 без failures, version validator 8/8, project-version, CI/release contract 13/13, privacy и diff checks PASS; в Sources нет OSLog/Logger/LayoutCorrectionDiagnostics. ChatGPT word/space/Undo/clipboard принят пользователем до v1.0.12, correction behavior в v1.0.13 не меняется. Cross-app Settings focus, installed update и остальные открытые matrix не объявляются пройденными. Подробное release evidence находится в STATE-HISTORY.

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
| S034 | Rich text и изображения в Paste Stack | `done` | implementation и пользовательский smoke закрыты; installed-app matrix и signed-update gate S031 остаются delivery gates |
| S035 | Вырезание файлов с индикацией в чёлке | `needs_verification` | S033, S025; installed Finder/accessibility/display matrix и окончательное подтверждение D-046 |
| S036 | Пять последних записей History в меню | `needs_verification` | реализация и automated checks; installed-app typed target/keyboard/VoiceOver/Light-Dark matrix, release gate S031 сохранён |
| S037 | Исправление раскладки по хоткею | `needs_verification` | опубликован v1.0.13 без временных логов; ChatGPT word/space/Undo/clipboard принят; полная sources/permissions/focus/VoiceOver/macOS14 matrix открыта |

## Блокеры и recheck points

- S037: core platform feasibility закрыт для выбранного bounded adapter и metadata tracking; production implementation опубликована в v1.0.13 без временных логов; основной ChatGPT smoke принят пользователем. Complete gesture/race/owner matrix и дополнительные targets/sources проверяются отдельно; неизвестные capabilities дают отказ. Постоянный keyboard buffer не разрешён; explicit clipboard transaction задан D-052.

- S033: закрыт после пользовательского подтверждения ручной установленной matrix. Release signing/update gates ведутся отдельно и не блокируют этот срез.

- S034: implementation, focused/full tests, builds и пользовательский smoke закрыты; installed source/target, Accessibility/VoiceOver, rapid-interaction и signed-update checks остаются delivery gates.
- S014/S008: нужен operational immutable rerun опубликованного release tag и clean-machine macOS 14 verification.
- S031: implementation, automated checks, manual acceptance и signed public release подтверждены; остаётся реальный installed Sparkle update smoke.
- S032: implementation, focused/full automated checks, universal builds и signed public `v1.0.8` подтверждены; остаётся visual/search/accessibility matrix в установленном приложении.
- S029: implementation, full SwiftPM и universal Release Xcode build подтверждены; остаются installed-app behavior/accessibility/display matrix и signed update с сохранением favorite после relaunch.
- Password-field History shortcut: исправление keyboard focus подтверждено пользователем; custom shortcut/reset и release gates остаются отдельно.
- Ограничение BL-006, отключение дисплея во время Top Notch reveal, принято и не блокирует S030.

## Последняя проверка

- 2026-10-06: v1.0.13/build14 опубликован без временного logger S037. Release/Pages SUCCESS; публичные ZIP/DMG checksums, stable/latest alias, codesign/stapler/Gatekeeper, Sparkle Ed25519 и public executable logging scan PASS.

- 2026-10-06: v1.0.12/build13 опубликован, release и Pages jobs SUCCESS. Публичные ZIP/DMG checksums, stable DMG alias, app codesign/stapler/Gatekeeper и Sparkle Ed25519 verification PASS. Пользователь подтвердил основной ChatGPT correction path до публикации. Installed Sparkle update остаётся открытым.

- 2026-10-02: S037 реализован локально и уточнён по пользовательскому smoke: полный SwiftPM 314 tests / 0 failures / 0 skips, signed universal Debug и unsigned universal Release, strict codesign, version/CI/release contracts, public-readiness/update-privacy и Sparkle runtime linking прошли. Core synthetic platform/hardware metadata proof отделён от installed feature matrix; дополнительный production AX adapter runtime probe пропущен до payload read, потому что прежнее owned TextEdit окно недоступно. Probe utility изолирован от обычного app target; версия 1.0.11/build 12 сохранена. Подробное evidence и незакрытые gates — в Implementation report S037 и D-051.

- 2026-09-22: уточнение UI S035 по пользователю: только compact Finder Cut, без expansion; значок вырезания/состояния слева, крестик справа, имя/количество либо ошибка снизу. 282 SwiftPM tests, 0 failures, 5 pasteboard environment skips; development-signed universal Debug build и synthetic offscreen ready/error render. Новая installed-app cancel/hover/VoiceOver/display проверка остаётся открытой.

- 2026-09-22: S036: 8 новых tests и полный SwiftPM suite, 279 tests / 0 failures / 0 skipped. Финальный прогон использовал идентичную копию Sources/Tests в `/private/tmp`, поскольку чтение `.git/config` и старого `.build` в Documents зависало. Development-signed universal Debug build и strict codesign verification прошли. Подробности находятся в Implementation report S036; installed-app acceptance не заявляется.

- 2026-09-21: S035 реализован: Finder AX admission для локальных regular files, non-consuming ⌘X, bounded clipboard correlation/self-write suppression, Cut Top Notch panel, Stack arbitration и одноразовый tagged ⌥⌘V. Stale clipboard invalidates Cut; ordinary ⌘V replays only when destination context is unchanged. Synthetic probe подтвердил native перемещение через tagged ⌘C → ⌥⌘V, но не дал result/progress API; 10 focused Finder Cut tests проходят. Installed Finder/accessibility/display matrix остаётся открытой.

- 2026-09-15: S034 implementation: History-first typed capture/paste для text/rich text/images, session leases, expiry protection, Delete/Clear All revocation и unavailable cards. Пользовательский smoke выявил placeholder в compact image preview до раскрытия панели; исправлено eager thumbnail request после Stack capture и реактивным обновлением compact view по thumbnail revision. Focused thumbnail regression test и S034 tests `4/4`; полный SwiftPM: `259` tests, `0` failures, `5` skipped; development-signed universal Debug и unsigned universal Debug/Release builds; version contract и embedded Sparkle runtime linking прошли. Installed-app rerun именно после thumbnail fix, остальная source/target matrix, Accessibility/VoiceOver, rapid-interaction и signed Sparkle update gates остаются открыты.

- 2026-09-16: пользователь подтвердил считать S034 завершённым. Delivery gates из предыдущей проверки сохранены отдельно и не переобозначены как пройденные.

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

Установить опубликованное обновление 1.0.13 через Sparkle из предыдущей Release версии; проверить сохранение History/favorites и Accessibility после relaunch. Это отдельный installed-update gate, публикация его не закрывает.

Для S037: основной ChatGPT word/space/Undo/clipboard smoke закрыт пользователем. Продолжить полную gesture/source/permission/focus/VoiceOver matrix, macOS14, 3+ sources и IME; проверить newer Copy и History/Stack suppression в установленном приложении.

Провести S036 installed-app matrix на synthetic данных в development-signed Debug: TextEdit plain/rich, браузер, image target и Finder reference; мышь/клавиатура/Escape, отказ Accessibility, закрытый target, active Stack, VoiceOver и Light/Dark. Ожидается одна вставка полного payload в исходное приложение без открытия History при успехе.

S034 закрыт по пользовательскому smoke acceptance и автоматическим проверкам. Его installed-app и signed-update проверки остаются delivery gates; отдельные release gates S014/S008, S031 и S032 остаются в общем порядке ниже.


1. Проверить сброс History к первому элементу после прокрутки и повторного открытия; отдельно проверить custom shortcut/reset и обычное text field.
2. Выполнить S032 installed-app visual/search/accessibility matrix, включая card reuse, selection-only update, URL-first search и exact `⇧Backspace`.
3. Выполнить реальный Sparkle update для S031 с сохранением History.
4. Выполнить clean-machine macOS14 install/launch и operational immutable-rerun gate S014. Выпуск v1.0.13 завершён, опубликованные tag/assets неизменяемы.

Подробные исторические записи не являются обязательным operational-контекстом. Открывайте [`STATE-HISTORY.md`](STATE-HISTORY.md) только если нужно восстановить происхождение решения, старый verification result или release evidence.
