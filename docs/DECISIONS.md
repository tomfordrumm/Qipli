# Qipli — журнал решений

Дата актуализации: 2026-08-09

Статусы: `accepted` — подтверждённое решение; `proposed` — рабочее предложение агента, которое можно заменить до зависимого среза; `assumption` — видимое предположение; `superseded` — заменённое решение.

## D-001 — Нативное приложение только для macOS

- Статус: `accepted`
- Дата: 2026-08-06
- Источник: исходный бриф
- Контекст: продукту нужны системный буфер обмена, глобальные сочетания и плавающие панели.
- Решение: создавать нативное приложение для macOS, без web/electron-оболочки.
- Причина: это прямое ограничение продукта и самый короткий путь к AppKit/Core Graphics API.
- Последствия: другие ОС и браузерная версия вне MVP.

## D-002 — Минимальная версия macOS 14

- Статус: `accepted`
- Дата: 2026-08-06
- Источник: пользователь
- Контекст: нижняя граница влияет на API, тестовую матрицу и охват.
- Решение: deployment target первой версии — macOS 14.
- Причина: пользователь выбрал баланс современной нативной реализации и охвата.
- Последствия: поддержка macOS 13 и ниже не входит в acceptance criteria.

## D-003 — Прямое распространение через GitHub Releases

- Статус: `accepted`
- Дата: 2026-08-06
- Источник: пользователь
- Контекст: App Store требует App Sandbox, а основной сценарий нуждается в Accessibility API и управлении событиями других приложений.
- Решение: распространять Developer ID-signed и notarized сборку через GitHub Releases.
- Причина: выбранный путь совместим с основным сценарием и open-source моделью.
- Последствия: Mac App Store исключён; понадобятся Apple Developer credentials и отдельный release workflow.

## D-004 — SwiftUI + AppKit, Core Graphics event tap

- Статус: `accepted`
- Дата: 2026-08-07
- Источник: технический план, подтверждённый автоматической и ручной проверкой S001
- Контекст: SwiftUI удобен для feature UI, но панели, status item, focus и глобальный ввод требуют нативного контроля.
- Решение: SwiftUI для содержимого, AppKit для shell/panels/focus, Core Graphics event tap для активного `⌘V` и synthetic paste.
- Причина: минимальный набор системных frameworks без стороннего runtime.
- Последствия: системные адаптеры отделяются от тестируемой state machine; S001 подтвердил permission, event, focus и synthetic-event подход на macOS 14.

## D-005 — Без App Sandbox, с Hardened Runtime

- Статус: `proposed`
- Дата: 2026-08-06
- Источник: агент; Apple Developer Documentation проверена 2026-08-06
- Контекст: Accessibility integration конфликтует с sandbox, но public direct distribution требует надёжной подписи и notarization.
- Решение: не включать App Sandbox в MVP; включить Hardened Runtime и не добавлять лишние runtime exceptions.
- Причина: сохранить основной сценарий и максимально возможное системное hardening в выбранной модели.
- Последствия: security review должен особенно проверять отсутствие сети, логирования содержимого и лишних entitlements.

## D-006 — Core Data с локальным SQLite store

- Статус: `accepted`
- Дата: 2026-08-07
- Источник: технический план, подтверждённый перед реализацией S002
- Контекст: нужны локальные поиск, retention, удаление и миграции для простой сущности.
- Решение: использовать Core Data с SQLite-backed store в Application Support.
- Причина: зрелый системный persistence layer без внешней зависимости; подходит для macOS 14 и заданной модели.
- Последствия: запросы не должны показывать просроченные записи; delete-all должен учитывать WAL/SHM; производительность поиска проверяется до оптимизации.

## D-007 — Menu bar utility без обязательного Dock icon

- Статус: `accepted`
- Дата: 2026-08-07
- Источник: технический план, подтверждённый ручной проверкой S001
- Контекст: приложение постоянно работает в фоне и в основном открывается глобальными сочетаниями.
- Решение: использовать status item как постоянную оболочку; история и стек — временные панели.
- Причина: соответствует фоновому характеру и не требует постоянного основного окна.
- Последствия: status menu даёт доступ к основным командам, разрешению и Quit; временные панели не создают обязательный Dock icon.

## D-008 — Удаление записи и всей истории в MVP

- Статус: `accepted`
- Дата: 2026-08-06
- Источник: пользователь
- Контекст: история может содержать секреты, а автоматической фильтрации нет.
- Решение: дать удаление отдельной записи и команду очистки всей истории Qipli.
- Причина: минимальный контроль владельца над чувствительными локальными данными.
- Последствия: destructive action требует подтверждения; очистка не обещает forensic secure erase и не очищает system pasteboard.

## D-009 — История локальна и не использует сеть

