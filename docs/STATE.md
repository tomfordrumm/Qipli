# Qipli — текущее состояние проекта

Последняя актуализация: 2026-10-16, v1.0.16/build17 опубликован; public ZIP/DMG/Sparkle проверены, installed update остаётся отдельным gate.

Источник operational-статусов: этот файл. Исторические переходы и прежние verification snapshots находятся в [`STATE-HISTORY.md`](STATE-HISTORY.md).

## Текущее положение

### Выпуск 1.0.16/build17

Публичный [v1.0.16](https://github.com/tomfordrumm/Qipli/releases/tag/v1.0.16), build `17`, annotated tag/main SHA `a333f7fad1afc7d7d0352f9ae2624cc2b57e6501`. [Feature PR #38](https://github.com/tomfordrumm/Qipli/pull/38) и [Release PR #39](https://github.com/tomfordrumm/Qipli/pull/39) слиты; [exact-main CI](https://github.com/tomfordrumm/Qipli/actions/runs/38870673262) SUCCESS на attempt2 без source changes. После approval пользователя [protected release и Pages](https://github.com/tomfordrumm/Qipli/actions/runs/38872025883) SUCCESS. Скачанные public ZIP/DMG SHA-256, stable/latest DMG equality, Developer ID/Hardened Runtime/nested Sparkle, notarization/stapling/Gatekeeper и публичный appcast 1.0.16/build17 PASS. Ed25519 подпись ZIP независимо проверена публичным ключом downloaded app. Evidence: STATE-HISTORY, artifacts `/private/tmp/qipli-1.0.16-verified/`. Installed update и реальный Option/cycle/title-field acceptance остаются открытыми.


### S037: локальные исправления надёжности, 2026-10-22

D-057 реализован локально; пользователь 2026-10-22 разрешил публикацию 1.0.17/build18 для собственного тестирования. Recovery/backoff/health-check и видимый input-unavailable, безопасный Copy refusal, same-field recheck, composition boundary и 30 s buffer, paced Backspace + Paste. SwiftPM 369/369, signed Dev/unsigned Release и codesign/privacy/CI/diff PASS; итоговый focused run 41/41 PASS. Подробности и пути сборок в S037.

Статус `needs_verification`: Chrome/Telegram comparison не выполнен из-за глобального focus admission, mutation не начиналась. Общий Telegram UI запрещён auto-review из-за private chats; prepared synthetic-field runner позволяет обойтись без чтения чатов. Пользователь остановил живые тесты, поскольку компьютер нужен для работы. Следующее действие при возобновлении: проверить synthetic Chrome/Telegram поле без ожидания пользователя у компьютера; подтвердить actual text, clipboard/Undo и реальные trigger/cycle. Нельзя объявлять совместимость или готовность заменить Punto по unit/build.

### S037 native correction D-056

`needs_verification`, реализация D-056 слита через PR #38 и опубликована в 1.0.16/build17. Обновлено 2026-10-16 после native проверки 15 октября. Production AX replacement заменён Copy/Paste выделения и physical-key replay слова. Документы/coverage, clipboard self-write suppression и guards обновлены. Full SwiftPM 365/365 и focused run 66/66 PASS; signed universal Debug и unsigned universal Release builds PASS.

Signed two-process owned NSTextView: word +0/+3 spaces, selection 6/12 288 UTF-16, фактический текст/caret/single native Undo/clipboard restore PASS, TIS switch mock. В реальном Final Cut effects-search оба production transport пути `ghbdtn → привет` подтверждены повторным Copy: paste 1196 ms, replay 1514 ms, включая подготовку/verification. Это transport integration, не installed Option/source-switch acceptance; UI automation отвергает modifier-only key. Поиск очищен, монтаж не менялся; прежняя `/Applications/Qipli.app` снова запущена после разрешённой пользователем остановки. Final Cut title fields/реальный Option/cycle/TIS, macOS14/permission/VoiceOver и delivery gates остаются открыты. По запросу 2026-10-16 опубликован 1.0.16/build17 для установленной пользовательской проверки; acceptance gates не закрываются публикацией.

### Локальная диагностика D-055

S038 остаётся `needs_verification`. Schema v2 опубликована с 1.0.15/build16, сохранена в 1.0.16; payload/raw identities не записываются, прежний opt-in сохраняется. Installed Settings/ChatGPT/VoiceOver acceptance остаётся открытым. Подробное evidence предыдущего выпуска находится в STATE-HISTORY.

### Qipli Dev identity

Статус: `needs_verification`. D-045 реализован: Debug `Qipli Dev.app` / `com.qipli.app.dev`, Apple Development, отдельные настройки, общий History store/assets и отключённый Sparkle. Подписанный universal `build-for-testing` прошёл; существующие `SecureUpdaterSettingsTests` 3/3; Release settings сохраняют `Qipli.app` / `com.qipli.app`. Strict codesign verification прошёл на копии в `/private/tmp/qipli-dev-identity-check/Qipli Dev.app` без Finder xattrs: Documents file provider повторно добавляет недопустимый FinderInfo к build test bundle. Проверка Accessibility остаётся за пользователем: обычный Cmd+R из Xcode, выдать Dev доступ, пересобрать и проверить сохранение доступа обеих версий. Версии запускать по очереди.


- Последняя опубликованная версия [v1.0.16](https://github.com/tomfordrumm/Qipli/releases/tag/v1.0.16), build17 от 2026-10-16. Native correction D-056 и local diagnostics D-055 опубликованы. Installed update проверяется отдельно.
- Milestones M1–M3 и M6–M9 завершены. M4/M5 сохраняют release gates S014/S008; M10 и M11 активны из-за оставшихся gates S031 и S032.
- S001–S007, S009–S013, S015–S016, S017–S027 и S030 имеют статус `done`.
- S028 остаётся в backlog по D-038. S029 возвращён в активный план по D-042; M12 описывает избранное в Top Notch.
- S014 имеет статус `needs_verification`: публичный `v1.0.8` подтверждён, остаётся operational immutable-rerun proof и clean-machine macOS 14 install/launch.
- S008 остаётся `blocked` до закрытия release verification matrix, связанной с S014.

## Новая запланированная работа

Локальное уточнение 2026-10-08, ветка `feature/history-plain-paste-correction-feedback`: Shift-double-click plain paste, S037 ceiling 12 288 UTF-16 и transient error panel на три секунды реализованы по D-053. SwiftPM 333/333, signed universal Debug/strict-deep codesign, unsigned universal Release, version/privacy/diff checks PASS. Owned NSTextView 12 288: полная замена, сохранение context/selection, native Undo и clipboard PASS отдельно для native paste и Unicode fallback. Real mouseUp callback и notice timer/races/layout проверены. Версия/build 1.0.13/14 не менялись; опубликованное приложение не обновлено. Следующее действие: installed user smoke Shift-double-click, длинного выделения и анимации ошибки в Dev; S037 остаётся needs_verification.

S037 `needs_verification`: актуальная переделка D-056 описана выше; предыдущая on-demand AX реализация D-052 доставлена в v1.0.12. Полный SwiftPM 325/325, signed universal Debug/unsigned Release и owned NSTextView word+0/3 spaces/selection/native Undo PASS. Пользователь подтвердил новую Dev в ChatGPT: исправление слова без выделения без пробела и после пробелов, один ⌘Z и сохранение clipboard. Дополнительные sources, permission/focus races, VoiceOver/macOS14 и установленное Sparkle обновление остаются открыты. Подробности в Implementation report S037.

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

`v1.0.16`, build `17`, tag/main SHA `a333f7fad1afc7d7d0352f9ae2624cc2b57e6501`, опубликован 2026-10-16. [Release](https://github.com/tomfordrumm/Qipli/releases/tag/v1.0.16), [workflow](https://github.com/tomfordrumm/Qipli/actions/runs/38872025883). ZIP/DMG/checksums/stable/latest aliases и Sparkle feed проверены независимо. Installed update, сохранение History/favorites/Accessibility и реальный Option/cycling в Final Cut остаются отдельными gates.

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
| S037 | Исправление раскладки по хоткею | `needs_verification` | D-056 native transport: owned field и Final Cut search PASS; installed Option/cycle/TIS/title fields, permissions/VoiceOver/macOS14 matrix открыта |
| S038 | Opt-in локальная диагностика | `needs_verification` | automated/build/UI render PASS; installed Settings/VoiceOver/Finder и correction smoke открыты |

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

- 2026-10-16: v1.0.16/build17 publication и release/Pages SUCCESS; public ZIP/DMG/checksums/aliases, version, signing/notarization/Gatekeeper и Sparkle public-key signature PASS. Installed update не выполнялся.

- 2026-10-15: v1.0.15/build16 publication и release/Pages SUCCESS; публичные ZIP/DMG checksums, signing/notarization/Gatekeeper и Sparkle public-key signature PASS. Installed update не выполнялся.

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

Обновить установленную Release до 1.0.16/build17 через Check for Updates или опубликованный DMG. Проверить реальный левый Option, цикл системных раскладок, последнее слово и выделение в Final Cut, включая title/text fields, native Undo и сохранение clipboard. Effects-search transport paths уже подтверждены отдельно, детали в S037. Dev сборка для отдельных probes сохранена: `/private/tmp/qipli-native-correction-xcode/Build/Products/Debug/Qipli Dev.app`.

Отдельно проверить installed Sparkle update с сохранением History/favorites/Accessibility/diagnostics opt-in и реальный correction trail schema v2. Installed Settings/VoiceOver/Finder/ChatGPT matrix и clean-machine macOS14 gate остаются открытыми. Опубликованные v1.0.16 tag/assets неизменяемы; исправления выходят новой версией.
