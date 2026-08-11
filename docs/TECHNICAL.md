# Qipli — технический контракт

Статус: архитектура MVP

Дата базовой проверки платформы: 2026-08-06; S004 input/panel contracts перепроверены: 2026-08-08; Accessibility identity/release signing перепроверены: 2026-08-09

Поддерживаемая платформа: macOS 14+

## 1. Выбранный технический профиль

Qipli — нативное menu bar приложение на Swift. Интерфейс строится на SwiftUI там, где это не мешает управлению окнами, и на AppKit для `NSStatusItem`, плавающих `NSPanel`, активации приложений и точного контроля фокуса. Системные события клавиатуры обрабатываются через Core Graphics event tap. История хранится локально через Core Data с SQLite-backed store.

Приложение распространяется напрямую через GitHub Releases, подписывается Developer ID, использует Hardened Runtime и проходит notarization. App Sandbox для MVP не включается: выбранный сценарий требует Accessibility API и управления событиями других приложений, а Apple перечисляет использование accessibility API в assistive apps среди действий, несовместимых с App Sandbox.

## 2. Потребности и возможности платформы

| ID | Потребность | Компонент | Статус | Основание и контроль |
|---|---|---|---|---|
| NEED-001 | Видеть изменения общего буфера | `NSPasteboard.general` и `changeCount` | supported | Apple документирует общий pasteboard и счётчик смены владельца. Проверить polling и self-write suppression на macOS 14/15 в S002. |
| NEED-002 | Глобально перехватывать активный `⌘V` и отправлять синтетическую вставку | `CGEvent` event tap + Accessibility trust | supported с разрешением | Apple документирует создание/включение event tap и проверку `AXIsProcessTrustedWithOptions`. Проверить на чистой macOS 14 в S001. |
| NEED-003 | Показывать компактные панели поверх приложений | AppKit `NSPanel` + SwiftUI content | supported | Стандартная нативная оконная модель; проверить focus/non-activating поведение в S001/S003. |
| NEED-004 | Хранить и удалять локальную 30-дневную историю | Core Data SQLite store в Application Support | supported | Локальный компонент приложения, внешняя платформа не требуется. Проверить миграцию, purge и восстановление после ошибки в S002. |
| NEED-005 | Распространять бинарник вне Store | Developer ID + Hardened Runtime + notarization | supported | Apple поддерживает direct distribution и требует Hardened Runtime для notarization. Проверить credentials и release workflow перед S008. |
| NEED-006 | Работать в Mac App Store с выбранным event-control дизайном | App Sandbox | unsupported для MVP | App Store требует sandbox; Apple указывает несовместимость accessibility API assistive apps с sandbox. Mac App Store исключён из MVP. |

### Авторитетные источники