- Статус: `accepted`
- Дата: 2026-08-06
- Источник: исходный бриф
- Контекст: приватность — ключевое ограничение, аккаунтов и синхронизации нет.
- Решение: приложение не содержит продуктовой сети, telemetry или remote crash upload.
- Причина: основной результат полностью локален.
- Последствия: network entitlements отсутствуют; release notarization использует сеть только вне runtime приложения.

## D-010 — Paste Stack не сохраняется как отдельная сущность

- Статус: `accepted`
- Дата: 2026-08-06
- Источник: исходный бриф, техническая форма предложена агентом
- Контекст: завершённые наборы явно отложены, а копирования всё равно остаются в истории.
- Решение: текущая stack session живёт в памяти; после завершения, отмены или перезапуска отдельная очередь недоступна.
- Причина: минимальный жизненный цикл без дублирования persistent data.
- Последствия: восстановление после crash не обещается; история остаётся независимым источником повторной вставки.

## D-011 — Семантика «used» основана на отправленной команде

- Статус: `accepted`
- Дата: 2026-08-06
- Источник: агент; ограничение межпроцессной вставки macOS
- Контекст: Qipli не может надёжно узнать, изменило ли стороннее поле своё содержимое после `⌘V`.
- Решение: переводить элемент с exact occurrence UUID в used только после успешной подготовки pasteboard и отправки tagged события `⌘V`; writer/permission/dispatch failure освобождает reservation обратно в pending.
- Причина: это единственное наблюдаемое приложением событие без интеграции с каждой целью.
- Последствия: UI и документация не называют used подтверждением вставки; retry сохраняет pending occurrence, а reactivation остаётся механизмом восстановления S007. S006 покрывает этот контракт deterministic state/executor tests и complete manual macOS verification.

## D-012 — Сильная активация только для явно вызванной History

- Статус: `accepted`
- Дата: 2026-08-07
- Источник: ручная проверка S003 пользователем; AppKit macOS 14 activation guidance перепроверена 2026-08-07.
- Контекст: обычный `NSApp.activate()` — кооперативный запрос и в accessory app может оставить предыдущее приложение активным, из-за чего History видна, но не получает клавиатуру.
- Решение: сразу после явной команды пользователя `⌘⇧V` или пункта меню Qipli изолированно вызывает legacy `activate(ignoringOtherApps: true)`, затем проверяет `isActive` и повторно делает History panel key/focus. Другие пути не используют эту активацию.
- Причина: History — keyboard-first surface; команда пользователя является явным намерением переключить фокус. Вызов локализован в одном AppKit adapter из-за deprecation на macOS 14.
- Последствия: Qipli намеренно перехватывает фокус только по собственному hotkey/menu action; сохраняется ограниченная проверка активации и ручная проверка реального focus flow перед `done`.

## D-013 — Activity recency без миграции history store

- Статус: `accepted`
- Дата: 2026-08-08
- Источник: подтверждённый пользовательский сценарий S003.
- Контекст: повторная вставка старой exact occurrence должна поднимать её в History и продлевать 30-day retention, но programmatic Core Data model уже имеет SQLite attribute `capturedAt` в user stores.
- Решение: domain timestamp называется `activityAt`: initial capture или successfully dispatched history paste. Durable storage продолжает использовать существующий key `capturedAt`, обновляя его тем же activity value; новый attribute не добавляется.
- Причина: сохраняет ID/text и совместимость существующих SQLite stores без migration risk.
- Последствия: порядок и retention считаются от capture-or-use; promotion выполняется только после tagged paste dispatch, а storage error promotion не меняет результат уже отправленной paste-команды и не вызывает повторный dispatch.

## D-014 — `⌘⇧C` копирует текущее выделение при старте Paste Stack

- Статус: `accepted`
- Дата: 2026-08-08
- Источник: пользователь
- Контекст: hotkey должен немедленно собрать уже выделенное значение, а не заставлять пользователя запускать empty Stack и отдельно нажимать Copy. Status menu не имеет source selection.
- Решение: global `⌘⇧C` начинает либо сохраняет текущую StackSession и отправляет tagged synthetic ordinary `⌘C` в остающееся active source app. Menu Start начинает пустую session и не dispatch-ит Copy. Повторный hotkey не reset-ит session, но отправляет очередную Copy.
- Причина: совпадает с ожидаемым copy-to-stack flow и сохраняет единственный History-first capture pipeline.
- Последствия: target app, а не Qipli, пишет pasteboard; resulting change не self-write и append в Stack происходит только после durable History capture. Ordinary `⌘C`/`⌘V` не меняются; sequential paste остаётся S006.

## D-015 — Reactivate Previous назначает one-shot priority, а не target undo

