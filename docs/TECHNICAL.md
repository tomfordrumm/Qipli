# Qipli — технический контракт

Статус: архитектура публичного приложения, typed/formatted History и единой Top Notch оболочки History/Paste Stack

Дата базовой проверки платформы: 2026-08-06; S004 input/panel contracts перепроверены: 2026-08-08; Accessibility identity/release signing перепроверены: 2026-08-09; Settings/onboarding/ServiceManagement перепроверены: 2026-08-12; Developer ID/notarization и GitHub Actions/Releases перепроверены: 2026-08-26; Sparkle `2.9.6` contracts перепроверены: 2026-08-28; typed pasteboard/UTType/bookmark contracts перепроверены: 2026-08-31; notch geometry/window/collection contracts перепроверены: 2026-09-01; RTF/HTML pasteboard contracts и open-source precedents перепроверены: 2026-09-03

Поддерживаемая платформа: macOS 14+

## 1. Выбранный технический профиль

Qipli — нативное menu bar приложение на Swift. Интерфейс строится на SwiftUI там, где это не мешает управлению окнами, и на AppKit для `NSStatusItem`, плавающих `NSPanel`, активации приложений и точного контроля фокуса. Системные события клавиатуры обрабатываются через Core Graphics event tap. История хранится локально через Core Data с SQLite-backed store.

Приложение распространяется напрямую через публичные GitHub Releases, подписывается Developer ID, использует Hardened Runtime и проходит notarization. Версионный tag запускает защищённый release workflow, а Sparkle использует публичный HTTPS appcast и отдельную EdDSA signature для обновлений. App Sandbox для MVP не включается: выбранный сценарий требует Accessibility API и управления событиями других приложений, а Apple перечисляет использование accessibility API в assistive apps среди действий, несовместимых с App Sandbox.

## 2. Потребности и возможности платформы

| ID | Потребность | Компонент | Статус | Основание и контроль |
|---|---|---|---|---|
| NEED-001 | Видеть изменения общего буфера | `NSPasteboard.general` и `changeCount` | supported | Apple документирует общий pasteboard и счётчик смены владельца. Проверить polling и self-write suppression на macOS 14/15 в S002. |
| NEED-002 | Глобально перехватывать активный `⌘V` и отправлять синтетическую вставку | `CGEvent` event tap + Accessibility trust | supported с разрешением | Apple документирует создание/включение event tap и проверку `AXIsProcessTrustedWithOptions`. Проверить на чистой macOS 14 в S001. |
| NEED-003 | Показывать компактные панели поверх приложений | AppKit `NSPanel` + SwiftUI content | supported | Стандартная нативная оконная модель; проверить focus/non-activating поведение в S001/S003. |
| NEED-004 | Хранить и удалять локальную 30-дневную историю | Core Data SQLite store в Application Support | supported | Локальный компонент приложения, внешняя платформа не требуется. Проверить миграцию, purge и восстановление после ошибки в S002. |
| NEED-005 | Распространять бинарник вне Store | Developer ID + Hardened Runtime + notarization | supported | Apple поддерживает direct distribution и требует Hardened Runtime для notarization. Проверить credentials и release workflow перед S008. |
| NEED-006 | Работать в Mac App Store с выбранным event-control дизайном | App Sandbox | unsupported для MVP | App Store требует sandbox; Apple указывает несовместимость accessibility API assistive apps с sandbox. Mac App Store исключён из MVP. |
| NEED-007 | Сохранять локальные shortcuts и completion onboarding | `UserDefaults` за typed validation boundary | supported | Системное key-value storage достаточно для малых несекретных preferences; S010/S011 проверяют atomic validated snapshot и fallback. |
| NEED-008 | Запускать main app при входе по явному выбору пользователя | `ServiceManagement.SMAppService.mainApp` | supported на macOS 13+ | Apple документирует register/unregister/status и subsequent-login launch для main application. Qipli поддерживает macOS 14+, helper не нужен. |
| NEED-009 | Дать быстрый опциональный first-run setup до clipboard capture | AppKit/SwiftUI onboarding + startup gate | supported | Apple HIG рекомендует быстрый optional onboarding, контекстный user-triggered permission request и откладывание необязательной кастомизации. |
| NEED-010 | Проверять публичные изменения без доступа к release secrets | GitHub Actions на GitHub-hosted macOS runner | supported | Push/PR workflow получает только read-only repository access и выполняет unsigned tests/build. Реальный run проверяется в S013. |
| NEED-011 | Автоматизировать Developer ID signing и notarization по тегу | Защищённый GitHub Environment, ephemeral Keychain, `xcodebuild`, `notarytool`, `stapler` | supported при credentials | Apple поддерживает scripted notarization; GitHub-hosted runners изолированы. S014 рано проверяет exportable certificate и App Store Connect API key. |
| NEED-012 | Доставлять обновления вне Mac App Store | Sparkle 2, GitHub Release assets и GitHub Pages appcast | supported | Sparkle поддерживает Developer ID-signed app bundles, EdDSA-signed ZIP и HTTPS appcast. S015 проверяет реальный old-to-new update. |
| NEED-013 | Читать и восстанавливать несколько pasteboard items и representations | `NSPasteboardItem`, `NSPasteboardReading`/`NSPasteboardWriting`, `UniformTypeIdentifiers` | supported | AppKit предоставляет `pasteboardItems`, `writeObjects` и typed data/string/property-list representations. S023 выполняет contract probe на macOS 14+ до смены production capture. |
| NEED-014 | Хранить inline images локально без загрузки payload в History snapshot | Core Data metadata + managed files в Application Support | supported | Системный file storage не требует новой runtime dependency. S024 проверяет atomic ownership, quotas, restart, cleanup и bounded thumbnail decode. |
| NEED-015 | Сохранять reference на локальный file/video без копирования source bytes | file URL + Foundation URL bookmark data | supported с runtime recheck | Bookmark может разрешать URL позднее и сообщать stale data. S025 проверяет move/rename/delete, stale refresh и pasteback на реальных Finder items. |
| NEED-016 | Привязать transient History к camera-safe верхней области конкретного display | `NSScreen.safeAreaInsets`, auxiliary top areas и `visibleFrame` | supported с hardware verification | AppKit предоставляет safe-area geometry; S027 проверяет MacBook с camera housing, notchless external display, full-screen Space и изменение screen parameters без hardcoded notch dimensions. |
| NEED-017 | Показывать bounded карточки с reusable views, selection и prefetch | `NSCollectionView` + flow/custom layout | supported | AppKit collection view отделяет data source/layout, переиспользует item views и поддерживает selection/prefetch. S027 использует horizontal History shelf; S030 переиспользует bounded horizontal presentation contract для ordered text Stack cards. |
| NEED-018 | Сохранить форматирование текста и дать явную plain-only вставку | `NSPasteboardItem` с `.string`, `.rtf`, `.html` + local History key routing | supported с source/target matrix | AppKit определяет стандартные RTF/HTML pasteboard types и multi-representation item. S031 проверяет raw round-trip, size policy, `Enter`/double-click rich paste и exact `⇧Enter` plain paste на macOS 14+. |

### Авторитетные источники