- Apple, [`NSPasteboard`](https://developer.apple.com/documentation/appkit/nspasteboard), [`changeCount`](https://developer.apple.com/documentation/appkit/nspasteboard/changecount) и [`clearContents()`](https://developer.apple.com/documentation/appkit/nspasteboard/clearcontents()): ownership changes advance `changeCount`, while `clearContents()` returns the resulting count.
- Apple, [`CGEvent`](https://developer.apple.com/documentation/coregraphics/cgevent), включая event taps, и [`tapEnable`](https://developer.apple.com/documentation/coregraphics/cgevent/tapenable(tap:enable:)).
- Apple, [`CGEventTapOptions.defaultTap`](https://developer.apple.com/documentation/coregraphics/cgeventtapoptions/defaulttap): active filter может возвращать `nil`, чтобы потребить exact event; passive tap не может менять stream. Callback вызывается на run loop, а разрешение/маска могут сделать создание tap недоступным.
- Apple, [`NSWindowDelegate.windowShouldClose(_:)`](https://developer.apple.com/documentation/appkit/nswindowdelegate/windowshouldclose(_:)) и [`NSWindow.orderOut(_:)`](https://developer.apple.com/documentation/appkit/nswindow/orderout(_:)): delegate перехватывает user close reusable panel, а `orderOut` скрывает её без release.
- Apple, [Human Interface Guidelines: Materials](https://developer.apple.com/design/human-interface-guidelines/materials) и [Adopting Liquid Glass](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass): Liquid Glass образует функциональный слой, применяется умеренно, а `regular` предпочтителен для text-heavy surfaces и системно адаптируется к Reduce Transparency/Increase Contrast.
- Apple, [`NSGlassEffectView`](https://developer.apple.com/documentation/appkit/nsglasseffectview) и [`NSVisualEffectView`](https://developer.apple.com/documentation/appkit/nsvisualeffectview): настоящий AppKit glass доступен с macOS 26, тогда как semantic visual-effect material является fallback для deployment target macOS 14.
- Apple, [`CGEvent.post(tap:)`](https://developer.apple.com/documentation/coregraphics/cgevent/post(tap:)): tagged synthetic Copy входит в Quartz event stream перед taps в выбранной позиции; [`eventSourceUserData`](https://developer.apple.com/documentation/coregraphics/cgeventfield/eventsourcuserdata) содержит 64-bit marker, а [`CGEventSource`](https://developer.apple.com/documentation/coregraphics/cgeventsource) описывает state generated/posted events.
- Apple, [`NSWindow.CollectionBehavior.canJoinAllSpaces`](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/canjoinallspaces) и [`fullScreenAuxiliary`](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/fullscreenauxiliary): вспомогательная panel показывается во всех Spaces и рядом с full-screen window.
- Apple, [`NSScreen`](https://developer.apple.com/documentation/appkit/nsscreen): список displays и `visibleFrame` для placement временной panel.
- Apple, [`AXIsProcessTrustedWithOptions`](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions).
- Apple, [`TN3127: Inside Code Signing — Requirements`](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements) и [`Creating distribution-signed code for macOS`](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac): privacy permission identity следует designated requirement; ad-hoc `Sign to Run Locally` привязан к exact build и не является стабильной identity между сборками.
- Apple, [Protecting user data with App Sandbox](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox) и [App Sandbox](https://developer.apple.com/documentation/security/app-sandbox).
- Apple, [Preparing your app for distribution](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution), [Hardened Runtime](https://developer.apple.com/documentation/security/hardened-runtime) и [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

Базовые ссылки и выводы проверены 2026-08-06. S006/S007 повторно сверили scoped input/panel contracts 2026-08-08: `.defaultTap` как active filter (только он может вернуть `nil` и удалить exact event), callback run-loop delivery, permission/mask failure, 64-bit `eventSourceUserData`, ownership `changeCount` и `clearContents()` result; `windowShouldClose(_:)` как user-close interception и `orderOut(_:)` для hiding reusable nonactivating panel. S009 design recheck 2026-08-08 подтвердил HIG material hierarchy и local macOS 26 SDK availability `NSGlassEffectView` при сохранении `NSVisualEffectView` fallback. Release, sandbox/entitlements и остальные platform sources этим recheck не подтверждаются и должны быть перепроверены перед изменением соответствующих контрактов и перед S008.

## 3. Компоненты и ответственность

```text
System pasteboard ──> PasteboardMonitor ──> HistoryService ──> Core Data
                              │                    │
                              └──> StackSession    └──> HistoryViewModel
                                      │                    │
Keyboard event tap ──> InputCoordinator             History NSPanel
                              │
                              ├──> StackSession ──> Stack NSPanel
                              └──> PasteExecutor ──> prior frontmost app
```

### Application shell

- управляет жизненным циклом menu bar utility и единственным экземпляром приложения;
- предоставляет команды «История», «Начать/закрыть Paste Stack», состояние разрешения и «Выйти»;
- создаёт панели истории и стека, не смешивая оконную логику с доменными правилами.

### PasteboardMonitor

- периодически сравнивает `NSPasteboard.general.changeCount` с последним обработанным значением;
- извлекает только неизменённое строковое представление;
- передаёт exact observed `changeCount`; Stack capture snapshot-ит identity активной session и её start watermark до deferred main-actor обработки, чтобы copy до Start или от отменённой session не попало в новую session;
- распознаёт изменения, созданные самим Qipli, и не возвращает их в capture pipeline;
- сериализует обработку, чтобы быстрые изменения не меняли порядок.

Частота polling — настраиваемая реализационная константа, которую выбирают по тестам энергопотребления и потери быстрых копирований; продуктовый контракт не задаёт выдуманный интервал.

### HistoryService

- является единственной точкой записи, поиска, удаления и retention cleanup;
- не отдаёт записи, чья последняя активность старше или равна 30 дням, даже если фоновая очистка ещё не завершилась;
- поддерживает отдельные одинаковые события;
- выполняет очистку при запуске, перед выдачей результатов и периодически при длительной работе;
- при «Очистить всё» уничтожает/пересоздаёт persistent store либо эквивалентно удаляет основную БД и sidecar-файлы после закрытия соединений.

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

### Panel material boundary

- `PanelController` сохраняет ownership, lifecycle, activation, focus, close delegate, level, Spaces/full-screen и display-placement contracts; material wrapper не принимает feature decisions;
- один AppKit factory/provider оборачивает existing `NSHostingView` каждой History/Paste Stack/Permission panel в ровно один outer material surface;
- на macOS 26+ provider использует `NSGlassEffectView` style `regular`; вызов закрыт `#available(macOS 26.0, *)`, поэтому deployment target остаётся macOS 14;
- на macOS 14–25 provider использует `NSVisualEffectView` с semantic `.popover` material, `.behindWindow` blending и system-managed state; implementation не имитирует Liquid Glass custom blur/shader;
- panel использует `.fullSizeContentView` вместе с clear nonopaque background и transparent title bar, поэтому outer material покрывает native title bar; feature-owned `NSHostingView` constraint’ится к `contentLayoutGuide`, чтобы не попасть под traffic lights/toolbar area при сохранённых titled/closable chrome, dragging и accessibility semantics;
- Lists, rows и individual controls не получают отдельные custom glass layers. На macOS 26 standard controls принимают актуальное системное оформление автоматически;
- system labels/selection colors и accessibility settings определяют contrast. Reduce Transparency может сделать surface непрозрачнее, и код не пытается обходить этот выбор пользователя;
- capability selection имеет injected deterministic seam, но ни tests, ни provider не читают clipboard payload.

## 4. Критические последовательности

### Захват внешнего копирования

1. Monitor замечает новый `changeCount`.
2. Self-write registry подтверждает, что изменение не принадлежит Qipli.
3. Monitor читает текст ровно один раз и передаёт observed `changeCount`; перед deferred work snapshot-ятся optional active Stack session UUID и start watermark.
4. `HistoryService` сначала сохраняет запись; только после успеха StackSession с тем же UUID получает отдельный occurrence, если observed `changeCount` строго больше watermark. Отмена/новый Start между этими шагами или write до Start оставляет событие только в History.
5. UI обновляется из наблюдаемого состояния; ошибка хранения не маскируется.

Порядок «сначала история, потом стек» гарантирует, что отмена/сбой стека не оставит значение только в памяти.

### Сбор Paste Stack (S004)

1. Deferred global `⌘⇧C` action snapshots/starts session with current pasteboard `changeCount`, показывает nonactivating panel и только затем dispatch-ит tagged ordinary `⌘C`; repeated hotkey сохраняет session/occurrences, но повторяет Copy. Target app остаётся active и владеет resulting pasteboard write.
2. Menu Start создаёт одну пустую session без Copy; menu меняется на Cancel.
3. Resulting target-owned pasteboard change не self-write и не append-ится напрямую: Monitor → HistoryService → matching StackSession сохраняет History-first/watermark guarantees. Если tagged Copy dispatch observable fails, panel показывает retryable error; отсутствие pasteboard change у target не заявляется как capture error.
4. Stack panel — `NSPanel` с `.nonactivatingPanel`, floating level, `.canJoinAllSpaces` и `.fullScreenAuxiliary`; она не вызывает App activation или `makeKey`.
5. Перед показом panel выбирается `NSScreen` под курсором (fallback main/first screen), а чистая placement function центрирует компактный frame и clamp-ит origin к `visibleFrame` этого display.
6. Exact global Escape или close/cancel освобождает только StackSession и скрывает panel; записи History не затрагиваются.

### Вставка из истории

1. До активации history panel сохраняются frontmost application и контекст, достаточный для возврата.
2. Явный `⌘⇧V`/menu action сначала делает History panel visible, затем через единственный AppKit adapter запрашивает strong user-initiated activation; после `isActive` panel вновь становится key и получает focus поиска. После order-front свежий показ подаёт отдельный viewport-reset signal: список уже перечитан и выбран первый entry, поэтому на следующем main-run-loop turn он non-animated прокручивается к нему с top anchor. Paste-failure reopen не подаёт этот signal и сохраняет retry context. Legacy API допускается только в этом adapter, поскольку cooperative `activate()` не гарантирует keyboard focus accessory app.
3. По `Enter` immutable selected text становится внутренней записью в system pasteboard, а exact final `changeCount` сразу регистрируется как self-write.
4. Пока Qipli ещё active, оно yield/request-activates прежнее приложение. Если macOS немедленно отклоняет запрос, History остаётся visible, команда не отправляется и UI показывает retryable error.
5. History остаётся visible, пока Qipli ждёт bounded deadline с main-run-loop retries для обновления `NSRunningApplication.isActive`; только при active target panel закрывается непосредственно перед synthetic `⌘V`.
6. После accepted-but-exhausted activation History остаётся in place с ошибкой; после dispatch failure закрытая panel повторно открывается. В обоих случаях pasteboard не переписывается и команда не дублируется.
7. Только после успешной отправки tagged `⌘V` `PanelController` неблокирующе обновляет activity exact selected ID. Ошибка этого durable update не меняет уже успешный результат paste и не вызывает повторную отправку.
8. UI сообщает только об отправке команды; реальное принятие текста сторонним приложением наблюдать надёжно нельзя.

### Вставка из Paste Stack

1. Active event tap получает exact untagged ordinary `⌘V` keyDown. Если Stack inactive, завершён, пуст или input tagged/modified, он возвращает original event. При accepted input `StackSession` synchronously reserves exact pending UUID by direct/reverse traversal либо selected used reactivation-priority UUID and locks direction/order; repeat while reserved is consumed without another transaction. Exact `⌘⇧Z` может только назначить последнюю successfully dispatched occurrence priority и возвращает original event во всех остальных состояниях.
2. Deferred main-run-loop executor publishes processing state, rechecks the same session UUID/reservation and Accessibility trust, then writes the immutable exact text to system pasteboard.
3. Writer returns the exact final `changeCount`; monitor receives that count as a self-write before control returns to its next poll, so the write cannot re-enter History/Stack capture.
4. Executor posts tagged synthetic ordinary `⌘V`. Only a successful dispatch converts the exact reservation to used; a permission, writer, dispatch or input-listener failure returns traversal reservation to pending but returns reactivation reservation to used while retaining priority, then publishes a retryable non-payload error.
5. Used occurrences remain visible and disabled; one Reactivate action or `⌘⇧Z` priority is marked separately from traversal Next. Append/cancel/deferred UI intents validate the current session/UUID domain atomically.
6. After the last successful dispatch, all occurrences are first published as used. One deterministic deferred turn verifies the same session is still complete and has no reactivation priority, then releases it, closes the nonactivating panel and restores the menu Start state. A reactivation before that turn prevents finish; it does not reactivate a target app.

При гонке с внешней сменой pasteboard предпочтение отдаётся безопасности: не вставлять неизвестное значение как элемент стека, показать сбой и сохранить текущую сессию для повтора.

## 5. Данные

### HistoryEntry — persisted

Минимальный продуктовый контракт:

| Поле | Назначение |
|---|---|
| `id` | стабильный локальный UUID записи |
| `text` | исходная строка без нормализации |
| `activityAt` | последняя активность: initial capture либо успешно отправленная history paste-команда; задаёт порядок и retention |

Domain property называется `activityAt`, но SQLite/Core Data attribute key остаётся `capturedAt` для совместимости с уже созданными user stores; он хранит то же activity значение и не требует migration. Индекс по legacy key `capturedAt` обязателен. Дополнительное поисковое поле или индекс допустимы после профилирования, но не должны менять исходный `text`. Метаданные приложения-источника в MVP не сохраняются.

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

### Владение и жизненный цикл

- Store находится в Application Support текущего пользователя и не синхронизируется через iCloud.
- Qipli не создаёт сетевых копий, резервных копий или экспортов.
- Просроченные записи исключаются из запросов синхронно с пользовательской точки зрения и удаляются из store обслуживающей операцией.
- Удаление отдельной записи и auto-prune — логическое удаление; из-за SQLite/SSD приложение не обещает forensic secure erase.
- «Очистить всё» должно удалить управляемые store/SQLite/WAL/SHM файлы после безопасного закрытия store, но также не заявляется как secure erase накопителя.

## 6. Разрешения и безопасность

- До запроса Accessibility приложение объясняет, что разрешение нужно для глобальных сочетаний и отправки вставки в активное стороннее приложение.
- Проверка доверия выполняется официальным API; отказ пользователя оставляет просмотр, поиск и удаление доступными, но блокирует системную вставку и Paste Stack с явным объяснением.
- Изменение Accessibility в System Settings обнаруживается автоматически: во время собственного permission flow Qipli выполняет bounded polling, а при возвращении в приложение — немедленный recheck. Одинаковое состояние повторно не публикуется и не пересоздаёт здоровый event tap.
- App Sandbox выключен только по причине основного системного сценария; Hardened Runtime остаётся включённым, исключения добавляются только при доказанной необходимости.
- В release-конфигурации нет network client/server entitlement, аналитики и автоматической отправки crash reports.
- Clipboard text, поисковые запросы и превью не попадают в логи, `print`, signpost metadata или имена файлов.
- UI предупреждает, что автоматической фильтрации секретов нет. Preview должен избегать лишнего раскрытия длинного текста, но полное значение остаётся доступным пользователю.
- Все операции с Core Data выполняются в последовательной модели конкурентности; UI не получает managed objects, привязанные к чужому context.

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
  PasteStack/        state machine, panel feature
  Input/             permissions, hotkeys, event tap, paste executor
  Shared/            narrowly shared types and utilities
QipliTests/           domain and adapter-contract tests
QipliUITests/         in-app keyboard and panel flows
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
- build: Debug и Release для deployment target macOS 14.

### Вручную на чистой системе

- выдача, отказ и последующее включение Accessibility;
- сценарии PJ-001 и PJ-002 в матрице приложений;
- быстрые последовательные копирования и одинаковые строки;
- sleep/wake, повторный запуск, отключение event tap системой;
- удаление истории и проверка отсутствия её записей после перезапуска;
- запуск подписанного notarized артефакта, Gatekeeper и повторная проверка разрешения после обновления.
- S009 visual matrix на macOS 26+ и fallback macOS 14–25: все панели, Light/Dark, Reduce Transparency, Increase Contrast, разные desktop backgrounds, focus/nonactivation и clean console.

## 10. Сборка и распространение

- Xcode project/Swift package configuration хранится в репозитории; зависимости по возможности ограничены системными frameworks.
- Deployment target — macOS 14. Архитектуры релизного бинарника должны быть явно выбраны в S008 по доступной build-инфраструктуре; universal binary предпочтителен, но пока является предположением.
- Debug может использовать development signing. Локальный устанавливаемый ZIP создаётся только `scripts/package-local.sh` со стабильной `Apple Development` identity; ad-hoc `Sign to Run Locally` отклоняется и не должен использоваться для проверки сохранения TCC-разрешения между rebuilds.
- Public release создаётся только `scripts/package-release.sh`: Developer ID Application, Hardened Runtime, secure timestamp, notarization через Keychain profile, stapled ticket и повторная проверка распакованного ZIP. Pipeline fail-closed отклоняет ad-hoc/no-Team-ID, `get-task-allow`, App Sandbox/network entitlements, неверный bundle/minimum OS, non-universal binary, `FinderInfo`/resource-fork metadata, отсутствие stapled ticket или Gatekeeper acceptance.
- Release artifact публикуется через GitHub Releases вместе с checksum и краткими инструкциями по Accessibility и локальному хранению.
- Notarization требует внешней сети и Apple credentials только в release pipeline; работа установленного Qipli от них не зависит.

Локальная package-команда требует full certificate name из `security find-identity -v -p codesigning`:

```sh
QIPLI_DEVELOPMENT_TEAM=TEAM_ID \
QIPLI_APPLE_DEVELOPMENT_IDENTITY='Apple Development: Name (TEAM_ID)' \
scripts/package-local.sh
```

Public release использует Developer ID certificate и заранее сохранённый `notarytool` Keychain profile:

```sh
QIPLI_DEVELOPMENT_TEAM=TEAM_ID \
QIPLI_DEVELOPER_ID_APPLICATION='Developer ID Application: Name (TEAM_ID)' \
QIPLI_NOTARY_PROFILE=qipli-notary \
scripts/package-release.sh
```

## 11. Технические предположения и точки перепроверки

- Core Data достаточно для объёма 30-дневной текстовой истории; до оптимизации нужно измерить реальный объём и поиск на репрезентативном локальном наборе.
- Одного Accessibility-разрешения достаточно для выбранного event tap/paste flow на macOS 14+; S001 обязан проверить это на чистом профиле и не скрывать дополнительное системное требование, если оно появится.
- Developer ID учётная запись и signing credentials будут доступны к S008; отсутствие credentials не блокирует S001–S007.
- Menu bar оболочка и отсутствие Dock icon — предложение агента, а не решение из исходного брифа.
- Universal release (Apple Silicon + Intel) — предпочтение, которое нужно подтвердить доступной CI/build-машиной перед S008.

Изменение любого из этих пунктов записывается в [`DECISIONS.md`](DECISIONS.md), а затронутые критерии срезов обновляются до продолжения реализации.