- Статус: `accepted`
- Дата: 2026-08-08
- Источник: пользователь
- Контекст: `⌘⇧Z` должен исправлять ошибочный Paste Stack occurrence, не меняя normal system Redo и не создавая ложного обещания undo в стороннем приложении.
- Решение: exact untagged `⌘⇧Z` при active Stack и хотя бы одном successfully dispatched occurrence повторно активирует только последний such UUID как one-shot Next. Он не вставляет немедленно; пользователь нажимает обычный `⌘V`. До первой successful dispatch, вне active Stack, для tagged/keyUp/other modifiers shortcut проходит без изменения. Повтор до новой successful dispatch идемпотентен, а manual Reactivate может быть заменён этим priority.
- Причина: UUID priority сохраняет traversal cursor, не требует отслеживать target app и оставляет system Redo нетронутым вне narrow Stack contract.
- Последствия: StackSession хранит one reactivation priority и last successfully dispatched UUID; failure rollback оставляет reactivation used/priority retryable, cancel/finish освобождает оба значения.

## D-016 — Адаптивный regular glass без повышения deployment target

- Статус: `accepted`
- Дата: 2026-08-08
- Источник: пользователь; Apple HIG Materials и AppKit API перепроверены 2026-08-08
- Контекст: History, Paste Stack и Permission должны выглядеть как прозрачные стеклянные overlay-панели на новых macOS, но первая версия продолжает поддерживать macOS 14+.
- Решение: все три панели используют общий material boundary. На macOS 26+ он оборачивает content в один `NSGlassEffectView` со style `regular`; на macOS 14–25 использует один семантический `NSVisualEffectView` fallback. Нативные title bar, close control и window dragging сохраняются; `clear` и полностью borderless chrome не входят в S009.
- Причина: настоящий Liquid Glass доступен только с macOS 26. `regular` рекомендован для поверхностей с большим количеством текста, лучше сохраняет читаемость и системно адаптируется к accessibility settings. Один effect container на panel снижает rendering cost и визуальный шум.
- Последствия: deployment target остаётся macOS 14; реализация компилируется latest SDK с availability branch, не меняет focus/nonactivating behavior и требует ручной visual/accessibility matrix на macOS 26 и fallback-проверку на macOS 14–25.

## D-017 — Стабильная signing identity и fail-closed packaging

- Статус: `accepted`
- Дата: 2026-08-09
- Источник: пользователь; Apple TN3127, distribution signing и notarization guidance перепроверены 2026-08-09; реальный Developer ID/notarization pipeline проверен 2026-08-26
- Контекст: установленный ad-hoc build имел CDHash-only designated requirement, `get-task-allow` и запрещённый `FinderInfo` xattr. System Settings показывал включённую запись Qipli, пока текущий процесс и UI не получали пригодную стабильную identity/state.
- Решение: разделить два явных packaging channel. Local install требует `Apple Development` identity и предназначен только для команды подписанта. Public release требует Developer ID Application, secure timestamp, Hardened Runtime, notarization, stapling и Gatekeeper. Оба channel запрещают ad-hoc fallback, проверяют Team ID/designated requirement/architectures/xattrs и повторно проверяют распакованный ZIP; release дополнительно запрещает `get-task-allow`, App Sandbox и network entitlements.
- Причина: macOS связывает privacy permissions с designated requirement; только стабильная signer-based identity переживает rebuild/upgrade, а fail-closed pipeline не позволяет принять локальный тестовый artifact за релиз.
- Последствия: без соответствующего certificate packaging завершается ошибкой. Локальный pipeline не передаёт signing secrets через environment или repository и использует named Keychain profile. Защищённая CI-передача credentials позднее регулируется D-025. Certificate precheck не полагается на `security find-identity`, потому что он не перечисляет Data Protection Keychain identities; источником истины служат фактическая Xcode подпись и строгий verifier. Реальные Developer ID/notarization credentials подтверждены 2026-08-26, но S008 остаётся `blocked` до полной release verification matrix.

## D-018 — Settings и onboarding входят в первый публичный релиз после core MVP

- Статус: `accepted`
- Дата: 2026-08-12
- Источник: пользователь
- Контекст: core History/Paste Stack уже подтверждён ежедневным использованием владельцем, но Developer ID/notarization credentials ожидаются позднее. Настройки и first-run experience можно подготовить до release gate.
- Решение: не переопределять подтверждённую границу core MVP, а добавить S010/S011 как ранний post-MVP setup layer, обязательный перед первым публичным релизом. S008 зависит от обоих срезов и проверяет их на clean signed install.
- Причина: это позволяет продолжать продуктовую работу без ложного завершения S008 и не выпускать внешний artifact без понятного onboarding/settings path.
- Последствия: S011 начинается после завершения S010. S008 остаётся финальным release gate до завершения S011/S012, S014/S015 и полной release verification matrix; локальный credential blocker снят 2026-08-26, hosted CI credentials проверяются в S014.

## D-019 — Launch at Login через main app service и только explicit opt-in

