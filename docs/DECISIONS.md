# Qipli — журнал решений

Дата актуализации: 2026-08-07

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
