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
- Уточнение 2026-09-07: History opener использует публичный Carbon `RegisterEventHotKey`, поскольку Secure Event Input блокирует keyboard event tap. Регистрация exclusive, без сторонней dependency или новых permissions; ошибка регистрации сохраняет прежний tap fallback. Settings обновляет регистрацию, stop снимает её, успешная регистрация исключает duplicate dispatch из tap. Проверены Apple SDK `CarbonEvents.h` и опубликованная [матрица input API AltTab](https://github.com/lwouis/alt-tab-macos/blob/master/src/experimentations/README.md). Автоматические проверки не заменяют installed-app password-field acceptance.

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
- Последствия: Qipli намеренно перехватывает фокус только по собственному hotkey/menu action; реальный focus flow проверяется вручную перед `done`.
- Уточнение 2026-09-08: после сообщения пользователя об открытии History из password field без keyboard focus три run-loop проверки заменены ожиданием `NSApplication.didBecomeActiveNotification` и одним deferred activation retry после Carbon handler. Закрытие, paste handoff и повторный show отменяют прежнее ожидание; скрытая panel не получает focus. Это не отключает Secure Event Input. Apple [activation guidance](https://developer.apple.com/documentation/appkit/nsapplication/activate%28ignoringotherapps%3A%29) перепроверена: запрос может завершиться с задержкой.

- Текущий контракт, 2026-09-08: live Debug trace после пользовательского воспроизведения в Chrome показал `secureInput=true`, `frontChrome=true`, `active=false`, `key=false` даже через 1000 ms после двух AppKit requests. Для History прежняя strong-activation стратегия заменена на `.nonactivatingPanel` с `orderFrontRegardless`/`makeKey` и Search focus по key-window transition. Пользователь подтвердил исправление фокуса в Chrome password field 2026-09-08; временная диагностика удалена по его запросу. Settings/onboarding продолжают использовать прежний adapter. Native panel получает keyboard focus независимо от app activation; Secure Input не отключается. Уже active paste target не реактивируется, а panel освобождает focus до synthetic paste. Основания: Apple [nonactivatingPanel](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel), [becomesKeyOnlyIfNeeded](https://developer.apple.com/documentation/appkit/nspanel/becomeskeyonlyifneeded), а также аналогичный public AppKit путь в [Maccy FloatingPanel](https://github.com/p0deje/Maccy/blob/master/Maccy/FloatingPanel.swift). Подтверждение исправления focus не заменяет отдельную release matrix, включая custom shortcut/reset.

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

- Статус: `superseded by D-038` для текущего presentation; historical S012 evidence сохраняется
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

- Статус: `superseded by D-038`
- Дата: 2026-09-01
- Источник: пользователь
- Контекст: текущая native-table History надёжна и быстра с клавиатуры, но узкое обычное окно использует мало площади карточки для многострочного текста и media preview. Пользователь хочет быстрый вызов из верхней чёлки MacBook, Search прямо в панели и отдельное полноценное окно для более глубокого просмотра.
- Решение: default `⌘⇧V` показывает borderless Top Notch на текущем экране, раскрывающийся вниз от camera-safe верхней области или top-center fallback. Top Notch содержит Search и horizontal type-aware cards. `Развернуть` передаёт query, selected occurrence и captured target отдельному resizable History window, которое показывает ровно три карточки в ряду. Одновременно интерактивно только одно History presentation. Первая поставка фиксирует top placement; правый, левый и нижний edge остаются будущей настройкой.
- Причина: transient shelf сокращает путь частой вставки, а отдельная библиотека даёт карточкам достаточно площади, не перегружая быстрый вызов. Разделение на два presentation сохраняет проверяемую window/focus boundary и не заставляет компактную панель изображать полноценный browser.
- Последствия: D-032 больше не предписывает `NSTableView` как визуальную поверхность после S028, но сохраняет обязательные synchronous selection/viewport/paste guarantees. Top Notch получает отдельную geometry/state machine, полная History становится обычным отдельным окном, а Paste Stack и ordinary `⌘V` не меняются. Remote URL preview, hover-only behavior и edge-placement Settings в S027–S029 не входят.

## D-037: Favorites не продлевает 30-day retention

- Статус: `superseded by D-042`; ранее withdrawn to backlog by D-038
- Дата: 2026-09-01
- Источник: консервативное предположение агента из запроса пользователя о Favorites
- Контекст: пользователь подтвердил раздел Favorites, но не определил, должен ли favorite закреплять occurrence бессрочно. Бессрочное хранение изменит существующий privacy/retention contract, cleanup и ожидания по disk usage.
- Решение: в первой версии Favorite является локальным marker и фильтром существующих occurrences. Delete, expiry и Clear All удаляют occurrence вместе с marker; favorite сам по себе не меняет activity time и не отменяет 30-day retention.
- Причина: такое поведение добавляет навигацию без скрытого расширения срока хранения чувствительного clipboard payload.
- Последствия: перед переводом S029 в `ready` пользователь подтверждает или меняет решение. Бессрочные pins потребуют отдельного product/technical решения, migration/cleanup semantics и понятного UI.

## D-038: Top Notch остаётся единственной текущей History surface и принимает Paste Stack

- Статус: `accepted`
- Дата: 2026-09-02
- Источник: пользователь
- Контекст: после приёмки S027 пользователь не видит ближайшей ценности в отдельном полноразмерном окне History и хочет сосредоточить дальнейший UI polish в верхней Top Notch оболочке. Отдельная плавающая Paste Stack panel создаёт второй визуальный язык и отдельное положение окна, хотя Stack является таким же быстрым overlay-сценарием Qipli.
- Решение: отдельное полноценное окно History, действие `Развернуть` и Favorites уходят из активного плана в backlog. `⌘⇧V` продолжает открывать transient activating History Top Notch. Paste Stack переносится в ту же верхнюю форму, placement и motion, но сохраняет отдельную nonactivating panel configuration: Stack не становится key, не забирает focus у source/target app, не закрывается по History click-away/resign-key и завершается только existing Cancel/Escape/auto-finish paths. Специальный переход из активного Stack в History не входит в текущий пользовательский путь и не является acceptance criterion.
- Причина: один верхний shell делает частые History и Stack сценарии визуально цельными, а отказ от непроверенного full-library режима сокращает scope. Раздельные AppKit activation/lifecycle contracts сохраняют уже принятую надёжность системной вставки.
- Последствия: S028/S029 и их requirements сохраняются как backlog evidence, но не входят в coverage текущей поставки. S030 становится ближайшим ready slice. D-022 остаётся историей принятого S012, но movable frame, position restore и custom window drag больше не являются целевым Paste Stack presentation. D-036/D-037 не управляют активным планом.

## D-039: Formatted History хранит raw RTF/HTML рядом с canonical plain text

- Статус: `accepted`
- Дата: 2026-09-03
- Источник: пользователь подтвердил default rich paste, `⇧Enter` plain paste и plain-only oversize fallback; storage/limit детали уточнены при техническом планировании
- Контекст: Qipli уже хранит typed History, но text occurrence материализуется только как plain string, поэтому повторная вставка теряет bold/italic, links, lists и другие стили. Default `⌘⇧V` уже принадлежит открытию History; попытка использовать его же как system-wide paste-without-formatting создала бы неоднозначный input contract.
- Решение: canonical exact plain string остаётся основой validation, search, preview и text-only Paste Stack. Для того же ordered pasteboard item Qipli дополнительно allowlist-ит source-provided `public.rtf` и `public.html` и сохраняет raw bytes как managed assets. `Enter` и double-click пишут rich representations вместе с plain fallback; exact local `⇧Enter` пишет только plain string. RTFD, WebArchive, private/dynamic types и arbitrary passthrough исключены. Production defaults — 16 MiB на rich representation, 32 MiB на occurrence и 512 MiB на все durable rich assets. При overflow или capture-write failure допустимый text сохраняется plain-only с non-payload notice; existing History не удаляется. Missing/corrupt уже committed rich asset останавливает default paste, а пользователь может явно повторить через `⇧Enter`. AppKit может materialize один полный allowlisted `Data` до проверки размера; Qipli запрашивает representations последовательно, не создаёт дополнительных полных копий и трактует limits как admission/persistence ceilings, не streaming guarantee.
- Причина: raw standard representations сохраняют source fidelity и target choice без сложной/потерянной конверсии через `NSAttributedString`. Отдельное local modifier-действие не конфликтует с History shortcut и делает намерение пользователя явным. Более низкие, чем у универсальных multi-MIME managers, ceilings соответствуют узкому text-formatting scope и текущей bounded History архитектуре.
- Последствия: rich bytes не входят в descriptors или search и получают тот же 30-day/Delete/Clear All/orphan lifecycle, что Qipli-managed assets. `HistoryEntry.isTypedEntry` недостаточен для определения formatted materialization, потому что primary kind остаётся text; implementation вводит явный rich manifest/capability. Paste Stack продолжает сохранять и вставлять только canonical plain text. Изменение limits после controlled TextEdit/browser probe требует синхронного обновления D-039 и S031 до production code.

## D-040: History cards убирают type labels, а поиск получает URL-first ranking

- Статус: `accepted`
- Дата: 2026-09-04
- Источник: пользователь после проверки текущей Top Notch History и результата поиска `localhost`
- Контекст: текущая карточка одновременно показывает type icon и подпись `Text`/`URL`/`Image`, thumbnail занимает только внутреннюю полосу, а основной текст визуально крупнее нужного. Обычный Backspace при пустом Search удаляет выбранную occurrence. Search проверяет только наличие localized substring и сохраняет общий activity order, поэтому более свежие text fragments с `localhost` вытесняют настоящие URL за первый экран. Дополнительно пользователь наблюдает визуальную перезагрузку всей ленты при клике по любой карточке; текущий bridge после model publication безусловно снимает и повторно применяет selection, а готовность одного thumbnail повышает общую snapshot revision и ведёт к `reloadData()` всей коллекции.
- Решение: убрать видимую type label, сохранить icon и полный accessibility label, уменьшить основной card text до системных 13 pt. Image thumbnail становится full-bleed aspect-fill background с icon overlay и нижней затемнённой подложкой под bounded metadata/state. Обычный Backspace не удаляет History; exact local `⇧Backspace` удаляет выбранную occurrence при пустом или непустом Search. Search сохраняет прежний match set, но сортирует exact/prefix URL domain/address matches, затем остальные typed URL matches, затем остальные matches; внутри каждой группы действует `(activityAt DESC, id DESC)`. Search continuation включает rank и применяется ко всему retention window. Collection coordinator разделяет snapshot, selection и thumbnail updates: mouse click не повторяет уже применённый native selection, same-ID selection становится no-op, thumbnail completion обновляет только соответствующий visible item, а `reloadData()` остаётся только для фактического изменения snapshot identity/order.
- Причина: icon уже сообщает тип визуально, full-bleed лучше использует малую площадь карточки, а modifier снижает риск случайного удаления во focused Search. URL-first ranking соответствует намерению найти сохранённую ссылку и устраняет наблюдаемую ситуацию, где incidental text matches занимают весь первый экран.
- Последствия: VoiceOver по-прежнему получает type/state/selection, URL-подобный plain text не переклассифицируется, remote preview и новый network owner не появляются. Unfiltered History остаётся latest-first. Search implementation должна доказать bounded page size, stable cross-rank continuation, отсутствие duplicate/gap, stale-query safety и deep URL match beyond the first chronological page; сортировка только уже загруженной page недостаточна. Selection-only update сохраняет scroll viewport и не вызывает повторный search/storage read; keyboard navigation по-прежнему может явно центрировать offscreen selection.

## D-041: Исправления performance review без изменения paste fidelity

- Статус: `accepted`
- Дата: 2026-09-07
- Источник: пользователь подтвердил реализацию всех findings review; численные бюджеты и механизм миграции выбраны при реализации.
- Контекст: optimized synthetic SQLite benchmark на 10 000 коротких text entries дал median 507 ms для отсутствующего query и 332 ms для первой страницы text matches. Repository сканировал три rank groups, full entries материализовались до display projection, asset quotas пересчитывали дерево файлов при каждом capture, а UI сохранял compatibility search для test stores.
- Решение: один cancellable chronological scan классифицирует каждую candidate не более одного раза и держит не более `limit + 1` UUID/date/rank на группу; localized matching, rank и exact payload сохраняются. Optional persisted display/search projections добавляются lightweight migration, заполняются ограниченными batches и обновляются атомарно с occurrence; text не дублируется в derived search field. Unfiltered pages читают только display projection. Asset stores ведут in-memory byte totals, сверяются с диском при первом использовании/восстановлении и инвалидируют totals при cleanup/failure. Thumbnail budget снижается со 128 до 16 MiB encoded data, eviction учитывает последнее использование; memory pressure очищает производные данные. Ordered capture admission ограничивается 64 MiB pending payload и 64 occurrences; переполнение отклоняет новую occurrence с payload-free notice, не вытесняет сохранённую историю и сообщает Stack о пропущенном capture. Один oversized blob всё ещё может быть materialized AppKit до проверки размера; image representations проверяются по мере чтения. Non-paging compatibility и test-only probes переносятся из product code в tests.
- Последствия: новая projection требует проверки migration/restart, typed availability refresh, exact rich/plain paste и отсутствия UI payload snapshots. Search всё ещё выполняет localized substring scan, без FTS/сети/новых dependencies. Quota accounting предполагает единственного writer внутри приложения; crash/restart и failure выполняют reconciliation. Pending byte budget относится к admitted payload, не является обещанием общего RSS ceiling. Все существующие release/manual gates сохраняются отдельно от automated evidence этого исправления.

## D-042: Избранное в Top Notch с защитой от автоматической очистки

- Статус: `accepted`
- Дата: 2026-09-08
- Источник: пользователь подтвердил header star слева над Search, toggle на карточках, отсутствие категорий и защиту избранного от автоматической очистки; также подтверждён возврат обычной retention после снятия звезды.
- Решение: вернуть S029 из BL-005 в активный план независимо от S028. History/Favorites переключаются в существующей панели; Search ограничивается выбранным режимом. Favorite является marker существующей occurrence, сохраняется после relaunch и защищает owned payload от expiry. Toggle не меняет activityAt.
- Уточнения планирования: History включает favorites; режим сбрасывается на History при новом открытии. Ручные Delete/Clear All сохраняют смысл и включают favorites, UI сообщает это явно. Существующие media quotas остаются общими, favorite не даёт quota exemption. Эти детали сохраняют текущие data/delete contracts и не добавляют пользовательских разделов.
- Последствия: D-037 заменён; D-038 сохраняется для Top Notch и отложенного S028, но больше не откладывает S029. Нужны migration, изменения всех read/expiry predicates, asset lifecycle и query identity. Категории, переименование, сохранённые стеки, password vault и image-as-file не входят в это решение. Implementation и verification ещё не выполнены.

## D-043: Единый компактный Paste Stack по центру

- Статус: `accepted`
- Дата: 2026-09-14
- Уточнение пользователя после просмотра реализации: заменить две боковые области одним центральным блоком. Панель начинается от верхнего края и заканчивается на нижней границе camera housing или строки меню.
- Решение: единая поверхность адаптивного размера от верхнего края экрана на всю высоту чёлки или строки меню; на notchless display у верхнего края. Квадратные карточки стопкой слева вне физического выреза, общее число скопированных элементов справа. Окно и hit region ограничены блоком.
- Hover/click раскрывают прежнюю полную панель. Session/input/persistence и ordinary Cmd+V вне Stack не меняются. Пользователь подтвердил ручную приёмку на устройстве 2026-09-15; mutable status среза ведётся в `STATE.md`.

## D-044: Rich text и изображения в Stack после компактной presentation

- Статус: `accepted`
- Дата: 2026-09-14
- Источник: пользователь выбрал «Оба: окно, затем rich text и картинки» при подготовке документации.
- Решение: S034 расширяет Stack existing text/RTF/HTML и inline-image payloads после S033. Используются existing History storage/materializer/writer, один copy остаётся одной occurrence. File/video, mixed image+reference и arbitrary/private types не входят в scope. S031 text-only Stack restriction заменяется только для этой новой поставки.
- Уточнения планирования: owned payload удерживается session lease, expiry не ломает активную серию, bytes входят в существующие quotas. Explicit Delete отзывает exact payload/preview и оставляет unavailable позицию, Clear All отменяет Stack перед очисткой. UI сообщает эти последствия. При paste нет молчаливой потери форматирования или пропуска картинки; новый plain-paste shortcut не добавляется. Это конкретизация хранения/удаления при планировании, а не отдельное пользовательское подтверждение каждой детали.
- Последствия: потребуются async materialization в Stack executor, ownership/revocation contracts и tests гонок с delete/cancel. Rich/image bytes не копируются в UI и не создают второй неограниченный store. Процессный lease не сохраняет Stack после relaunch. Реализация, ручная matrix и signed update остаются непроверенными.


## D-045: Отдельная Debug identity с общей History

- Статус: `accepted`
- Дата: 2026-09-14
- Источник: пользователь подтвердил Qipli Dev с отдельным Bundle ID и стабильной подписью, явно попросив не разделять базу.
- Решение: Debug использует `com.qipli.app.dev`, имя `Qipli Dev` и Apple Development с существующей Team. Sparkle в Debug не создаётся. Release identity и distribution pipeline не меняются.
- Последствия: отдельные Accessibility grant и UserDefaults/onboarding; общие History.sqlite и owned assets. Удаления и миграции Dev влияют на рабочую историю. Версии запускаются по очереди. Разрешение Dev выдаётся пользователем один раз; сохранение после пересборки проверяется вручную. Основание стабильной signing identity: Apple TN2206, https://developer.apple.com/library/archive/technotes/tn2206/_index.html, сверено 2026-09-14.


## D-046: Вырезание файлов с индикацией в компактном окне

- Статус: `proposed`
- Дата: 2026-09-14
- Подтверждённый запрос: добавить ⌘X для вырезания файлов с последующей вставкой в другое место и показать процесс в мини-окне у чёлки.
- Предложение: S035 после S033, отдельный от Stack временный Cut intent; первая версия Finder-only, ⌘X → ожидание в compact → ⌘V → native Finder move. S034 не является технической зависимостью.
- Уточнения планирования: один набор без накопления, source files остаются до вставки, native Finder owns move/conflicts; никаких собственных source copy/delete. Progress/success не выводятся из отправки клавиш. Конкуренция со Stack и invalidation описаны в S035.
- Открыто: подтвердить границу Finder-only и достаточность отображения подготовленного набора с передачей операции Finder. Проверить AX admission, copy correlation и result observability на устройстве до ready. Дополнительные permissions/API не утверждены.

- Подтверждённое уточнение UI, 2026-09-22: пользователь отказался от расширенного Finder Cut окна целиком. Только компактная панель: значок вырезания/состояния слева, крестик справа, имя/количество снизу; ошибка заменяет имя коротким сообщением. Подробности доступны в tooltip/VoiceOver без раскрытия. После dispatch крестик закрывает notice, а не отменяет операцию Finder. Это уточнение UI не закрывает остальные platform verification gates D-046.

## D-047: Пять последних записей History в status menu

- Статус: `accepted`
- Дата: 2026-09-21
- Источник: пользователь запросил пять последних записей между History и Paste Stack и подтвердил немедленную вставку в приложение, из которого открыто меню.
- Решение: S036 добавляет прямой доступ к пяти первым occurrences общей History. Пункт History и последующие команды сохраняются; используется существующая typed History paste.
- Уточнения планирования: activity order общей History без зависимости от Search/Favorites; bounded локальные подписи; нет placeholders до пяти. При active Stack предложено отключать recent actions с объяснением, сохраняя текущую границу BR-028. Эти детали не выдаются за отдельные ответы пользователя.
- Последствия: нужны независимая bounded projection, захват исходного target при открытии native menu и общий paste transaction guard. Новые permissions, storage schema и input interception не требуются. Focus/handoff и typed target acceptance проверяются при реализации S036.

## D-048: Явный History storage contract и общий execution owner

- Статус: `accepted`
- Дата: 2026-09-22
- Источник: пользователь подтвердил предложенное ревью упрощение кода без удаления функций.
- Решение: `HistoryStoring` требует paging, favorites, typed/rich payloads и Stack leases. `RetryingHistoryStore` сохраняет lazy retry и передаёт все эти операции. ApplicationShell создаёт один `SerializedHistoryService` для History UI, capture, payload reads и lease operations.
- Причина: optional capability casts скрывали отсутствие lease forwarding в production wrapper; два actor wrappers над одним service не задавали общего порядка операций.
- Последствия: runtime fallback для неполных stores удалён, text-only fakes остаются в Tests. Неиспользуемые full-history/occurrence API удалены из приложения; тестовые чтения проходят через paging и exact-entry lookup. Схема данных, retention, permissions и release contract не меняются. Исправлено удержание Stack payload от expiry через default wrapper. Проверки cancellation/revocation/focus и clipboard correlation сохраняются.

## D-049: Единый порядок веток и публикации релизов

- Статус: `accepted`
- Дата: 2026-09-22
- Источник: пользователь подтвердил предложенный порядок релиза и заменил префикс рабочих веток на `feature/`.
- Контекст: подготовка версий использовала разные имена `codex/*` и `release/*`; AGENTS.md не задавал общий порядок и объём релизных команд.
- Решение: закрепить правила веток и авторизации в [AGENTS.md](../AGENTS.md), операционные шаги в [RELEASING.md](RELEASING.md). Изменения доставляются через PR в `main`, затем отдельный PR подготовки версии; тег указывает на проверенный CI коммит `main`. Существующая `codex/release-1.0.11` является переходным исключением.
- Последствия: релизная ветка больше не служит веткой разработки. Явный запрос публикации разрешает весь необходимый процесс без повторных вопросов, сохраняя protected approval и обязательные проверки. Workflow, signing, notarization и Sparkle не меняются. Имена веток пока контролируются инструкциями, а не автоматическим CI правилом.

## D-050: Ручное исправление раскладки через левый Option

- Статус: `accepted` для пользовательского пути; replacement adapter и capability matrix требуют platform probe.
- Дата: 2026-10-01.
- Источник: пользователь запросил ограниченную функцию типа Punto Switcher, подтвердил последнее введённое слово, включая слово сразу перед пробелом, левый Option, системные раскладки и переход по кругу того же фрагмента при трёх и более sources.
- Решение: S037 исправляет выделение либо последнее введённое слово только по явному действию. Поддерживаемые keyboard layouts берутся из enabled/selectable input sources macOS. Повторное standalone нажатие левого Option переводит тот же диапазон дальше по циклу до invalidation новым вводом/focus/selection. Автокоррекция, словари и постоянный буфер набранного текста не входят.
- Уточнения планирования, не отдельные ответы пользователя: explicit opt-in toggle, alternative chord, видимый в Settings порядок, switch input source после проверенной замены, no-clipboard базовый путь, native Undo и отказ при active Stack/pending Cut/in-flight input. Конкретные word boundaries, source attribution выделения, бюджеты и срок transient cycle snapshot фиксируются по probe.
- Причина: нужен быстрый ручной сценарий, а постоянное накопление ввода существенно расширяет privacy boundary Qipli. Выбор источников по языку не заменяет physical-key mapping, IME нельзя молча приравнять к статической раскладке.
- Последствия: расширяется input contract S001 и shortcut settings S010, а не clipboard capture/storage. `AXSelectedText` в SDK read-only; tagged Unicode replacement, selection/caret, Undo и реальная совместимость не доказаны. До основной реализации обязателен probe. Clipboard-assisted fallback, новые permissions, helper или private API без отдельного решения не добавляются. D-020 сохраняет прежние три shortcuts и фиксированные `⌘V`/`Esc`; новая отдельная correction preference не сбрасывает их. Ошибки и причины отказа видны inline в Settings; popup и системные уведомления не используются.

## D-051: Bounded adapter и технические defaults S037

- Статус: `accepted` для replacement adapter, budgets, source policy и metadata-only fresh-input модели. Hardware baseline/6-unit word/3 spaces/standalone release подтверждены; external notification admission и complete installed feature matrix проверяются при реализации, без optimistic fallback.
- Дата: 2026-10-02.
- Источник: запрос пользователя реализовать S037 с выбором технического решения; решения ниже выбраны агентом по signed synthetic probe, а не выданы за отдельные пользовательские подтверждения. Evidence: Implementation report [S037](slices/S037-manual-layout-correction.md).
- Решение: public focused-application → focused-element chain, проверенные editable capabilities и bounded `AXStringForRange`; writable `AXSelectedTextRange` задаёт диапазон, один tagged Unicode key-down/up pair отправляется в прежний PID. Успех требует actual text/range postcondition. После dispatch повторная отправка запрещена. Проверка допуска выполняется для каждого focused field по его Accessibility capabilities, без app-name/bundle allowlist; это не обещает совместимость всех полей. TextEdit plain text и Chrome input остаются отдельными runtime evidence для проверенных targets, а не списком разрешённых приложений.
- Пределы: selected/replacement ≤4096 UTF-16 units, context ≤256, без усечения или chunking. Own NSTextView принял 4096 одним event и отменил native Undo; это не универсальный compatibility claim. AX request timeout ≤150 ms с уменьшением до остатка общего deadline 500 ms. Deadline — выбранный implementation ceiling, а не обещание времени ответа любого target. Cycle snapshot: idle TTL 5 s, hard TTL 30 s; external input/focus/selection/source-list/settings/permission/tap changes инвалидируют его раньше. Timer closures не удерживают payload после очистки snapshot.
- Sources: enabled/selectable static layouts с проверяемыми Unicode tables; порядок определяется source ID и виден в Settings, без предположения о порядке macOS UI. Для выделения исходным считается текущий допустимый source, если он представляет весь фрагмент; иначе нужен единственный такой source из допустимого списка. Не выбирать источник по алфавиту и не менять attribution после неоднозначности destination mapping. Все возможные physical key/Shift/Caps candidates должны давать один destination output, иначе отказ. Повторный цикл преобразует исходный operation seed в следующий source, сохраняя ожидаемый текущий текст только для freshness validation.
- Fresh word: обязателен metadata-only context baseline до ввода; post-hoc caret минус число клавиш не доказывает происхождение текста. Счётчики UTF-16 units, source/PID/AX identity, generation и monotonic timestamps допустимы; последовательность символов или keycodes не хранится. AX work выполняется вне event callback и его runloop. Неизвестный baseline, stale samples, composition или неподдерживаемые notifications не получают оптимистичный fallback.
- Уточнение fresh-word baseline, 2026-10-06: обычный набор может заменить выделение, существовавшее до первого keyDown. Этот preinput selection допускается только при нулевых aggregate input units на начало run; после ввода final selection должна быть пустой. Caret growth считается от начала исходного выделения, document count — от `initialCount - initialSelectedLength + insertedUnits`. Native pending selection → applied caret сохраняет baseline только при проверенной identity/source/PID, монотонном росте после первого replacement и input budget. Baseline, созданный внутри слова, не переносится назад и не получает permission исправить непроверенный префикс. Это локальное исправление metadata admission, без чтения текста до Option или расширения platform APIs. Реальные ChatGPT traces показывают поздний baseline, но причина первого пропуска в них ещё не записывалась; `firstInputStatus` сохраняет её для повторной проверки.
- Уточнение input invalidation, 2026-10-06: mouse/nontext/modified input и tap loss сбрасывают ledger и monitor baseline синхронно в metadata-only callback. Отложенный main callback инвалидирует только cycle/operation gate, не baseline. Иначе coalesced ранний reset мог очистить уже новый preinput snapshot, захваченный последующим keyDown. `onCorrectionInputInvalidation` больше не передаёт отложенный preserve flag, способный повторно очистить monitor. В event callback по-прежнему нет AX/TIS/payload reads.
- Queue ownership: TIS enumeration/current-source/property access выполняется на main queue; metadata и копия Unicode layout data передаются worker. Runtime harness выявил HIToolbox `dispatch_assert_queue` при background `TISGetInputSourceProperty`. AX messaging остаётся на serial background worker; event callback не вызывает TIS/AX. Runtime target admission основан на capability checks конкретного editable field, а не bundle allowlist. Error feedback остаётся inline в Settings, без popup/notification. Fixed status публикуется сразу, чтобы crash/termination не скрывали предыдущий этап probe.
- Self-fixture exception: AX entry points в своём процессе могут вызывать AppKit напрямую. Поэтому own synthetic AX fixture выполняет эти entry points на main, вне input callback. Это не production AX threading evidence: production Qipli UI исключается, запросы к external target остаются в serial background worker. Probe вынесен в самостоятельную test utility `scripts/probes/s037`, отсутствует в обычных Debug/Release targets и не является production helper.
- Последствия: toggle off по умолчанию и отдельные validated enable/trigger preferences сохраняют прежние shortcut reset/migration. Clipboard, History/Stack, permissions, entitlements и distribution не расширяются. 3+ sources, document-specific source memory, macOS 14 и installed feature matrix остаются отдельными gates; отсутствие этих проверок не выдаётся за поддержку.


## D-052: Исправление последнего слова по запросу и native paste

- Статус: `accepted` для реализации; installed ChatGPT/Undo/clipboard matrix ещё не пройдена.
- Дата: 2026-10-06.
- Источник: пользователь отверг повторные неработающие baseline fixes и запросил изучить реальные GitHub switchers и сделать рабочее решение. Read-only review: [langSwitcher AccessibilityService](https://github.com/reg2005/langSwitcher/blob/0bfebf6b5ef3dc37e1543a386fb67cc207eb08ce/LangSwitcher/Sources/Services/AccessibilityService.swift), [UASwitcher TextConverter](https://github.com/deimoc/UASwitcher/blob/e1456de66551185b89ca8fbc69e496e8e55345df/Sources/UASwitcher/TextConverter.swift), [Punto TextAccess](https://github.com/rshagiev/punto-switcher/blob/1c65abcfa7eb909b292f373bcb655893506ac297/Sources/PuntoNative/TextAccess.swift). Их рабочие пути используют explicit selection/typing counters и native paste либо physical replay, без mandatory непрерывного preinput AX baseline. Их compatibility claims не считаются Qipli runtime evidence; сторонний код не запускается и не включается как dependency.
- Решение: заменить обязательный baseline/notification proof из D-051 на on-demand bounded AX capture при явном Option. Для word path остаются recent external typing metadata (source/PID/word UTF-16 units/trailing ASCII spaces/5-second freshness), invalidation mouse/navigation/nontext/modified input и composition rejection. Сам целевой диапазон, границы, payload и focus/range/text проверяются в момент операции. Old token prefix, inside-token caret, pasted-only/old text без recent typing и Enter crossing отказывают. Background preinput AX polling не является условием выполнения. Без выделения операция не обещает доказать происхождение каждого символа при программном изменении редактора; это явная команда над текущим ограниченным диапазоном, защищённая target/range/text revalidation.
- Замена: single tagged native Cmd-V в захваченный PID после AX selection/range admission; без blind Backspace, записи всего AXValue, private APIs и повторной отправки. Clipboard transaction сохраняет все доступные item representations в памяти до временной записи plain text, только при неизменном исходном changeCount. Snapshot budget: до 64 items, 256 representations, 32 MiB; недоступные representations/превышение дают выбор single Unicode input до изменения поля, без clipboard mutation; гонка отменяет операцию. После dispatch транспорт не меняется и события не повторяются. Unicode compatibility подтверждается postcondition/native runtime, не предполагается для всех frameworks. Temporary write и restore регистрируются через PasteboardMonitor.registerSelfWrite и не поступают в History/Stack.
- Restore: только пока pasteboard.changeCount принадлежит текущей transaction; более новая внешняя Copy не перезаписывается. После подтверждённого paste restore немедленный; после неподтверждённого dispatch bounded grace 250 ms позволяет target обработать единственный queued paste, затем ownership-checked restore. Content/types сохраняются побайтно, исходный changeCount технически восстановить нельзя. Snapshot не пишется в storage/log/network и освобождается после restore/loss of ownership. Обычный Cmd-V вне явной correction не меняется.
- Verification: regression tests для word path без baseline, native field changes, old/pasted prefix refusal, clipboard restoration и concurrent external copy. Development-signed native probe на synthetic owned field должен проверить production adapter, caret/space/Undo и clipboard/self-write boundary. ChatGPT installed acceptance проверяется отдельно; passing unit suite не обозначает работоспособность конкретного поля.

## D-053: Shift-double-click, длинные выделения и transient correction feedback

- Статус: `accepted`
- Дата: 2026-10-08
- Источник: пользователь после проверки поведения v1.0.13.
- Решение: Shift-double-click History использует тот же plainText payload mode, что Shift-Enter; обычный double-click остаётся rich. Selected/replacement ceiling S037 увеличен втрое до 12 288 UTF-16 units. Context ≤256, operation deadline 500 ms, ownership/freshness/postcondition/Undo contract и отказ без chunking/усечения сохраняются. Новая величина supersedes ceiling D-051; прежнее runtime evidence не доказывает новый предел.
- Feedback: denied/failed correction сохраняется в Settings и показывается в маленькой верхней nonactivating панели с раскрытием/сворачиванием, в стиле Finder Cut. Через три секунды начинается сворачивание; новое сообщение обновляет timer. Completed не открывает панель. Отдельная presentation не заимствует Finder Cut session и не отменяет Stack/Cut. Mouse events проходят исходному приложению, focus не захватывается, Reduce Motion использует fade. Показываются только фиксированные сообщения без clipboard/text/source payload; системные уведомления и logs не добавляются.
- Причина: длинное явное выделение должно иметь больший рабочий диапазон, а отказ должен быть виден в момент команды. Silent Settings-only feedback из D-050/D-051 и S037 заменён этим правилом.
- Проверка: полный SwiftPM, unsigned universal Release, signed universal Debug и owned native selected-range/Undo probe для 12 288. Реальные редакторы и installed visual/gesture path проверяются отдельно, без объявления S037 done.

## D-054: Opt-in локальные диагностические журналы

- Статус: `accepted`
- Дата: 2026-10-15
- Источник: пользователь запросил диагностику в финальном приложении, выключенную по умолчанию.
- Решение: Settings General получает toggle, Show Logs и Clear Logs. Отдельный Foundation/Darwin writer принимает только typed enums и случайные operation IDs, без arbitrary string messages или error descriptions. Журнал включает UTC timestamp, session/operation UUID, version/build, этап, код причины и duration. Source IDs, target identities, клавиши и любые пользовательские payload/metadata исключены.
- Хранение: `~/Library/Logs/Qipli` и отдельная `Qipli Dev`; private directory/files, до десяти файлов по 1 MiB, retention семь дней по modification time с cleanup при startup, записи и ежечасно. При выключенном Qipli cleanup выполняется при следующем запуске. Очередь ограничена 256 событиями; перегрузка может терять диагностические события, но не задерживает input.
- Ownership: serial utility queue, generation invalidation для queued records при disable/clear; только собственные имена файлов, отказ на symlinks/non-regular files. Отключение сохраняет прежние журналы до retention/явной очистки. Никаких uploads, OSLog, новых permissions, helper или persistence dependencies.
- Supersedes отсутствие stage/error logging из D-053 и технического контракта S037 только при explicit opt-in. Update module по-прежнему не логирует.
- Verification: default-off/no-file, relaunch, disable/clear races, rotation/age/permissions, unsafe filesystem, schema privacy, correction outcomes и Settings controls. Installed signed UI acceptance ведётся отдельно.


## D-055: Evidence для расследования correction incidents

- Статус: `accepted`
- Дата: 2026-10-15
- Источник: пользователь после двух ChatGPT failures потребовал сохранять максимум диагностической информации для расследования. В schema v1 `wordProof/unavailable` и `replacement/unavailable` теряли конкретный AX вызов и причину.
- Решение: расширить S038 schema v2 конкретными API/attribute/system-result/type/range/check/timing данными, terminal outcomes и корреляцией delayed clipboard restore. Именованные успешные проверки и polling observations сохраняются вместе с отказами. Последняя конкретная причина дублируется в terminal record, потеря событий отмечается sequence gaps и counted overflow report. Terminal reserve восемь записей сверх основной очереди 256, не более одной pending overflow task на generation; input thread не ждёт диск.
- Privacy: максимум структурного evidence без текста/clipboard, hashes, raw source/app/window IDs, key stream, URL/filename/path/media metadata и произвольных строк. Разрешены fixed browser family chrome/safari/firefox/edge/other, static field role/value type, числовые lengths/ranges и булевы equality checks. Source identities только operation-local sorted ordinals. Raw numeric AXError/OSStatus не превращается в error description. Это уточнение D-054/BR-041; arbitrary identity/payload logging по-прежнему запрещено.
- Граница: instrument existing calls/checks, не читать новое содержимое, не менять input permissions/correction transport/deadline/обычный Cmd-V. Default-off/local-only, storage ≤10 MiB/7 дней и Dev/Release separation сохраняются. Не обещать ретроспективно восстановить отсутствующее evidence или доказать внутренний bug браузера только по AX failure.
- Проверка: injected AX API failures, wrong types, short strings, focus/permission/secure-input/setter/deadline cases; synthetic clipboard ownership/restore; schema privacy/old records/overflow and terminal-cause retention; SwiftPM и universal builds. Установленный ChatGPT reproduction новой сборкой остаётся отдельным acceptance gate.


## D-056: Copy/Paste выделения и replay недавнего слова

- Статус: `accepted` для реализации, native acceptance отдельно.
- Дата: 2026-10-15.
- Источник: пользователь подтвердил переход на Copy/Paste выделения и короткий буфер нажатий/replay слова после двух Final Cut failures в 18:11 Lisbon. AX messaging исчерпал 500 ms до mutation.
- Решение: production correction больше не требует AXValue/settable selected range/AXStringForRange/character count и полного AX postcondition. Один metadata-only preflight проверяет focused text role, password/Secure Input и PID; допускаются text/search/combo fields без writable AXValue. Выделение читается native Copy и заменяется одним native Paste. При доступном пустом selected range Copy пропускается, иначе Copy имеет приоритет над word buffer. Отсутствие свежего текстового Copy не подменяется старым clipboard.
- Последнее слово: только enabled correction хранит до 256 физических клавиш с Shift/Caps в памяти, максимум пять секунд после ввода, восемь trailing ASCII spaces. Ни event objects, ни Unicode stream не хранятся. Клавиши позволяют восстановить текст, поэтому это чувствительные transient данные. Mouse/navigation/modified input, source/app/permissions/settings/tap changes очищают buffer; dead/composition paths отклоняются. Word replay удаляет число graphemes исходного слова/пробелов и отправляет Unicode replacement в исходный PID. После начала mutation fallback/retry запрещён.
- Ownership: tagged Copy/Paste/Backspace/Unicode исключаются из capture/input ledger. Clipboard snapshot до Copy ограничен 64 items/256 representations/32 MiB, живёт в памяти; monitor временно приостановлен на correction Copy, exact observed Copy/write/restore counts регистрируются как self-writes. Более новая внешняя Copy отменяет mutation/restore. Не поддерживаем произвольную одновременную программную запись clipboard как доказуемо отличимую от ответа на Copy.
- Поведение: после замены курсор в конце результата; циклическое исправление использует исходные клавиши/seed и native replay предыдущего результата, idle TTL 5 s/hard TTL 30 s. Native Undo grouping зависит от редактора, single-step Undo больше не универсальный контракт. Completed означает dispatch завершён и source switch подтверждён, а не AX-доказательство текста. UI сообщает неподтверждённую отправку отдельно от отказа до dispatch.
- Проверки перед каждой отправкой: frontmost PID, input generation, permission/Secure Input; при изменении контекста прекращаем без повторной отправки. AX metadata preflight имеет отдельный bounded timeout, Copy и paste grace имеют свои лимиты; старый общий 500 ms ceiling отменён. Не обещаем произвольные read-only/custom fields, IME или программное перемещение caret без observable input.
- Supersedes D-051/D-052 и D-053 в части production AX admission/replacement/postcondition, запрета key buffer/Backspace, selection preservation и общего deadline. D-054/D-055 privacy logging сохраняется, добавляются только typed native stages. Старый AX adapter остаётся probe/regression utility. Permissions, entitlements, сеть, History/Stack, обычный ⌘V и release scope не меняются.
- Verification: key-buffer TTL/bounds/physical mapping/cycle; fake native service selection/word/races/no-retry; clipboard Copy/write/restore/self-write exclusion; signed owned-field replay/Copy/Paste; Final Cut text field live acceptance. Final Cut не считается проверенным по unit tests или сборке.

## D-057: восстановление global input и надёжность native correction

- Статус: accepted для локальной реализации 2026-10-22; Chrome/Telegram и installed acceptance проверяются отдельно. Пользователь поручил исправить сбои и сравнить способы ввода, без публикации релиза.
- Event tap: disabled callback сначала пробует немедленное re-enable. Успех сбрасывает retry backoff независимо от новых keyDown. Неудача показывает недоступность и запускает пересоздание с задержками 0.25–5 s без busy loop и без окончательного исчерпания попыток. Проверка фактических port validity/enabled раз в 5 s восстанавливает необнаруженное отключение. Stop отменяет queued retry и timer. Existing main-runloop/input arbitration сохраняются; отдельный input thread не вводится без необходимости и проверки потокобезопасности владельцев Stack/Cut.
- Word buffer: ≤256 физических клавиш, срок в памяти до 30 s после ввода вместо 5 s, без persistence/logging. Context invalidations сохраняются. Неизвестная composition запрещает текущий token; plain Space завершает его и допускает только следующее слово. Escape/Return/Tab очищают composition и buffer. Не предполагается, что произвольный mouse/navigation завершают dead-key sequence.
- Selection: если Copy не вернул текст, при непустом или неизвестном выделении запрещён fallback к Backspace/word replay. Дополнительная metadata-only проверка focused AX element/PID перед Copy и mutation обнаруживает смену поля внутри приложения; AX text/value и writable-range prerequisites не возвращаются.
- Transport: сравниваются Unicode replay и Backspace + native Paste. Для Paste clipboard snapshot и replacement готовятся до удаления. Backspace получает pacing, после начала mutation нет повторной попытки/смены транспорта. Clipboard ownership проверяется до удаления и Paste; restore grace и self-write protection сохраняются. Отдельный signed synthetic runner выбирает Unicode/Paste через injection; product launch modes не добавлены. Приложение использует native Paste, installed acceptance остаётся открытым. Фактическая совместимость и Undo остаются runtime gates, dispatch не объявляется доказательством изменения текста.
- Apple platform review: [event tap callback/runloop](https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate(tap:place:options:eventsofinterest:callback:userinfo:)), [re-enable](https://developer.apple.com/documentation/coregraphics/cgevent/tapenable(tap:enable:)), [Unicode events](https://developer.apple.com/documentation/coregraphics/cgevent/keyboardsetunicodestring(stringlength:unicodestring:)), [Secure Input TN2150](https://developer.apple.com/library/archive/technotes/tn2150/_index.html). Минимальная macOS, permissions, entitlements, sandbox и distribution не меняются. Secure Input не обходится.
- Verification: repeated timeout/success без keyDown, backoff/reset, unsafe Copy fallback, composition recovery/TTL, clipboard failure before mutation, focused-field race; полный SwiftPM, signed Dev и unsigned Release. Реальные Google Search/Chrome omnibox и Telegram synthetic fields проверяются без отправки сообщений; итог записывается в S037 и STATE.


## D-058: переключение раскладки до clipboard grace и причины stale

- Статус: accepted для локального исправления по запросу пользователя 2026-10-29; installed acceptance отдельно.
- Evidence: в локальных журналах 1.0.17/build18 за 29 октября пять операций завершились `keyReplay/passed → finished/stale` после отправки Paste и до layoutSwitch. Код проверял общий epoch после 250 ms clipboard grace. Какое конкретное событие меняло epoch в этих исторических случаях, старый журнал не позволяет установить.
- Решение: native Paste возвращает управление сразу после dispatch. Coordinator проверяет freshness и переключает source до первого ожидания. Grace 250 ms переносится в async `finish`: lease и operation ownership удерживаются до ownership-checked restore. Cancellation не сокращает grace; новый внешний Copy сохраняется. Новое событие во время grace может инвалидировать cycle, но не меняет уже завершённый результат source switch. Проверки до mutation/между Backspace/до Paste, отказ при partial replay, запрет retry и обычный ⌘V сохраняются.
- Диагностика: trigger и успешные lifecycle events не становятся lastFailure. Stale guard содержит step, отдельный input/modifier/gate epoch check, числовые expected/observed и текущие поколения; проверки target/field/permission/Secure Input имеют typed причины. Текст, клавиши, source IDs, PIDs и пользовательские paths не записываются.
- Apple contracts перепроверены 2026-10-29: [`postToPid`](https://developer.apple.com/documentation/coregraphics/cgevent/posttopid(_:)) не возвращает подтверждение приёма текста; [`changeCount`](https://developer.apple.com/documentation/appkit/nspasteboard/changecount) отражает изменение владельца pasteboard. Grace остаётся эвристикой потребления Paste, `completed` не объявляется проверкой фактического текста. Permissions/event-tap mask/entitlements/minimum macOS/distribution не меняются.
- Проверка после review: native transport допускает injection существующего `CorrectionAXClient`, frontmost PID и event poster; production defaults используют прежние системные API. Timer, clipboard lease и finish не подменяются в regression tests. Это позволяет проверять реальную задержку/cancellation/restore на named test pasteboard без Accessibility grant и внешнего ввода. Compatibility probe переключает source до grace и проверяет результат после него.

## D-059: Общая сторона экрана и проработка панелей

- Дата: 2026-10-29. Статус: accepted.
- Основание: пользователь запросил более проработанные окна и размещение сверху/справа/слева/снизу; отдельно подтвердил одну сторону для обеих панелей.
- Решение: единая local preference с default Top. После пользовательской проверки выбран чёрный «жидкий остров», соединённый с физическим краем экрана на всём переходе. Top сохраняет notch integration; остальные края получают тот же повёрнутый вогнутый контур без внешнего зазора. Reserved Dock space находится внутри чёрной оболочки, controls остаются в visibleFrame. Слева/справа вертикальные карточки, сверху/снизу горизонтальные. Единые токены отступов, радиусов и коротких interruptible transitions. Нативные AppKit/SwiftUI, без dependency.
- Последствия: D-038/D-043 ограничивают только default Top, запрет альтернативного положения отменён для History/Stack. Finder Cut и correction notice не перемещаются. Нужны отдельные geometry/persistence/lifecycle и installed accessibility/display checks.