- Статус: `accepted`
- Дата: 2026-08-12
- Источник: пользователь; Apple ServiceManagement documentation перепроверена 2026-08-12
- Контекст: menu bar utility полезна при постоянной работе, но запуск без согласия пользователя и локальный boolean, расходящийся с System Settings, создают недоверие и ложное состояние.
- Решение: использовать `SMAppService.mainApp` без helper process. Settings и onboarding читают фактический `status`; register/unregister выполняются только после явного действия. Onboarding показывает автозапуск выключенным по умолчанию, а `requiresApproval` ведёт в Login Items Settings.
- Причина: системный API поддерживает main application как login item на macOS 13+, предоставляет status/register/unregister и соответствует deployment target macOS 14.
- Последствия: login-item state не дублируется в `UserDefaults`; errors и external disable видимы. `notFound` не блокирует явную попытку регистрации: macOS 26.6 canary 2026-08-27 подтвердил переход `notFound → enabled` после `register()`. S010 тестирует adapter без изменения реального system state, manual logout/login повторяется в S008 на подписанном artifact.

## D-020 — Настраиваются три Qipli shortcuts, а `⌘V` и `Esc` остаются фиксированными

- Статус: `accepted`
- Дата: 2026-08-12
- Источник: пользователь; safety constraints следуют из действующих input contracts
- Контекст: пользователь хочет переопределять горячие клавиши, но ordinary paste и narrow active-Stack cancel являются фундаментальными pass-through/consume guarantees.
- Решение: настраиваются History, Start/Collect Paste Stack и Reactivate Previous; defaults — `⌘⇧V`, `⌘⇧C`, `⌘⇧Z`. Обычный `⌘V` и `Esc` не настраиваются. Bindings применяются атомарным validated snapshot, не могут конфликтовать друг с другом или с защищёнными input actions; все внешние app conflicts не обещаются.
- Причина: пользователь получает нужную гибкость без размывания главной гарантии «обычный `⌘V` не меняется вне active Stack» и без частично применённых комбинаций.
- Последствия: event adapter получает current immutable snapshot; invalid/corrupt preferences сохраняют последнее рабочее значение или fail closed восстанавливают defaults. S010 обязан покрыть runtime update, restart, reset и regression event-tap matrix.

## D-021 — Onboarding одноразовый, опциональный и контекстно запрашивает разрешение

- Статус: `accepted`
- Дата: 2026-08-12
- Источник: пользователь; Apple HIG Onboarding/Privacy перепроверены 2026-08-12
- Контекст: внешний пользователь должен понять локальную историю, чувствительные данные, permissions и hotkeys, но обязательный мастер или prompt на старте создаёт лишний барьер.
- Решение: на fresh local preferences profile onboarding показывается до первого pasteboard read, допускает Finish, Skip и close, запрашивает Accessibility и включает Launch at Login только по явному действию и доступен повторно из Settings. Повторный запуск не сбрасывает настройки или completion.
- Причина: быстрый optional flow даёт privacy context до capture/permission, сохраняя возможность сразу продолжить в честном degraded state.
- Последствия: startup shell получает idempotent onboarding gate; crash до сохранённого dismissal повторяет flow, а manual re-open не останавливает monitor. S011 реализуется после общих services S010.

## D-022 — Borderless chrome применяется только к Paste Stack

- Статус: `accepted`
- Дата: 2026-08-12
- Источник: пользователь; Apple AppKit `borderless`, `nonactivatingPanel` и `performDrag(with:)` documentation перепроверены 2026-08-12
- Контекст: пользователь выбрал edge-to-edge Paste Stack с custom header вместо native title bar, сохранив компактную overlay-модель и существующую stack behavior.
- Решение: узко заменить D-016 только для Paste Stack: panel использует borderless nonactivating style, один прежний adaptive material surface, system shadow и continuous clipping. Header владеет Cancel, единственным title и direction toggle; отдельная background drag-region передаёт исходный mouse-down в `NSWindow.performDrag(with:)`. History и Permission сохраняют native chrome.
- Причина: edge-to-edge список и компактный header соответствуют выбранному референсу, а системный drag API сохраняет Spaces/window-server behavior без превращения всего List в movable background.
- Последствия: native red close и title bar исчезают только у Paste Stack; custom Close обязан вызывать existing idempotent cancel path, panel остаётся nonactivating, а drag/reorder/input/accessibility contracts проверяются в S012.

## D-023: Accessibility управляется через Settings без отдельной панели

- Статус: `accepted`
- Дата: 2026-08-26
- Источник: пользователь после визуальной проверки S010
- Контекст: после появления Accessibility state и actions в Settings General пункт `Permission: …` в status menu и отдельная Permission panel показывали тот же функционал вторым путём.
- Решение: удалить Permission item, Permission panel, её SwiftUI presentation и window configuration. Если Paste Stack нельзя запустить из-за Accessibility или input listener, Qipli открывает singleton Settings на General.
- Причина: один понятный путь убирает лишнюю строку status menu и второе окно, не меняя системный permission service.
- Последствия: `AccessibilityPermissionService`, grant/revoke polling и event-tap start/stop остаются прежними. Permission-specific части D-016 и D-022 сохраняются как история реализованных срезов, но больше не описывают текущий UI.

