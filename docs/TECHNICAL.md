# Qipli — технический контракт

Статус: архитектура MVP

Дата проверки платформы: 2026-08-06

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

- Apple, [`NSPasteboard`](https://developer.apple.com/documentation/appkit/nspasteboard) и [`changeCount`](https://developer.apple.com/documentation/appkit/nspasteboard/changecount).
- Apple, [`CGEvent`](https://developer.apple.com/documentation/coregraphics/cgevent), включая event taps, и [`tapEnable`](https://developer.apple.com/documentation/coregraphics/cgevent/tapenable(tap:enable:)).
- Apple, [`AXIsProcessTrustedWithOptions`](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions).
- Apple, [Protecting user data with App Sandbox](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox) и [App Sandbox](https://developer.apple.com/documentation/security/app-sandbox).
- Apple, [Preparing your app for distribution](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution), [Hardened Runtime](https://developer.apple.com/documentation/security/hardened-runtime) и [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

Ссылки и выводы проверены 2026-08-06. Их нужно перепроверить перед изменением способа распространения, sandbox/entitlements, минимальной macOS или механизма глобального ввода, а также перед S008.

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
- передаёт внешнее событие в историю и, если активен стек, в текущую сессию;
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

- чистая тестируемая state machine в памяти;
- владеет списком occurrence, базовым порядком, направлением, состояниями pending/next/used и одноразовым приоритетом reactivated;
- не пишет отдельную «сохранённую очередь» в Core Data;
- завершает сессию при отсутствии активных элементов или явной отмене.

### InputCoordinator и PasteExecutor

- регистрируют глобальные сочетания и event tap только в разрешённом состоянии, включая `Esc` как отмену только при активном стеке;
- active event tap потребляет только exact untagged `⌘⇧V` и `⌘⇧C` keyDown, чтобы target app не исполнил собственную команду до открытия Qipli; обычный `⌘V`, другие modifiers и Qipli synthetic events проходят без изменения;
- не модифицируют обычный `⌘V`, когда стек не активен;
- перед внутренней записью помечают ожидаемый `changeCount`/операцию, чтобы монитор пропустил self-write;
- быстро подготавливают следующий текст в pasteboard и отправляют/пропускают событие вставки, не блокируя event tap тяжёлой работой;
- помечают элемент used после отправки команды вставки, а не после недоступного подтверждения целевого поля;
- распознают собственное синтетическое событие, чтобы избежать рекурсии;
- реагируют на системное отключение event tap, пытаются безопасно переустановить его и показывают ошибку при неуспехе.

## 4. Критические последовательности

### Захват внешнего копирования

1. Monitor замечает новый `changeCount`.
2. Self-write registry подтверждает, что изменение не принадлежит Qipli.
3. Monitor читает текст ровно один раз и передаёт событие в `HistoryService`.
4. После успешного сохранения активная `StackSession` получает отдельный occurrence того же события.
5. UI обновляется из наблюдаемого состояния; ошибка хранения не маскируется.

Порядок «сначала история, потом стек» гарантирует, что отмена/сбой стека не оставит значение только в памяти.

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

1. Event tap получает пользовательский `⌘V` при активной сессии.
2. Coordinator атомарно запрашивает у state machine следующий occurrence.
3. Текст записывается в pasteboard как self-write, затем `⌘V` передаётся цели без рекурсивного перехвата.
4. Occurrence помечается used; панель показывает его disabled.
5. Если ожидающих элементов не осталось, сессия завершается и панель закрывается.

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
| `state` | pending, next или used |
| `reactivationPriority` | временный признак «вставить следующим» |

### Владение и жизненный цикл

- Store находится в Application Support текущего пользователя и не синхронизируется через iCloud.
- Qipli не создаёт сетевых копий, резервных копий или экспортов.
- Просроченные записи исключаются из запросов синхронно с пользовательской точки зрения и удаляются из store обслуживающей операцией.
- Удаление отдельной записи и auto-prune — логическое удаление; из-за SQLite/SSD приложение не обещает forensic secure erase.
- «Очистить всё» должно удалить управляемые store/SQLite/WAL/SHM файлы после безопасного закрытия store, но также не заявляется как secure erase накопителя.

## 6. Разрешения и безопасность

- До запроса Accessibility приложение объясняет, что разрешение нужно для глобальных сочетаний и отправки вставки в активное стороннее приложение.
- Проверка доверия выполняется официальным API; отказ пользователя оставляет просмотр, поиск и удаление доступными, но блокирует системную вставку и Paste Stack с явным объяснением.
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
- UI: focus поиска, arrows, selection, empty/no-results, stack states и drag reorder внутри Qipli;
- build: Debug и Release для deployment target macOS 14.

### Вручную на чистой системе

- выдача, отказ и последующее включение Accessibility;
- сценарии PJ-001 и PJ-002 в матрице приложений;
- быстрые последовательные копирования и одинаковые строки;
- sleep/wake, повторный запуск, отключение event tap системой;
- удаление истории и проверка отсутствия её записей после перезапуска;
- запуск подписанного notarized артефакта, Gatekeeper и повторная проверка разрешения после обновления.

## 10. Сборка и распространение

- Xcode project/Swift package configuration хранится в репозитории; зависимости по возможности ограничены системными frameworks.
- Deployment target — macOS 14. Архитектуры релизного бинарника должны быть явно выбраны в S008 по доступной build-инфраструктуре; universal binary предпочтителен, но пока является предположением.
- Debug может использовать development signing. Public release: Developer ID Application, Hardened Runtime, secure timestamp, notarization и stapled ticket.
- Release artifact публикуется через GitHub Releases вместе с checksum и краткими инструкциями по Accessibility и локальному хранению.
- Notarization требует внешней сети и Apple credentials только в release pipeline; работа установленного Qipli от них не зависит.

## 11. Технические предположения и точки перепроверки

- Core Data достаточно для объёма 30-дневной текстовой истории; до оптимизации нужно измерить реальный объём и поиск на репрезентативном локальном наборе.
- Одного Accessibility-разрешения достаточно для выбранного event tap/paste flow на macOS 14+; S001 обязан проверить это на чистом профиле и не скрывать дополнительное системное требование, если оно появится.
- Developer ID учётная запись и signing credentials будут доступны к S008; отсутствие credentials не блокирует S001–S007.
- Menu bar оболочка и отсутствие Dock icon — предложение агента, а не решение из исходного брифа.
- Universal release (Apple Silicon + Intel) — предпочтение, которое нужно подтвердить доступной CI/build-машиной перед S008.

Изменение любого из этих пунктов записывается в [`DECISIONS.md`](DECISIONS.md), а затронутые критерии срезов обновляются до продолжения реализации.