- Apple, [`NSPasteboard`](https://developer.apple.com/documentation/appkit/nspasteboard), [`changeCount`](https://developer.apple.com/documentation/appkit/nspasteboard/changecount) и [`clearContents()`](https://developer.apple.com/documentation/appkit/nspasteboard/clearcontents()): ownership changes advance `changeCount`, while `clearContents()` returns the resulting count.
- Apple, [`NSPasteboard.pasteboardItems`](https://developer.apple.com/documentation/appkit/nspasteboard/pasteboarditems), [`writeObjects(_:)`](https://developer.apple.com/documentation/appkit/nspasteboard/writeobjects(_:)), [`NSPasteboardItem`](https://developer.apple.com/documentation/appkit/nspasteboarditem), [`NSPasteboardReading`](https://developer.apple.com/documentation/appkit/nspasteboardreading) и [`NSPasteboardWriting`](https://developer.apple.com/documentation/appkit/nspasteboardwriting): один pasteboard может содержать несколько ordered items, а item может предоставлять несколько typed representations.
- Apple, [`NSPasteboard.PasteboardType.string`](https://developer.apple.com/documentation/appkit/nspasteboard/pasteboardtype/string), [`rtf`](https://developer.apple.com/documentation/appkit/nspasteboard/pasteboardtype/rtf) и [`html`](https://developer.apple.com/documentation/appkit/nspasteboard/pasteboardtype/html): plain text, RTF и HTML являются стандартными representations одного pasteboard item; target выбирает поддерживаемое представление.
- Apple, [`UniformTypeIdentifiers`](https://developer.apple.com/documentation/uniformtypeidentifiers), [system-declared UTTypes](https://developer.apple.com/documentation/uniformtypeidentifiers/system-declared-uniform-type-identifiers) и [`URL` bookmark APIs](https://developer.apple.com/documentation/foundation/url): типы text, URL, file URL, image и movie классифицируются через UTType, а bookmark data создаётся и позднее разрешяется с явным stale state.
- Apple, [`CGEvent`](https://developer.apple.com/documentation/coregraphics/cgevent), включая event taps, и [`tapEnable`](https://developer.apple.com/documentation/coregraphics/cgevent/tapenable(tap:enable:)).
- Apple, [`CGEventTapOptions.defaultTap`](https://developer.apple.com/documentation/coregraphics/cgeventtapoptions/defaulttap): active filter может возвращать `nil`, чтобы потребить exact event; passive tap не может менять stream. Callback вызывается на run loop, а разрешение/маска могут сделать создание tap недоступным.
- Apple, [`NSWindowDelegate.windowShouldClose(_:)`](https://developer.apple.com/documentation/appkit/nswindowdelegate/windowshouldclose(_:)) и [`NSWindow.orderOut(_:)`](https://developer.apple.com/documentation/appkit/nswindow/orderout(_:)): delegate перехватывает user close reusable panel, а `orderOut` скрывает её без release.
- Apple, [Human Interface Guidelines: Materials](https://developer.apple.com/design/human-interface-guidelines/materials) и [Adopting Liquid Glass](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass): Liquid Glass образует функциональный слой, применяется умеренно, а `regular` предпочтителен для text-heavy surfaces и системно адаптируется к Reduce Transparency/Increase Contrast.
- Apple, [`NSGlassEffectView`](https://developer.apple.com/documentation/appkit/nsglasseffectview) и [`NSVisualEffectView`](https://developer.apple.com/documentation/appkit/nsvisualeffectview): настоящий AppKit glass доступен с macOS 26, тогда как semantic visual-effect material является fallback для deployment target macOS 14.
- Apple, [`CGEvent.post(tap:)`](https://developer.apple.com/documentation/coregraphics/cgevent/post(tap:)): tagged synthetic Copy входит в Quartz event stream перед taps в выбранной позиции; [`eventSourceUserData`](https://developer.apple.com/documentation/coregraphics/cgeventfield/eventsourcuserdata) содержит 64-bit marker, а [`CGEventSource`](https://developer.apple.com/documentation/coregraphics/cgeventsource) описывает state generated/posted events.
- Apple, [`NSWindow.CollectionBehavior.canJoinAllSpaces`](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/canjoinallspaces) и [`fullScreenAuxiliary`](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/fullscreenauxiliary): вспомогательная panel показывается во всех Spaces и рядом с full-screen window.
- Apple, [`NSScreen`](https://developer.apple.com/documentation/appkit/nsscreen), [`safeAreaInsets`](https://developer.apple.com/documentation/appkit/nsscreen/safeareainsets), [`auxiliaryTopLeftArea`](https://developer.apple.com/documentation/appkit/nsscreen/auxiliarytopleftarea) и [`auxiliaryTopRightArea`](https://developer.apple.com/documentation/appkit/nsscreen/auxiliarytoprightarea): список displays, `visibleFrame` и camera-safe geometry для placement временной panel.
- Apple, [`NSPanel.becomesKeyOnlyIfNeeded`](https://developer.apple.com/documentation/appkit/nspanel/becomeskeyonlyifneeded): nonactivating panel может становиться key только при взаимодействии с view, которому нужен keyboard input; Top Notch всё равно использует явную user-triggered activation для Search focus.
- Apple, [`NSCollectionView`](https://developer.apple.com/documentation/appkit/nscollectionview), [`NSCollectionViewLayout`](https://developer.apple.com/documentation/appkit/nscollectionviewlayout) и [`NSCollectionViewGridLayout`](https://developer.apple.com/documentation/appkit/nscollectionviewgridlayout): collection view поддерживает reusable items, selection, prefetch и сменяемую layout strategy для shelf/grid presentations.
- Apple, [`AXIsProcessTrustedWithOptions`](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions).
- Apple, [`SMAppService`](https://developer.apple.com/documentation/servicemanagement/smappservice), [`mainApp`](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp), [`register()`](https://developer.apple.com/documentation/servicemanagement/smappservice/register()) и [`Status`](https://developer.apple.com/documentation/servicemanagement/smappservice/status-swift.enum): main app можно зарегистрировать для последующих login; status различает not registered, enabled, requires approval и not found.
- Apple, [Updating helper executables from earlier versions of macOS](https://developer.apple.com/documentation/servicemanagement/updating-helper-executables-from-earlier-versions-of-macos): фактический Service Management status нужно отражать в UI и при необходимости открывать Login Items Settings.
- Apple HIG, [Onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding) и [Privacy](https://developer.apple.com/design/human-interface-guidelines/privacy): onboarding должен быть быстрым и опциональным; permission запрашивается в понятном контексте после действия пользователя, а необязательная настройка не должна мешать началу работы.
- Apple, [`TN3127: Inside Code Signing — Requirements`](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements) и [`Creating distribution-signed code for macOS`](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac): privacy permission identity следует designated requirement; ad-hoc `Sign to Run Locally` привязан к exact build и не является стабильной identity между сборками.
- Apple, [Protecting user data with App Sandbox](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox) и [App Sandbox](https://developer.apple.com/documentation/security/app-sandbox).
- Apple, [Preparing your app for distribution](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution), [Hardened Runtime](https://developer.apple.com/documentation/security/hardened-runtime) и [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).
- Apple, [Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow): `notarytool` поддерживает автоматизированную отправку, ожидание результата и App Store Connect API credentials.
- GitHub, [GitHub-hosted runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners), [Using secrets in GitHub Actions](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets), [Triggering a workflow](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow) и [Managing releases](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository): macOS runners, protected secrets, tag filters и release assets поддерживают выбранный pipeline.
- Sparkle, [Documentation](https://sparkle-project.org/documentation/) и [Publishing an update](https://sparkle-project.org/documentation/publishing/): regular app update требует возрастающий `CFBundleVersion`, HTTPS feed, Developer ID code signature и EdDSA-signed archive; `generate_appcast` является рекомендуемым способом создания feed.

Implementation precedents, проверенные 2026-09-03 и не являющиеся runtime dependencies:

- [Maccy `Clipboard.swift` на commit `39e0ba5`](https://github.com/p0deje/Maccy/blob/39e0ba5e8161dc75ac082ea51bcedc74d6a23564/Maccy/Clipboard.swift) (MIT) allowlist-ит `.string`, `.rtf`, `.html`, сохраняет raw data и для plain mode оставляет только string representation. Qipli использует этот поведенческий паттерн, но сохраняет собственные typed-storage, paging и input contracts.
- [CopyQ FAQ на commit `df0a192`](https://github.com/hluk/CopyQ/blob/df0a192ce3e21dffb102a6385092c23bcdb7d530/docs/faq.rst#L213-L242) (GPL) подтверждает multi-MIME history и необходимость per-format byte ceilings; его built-in default 100 MiB не переносится в Qipli, потому что Qipli выбирает более узкий formatted-text scope и bounded managed storage.
- [Clipbara `PasteService.swift` на commit `d64bc61`](https://github.com/mobrava/Clipbara/blob/d64bc61f5a0f73c6f539643b5261c43ae3afa4e5/Clipbara/Services/PasteService.swift#L8-L49) (GPL) подтверждает UX с modifier-controlled plain paste. GPL-код не копируется; Qipli реализует собственный exact `⇧Enter` History action.

Базовые ссылки и выводы проверены 2026-08-06. S006/S007 повторно сверили scoped input/panel contracts 2026-08-08: `.defaultTap` как active filter, callback run-loop delivery, permission/mask failure, 64-bit `eventSourceUserData`, ownership `changeCount` и `clearContents()` result; `windowShouldClose(_:)` как user-close interception и `orderOut(_:)` для hiding reusable nonactivating panel. S009 design recheck 2026-08-08 подтвердил HIG material hierarchy и local macOS 26 SDK availability `NSGlassEffectView` при сохранении `NSVisualEffectView` fallback. S010/S011 recheck 2026-08-12 подтвердил `SMAppService.mainApp` и HIG optional/contextual onboarding guidance. S013/S014 platform recheck 2026-08-26 подтвердил GitHub-hosted macOS runners, protected secrets, tag triggers, same-repository Releases и Apple automated notarization. S015 recheck 2026-08-28 подтвердил current stable Sparkle `2.9.6`, programmatic `SPUStandardUpdaterController`, Info.plist `SUFeedURL`/`SUPublicEDKey`, explicit automatic-check preference и EdDSA appcast tooling. Typed-History recheck 2026-08-31 подтвердил multi-item pasteboard APIs, standard UTTypes и Foundation bookmark APIs; exact behavior на Finder/browser/image source apps остаётся ранним runtime probe S023–S025. Top Notch recheck 2026-09-01 подтвердил `NSScreen` safe/auxiliary geometry, auxiliary full-screen window behavior и AppKit collection-view layout/reuse contracts; фактическая форма camera housing и animation остаются hardware/visual gates S027. Formatted-text recheck 2026-09-03 подтвердил standard `.string`/`.rtf`/`.html` types, raw multi-representation storage и modifier-controlled plain-paste precedents; exact source/target representation mix остаётся controlled/manual gate S031. `v1.0.1` launch failure дополнительно подтвердил обязательный embedded-framework `LC_RPATH`; реальный old-to-new Sparkle update переносится на `v1.0.2 → v1.0.3`.

## 3. Компоненты и ответственность

```text
System pasteboard ──> PasteboardMonitor ──> HistoryService ──> Core Data
                              │                    │
                              └──> StackSession    └──> HistoryPresentationState
                                      │                    ├──> Top Notch History NSPanel
Keyboard event tap ──> InputCoordinator             └──> Full History NSWindow
                              │
                              ├──> StackSession ──> Top Notch nonactivating Stack NSPanel
                              └──> PasteExecutor ──> prior frontmost app

Local preferences ──> SettingsService ──> Shortcut snapshot ──> InputCoordinator
System login items ──> LaunchAtLoginService ──> Settings / Onboarding
First-run state ──> OnboardingCoordinator ──> startup gate ──> PasteboardMonitor

Version tag ──> protected GitHub Actions ──> signed/notarized DMG + ZIP ──> GitHub Release
Landing page ──> releases/latest/download/Qipli.dmg ──> drag Qipli to Applications
Sparkle updater ──> public HTTPS appcast ──> EdDSA-verified ZIP ──> in-place app update
```

### Public CI и release automation

- pull request и push в `main` используют отдельный unsigned workflow с `contents: read`; workflow не импортирует certificates и не читает release environment secrets;
- tag workflow принимает только documented stable tag format, проверяет version/build contract и работает с exact tagged commit;
- release job получает минимальные write permissions, проходит protected GitHub Environment и импортирует exportable Developer ID identity во временный Keychain;
- notarization использует App Store Connect API key из GitHub Secrets; `.p12`, `.p8`, пароли и Sparkle private key никогда не коммитятся и не печатаются;
- existing fail-closed verifier остаётся общей границей для local и CI packaging. CI не дублирует ослабленную проверку;
- GitHub Release сначала создаётся как draft. Versioned DMG, identical stable `Qipli.dmg` alias, DMG checksum, ZIP, ZIP checksum и release notes проверяются до публикации; failed run не меняет текущий stable feed;
- EdDSA secret проходит раннюю fail-closed сверку с `SUPublicEDKey`; после публичной проверки release asset appcast упаковывается в отдельный Pages artifact и разворачивается pinned official Pages Actions;
- временный Keychain и key files удаляются в unconditional cleanup step. Fork/PR code не исполняется в контексте release secrets.

### SecureUpdater

- Sparkle `2.9.6` подключается через exact Swift Package Manager dependency к production Xcode target и обновляется отдельным reviewable change;
- `SPUStandardUpdaterController` или изолированный adapter владеет check/download/install lifecycle, а Application shell предоставляет `Check for Updates…` и Settings binding;
- automatic checks выключены по умолчанию и включаются только явным действием пользователя. Silent install без подтверждения не используется в первой версии;
- `SUFeedURL` указывает на публичный GitHub Pages HTTPS appcast; `SUPublicEDKey` хранит только public key, private EdDSA key доступен release job;
- appcast публикуется после проверенного GitHub Release asset и содержит возрастающий numeric build, short version, minimum macOS и EdDSA signature;
- update path не получает clipboard/history/search services и не добавляет их значения в URL, headers, release notes или updater logs;
- invalid feed, EdDSA, Apple signature, download или install failure сохраняет текущий app bundle и локальные data/preferences. Фактический Accessibility state перепроверяется после relaunch.

### Application shell

- управляет жизненным циклом menu bar utility и единственным экземпляром приложения;
- предоставляет команды «История», «Начать/закрыть Paste Stack», Settings, состояние разрешения и «Выйти»;
- создаёт activating History Top Notch, отдельную nonactivating Paste Stack Top Notch presentation и singleton Settings/onboarding windows, не смешивая оконную логику с доменными правилами;
- хранит History query, selected occurrence и captured paste target только в History presentation; Stack presentation наблюдает существующий `StackSessionController` и не становится владельцем input/paste transactions;
- на первом локальном запуске удерживает старт `PasteboardMonitor` за onboarding gate; после Finish/Skip/close запускает normal shell services ровно один раз.

### PasteboardMonitor

- периодически сравнивает `NSPasteboard.general.changeCount` с последним обработанным значением;
- до S023 извлекает только неизменённое строковое представление; typed boundary S023 читает ordered `NSPasteboardItem` descriptors и только заранее разрешённые representations;
- не запрашивает каждый advertised custom type: unsupported/provider-owned representations игнорируются, чтобы capture не выполнял произвольную дорогую materialization;
- передаёт exact observed `changeCount`; Stack capture snapshot-ит identity активной session и её start watermark до deferred main-actor обработки, чтобы copy до Start или от отменённой session не попало в новую session;
- распознаёт изменения, созданные самим Qipli, и не возвращает их в capture pipeline;
- сериализует обработку, чтобы быстрые изменения не меняли порядок.

Частота polling — настраиваемая реализационная константа, которую выбирают по тестам энергопотребления и потери быстрых копирований; продуктовый контракт не задаёт выдуманный интервал.

### HistoryService

- является единственной точкой записи, поиска, удаления и retention cleanup;
- выполняет persistent-store work через последовательную background execution boundary; main actor получает только immutable `HistoryEntry` snapshots;
- до S023 хранит актуальный text snapshot; после S023 выдаёт bounded `HistoryOccurrenceDescriptor` pages и не держит полный retention window в UI memory;
- initial page и каждая следующая page содержат не более 500 occurrences; keyset cursor использует строгий `(activityAt, id)` order вместо растущего `OFFSET`;
- empty query получает ordered page, а непустой query выполняется persistent-store boundary по всему retention window и возвращает тот же bounded descriptor contract;
- не отдаёт записи, чья последняя активность старше или равна 30 дням, даже если фоновая очистка ещё не завершилась;
- поддерживает отдельные одинаковые события;
- выполняет batch retention cleanup при запуске, перед выдачей результатов и периодически при длительной работе без материализации удаляемых managed objects;
- использует persistent index для exact UUID lookup; индекс сортировки добавляется только если S018 докажет измеримый выигрыш без неприемлемой цены записи;
- при «Очистить всё» уничтожает/пересоздаёт persistent store либо эквивалентно удаляет основную БД и sidecar-файлы после закрытия соединений.

### Typed payload и managed asset storage

- `HistoryOccurrence` владеет ordered clipboard items; каждый item хранит только поддерживаемые representations и один derived display/search descriptor;
- text и малая metadata остаются в Core Data. Inline image bytes записываются в Qipli-managed Application Support directory по opaque occurrence/item ID без clipboard text, filename или URL в имени;
- capture image идёт через temporary file, capacity validation и atomic move. Core Data commit публикуется только после durable asset placement; ошибка откатывает metadata и удаляет temporary data;
- file/video item хранит URL bookmark/reference и snapshot metadata, но не копирует source bytes. Resolution выполняется только для paste или явной локальной metadata refresh; stale bookmark обновляется после успешного resolution;
- thumbnail является производным cache artifact, не источником paste payload. UI запрашивает его только для visible rows; cache miss не блокирует список и не меняет occurrence availability;
- delete/expiry/Clear All удаляют owned assets и derivatives. Они никогда не удаляют referenced source. Startup maintenance трогает только файлы, безопасно распознанные как Qipli-owned temp/orphan artifacts;
- per-item и total-byte limits инъецируются в policy tests. Production values фиксируются решением до перевода S024 в `ready`; overflow отклоняет новый managed item и не запускает auto-eviction старой истории.
- S031 расширяет managed storage отдельным rich-text manifest для raw RTF/HTML bytes. Rich assets используют opaque Qipli IDs, integrity digest и atomic temp-to-final commit; они не переиспользуют filename, URL или markup-derived path и не входят в descriptors.
- Canonical plain text остаётся Core Data/search/preview/Stack value. Наличие rich manifest является отдельным materialization capability и не выводится из `HistoryEntry.isTypedEntry`, потому что formatted text по-прежнему имеет text primary kind.
- Rich capacity policy: 16 MiB на representation, 32 MiB на occurrence и 512 MiB на все durable rich assets. Overflow не отменяет допустимый text capture: occurrence сохраняется как plain-only, а partial rich temp files удаляются. Missing/corrupt committed rich asset, напротив, не приводит к silent plain fallback во время default paste. Поскольку `NSPasteboardItem.data(forType:)` не даёт pre-read byte length или streaming API, adapter запрашивает allowlisted representations последовательно и избегает дополнительных полных копий, но один candidate может быть materialized системой до admission check.

### Performance boundary

- S017 фиксирует воспроизводимые baselines на синтетических payload-free fixtures примерно для 1 800, 10 000 и 50 000 History entries, длинного текста и больших Paste Stack. Наблюдённые wall-clock значения являются evidence для регрессий, но не превращаются в выдуманный публичный SLA.
- Проверки разделяют storage/query, search/filter, preview construction, Stack traversal/render preparation и pasteboard scheduler. Каждая последующая оптимизация обязана иметь focused regression test на изменяемую границу.
- Локальная Debug/test instrumentation может измерять длительность и счётчики операций, но не включает clipboard text, search query, preview, UUID или другие пользовательские payload в сообщения, signpost metadata и имена файлов.
- Абсолютные timing thresholds применяются только к стабильным алгоритмическим seams или явно калибруемым benchmark runs. Обычный CI прежде всего проверяет сложность, отсутствие main-thread persistent I/O, cancellation/stale-result contracts и число обходов, чтобы не стать flaky из-за shared runner load.

### StackSession

- чистая тестируемая in-memory collection boundary с UUID session token, pasteboard `changeCount` start watermark и отдельными UUID occurrence;
- в S005 владеет base visible order с уникальными contiguous `position`, session-level `.direct`/`.reverse` и deterministic next (верх для direct, низ для reverse); reorder принимает только полную уникальную перестановку exact occurrence UUID и отвергает invalid input атомарно;
- external append во время collection всегда добавляется в конец текущего base order; `markTraversalStarted()` блокирует reorder/direction до конца session, но actual paste/used/reactivation остаются S006–S007;
- не пишет отдельную «сохранённую очередь» в Core Data;
- освобождается при явной отмене/close; новая session всегда пустая.

### InputCoordinator и PasteExecutor

- регистрируют глобальные сочетания и event tap только в разрешённом состоянии, включая `Esc` как отмену только при активном стеке;
- active event tap потребляет exact untagged `⌘⇧V` и `⌘⇧C` keyDown, untagged `Esc` без semantic Shift/Control/Option/Command при active stack, exact untagged `⌘⇧Z` только при active Stack с successfully dispatched occurrence, и exact untagged ordinary `⌘V` только при active Stack с pending/reactivation-priority/reserved occurrence. `⌘⇧Z` только назначает последний successfully dispatched UUID одноразовым reactivation priority; tagged synthetic events, keyUp, other modifier variants и `⌘⇧Z` вне этого narrow admission проходят без изменения как system Redo. Deferred `⌘⇧C` action posts tagged ordinary `⌘C`, который marker пропускает обратно к source app;
- synchronous callback только atomically reserve/pass/consume decision; pasteboard work и dispatch deferred. Повтор input при existing reservation потребляется без second transaction;
- не модифицируют ordinary `⌘V`, когда стек не активен, исчерпан или закрыт;
- сразу после synchronous internal write регистрируют returned exact final `changeCount`, до следующего run-loop poll, чтобы монитор пропустил self-write;
- быстро подготавливают следующий текст в pasteboard и отправляют/пропускают событие вставки, не блокируя event tap тяжёлой работой;
- помечают элемент used после отправки команды вставки, а не после недоступного подтверждения целевого поля;
- распознают собственное синтетическое событие, чтобы избежать рекурсии;
- реагируют на системное отключение event tap, пытаются безопасно переустановить его и показывают ошибку при неуспехе.
- после системного prompt или открытия Accessibility Settings выполняют ограниченный polling официального trust API; реальный переход grant/revoke публикуется в UI и соответственно запускает/останавливает event tap без перезапуска приложения. При повторной активации Qipli trust также перепроверяется; clipboard/search payload в этот путь не попадает.

S010 заменяет hard-coded History/Stack/Reactivate Previous match значениями из immutable validated shortcut snapshot. Event tap по-прежнему потребляет только exact untagged keyDown текущих трёх Qipli commands; ordinary `⌘V`, active-Stack `Esc`, synthetic marker, keyUp и narrow reactivation admission остаются отдельными неизменяемыми контрактами. Snapshot меняется атомарно без teardown здорового event tap. Валидация гарантирует уникальность Qipli bindings и защищает системные/продуктовые input actions, но не заявляет глобальную осведомлённость о shortcuts сторонних приложений.

S031 не добавляет global event-tap binding. History-owned local key routing различает unmodified `Enter`/keypad Enter и exact Shift-only `⇧Enter`: первый выбирает default rich materialization, второй — plain-only payload. Command/Control/Option combinations, keyUp и unrelated input возвращаются текущему responder; double-click использует default rich mode.

### Settings, preferences и launch at login

- Settings window — singleton active AppKit window со SwiftUI content; она не наследует nonactivating/floating behavior Stack и не создаёт постоянный Dock icon;
- typed preferences service загружает три shortcuts и onboarding completion из `UserDefaults`, валидирует весь shortcut snapshot и fail closed восстанавливает defaults при несовместимых данных;
- До S030 standalone Paste Stack сохранял в `UserDefaults` последнюю пару конечных координат панели. S030 перестаёт читать и обновлять эту preference для presentation; устаревшее несекретное значение можно оставить для совместимости, но оно не влияет на Top Notch geometry;
- invalid edit не записывается и не меняет runtime snapshot; Reset to Defaults затрагивает только shortcuts;
- существующий `AccessibilityPermissionService` остаётся единственным permission source of truth для History fallback, Settings и onboarding; отдельные status-menu item и Permission panel отсутствуют;
- `LaunchAtLoginServicing` изолирует `SMAppService.mainApp.status`, `register()`, `unregister()` и открытие Login Items Settings. `requiresApproval` не считается enabled; `notFound` остаётся явным retryable состоянием и разрешает user-triggered `register()`; errors видимы и retryable;
- production login-item adapter не требует helper bundle, LaunchAgent, daemon, новой entitlement или network access;
- при активации Qipli и открытии Settings фактические Accessibility/login-item states refresh-ятся, чтобы внешние изменения в System Settings не маскировались локальным toggle state.

### OnboardingCoordinator

- решает только first-run/reopen presentation и idempotent startup gate, переиспользуя permission, shortcut и launch-at-login services S010;
- fresh profile показывает privacy/value screen до первого pasteboard read; Finish, Skip или explicit close сохраняют completion и один раз запускают normal monitoring;
- crash/force quit до сохранённого dismissal оставляет flow pending; manual re-open не останавливает уже работающий monitor и не меняет completion;
- permission request и login-item registration происходят только после соответствующего явного действия пользователя;
- onboarding не читает clipboard payload и не создаёт тестовую history entry.

### Top Notch presentation boundary

- `PanelController` сохраняет ownership, lifecycle, activation, focus, close delegate, level, Spaces/full-screen и display-placement contracts; material wrapper не принимает feature decisions;
- один AppKit shell/provider задаёт общие shape, safe-area geometry, mask transition и content-safe insets для History и Paste Stack Top Notch; каждый presentation содержит ровно одну outer surface;
- на macOS 26+ provider использует `NSGlassEffectView` style `regular`; вызов закрыт `#available(macOS 26.0, *)`, поэтому deployment target остаётся macOS 14;
- на macOS 14–25 provider использует `NSVisualEffectView` с semantic `.popover` material, `.behindWindow` blending и system-managed state; implementation не имитирует Liquid Glass custom blur/shader;
- Top Notch использует отдельный reusable borderless activating `NSPanel`: shortcut сначала captures non-Qipli target, затем делает panel key и фокусирует Search. Frame привязан к текущему screen и раскрывается вниз; top anchor не двигается во время resize. Placement использует safe-area/auxiliary-area geometry и `visibleFrame`, а на notchless display выбирает top-center fallback ниже menu bar;
- History `NSCollectionView` остаётся horizontal reusable card boundary. Coordinator разделяет snapshot, selection и thumbnail updates: при неизменных IDs/revision mouse selection не вызывает `reloadData()` или storage/search work, уже выбранный ID является no-op, а готовый thumbnail reconfigure-ит только соответствующий visible item. Stack получает bounded horizontal ordered cards без второй long-lived occurrence collection; exact text не копируется в отдельную presentation model и не обходится целиком ради preview;
- top/right/left/bottom placement моделируется будущим enum, но production S027 реализует только `.top`; остальные values не появляются в Settings и не проходят partial runtime paths;
- Paste Stack использует отдельную reusable borderless `.nonactivatingPanel` configuration с теми же safe-area frame и mask transitions. Она не вызывает app activation/`makeKey`, не получает History outside-click/resign-key hooks и остаётся раскрытой до Cancel, global Escape или auto-finish. Отдельный movable frame, window drag region и saved-origin restore удаляются из active path;
- специальный transition между active Stack и History не входит в S030. Реализация не добавляет tab/navigation state или обещание возврата между modes;
- Lists, cards и individual controls не получают отдельные custom glass layers. На macOS 26 standard controls принимают актуальное системное оформление автоматически;
- system labels/selection colors и accessibility settings определяют contrast. Reduce Transparency может сделать surface непрозрачнее, и код не пытается обходить этот выбор пользователя;
- capability selection имеет injected deterministic seam, но ни tests, ни provider не читают clipboard payload.

## 4. Критические последовательности

### Захват внешнего копирования

1. Monitor замечает новый `changeCount`.
2. Self-write registry подтверждает, что изменение не принадлежит Qipli.
3. Monitor читает текст ровно один раз и передаёт observed `changeCount`; перед deferred work snapshot-ятся optional active Stack session UUID и start watermark.
4. Monitor передаёт capture в последовательную asynchronous History pipeline и может дождаться её drain перед user-triggered fresh History show.
5. `HistoryService` сначала durably сохраняет запись на background boundary; только после успеха StackSession с тем же UUID получает отдельный occurrence, если observed `changeCount` строго больше watermark. Отмена/новый Start между этими шагами или write до Start оставляет событие только в History.
6. Main actor публикует новый immutable snapshot; ошибка хранения не маскируется и не создаёт Stack-only occurrence.

Порядок «сначала история, потом стек» гарантирует, что отмена/сбой стека не оставит значение только в памяти.

### Typed capture и publication (S023–S025)

1. Monitor замечает новый `changeCount`, отклоняет exact self-write и snapshots ordered pasteboard items plus advertised type identifiers.
2. Classifier выбирает только поддерживаемые representations. Один observed change создаёт одну occurrence; несколько items сохраняют исходный order. Приоритет primary display kind не удаляет дополнительные representations, нужные для faithful pasteback.
3. Text/URL metadata валидируется в памяти. Inline image проходит size policy и пишется в opaque temporary asset file вне main actor. File/video URL превращается в bookmark/reference без чтения source contents.
4. Если representation unsupported, image превышает limit или managed write не завершается, новая occurrence целиком отклоняется. Пользователь получает bounded non-payload reason; старая History и Stack не меняются.
5. После durable asset placement repository commits occurrence/items/representations metadata. Только затем main actor вставляет новый descriptor в первую page. Interrupted process до commit не оставляет видимую partial occurrence; maintenance может удалить только распознанный Qipli temp/orphan.
6. Active text-only Stack получает item только если occurrence имеет допустимый exact text payload. Media occurrence остаётся в History и не меняет session order, next или traversal state.

### Formatted text capture и publication (S031)

1. После self-write rejection reader snapshots ordered pasteboard items и canonical `.string`. Только occurrence с допустимым непробельным canonical text допускает rich capture.
2. Для каждого того же item classifier allowlist-ит `.rtf` и `.html`; RTFD, WebArchive, private/dynamic и source-specific types игнорируются без вызова их data providers.
3. Adapter последовательно запрашивает каждый allowlisted `Data` не более одного раза, проверяет materialized byte count против 16 MiB per-representation, 32 MiB per-occurrence и 512 MiB total durable policy и немедленно отбрасывает oversized candidate. AppKit не позволяет гарантировать rejection до materialization; Qipli не создаёт вторую полную in-memory копию. Допустимые raw bytes один раз пишутся в opaque temporary files вне main actor.
4. Repository атомарно commits text occurrence и rich manifest после durable asset placement. Если rich overflow/write fails, временные rich assets удаляются, а та же occurrence commits plain-only и публикует bounded non-payload notice.
5. Page/search descriptor содержит canonical bounded text preview и capability flag/representation descriptors, но не markup, raw bytes, byte count или source metadata. Search не парсит RTF/HTML.
6. Active Stack после successful History commit получает только canonical text snapshot; rich manifest не входит в StackSession.

### Сбор Paste Stack (S004)

1. Deferred global `⌘⇧C` action snapshots/starts session with current pasteboard `changeCount`, показывает nonactivating Paste Stack Top Notch и только затем dispatch-ит tagged ordinary `⌘C`; repeated hotkey сохраняет session/occurrences, но повторяет Copy. Target app остаётся active и владеет resulting pasteboard write.
2. Menu Start создаёт одну пустую session без Copy; menu меняется на Cancel.
3. Resulting target-owned pasteboard change не self-write и не append-ится напрямую: Monitor → HistoryService → matching StackSession сохраняет History-first/watermark guarantees. Если tagged Copy dispatch observable fails, panel показывает retryable error; отсутствие pasteboard change у target не заявляется как capture error.
4. Stack panel — borderless `NSPanel` с `.nonactivatingPanel`, Top Notch level, `.canJoinAllSpaces` и `.fullScreenAuxiliary`; она не вызывает App activation или `makeKey` и не закрывается при работе во внешнем приложении.
5. Перед показом выбирается screen из текущего source/target context с bounded mouse/main/first fallback. Frame вычисляется тем же safe-area/auxiliary-area contract, что S027; legacy saved floating origin игнорируется.
6. Exact global Escape или Cancel освобождает только StackSession, запускает reverse mask transition и после него выполняет `orderOut`; записи History не затрагиваются.

### Вставка из истории

1. До активации History сохраняются frontmost non-Qipli application и контекст, достаточный для возврата; текущий display определяется из active target window/mouse fallback без чтения clipboard payload.
2. После startup History reload reusable Top Notch prewarm-ится без показа. Явный `⌘⇧V`/menu action вычисляет safe top frame, раскрывает panel вниз и через единственный AppKit adapter запрашивает strong user-initiated activation; после `isActive` panel становится key и Search получает focus. Fresh show синхронно выбирает first occurrence и card shelf возвращает viewport к leading anchor; paste-failure reopen не сбрасывает retry context.
3. До S023 по `Enter` immutable selected text становился внутренней записью в system pasteboard. Typed History materializes selected occurrence only after reservation: text/URL берутся из metadata, image читается из managed asset, file/video reference разрешается без чтения всего source в память. В S031 default `Enter`/double-click добавляет сохранённые RTF/HTML рядом с canonical `.string`, а exact `⇧Enter` materializes только `.string`. Writer восстанавливает ordered pasteboard items и выбранные supported representations. Exact final `changeCount` сразу регистрируется как self-write.
4. Сразу после successful write активное History presentation в том же обработчике становится прозрачным и перестаёт принимать mouse events. Пока невидимая Qipli ещё active, оно yield/request-activates captured application; command не отправляется до подтверждённого active target.
5. Bounded deadline с main-run-loop retries проверяет `NSRunningApplication.isActive`; при active target presentation выполняет `orderOut` перед synthetic `⌘V`. Пользователь не видит activation wait.
6. После accepted-but-exhausted activation или dispatch failure presentation восстанавливается с retryable error. Pasteboard не переписывается и команда не дублируется.
7. Только после успешной отправки tagged `⌘V` `PanelController` неблокирующе обновляет activity exact selected ID. Durable/cache order меняется сразу, но visible cards не перестраиваются до следующей fresh History presentation; ошибка durable update не меняет уже успешный paste.
8. AppKit key monitor ограничен текущим key History presentation и exact unmodified keyDown. Arrow routing синхронно обновляет exact selected ID и вызывает collection-view scroll-to-visible без ожидания SwiftUI render. Enter начинает transaction непосредственно в handler.
9. Одна UUID transaction блокирует повторные Enter/double-click до completion. Target activation notification проверяет exact captured application и завершает handoff сразу; bounded timer остаётся fallback и единственным timeout path.
10. `windowDidResignKey` и History-only local/global mouse monitor скрывают History Top Notch без focus restoration. Explicit Escape использует отдельный cancel path. Paste Stack Top Notch не получает эти dismissal hooks.
11. UI сообщает только об отправке команды; реальное принятие text/media сторонним приложением наблюдать надёжно нельзя. Missing/corrupt payload останавливает write до conceal/activation и оставляет активное History presentation открытым с exact unavailable state.

### Вставка из Paste Stack

1. Active event tap получает exact untagged ordinary `⌘V` keyDown. Если Stack inactive, завершён, пуст или input tagged/modified, он возвращает original event. При accepted input `StackSession` synchronously reserves exact pending UUID by direct/reverse traversal либо selected used reactivation-priority UUID and locks direction/order; repeat while reserved is consumed without another transaction. Exact `⌘⇧Z` может только назначить последнюю successfully dispatched occurrence priority и возвращает original event во всех остальных состояниях.
2. Deferred main-run-loop executor publishes processing state, rechecks the same session UUID/reservation and Accessibility trust, then writes the immutable exact text to system pasteboard.
3. Writer returns the exact final `changeCount`; monitor receives that count as a self-write before control returns to its next poll, so the write cannot re-enter History/Stack capture.
4. Executor posts tagged synthetic ordinary `⌘V`. Only a successful dispatch converts the exact reservation to used; a permission, writer, dispatch or input-listener failure returns traversal reservation to pending but returns reactivation reservation to used while retaining priority, then publishes a retryable non-payload error.
5. Used occurrences remain visible and disabled; one Reactivate action or `⌘⇧Z` priority is marked separately from traversal Next. Append/cancel/deferred UI intents validate the current session/UUID domain atomically.
6. After the last successful dispatch, all occurrences are first published as used. One deterministic deferred turn verifies the same session is still complete and has no reactivation priority, then releases it, runs the reverse Top Notch transition, orders out the nonactivating panel and restores the menu Start state. A reactivation before that turn prevents finish; it does not reactivate a target app.

При гонке с внешней сменой pasteboard предпочтение отдаётся безопасности: не вставлять неизвестное значение как элемент стека, показать сбой и сохранить текущую сессию для повтора.

## 5. Данные

### HistoryEntry — текущая persisted text schema

Минимальный продуктовый контракт:

| Поле | Назначение |
|---|---|
| `id` | стабильный локальный UUID записи |
| `text` | исходная строка без нормализации |
| `activityAt` | последняя активность: initial capture либо успешно отправленная history paste-команда; задаёт порядок и retention |

Domain property называется `activityAt`, но SQLite/Core Data attribute key остаётся `capturedAt` для совместимости с уже созданными user stores; он хранит то же activity значение и не требует migration. Индекс по legacy key `capturedAt` обязателен. Дополнительное поисковое поле или индекс допустимы после профилирования, но не должны менять исходный `text`. Метаданные приложения-источника в MVP не сохраняются.

S023 выполняет lightweight migration каждой legacy row в typed occurrence с одним text item, сохраняя UUID, exact text и legacy `capturedAt` activity value. Миграция не переписывает `PROJECT_BRIEF.md` и не меняет 30-day retention semantics.

### HistoryOccurrence и payload items — target typed schema

`HistoryOccurrence` является единицей списка, поиска, activity promotion, retention и delete. Она может содержать несколько ordered payload items, потому что Finder и другие приложения записывают несколько объектов одним pasteboard change.

| Данные occurrence | Назначение |
|---|---|
| `id` | стабильный UUID occurrence; legacy text UUID сохраняется при migration |
| `activityAt` | capture-or-successful-history-paste activity, order и retention |
| `primaryKind` | derived row kind: text, URL, image, file collection или video/file collection |
| `displayTitle` | bounded local display metadata, не paste payload |
| `searchableText` | локально derived text/URL/domain/filename/extension/type metadata; OCR отсутствует |
| `itemCount` | число ordered pasteboard items |
| `managedByteCount` | сумма owned payload bytes для capacity/cleanup; referenced source size не считается owned storage |

`HistoryPayloadItem` принадлежит одной occurrence и имеет стабильный UUID plus contiguous `position`. `HistoryRepresentation` принадлежит item и хранит UTType identifier, storage kind, byte count и representation-specific value:

- `inlineText`: exact string или URL metadata в Core Data;
- `managedAsset`: opaque relative path, expected byte count и integrity metadata для Qipli-owned image;
- `managedRichText`: opaque relative path, expected byte count и integrity digest для raw `public.rtf`/`public.html`; canonical plain text остаётся отдельной `inlineText` representation того же item;
- `fileReference`: bookmark/reference data plus last known local display metadata; source bytes не принадлежат Qipli;
- `derivedThumbnail`: не persisted representation и не участвует в pasteback; это удаляемый cache по item/revision.

Page/search API возвращает только `HistoryOccurrenceDescriptor`: occurrence ID, activity, primary kind, bounded title/search presentation, item count и availability summary. Exact text, bookmark data, managed path, image bytes и thumbnail bytes не входят в descriptor.

Unfiltered History продолжает использовать cursor `(activityAt DESC, id DESC)`. Ranked search использует отдельный устойчивый continuation key `(rank ASC, activityAt DESC, id DESC)`. Rank вычисляется из уже сохранённых representations и reference metadata без schema migration: exact или prefix match URL domain/address получает первую группу, остальные typed URL metadata matches вторую, все остальные localized case-insensitive substring matches третью. URL-подобный plain text не переклассифицируется. Repository проходит группы последовательно и возвращает максимум 500 descriptors плюс bounded continuation evidence; перестановка только уже полученной chronological page не выполняет full-retention ranking и не считается реализацией контракта.

Все pasteboard variants входят в History через один `HistoryCapture` boundary. Capture result содержит только committed descriptor и bounded user notice; production UI не кэширует full `HistoryEntry`, а materializes exact payload по UUID непосредственно перед paste. Image и rich stores используют общий managed-directory boundary для root containment, symlink rejection, temp cleanup и digest verification.

### StackOccurrence — только память

| Поле | Назначение |
|---|---|
| `id` | уникальный UUID occurrence, не зависящий от текста |
| `historyEntryID` | связь с успешно сохранённой записью истории |
| `text` | неизменяемый снимок для вставки |
| `position` | базовый видимый порядок |
| `state` | pending, processing или used; next — derived traversal/priority marker, не отдельное durable state |
| `reactivationPriority` | временный признак «вставить следующим» |
| `lastSuccessfullyDispatchedOccurrenceID` | exact UUID для узкого Reactivate Previous; не является undo history и очищается вместе с session |

### Локальные preferences

| Данные | Назначение |
|---|---|
| shortcut snapshot | bindings History, Start/Collect Paste Stack и Reactivate Previous; загружаются и валидируются атомарно |
| onboarding completion | one-time dismissal для текущего preferences domain |
| automatic update checks | локальный explicit opt-in; default `false`, изменение не влияет на manual check |

Launch-at-login state не дублируется в `UserDefaults`: источником истины является `SMAppService.mainApp.status`.

### Владение и жизненный цикл

- Store находится в Application Support текущего пользователя и не синхронизируется через iCloud.
- Core Data SQLite является каталогом metadata. Managed images, rich-text payloads и thumbnails находятся в отдельных Qipli-owned subdirectories Application Support; relative paths не принимаются от pasteboard и не могут выходить за эти roots.
- Qipli не создаёт сетевых копий, резервных копий или экспортов. Updater загружает только публичный appcast и выбранный release artifact.
- Просроченные записи исключаются из запросов синхронно с пользовательской точки зрения и удаляются из store обслуживающей операцией.
- Удаление отдельной записи и auto-prune — логическое удаление; из-за SQLite/SSD приложение не обещает forensic secure erase.
- Delete/expiry сначала делает occurrence недоступной новым page/search/paste operations, затем удаляет owned image/rich assets и derivatives. Сбой cleanup оставляет только Qipli-owned orphan для следующего maintenance и не возвращает occurrence в UI.
- «Очистить всё» должно удалить управляемые store/SQLite/WAL/SHM, managed-assets, thumbnails и temp files после безопасного закрытия owners, но также не заявляется как secure erase накопителя. Referenced source files не удаляются.

## 6. Разрешения и безопасность

- До запроса Accessibility приложение объясняет, что разрешение нужно для глобальных сочетаний и отправки вставки в активное стороннее приложение.
- На fresh profile privacy/onboarding surface показывается до начала чтения pasteboard и сообщает о 30-дневной локальной истории и отсутствии автоматической фильтрации секретов.
- Проверка доверия выполняется официальным API; отказ пользователя оставляет просмотр, поиск и удаление доступными, но блокирует системную вставку и Paste Stack с явным объяснением.
- Изменение Accessibility в System Settings обнаруживается автоматически: во время собственного permission flow Qipli выполняет bounded polling, а при возвращении в приложение — немедленный recheck. Одинаковое состояние повторно не публикуется и не пересоздаёт здоровый event tap.
- App Sandbox выключен только по причине основного системного сценария; Hardened Runtime остаётся включённым, исключения добавляются только при доказанной необходимости.
- В release-конфигурации нет network client/server entitlement, аналитики и автоматической отправки crash reports.
- Единственный runtime network owner — SecureUpdater. Он не получает ссылки на HistoryService, StackSession или search state и не добавляет product payload в request metadata.
- Автоматическая проверка не стартует без локального opt-in. Manual check создаёт один понятный user-triggered request; offline state не мешает clipboard flows.
- Release workflow не запускается на pull request code с secrets. Developer ID `.p12`, App Store Connect `.p8`, passwords и Sparkle private EdDSA key живут только в protected GitHub Environment и ephemeral runner files/Keychain.
- Git history и текущий tree проходят credential/user-data audit до смены visibility. Обнаруженный реальный secret удаляется из history и ротируется до публикации, а не только добавляется в `.gitignore`.
- Clipboard text, RTF/HTML bytes/markup, URL, filename/path, image/media metadata, поисковые запросы и превью не попадают в логи, `print`, signpost metadata или имена managed файлов.
- UI предупреждает, что автоматической фильтрации секретов нет. Preview должен избегать лишнего раскрытия длинного текста и media, но exact retained representation остаётся доступным для явной вставки.
- Все операции с Core Data выполняются в последовательной модели конкурентности; UI не получает managed objects, привязанные к чужому context.
- Managed asset path строится только из Qipli-owned opaque IDs и проверенного root. Pasteboard filename/path не используется как destination path; symbolic-link/path traversal не может вывести write/delete за managed roots.
- Capacity admission выполняется до durable publication. Per-item и total owned-byte limits применяются также к representations, которые обещают большое содержимое. Unsupported/custom provider data не materialize-ится; allowlisted RTF/HTML запрашивается по одному и проверяется сразу после единственного AppKit `Data` read, поскольку pre-read length/streaming API отсутствует.
- Перед synthetic `Command-V` writer связывает reserved occurrence с prepared representation manifest и exact final `changeCount`. External pasteboard mutation до dispatch приводит к fail-closed retryable error, а не к отправке неизвестного payload.

## 7. Состояние фокуса и совместимость приложений

History panel может стать key window для поиска, поэтому Qipli сохраняет прежнее frontmost application до показа панели. Вставка выполняется после закрытия панели и повторной активации приложения.

Обязательная ручная матрица:

- нативное поле AppKit/SwiftUI;
- браузерное текстовое поле;
- редактор кода;
- многострочное поле с Unicode и переводами строк;
- read-only и secure/password field;
- приложение, закрывшееся между открытием истории и `Enter`;
- Space/full-screen окно и несколько дисплеев.

Qipli не обещает вставку в поля, которые игнорируют стандартный `⌘V`, запрещают paste или изолируют ввод. В этих случаях текст остаётся в истории и системном pasteboard.

## 8. Структура исходного кода

Рекомендуемая, но не предписанная на уровне отдельных файлов форма:

```text
Qipli app target
  Application/       lifecycle, status item, panel coordination
  Clipboard/         pasteboard adapter and monitor
  History/           model, repository/service, history feature
  MediaAssets/       managed image/rich-text storage, reference resolution and thumbnail cache
  PasteStack/        state machine, panel feature
  Input/             permissions, hotkeys, event tap, paste executor
  Settings/          validated preferences, Settings/onboarding UI, login item adapter
  Updates/           Sparkle adapter, updater preferences and user-facing update actions
  Shared/            narrowly shared types and utilities
QipliTests/           domain and adapter-contract tests
QipliUITests/         in-app keyboard and panel flows
.github/workflows/    unsigned CI and protected tag release workflow
```

Не создавать helper process, XPC service, сервер или сторонний persistence layer без подтверждённой необходимости.

## 9. Тестовая стратегия

### Автоматически

- unit: retention boundary from capture-or-use, duplicate events, order/reverse traversal, reactivation priority, cancel/finish transitions;
- unit: self-write suppression и отсутствие рекурсивного synthetic event;
- repository: create/search/promote/delete/delete-all и durable restart на временном Core Data store;
- integration с fake adapters: history Enter flow, permission denied, activation failure, event tap disabled;
- permission integration: asynchronous grant/revoke, bounded unchanged polling и повторный запуск/остановка input adapter после state transition;
- UI: focus поиска, arrows, selection, empty/no-results, stack states и drag reorder внутри Qipli;
- S004: session uniqueness/duplicates/release, save-before-append, stale deferred capture token/start watermark, hotkey start → panel → tagged source-Copy ordering/repeat/menu-empty/failure, Escape active-filter contract и pure multi-display placement clamp;
- S005: 0/1/N direct/reverse next, exact-ID reorder with duplicate text, contiguous positions, invalid atomic rejection, append after reorder, traversal lock and drag/accessibility intent seam;
- S009: capability/provider selection, one-surface-per-panel configuration и неизменность History activation/Paste Stack nonactivation/window lifecycle contracts;
- S010: shortcut codec/atomic validation/default recovery/runtime matching, singleton Settings lifecycle и injected `SMAppService` status/register/unregister adapter;
- S011: fresh/completed/interrupted/reopened onboarding state machine, startup gate idempotence и отсутствие implicit permission/login-item side effects;
- S013: version/tag validation, CI permission/static-secret checks и unsigned SwiftPM/Xcode build path;
- S014: release admission, draft/publish ordering, cleanup behavior и fail-closed packaging with fake command boundaries; реальная подпись/notarization проверяется отдельным protected run;
- S015: updater opt-in/default/manual-check state, feed/version selection, invalid-signature/offline/install failure через injected adapter без реальной сети в unit tests;
- S017: payload-free benchmark fixtures, baseline report и instrumentation counters для History/search/preview/Stack/polling без пользовательского clipboard;
- S018: UUID index contract, batch retention без managed-object materialization и измеряемый query-plan regression;
- S019: persistent I/O не на main thread, последовательность быстрых capture, save-before-append, fresh-show drain и отсутствие unconditional show reload;
- S020: cancellable/stale-safe localized search, ограниченный preview traversal и exact full-text storage/search/paste;
- S021: direct/reverse next за один линейный проход и одна подготовка next-ID на render snapshot без скрытого O(N²);
- S022: один scheduler callback на tick, tolerance/cancel lifecycle, self-write suppression и capture frequency без реального pasteboard в unit tests;
- S023: legacy text migration, keyset pages ≤500, database-backed full-retention search, stale/cancel guards, new-capture/promotion/delete during paging и доказательство отсутствия full payload snapshot на 1 800/10 000/50 000 synthetic occurrences;
- S024: allowlisted image representations, atomic temp-to-managed commit, injected per-item/total capacity policy, oversize/no-auto-eviction, restart, corrupt asset, visible-row-only thumbnail decode и exact image pasteback/self-write suppression;
- S025: URL/file/video classification, ordered multi-item occurrence, bookmark create/resolve/stale refresh, moved/renamed/deleted source, metadata-only search и отсутствие source delete/copy;
- S026: upgrade migration from public text store, interrupted capture/delete recovery, orphan cleanup restricted to managed roots, Clear All inventory, update preservation и payload-free privacy/log scan;
- S027: pure safe-area placement для camera/notchless/multi-display frames, presentation state machine, horizontal card reuse, Search focus, one-dimensional selection, click-away и прежний single paste transaction;
- S030: shared safe-area shape/motion with separate nonactivating Stack lifecycle, source/target focus preservation, horizontal ordered cards, reorder/direction, Next/Processing/Used/reactivation/error states, reverse finish/cancel и отсутствие legacy floating-window placement;
- S031: allowlisted `.string`/`.rtf`/`.html` capture, sequential one-read admission, raw-byte restart round-trip, rich capacity/plain-only fallback, exact `Enter`/`⇧Enter` routing, default/plain paste payloads, corrupt asset handling и managed-rich lifecycle;
- S032: pure search-rank classification, cross-rank cursor pagination без duplicate/gap, deep URL match beyond the first chronological page, exact `⇧Backspace` admission, ordinary Backspace pass-through, selection-only collection reconciliation без full reload и targeted thumbnail update с reusable full-bleed image/text card state reset;
- build: Debug и Release для deployment target macOS 14.

### Вручную на чистой системе

- выдача, отказ и последующее включение Accessibility;
- сценарии PJ-001 и PJ-002 в матрице приложений;
- быстрые последовательные копирования и одинаковые строки;
- sleep/wake, повторный запуск, отключение event tap системой;
- удаление истории и проверка отсутствия её записей после перезапуска;
- запуск подписанного notarized артефакта, Gatekeeper и повторная проверка разрешения после обновления.
- S009 visual matrix на macOS 26+ и fallback macOS 14–25: все панели, Light/Dark, Reduce Transparency, Increase Contrast, разные desktop backgrounds, focus/nonactivation и clean console.
- S010 custom-shortcut/restart/reset matrix и Launch at Login enable → logout/login → disable, включая external disable/requires-approval/error.
- S011 clean-profile onboarding до pasteboard capture: Finish, Skip, close, deny/grant, interruption/relaunch и manual re-open from Settings.
- S013 public GitHub PR и `main` run без release secrets, включая fork behavior и branch protection status.
- S014 protected tag создаёт Developer ID/notarized draft release; опубликованный asset скачивается заново, проходит checksum, Gatekeeper и clean-machine launch.
- S015 две последовательные production-signed версии проходят manual check, opt-in background check, download, install, relaunch, data/preferences preservation и Accessibility recheck; tampered archive/feed и offline path оставляют старую версию рабочей.
- S023 real installed History: legacy text survives upgrade; first page, load-more, search, arrows, Enter, delete и fresh capture проходят без visible pause или duplicate page rows.
- S024 copy image from at least one native app and one browser, relaunch Qipli, inspect thumbnail, search local metadata, paste into a compatible target, then Delete/Clear All and confirm owned asset removal.
- S025 Finder single/multi-file plus video reference: copy, search, paste while source exists, rename/move recheck, delete source and verify unavailable state; Qipli delete/clear must not change source files.
- S026 clean-machine signed update from the last text-only public build preserves text History and starts with empty managed asset roots; privacy/network inspection confirms no media payload leaves the Mac.
- S027 MacBook camera-housing plus notchless external-display matrix: current-screen placement, menu-bar clearance, full-screen Space, Search focus, arrows/Enter/Delete/Escape/click-away, Light/Dark, Reduce Motion/Transparency и unchanged ordinary `⌘V`.
- S030 Top Notch Stack matrix: source Copy, menu-empty Start, reorder/direction, exact sequential paste, Reactivate/`⌘⇧Z`, failure retry, cancel/Escape, auto-finish, camera-housing/notchless/second-display/full-screen placement and nonactivation in at least two external apps.
- S031 formatted text matrix: TextEdit, browser contenteditable, Notes и один installed office editor как source/target; rich default paste, `⇧Enter` plain paste, IDE/plain target, restart, oversize fallback, corrupt asset retry, active Stack и Delete/Clear All.
- S032 History polish matrix: `localhost` с более старой typed URL и свежими text matches, empty/non-empty Search delete shortcuts, click и повторный click без reload/viewport jump, native/browser image thumbnails без full-collection reload, horizontal card reuse, Light/Dark, Increase Contrast и VoiceOver type/selection announcement.

## 10. Сборка и распространение

- Xcode project/Swift package configuration хранится в репозитории. Sparkle `2.9.6` является единственной новой runtime dependency `v1.0.1` и фиксируется exact через Swift Package Manager. `v1.0.0` updater не содержит и обновляется вручную.
- Qipli executable связывает Sparkle через `@rpath` и для каждой universal architecture обязан содержать `LC_RPATH @executable_path/../Frameworks`. Unsigned CI, release gate и signed package verifier отклоняют app без resolvable embedded Sparkle до notarization/publication.
- Deployment target — macOS 14. Реальный Developer ID release archive 2026-08-26 подтвердил universal binary `arm64+x86_64`.
- `CFBundleShortVersionString` получает `MARKETING_VERSION`, `CFBundleVersion` получает возрастающий `CURRENT_PROJECT_VERSION`; stable tag `vX.Y.Z` обязан совпадать с short version до начала signing.
- `.github/workflows/ci.yml` запускается на pull request и push в `main`, использует `contents: read`, не получает release secrets и выполняет tests плюс unsigned build.
- `.github/workflows/release.yml` запускается только по документированному stable tag или эквивалентному manual dispatch для recovery, использует protected `release` Environment и не подписывает произвольный fork/PR commit.
- Debug может использовать development signing. Локальный устанавливаемый ZIP создаётся только `scripts/package-local.sh` со стабильной `Apple Development` identity; ad-hoc `Sign to Run Locally` отклоняется и не должен использоваться для проверки сохранения TCC-разрешения между rebuilds.
- Public release создаётся только `scripts/package-release.sh`: Developer ID Application, Hardened Runtime, secure timestamp, notarization app bundle, stapled ticket, повторная проверка распакованного ZIP, затем создание, Developer ID подпись, отдельная notarization и stapling финального DMG. DMG содержит branded background, `Qipli.app`, ссылку на `/Applications` и скомпилированный AppIcon. Pipeline fail-closed отклоняет ad-hoc/no-Team-ID, `get-task-allow`, App Sandbox/network entitlements, неверный bundle/minimum OS/icon, non-universal binary, forbidden metadata, отсутствие stapled ticket или Gatekeeper acceptance.
- Versioned DMG/ZIP и checksums сначала загружаются в draft GitHub Release вместе с identical alias `Qipli.dmg` и release notes. Workflow скачивает candidates через authenticated draft-asset API и проверяет их до stable publication; после публикации S014/S008 повторяют проверки через публичные URLs без GitHub authentication. Лендинг использует `releases/latest/download/Qipli.dmg`; Sparkle appcast продолжает ссылаться только на immutable versioned ZIP.
- Sparkle `generate_appcast` подписывает archive отдельным EdDSA key. GitHub Pages использует workflow-based HTTPS deployment без publishing branch или PAT; appcast разворачивается только после готового stable asset, не хранит private key и не ссылается на mutable `latest` URL.
- Notarization требует внешней сети и Apple credentials только в release pipeline; установленному Qipli эти credentials никогда не нужны.
- Core History/Paste Stack работают без сети. Manual или opt-in update check требует HTTPS-доступ к GitHub Pages и GitHub Releases.

Обе package-команды требуют full certificate common name. `security find-identity -v -p codesigning` может показать file-based identity, но не перечисляет Data Protection Keychain identities; фактическая Xcode подпись и последующий verifier остаются источником истины:

```sh
QIPLI_DEVELOPMENT_TEAM=TEAM_ID \
QIPLI_APPLE_DEVELOPMENT_IDENTITY='Apple Development: Name (TEAM_ID)' \
scripts/package-local.sh
```

Локальный public release использует Developer ID certificate и заранее сохранённый `notarytool` Keychain profile:

```sh
QIPLI_DEVELOPMENT_TEAM=TEAM_ID \
QIPLI_DEVELOPER_ID_APPLICATION='Developer ID Application: Name (TEAM_ID)' \
QIPLI_NOTARY_PROFILE=qipli-notary \
scripts/package-release.sh
```

CI использует тот же verifier, но создаёт временный Keychain, импортирует exportable Developer ID `.p12` из protected secret и аутентифицирует `notarytool` через временный App Store Connect `.p8`. Конкретные secret names принадлежат workflow; реальные значения и decoded files не должны появляться в command tracing или logs.

## 11. Технические предположения и точки перепроверки

- Измерение 2026-08-29 подтвердило, что текущий локальный 30-дневный объём помещается в Core Data, но main-thread synchronous pipeline и линейный search плохо масштабируются; S017–S020 сохраняют Core Data и устраняют подтверждённые bottlenecks без новой persistence dependency.
- S023 заменяет полный cached retention snapshot bounded descriptors и database-backed paging/search до добавления media. `fetchBatchSize` без `fetchLimit` не считается paging, потому что descriptor mapping не должен обходить весь result set.
- AppKit документирует multi-item/typed pasteboard contract, UTType и URL bookmarks, но representation mix зависит от source app. S023–S025 обязаны сначала записать payload-free inventories типов/счётчиков на synthetic или controlled clipboard и проверить Finder, browser и native image app до фиксации allowlist.
- Production managed-image policy принята в D-035: 32 MiB на image item, 64 MiB на occurrence, 1 GiB на durable original bytes, 128 MiB на пересоздаваемый thumbnail cache и 512 px на длинную сторону thumbnail. Значения являются defaults без UI; overflow отклоняет новую occurrence целиком и не запускает auto-eviction старой истории.
- S031 использует отдельные rich-text defaults 16 MiB на RTF/HTML representation, 32 MiB на occurrence и 512 MiB total durable storage. До production code controlled TextEdit/browser probe проверяет advertised types, raw sizes, sequential materialization и peak behavior; если эти ceilings дают неприемлемую latency/memory или отсекают обычные formatted copies, D-039 и slice обновляются до продолжения. Persistence limits не считаются pre-read memory limits: AppKit может вернуть один полный `Data` до size check.
- Одного Accessibility-разрешения достаточно для выбранного event tap/paste flow на macOS 14+; S001 обязан проверить это на чистом профиле и не скрывать дополнительное системное требование, если оно появится.
- Локальный Developer ID/notary pipeline подтверждён. Для S014 отдельно нужно подтвердить exportable Developer ID private key и App Store Connect API key в protected GitHub Environment; локальный Data Protection Keychain profile сам по себе не переносится на hosted runner.
- `UserDefaults` достаточно для малых несекретных preferences; несовместимая shortcut schema должна fail closed к defaults, а login-item status никогда не кэшируется как source of truth.
- Menu bar оболочка и отсутствие Dock icon — предложение агента, а не решение из исходного брифа.
- Universal release `arm64+x86_64` подтверждён локально; S014 должен повторить его на выбранном GitHub-hosted runner.
- GitHub Pages и Releases остаются публичными update endpoints. Если hosting меняется, новый HTTPS origin, redirect behavior и Sparkle feed migration проверяются до публикации.
- `NSScreen.safeAreaInsets` и auxiliary top areas дают системную геометрию, но не гарантируют одинаковую форму на каждом Mac/display mode. S027 не рисует копию физической чёлки по hardcoded pixels и требует hardware matrix до `done`.
- Первая Top Notch версия реализует только top placement. Future right/left/bottom placement переиспользует presentation states, но требует отдельного slice для screen-edge geometry, mirrored motion и Settings migration.

Изменение любого из этих пунктов записывается в [`DECISIONS.md`](DECISIONS.md), а затронутые критерии срезов обновляются до продолжения реализации.