## D-024: Публичный source и release distribution живут в одном GitHub-репозитории

- Статус: `accepted`
- Дата: 2026-08-26
- Источник: пользователь
- Контекст: пользователь планирует открыть текущий репозиторий. Отдельный public release repository добавил бы вторые permissions, token и publication lifecycle без подтверждённой пользы.
- Решение: после public-readiness audit текущий Qipli repository становится публичным. Его GitHub Releases хранят ZIP/checksum/release notes, а GitHub Pages публикует stable Sparkle appcast. Source, issues и release history остаются в одном месте.
- Причина: public assets доступны пользователю и Sparkle без GitHub authentication, а same-repository `GITHUB_TOKEN` не требует cross-repository PAT.
- Последствия: до смены visibility нужно выбрать лицензию, добавить README/SECURITY, проверить current tree и Git history на secrets/user data и настроить branch protection. Реальная смена visibility остаётся явным внешним действием и не выполняется во время подготовки документов.

## D-025: Pull request не получает release secrets, релиз создаётся только из защищённого тега

- Статус: `accepted`
- Дата: 2026-08-26
- Источник: пользователь после обсуждения release automation; GitHub Actions и Apple notarization sources перепроверены 2026-08-26
- Контекст: публичный repository принимает fork pull requests, но signing и update keys позволяют распространять исполняемый код от имени Qipli.
- Решение: PR и push в `main` запускают только unsigned tests/build с read-only permissions. Stable tag `vX.Y.Z` на разрешённом commit запускает отдельный protected release Environment, временный Keychain, Developer ID signing, App Store Connect API notarization, verifier и draft GitHub Release. Environment gate остаётся перед доступом к secrets и stable publication.
- Причина: tag делает release input однозначным, а разделение workflows не исполняет непроверенный PR code рядом с приватными ключами.
- Последствия: нужен exportable Developer ID `.p12`, App Store Connect `.p8` и минимальные GitHub permissions. Temporary credentials удаляются unconditional cleanup step. Release workflow fail closed завершает run при несовпадении tag/version/build или любой проверке подписи.

## D-026: Sparkle отвечает только за обновления и использует отдельную EdDSA signature

- Статус: `accepted`
- Дата: 2026-08-26
- Источник: пользователь после обсуждения auto-update; Sparkle documentation и GitHub Pages workflow deployment перепроверены 2026-08-28
- Контекст: Developer ID и notarization позволяют macOS доверять app bundle, но не дают приложению update discovery, feed или безопасную загрузку новой версии. `v1.0.0` уже опубликован без Sparkle и не может получить updater задним числом.
- Решение: `v1.0.1` добавляет exact Sparkle `2.9.6` через Swift Package Manager, manual `Check for Updates…`, выключенные по умолчанию automatic checks и user-confirmed install; пользователь устанавливает эту версию вручную. `v1.0.2` является первым реальным Sparkle update proof. Public key хранится в app, private EdDSA key только в release Environment. GitHub Pages appcast публикуется официальным workflow deployment после готового GitHub Release asset; branch push/PAT не используются.
- Причина: Apple code signature и Sparkle EdDSA закрывают разные границы доверия. Явный opt-in сохраняет локальную privacy-модель Qipli и не включает фоновую сеть молча.
- Последствия: `v1.0.0` обновляется только ручной установкой `v1.0.1`. Update request является единственным runtime network path и не получает clipboard/history/search payload. Первый stable channel использует полный ZIP; beta channel, delta updates, phased rollout и silent install остаются вне scope. S015 обязан доказать реальный update `v1.0.1 → v1.0.2` и сохранение данных/preferences с Accessibility recheck.

## D-027: History keyboard и dismissal принадлежат AppKit window lifecycle

- Статус: `accepted`
- Дата: 2026-08-27
- Источник: пользователь после комплексного ревью intermittent History behavior
- Контекст: SwiftUI `TextField.onKeyPress` работает только пока Search остаётся first responder, а три немедленных activation check не гарантируют focus для accessory app. Одновременно floating History с `hidesOnDeactivate = false` остаётся видимой после перехода пользователя в другое окно.
- Решение: exact unmodified Up/Down/Enter/Escape маршрутизируются локальным AppKit monitor только для key History panel; `windowDidBecomeKey` повторно запрашивает Search focus. `windowDidResignKey` и History-only local/global mouse monitor выполняют passive `orderOut` без активации captured target, тогда как explicit Escape сохраняет прежний focus-restoring cancel. History допускает только одну paste transaction до completion и использует workspace activation notification с bounded timer fallback.
- Причина: window lifecycle является устойчивой границей для межприложного focus, а один transaction token исключает повторные clipboard writes и synthetic paste commands во время delayed activation.
- Последствия: Paste Stack остаётся nonactivating и не наследует click-away behavior. Modified keys и text editing проходят native responder chain. Реальный macOS focus/paste/click-away path остаётся manual gate S016.

## D-028: Qipli публикуется под MIT без переписывания безопасной Git-истории

- Статус: `accepted`
- Дата: 2026-08-28
- Источник: пользователь после public-readiness audit S013
- Контекст: перед открытием repository оставались выбор лицензии, судьба пяти старых ignored `dist/*` paths и владелец ручного release gate. Audit не обнаружил credentials, private signing material или clipboard fixtures; inventory старых ZIP содержит только Qipli app bundles.
- Решение: публиковать Qipli под MIT с copyright `Sviatoslav Zhilichev`; сохранить существующую Git-историю без rewrite; назначить `tomfordrumm` required reviewer protected Environment `release`; после финального успешного audit разрешено перевести repository в public.
- Причина: MIT соответствует бесплатному open-source utility без copyleft-требования. Безопасная история сохраняет существующие commits и fork, а ручное подтверждение владельца остаётся перед доступом к release secrets и stable publication.
- Последствия: repository получает `LICENSE`, `README.md` и `SECURITY.md`; пять исторических release-output paths остаются видимы как старые бинарные артефакты и checksums. Любой новый credential или пользовательский payload всё равно блокирует public visibility и требует отдельного remediation plan.

## D-029: Broken stable release не переписывается, а получает versioned runtime hotfix

- Статус: `accepted`
- Дата: 2026-08-28
- Источник: пользователь после воспроизведения launch failure установленного `v1.0.1`
- Контекст: публичный signed/notarized `v1.0.1` содержал Sparkle.framework, но executable не имел `LC_RPATH @executable_path/../Frameworks` и завершался в `dyld` до `main`. Signing, notarization, stapling и Gatekeeper не проверяют, способен ли executable разрешить embedded dynamic framework. Release и production appcast уже были публичны, поэтому повторное перемещение тега нарушило бы immutable release contract.
- Решение: сохранить `v1.0.1` как исторический broken release; выпустить `v1.0.2 (3)` как ручной hotfix с explicit embedded-framework runpath. Unsigned CI, protected release gate и signed app verifier обязаны проверять Sparkle dependency и нужный `LC_RPATH` для каждой architecture. Первый реальный updater proof переносится на `v1.0.2 → v1.0.3`.
- Причина: новая версия сохраняет воспроизводимую публичную историю и numeric ordering, а runtime-linking gate закрывает точную границу, которую пропустили build/signing checks.
- Последствия: `v1.0.1` не может обновиться самостоятельно, потому что падает до запуска Sparkle; пользователь вручную устанавливает `v1.0.2`. Production appcast меняется только после успешного immutable `v1.0.2` release. S015 остаётся `in_progress` до manual launch `v1.0.2` и signed/notarized update `v1.0.2 → v1.0.3` с полной preservation/failure matrix.

## D-030: DMG служит ручной установке, ZIP остаётся каналом Sparkle

- Статус: `accepted`
- Дата: 2026-08-28
- Источник: пользователь
- Контекст: ссылка лендинга должна сразу скачивать готовый образ, а ручная установка на macOS должна быть интуитивной: открыть образ и перетащить Qipli в Applications. ZIP удобен для Sparkle, но заставляет пользователя самостоятельно распаковывать и переносить приложение.
- Решение: каждый следующий stable release публикует branded versioned DMG, его checksum и идентичный стабильный alias `Qipli.dmg` для `releases/latest/download/Qipli.dmg`. DMG содержит Qipli с собственным AppIcon, ссылку на `/Applications`, фон и стрелку; финальный контейнер отдельно подписывается Developer ID, notarize-ится, stapled и проходит Gatekeeper. Immutable versioned ZIP сохраняется как единственный asset appcast/Sparkle.
- Причина: DMG даёт привычный macOS install path и стабильную прямую ссылку без подмены роли update archive. Отдельная проверка финального контейнера гарантирует, что доверие относится к тому файлу, который открывает пользователь.
- Последствия: release pipeline создаёт и проверяет два контейнера, а protected run может занимать дольше из-за дополнительной notarization. Старые GitHub Releases остаются immutable и не получают DMG задним числом; прямая ссылка начнёт работать после публикации первого нового релиза с `Qipli.dmg`.

## D-031: Performance hardening сохраняет Core Data и переносит History I/O с main actor

- Статус: `accepted`
- Дата: 2026-08-29
- Источник: пользователь после глубокого performance review
- Контекст: текущий локальный store мал и быстро читается непосредственно SQLite, но приложение синхронно выполняет Core Data fetch/save/retention на main actor, повторно перечитывает всю History при каждом показе, фильтрует полный snapshot на каждом search keystroke и имеет скрытые лишние обходы длинного текста и Paste Stack. Exact UUID fetch не индексирован, retention материализует удаляемые managed objects, а pasteboard timer создаёт Task на каждый tick. Текущий idle CPU/memory не показывает утечку.
- Решение: сохранить Core Data и 30-дневный exact-text контракт без искусственного лимита entries или длины. Сначала S017 фиксирует payload-free baselines и алгоритмические checks; S018 добавляет UUID index, batch retention и query-plan proof; S019 вводит последовательную asynchronous background History boundary и актуальный immutable UI snapshot; S020 переносит cancellable search с main actor и ограничивает только display preview; S021 устраняет повторные Stack traversal; S022 добавляет tolerance/direct scheduler callback без снижения текущей polling frequency до отдельного copy-loss доказательства.
- Причина: подтверждённые bottlenecks находятся в execution model и линейных повторных обходах, а не в необходимости нового persistence backend. Последовательные срезы дают regression proof до и после каждого изменения и не смешивают storage, UI responsiveness и energy behavior в одном рискованном rewrite.
- Последствия: public SLA из локальных timing numbers не объявляется; CI проверяет stable contracts и сложность, а benchmark runs сохраняют observed baselines. Instrumentation и fixtures не содержат clipboard text, search query, preview или пользовательские UUID. Capture остаётся History-first, fresh History show ждёт уже поставленную capture pipeline, full text остаётся точным для storage/search/paste, ordinary `Command-V` и self-write suppression не меняются.

## D-032: Keyboard-first History использует native table с синхронным interaction bridge

- Статус: `accepted`
- Дата: 2026-08-30
- Источник: пользователь после видео и payload-free runtime trace
- Контекст: при 1 777 entries модель меняла selection менее чем за 0.4 ms, но SwiftUI `List` отображал его через 121–158 ms. `onAppear` ошибочно считал prefetched rows видимыми, поэтому highlight сначала уходил за viewport, а deferred `scrollTo` выполнялся позже. Enter дополнительно переносил paste start на следующий main-run-loop turn; cached recency publication могла перестроить closing list. Warm History order-front занимал 183–190 ms, cold path — до 794 ms.
- Решение: сохранить SwiftUI shell/search/footer, но заменить feature list на view-based `NSTableView`. AppKit keyboard monitor через weak interaction bridge синхронно применяет exact selected UUID и `scrollRowToVisible` в том же вызове; Enter начинает single paste transaction непосредственно в key handler и скрывает panel сразу после successful pasteboard write. Successful mark-used меняет durable/cache order, но публикуется только при следующем fresh presentation. Reusable panel prewarm выполняется после startup History reload.
- Причина: bottleneck подтверждён между model publication и SwiftUI render, а не в Core Data, pasteboard poll или selection calculation. Native table даёт императивный selection/viewport contract и переиспользование row views без полной перерисовки списка на каждый arrow.
- Последствия: History row rendering и selection принадлежат AppKit, остальной panel composition остаётся SwiftUI согласно D-004. Пользователь принял повторный Xcode replay; payload-free trace зафиксировала достаточные latency aggregates и затем полностью удалена, включая Release call sites. Остаточная S016 matrix сохраняет failure restore, VoiceOver/Delete/double-click и click-away/Command-Tab проверки.

## D-033: Typed History использует гибридное хранение и поставляется раньше media Paste Stack

- Статус: `accepted`
- Дата: 2026-08-31
- Источник: пользователь
- Контекст: следующий этап Qipli должен хранить не только текст, но и URL, изображения, файлы и видео. Полные media payload нельзя помещать в текущий `HistoryEntry.text`, полный UI snapshot или synchronous Stack paste path. Пользователь выбрал History-first поставку, metadata-only search и отсутствие OCR.
- Решение: text и URL metadata остаются локальными Core Data values; inline images сохраняются как Qipli-managed files; file/video сохраняются reference-only без автоматического копирования source bytes. Typed History поддерживает capture, bounded preview, metadata search и повторную вставку. Paste Stack до отдельного среза остаётся text-only. OCR изображений, анализ видео и remote URL preview исключены.
- Причина: гибридная модель сохраняет автономность inline clipboard images, не дублирует потенциально гигабайтные локальные файлы и не заставляет media изменить latency-критичный ordinary `Command-V` Stack contract.
- Последствия: missing file/video source получает явное unavailable state. Media copy при active Stack сохраняется в History, но не меняет Stack. Clear All удаляет Qipli-owned images/derivatives/reference metadata, но не source files. Новый network owner, OCR dependency или media Stack требуют отдельного решения.

## D-034: History становится bounded metadata catalogue с keyset pagination

- Статус: `accepted`
- Дата: 2026-08-31
- Источник: пользователь 2026-08-30 и техническое уточнение при планировании 2026-08-31
- Контекст: текущий store загружает все 30-day text occurrences в `allEntries` и выполняет линейный in-memory search. При текущих 1 885 rows это не авария, но модель не ограничивает working set и не подходит для media payload. `NSTableView` виртуализирует row views, а не data source.
- Решение: S023 вводит initial/load-more pages максимум по 500 occurrence descriptors, cursor по строгому `(activityAt, id)` order и database-backed search по всему retention window. UI snapshots не содержат exact media payload, bookmarks или thumbnails. Legacy text rows мигрируются без изменения UUID/activity/text. Full-retention row count не ограничивается этим решением.
- Причина: bounded catalogue ограничивает memory и decode work независимо от числа и типа retained occurrences, сохраняя 30-day product contract и быстрый repeated show.
- Последствия: S019 current full-snapshot implementation заменяется только после migration/search parity tests. `fetchBatchSize` без real `fetchLimit`/cursor не выполняет контракт. Capture, promotion, delete, retention и stale search должны иметь page-aware tests до media work.

## D-035: Managed images получают fail-closed capacity limits без auto-eviction

- Статус: `accepted`
- Дата: 2026-09-01
- Источник: пользователь принял предложенные production defaults после сравнения с публичными clipboard managers и технического recheck
- Контекст: inline image может занимать существенно больше text entry, а 30-day retention без byte policy допускает исчерпание диска. Скрытое удаление старой истории ради нового clipboard item нарушает ожидаемое владение данными.
- Решение: production policy получает лимит 32 MiB на image item, 64 MiB на одну occurrence, 1 GiB на все durable original image bytes, 128 MiB на пересоздаваемый thumbnail cache и 512 px на длинную сторону thumbnail. Превышение любого hard limit отклоняет новую occurrence целиком, показывает non-payload уведомление и не удаляет existing History. Policy инъецируется в тесты; значения не появляются в UI/logs как payload metadata.
- Причина: 32 MiB покрывает обычные Retina/browser images и несколько representations, 64 MiB ограничивает multi-item occurrence, а 1 GiB даёт большой локальный запас без неограниченного роста managed storage.
- Последствия: лимиты пока остаются production defaults без UI; позднее общий quota можно вынести в настройки с сохранением hard safety ceiling. Automatic LRU eviction и metadata-only placeholder для отклонённого image не входят в выбранное поведение.

## D-036: Default History открывается как Top Notch и разворачивается в отдельную карточную библиотеку

- Статус: `accepted`
- Дата: 2026-09-01
- Источник: пользователь
- Контекст: текущая native-table History надёжна и быстра с клавиатуры, но узкое обычное окно использует мало площади карточки для многострочного текста и media preview. Пользователь хочет быстрый вызов из верхней чёлки MacBook, Search прямо в панели и отдельное полноценное окно для более глубокого просмотра.
- Решение: default `⌘⇧V` показывает borderless Top Notch на текущем экране, раскрывающийся вниз от camera-safe верхней области или top-center fallback. Top Notch содержит Search и horizontal type-aware cards. `Развернуть` передаёт query, selected occurrence и captured target отдельному resizable History window, которое показывает ровно три карточки в ряду. Одновременно интерактивно только одно History presentation. Первая поставка фиксирует top placement; правый, левый и нижний edge остаются будущей настройкой.
- Причина: transient shelf сокращает путь частой вставки, а отдельная библиотека даёт карточкам достаточно площади, не перегружая быстрый вызов. Разделение на два presentation сохраняет проверяемую window/focus boundary и не заставляет компактную панель изображать полноценный browser.
- Последствия: D-032 больше не предписывает `NSTableView` как визуальную поверхность после S028, но сохраняет обязательные synchronous selection/viewport/paste guarantees. Top Notch получает отдельную geometry/state machine, полная History становится обычным отдельным окном, а Paste Stack и ordinary `⌘V` не меняются. Remote URL preview, hover-only behavior и edge-placement Settings в S027–S029 не входят.

## D-037: Favorites не продлевает 30-day retention

- Статус: `proposed`
- Дата: 2026-09-01
- Источник: консервативное предположение агента из запроса пользователя о Favorites
- Контекст: пользователь подтвердил раздел Favorites, но не определил, должен ли favorite закреплять occurrence бессрочно. Бессрочное хранение изменит существующий privacy/retention contract, cleanup и ожидания по disk usage.
- Решение: в первой версии Favorite является локальным marker и фильтром существующих occurrences. Delete, expiry и Clear All удаляют occurrence вместе с marker; favorite сам по себе не меняет activity time и не отменяет 30-day retention.
- Причина: такое поведение добавляет навигацию без скрытого расширения срока хранения чувствительного clipboard payload.
- Последствия: перед переводом S029 в `ready` пользователь подтверждает или меняет решение. Бессрочные pins потребуют отдельного product/technical решения, migration/cleanup semantics и понятного UI.
