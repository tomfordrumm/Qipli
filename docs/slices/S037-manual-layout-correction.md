---
id: S037
title: Исправление раскладки по хоткею
depends_on:
  - S001
  - S010
covers:
  - FR-053
  - FR-054
  - BR-039
  - BR-040
  - NFR-037
---

# S037: Исправление раскладки по хоткею

## Пользовательский результат

Пользователь набрал `ghbdtn`, нажал хоткей и получил `привет` в том же поле. Если выделена фраза `ghbdtn vbh`, Qipli заменяет именно выделение на `привет мир`. Обратное исправление также доступно. Это преобразование по расположению клавиш, а не транслитерация или перевод.

Запрос от 2026-10-01 подтверждает ручное исправление только что введённого или выделенного текста. Пользователь отдельно подтвердил последнее введённое слово, включая слово сразу перед пробелом, выбрал левый Option и попросил использовать раскладки, включённые в системе. При трёх и более раскладках подтверждён переход по кругу; повторный левый Option переводит тот же фрагмент дальше. Остальные предлагаемые defaults ниже остаются предположениями. Источники: раздел S037 в [PRODUCT.md](../PRODUCT.md) и [TECHNICAL.md](../TECHNICAL.md), D-050 в [DECISIONS.md](../DECISIONS.md). Operational-статус ведётся только в [STATE.md](../STATE.md).

## Актуальное поведение D-056

Контракт [D-056](../DECISIONS.md#d-056-copypaste-выделения-и-replay-недавнего-слова) заменяет AX replacement D-052. Выделение получает приоритет через native Copy, заменяется Paste. Без выделения недавнее слово восстанавливается из bounded physical-key buffer и заменяется Backspace + Unicode replay. Системные enabled/selectable static layouts и циклический seed сохраняются. Не требуются writable AXValue, AXStringForRange или character count. Единственный metadata preflight защищает текстовый focus/password; неизменный PID/input epoch проверяется перед отправками.

Buffer ≤256 keys, trailing spaces ≤8, freshness/automatic payload release 5 s. Навигация, click, modified input, source/app/settings/tap/permission changes сбрасывают buffer. После native replacement caret находится в конце; native Undo grouping определяется target. Cycle 5 s idle/30 s hard, без AX verification и без blind retry после mutation. Copy clipboard transaction сохраняет исходные representations, подавляет внутренний capture и уважает более новую Copy.

## Acceptance и verification D-056

- [x] Production shell использует native transport, не AX text/range replacement.
- [x] Selection Copy/Paste имеет приоритет, пустое AX выделение позволяет сразу replay слова; отсутствие range API не блокирует Copy.
- [x] Physical-key buffer bound/TTL/reset, Shift/Caps mapping, trailing spaces и synthetic exclusion покрыты tests.
- [x] Cycle использует seed исходной раскладки, input/PID/source races прекращают операцию без retry; ошибки после отправки говорят о возможном частичном изменении.
- [x] Clipboard original representations/empty clipboard/newer external Copy и suppression до exact Copy count покрыты tests.
- [x] SwiftPM full suite и signed universal Debug build.
- [x] Новый production native transport: signed owned-field selection/word/+0/+3 spaces/12 288 UTF-16, actual text/caret/clipboard и single native Undo. Source switch mock; cycle проверен unit tests.
- [x] Final Cut effects search: оба production transport пути проверены на synthetic `ghbdtn → привет`, результат подтверждён повторным Copy, поле очищено.
- [ ] Final Cut title/text editing: реальный левый Option, cycle/TIS и Undo/clipboard matrix. Nontext timeline refusal покрыт injected metadata test; live timeline mutation не выполнялась.
- [ ] Installed app/macOS14/permission/source/VoiceOver matrix и release/update gates.

### Implementation report D-056, 2026-10-15

Рабочий native transport выполняет один metadata-only text/password preflight на AX worker, native Copy с ожиданием свежего changeCount и один Paste либо tagged Backspace/Unicode replay. Полные AX text/range capabilities не нужны. Unicode events делятся по composed-character boundaries до 20 UTF-16 units; неподдерживаемый oversized grapheme отклоняется до удаления. Source переключается только после dispatch; completed не является AX postcondition. Старый adapter остаётся историческим probe/test utility.

Final SwiftPM run: 365 tests, 0 failures/skips; focused run 66/66. Подписанный arm64+x86_64 Debug и unsigned universal Release builds PASS. Shell native-probe launch не получил AX trust; LaunchServices run после bounded owned-fixture activation прошёл все четыре cases. Verification harness ограниченно ждёт фактического принятия native input; это ожидание не добавлено обратно в production AX pipeline. Owned NSTextView подтвердил native Undo одним действием, но это не универсальный контракт.

Final Cut live smoke, 2026-10-15: `scripts/probes/s037/S037FinalCutProbe.swift` допускает только наблюдавшийся effects-search identifier и exact synthetic seed, сохраняет clipboard через production lease. Copy/Paste PASS 1196 ms; Backspace/Unicode replay PASS 1514 ms. Оба результата прочитаны повторным Copy и сравнены без payload logging. TIS/trigger в этом transport probe не исполнялись. UI automation не смог отправить отдельный Option, поэтому installed gesture gate остаётся открытым. Синтетическое поле очищено, documents/timeline не изменялись. После explicit user approval Release временно остановлена для исключения captures тестовых Copy и запущена снова; Dev/probes завершены.

Reproduction: `S037_PROBE_SIGNING_IDENTITY='<local Apple Development identity>' bash scripts/probes/s037/build-native-paste.sh` создаёт owned-field harness. `bash scripts/probes/s037/build-final-cut.sh` с тем же signing env создаёт selection transport probe; `S037_FINALCUT_SWIFT_FLAGS='-D S037_WORD_PROBE'` выбирает word transport. Final Cut probe запускать только при согласованном smoke, с остановленной второй Qipli, пустым effects search, вручную подготовленным `ghbdtn` и последующей очисткой. Он отказывает при другом identifier/seed. Payload-free reports находятся в `/private/tmp/qipli-s037-native-paste-report.txt`, `/private/tmp/qipli-s037-final-cut-selection-report.txt` и `/private/tmp/qipli-s037-final-cut-report.txt`.

## Исторический контракт D-052, superseded в production D-056

Следующие исходные acceptance/probe snapshots описывают предыдущий AX adapter. Они не являются acceptance новой реализации.

## Приватность и взаимодействие с Qipli

Актуальный replacement/input contract: [D-052](../DECISIONS.md#d-052-исправление-последнего-слова-по-запросу-и-native-paste). Обязательный baseline D-051 заменён on-demand capture. Transport выбирается до mutation: ownership-checked native paste при доступном clipboard snapshot либо single Unicode event без clipboard mutation; после dispatch нет повторов.

Текст читается только по явному хоткею из текущего допустимого editable element. Постоянный буфер набранных символов, журнал клавиш и сохранение текста отсутствуют. Текст операции живёт только в памяти и освобождается после завершения/отмены. Secure Input, secure/password element, read-only element и неопределённый focus исключают операцию до чтения payload. Existing History password-field opener этим ограничением не меняется.

Явная correction может временно использовать system clipboard по D-052: bounded in-memory snapshot, exact-count self-write suppression, ownership-checked restore; newer external Copy сохраняется. Если snapshot недоступен/oversized, single Unicode transport оставляет clipboard нетронутым. History/Stack items не создаются, used-state не меняется. При active Stack, pending Finder Cut, Qipli-focused UI или другой in-flight Qipli input operation операция отклоняется, а результат показывается inline в Settings и в transient панели по D-053. Ordinary `⌘V`, `⌘X`, `Esc` и все чужие shortcuts сохраняют свои существующие owners.

## Вне scope

Автоматическое определение ошибок при наборе, автопереключение без явного действия, словари, исключения по словам, исправление орфографии, перевод/транслитерация, история набранного текста, восстановление после relaunch и работа в password fields. Terminal commands, multiple cursors, rich-text attributes/attachments и IME composition не получают обещания поддержки до отдельного решения. Не выполнять terminal fallback через Backspace: он может затронуть команду или отправить её.

## Обязательный platform probe

Проводится до основной реализации на synthetic тексте в development-signed Qipli Dev, macOS 14+.

1. Проверить left/right Option через `flagsChanged` и physical key code. Текущий adapter слушает только `keyDown`. Проверить down/up, chords, dead keys, Option-click, удержание, tap disable/recovery, sleep/wake и отсутствие ложного trigger. Callback не читает AX/pasteboard и не выполняет преобразование.
2. На representative plain-text fields в TextEdit, browser input/textarea и других app frameworks проверить focused editable element, selected text/range и bounded public AX range reads. Для каждого field фиксировать read/write/selection/undo capabilities; наличие API не доказывает совместимость. Это evidence для per-field admission rules, не app allowlist.
3. `AXSelectedText` в текущем SDK объявлен read-only. Не предполагать переносимую запись в него. Проверить путь AX selected range → tagged Unicode input через `CGEvent.keyboardSetUnicodeString`; Apple предупреждает, что frameworks могут игнорировать Unicode string. Не устанавливать целиком `AXValue` поля и не заменять текст слепым числом Backspace.
4. Проверить сохранение соседнего текста, UTF-16 ranges с emoji/combining marks, selection/caret и native single-step Undo. Обнаружить read-only/secure fields до чтения. Отдельно проверить IME/dead-key composition; если безопасную admission нельзя доказать, эта комбинация не поддерживается.
5. Между чтением и mutation перепроверять app PID, focused element, selection, исходный диапазон и generation. При изменении focus/текста/selection отменять операцию. После dispatch не делать blind retry, не глушить пользовательский ввод ради ожидания и не заявлять успех по одному факту отправки события. Проверить delayed dispatch и target acceptance.
6. Проверить enumeration enabled/selectable TIS input sources, Unicode keyboard-layout data, physical-key mapping и switch по результату замены. На synthetic тексте проверить RU/EN, дополнительную установленную статическую раскладку и отказ для IME. Проверить ambiguous key mappings, Shift/Caps Lock, источники с одним алфавитом, смену системного списка и режим macOS с запоминанием input source для документов. Не устанавливать/включать новые sources автоматически. Закрепить source attribution первой операции и порядок цикла для трёх и более sources.
7. До реализации определить и записать предел selected text/context, timeout и способ postcondition validation. Превышение лимита даёт отказ без усечения текста. Большой документ не материализуется целиком для поиска последнего слова.

Результат probe: compatibility evidence across representative app frameworks, выбранный replacement adapter, capability rules для focused fields и системных sources/mapping, бюджеты и срок жизни cycle snapshot. Runtime checks решают допуск для каждого поля; evidence одного редактора не обещает поддержку всех полей. Если Unicode/AX не проходит capability/postcondition checks в поле, операция для него отказывается. Не добавлять скрытый `⌘C/⌘V` fallback или постоянный keyboard buffer.

## Этапы поставки

1. Выполнить probe для согласованного левого Option, системных sources, цикла, последнего слова и выделения. Сохранить evidence без пользовательских payloads.
2. Поставить walking skeleton для выделенного plain text: toggle, один trigger, преобразование, свежий target/range, replacement, source switch, Undo и честные ошибки.
3. Добавить сценарий слова перед caret, настройки trigger и per-field capability admission. Оба пользовательских сценария нужны для завершения S037.
4. Пройти regression, installed-app/privacy и обычные signing/update gates перед публичной поставкой. Эти этапы не задают очередность относительно незакрытых существующих slices.

## Acceptance criteria

- [ ] Выделенное `ghbdtn vbh` превращается в `привет мир`, обратный путь работает; соседний текст неизменен.
- [ ] Последнее слово без выделения и слово перед пробелом исправляются по подтверждённой границе; Enter, середина слова и соседние символы не затрагиваются.
- [ ] Проверены case, Caps Lock/Shift, пунктуация, multi-line selection, emoji и combining marks; ambiguous/unsupported/oversize content даёт предсказуемый отказ без частичного изменения.
- [ ] Left Option срабатывает ровно один раз на standalone release. Right Option, Option typing/navigation/click, chords, repeats и recovery не запускают операцию.
- [ ] Системные sources обновляются при изменении enabled списка. Проверены два и три допустимых sources, подтверждённая target policy и unsupported IME без вмешательства в системную настройку.
- [ ] Настройки enable/disable, альтернативный chord, restart и reset не сбрасывают прежние shortcuts; конфликтующий binding не применяется.
- [ ] Focus/range race, secure/read-only/unavailable element, composition, timeout и missing source не приводят к замене чужого текста или blind retry.
- [ ] Selection/caret сохранены, `⌘Z` отменяет текст одним действием; изменение раскладки после успешной замены проверено отдельно от dispatch.
- [ ] Исходные clipboard representations сохраняются побайтно; temporary write/restore меняют changeCount и зарегистрированы как self-writes. Более новая внешняя Copy сохраняется; History/Stack не получают внутренних записей/used-state. Active Stack/Cut и in-flight History paste проходят arbitration.
- [ ] Installed-field capability evidence документирована для representative app frameworks; operation rejects unsupported fields без потери focus. App names не используются как allowlist; keyboard доступен, результат/ошибки показаны inline в Settings без popup/системных уведомлений.
- [ ] Payload не попадает в storage, logs, fixtures с реальными данными, network или telemetry. Permissions/entitlements остаются прежними.

## Verification

- Synthetic mapping/word-boundary tests и gesture state-machine tests, включая сохранение Option-комбинаций и tagged-event exclusion.
- Fake-adapter tests для freshness/generation, limits, cancellation, input owners, partial source-switch failure и postcondition без автоматического retry.
- Installed-app matrix из probe: plain fields, selected/no-selection, source switch, Undo, focus races, permission revoke, Secure Input, dead keys/IME, clipboard integrity и Qipli interactions.
- Focused/full SwiftPM, development-signed universal Debug build и privacy/diff check после реализации. Public delivery отдельно следует [RELEASING.md](../RELEASING.md).

## Implementation report

### Production implementation, 2026-10-02

Реализованы отдельные versioned preferences (off по умолчанию), enable/trigger Settings и видимый порядок enabled static sources; прежние три shortcuts и их migration/reset защищены от новых конфликтов. TIS catalog/classifier snapshots готовятся на main; event tap хранит только агрегатные counters, input/operation epochs и gesture state. Selection имеет приоритет; word path требует baseline до ввода, supported AX notifications и свежий metadata snapshot после ввода. Modifier changes отменяют незавершённую операцию, сохраняя provenance уже введённого слова. Paste/navigation/chords сбрасывают baseline; composition uncertainty не снимается этим сбросом.

`LayoutCorrectionCoordinator` выполняет source attribution и original-seed cycle на serial AX worker, с 5 s idle / 30 s hard TTL и автоматической очисткой capsule. `LayoutCorrectionAXAdapter` проверяет focused field по его фактическим Accessibility capabilities, запрещает Qipli UI/secure/read-only targets, читает только bounded ranges, отправляет один tagged Unicode pair и проверяет actual replacement/neighbors/selection/caret. Приложение не выбирается по bundle allowlist; это не blanket-гарантия совместимости любого editable field. Source switch идёт после verified replacement; ошибка switch не вызывает повторный ввод. Общий deadline 500 ms включает worker queue, каждый AX messaging timeout уменьшается до оставшегося времени и не превышает 150 ms. Active Stack/Cut, in-flight History paste, unavailable tap/permissions и изменённый context запрещают операцию. Ошибки и причины отказа доступны inline в Settings; popup и системных уведомлений нет.

Независимый Luna reviewer выявил два false-negative в fresh-word tracking: постоянный blocked-state после Cmd chord и смешение modifier epoch с text provenance. Они исправлены разделением epochs и сбросом word metadata; root review дополнительно исправил selection admission, замыкание цикла к origin, source refresh, select-capable admission и Caps Lock transition guard. Финальный reviewer recheck нашёл перезапись Settings source-list observer в Shell; callbacks объединены. Повторное read-only review подтвердило исправления, оставшихся concrete findings нет. Probe полностью изолирован в `scripts/probes/s037`, обычные Debug/Release не содержат launch modes.

Дополнительный signed test utility с production AX adapter собран и запущен в режиме проверки прежнего synthetic TextEdit документа. Он отказался до payload read: `productionAXAdapter=SKIPPED; exactOwnedWindow=false; payloadRead=false`. Поэтому новый production adapter runtime PASS не заявляется. Прежний platform replacement/Undo и hardware metadata proof ниже сохраняют только свою исходную область проверки.

Полный SwiftPM прошёл: `312 tests / 0 failures / 0 skips`, включая 26 новых S037 tests (AX admission 6, coordinator 9, model/gesture 9, preferences 2). После последней правки Settings callback повторный focused S037: `26/26`; финальные development-signed universal Debug и unsigned universal Release прошли для arm64/x86_64, strict codesign verification прошёл. PBX lint, diff check, public-readiness/update-privacy audit, version/CI contracts, version-validator 8/8, release-contract 13/13 и Sparkle runtime linking для обеих архитектур прошли. SwiftPM manifest/cache и codesign trust checks использовали доступ к host services; первоначальные sandbox/cache failures не обозначены как product failures. Единственное Xcode warning — пропуск AppIntents metadata extraction при отсутствии зависимости на этот framework.

Installed feature matrix остаётся открытой: selected/last-word/cycle с real event tap в capability-supported fields разных app frameworks, clipboard/changeCount/History/Stack integrity, source/focus/permission races, IME/dead keys, macOS 14, 3+ static sources и document-specific source memory. TextEdit/Chrome probe results остаются отдельными evidence для проверенных конкретных targets. Acceptance checkboxes не закрыты частичными unit/probe результатами. Версия сохранена `1.0.11` / build `12`; функциональная ветка не является release branch, публикация не выполнялась.

### Пользовательский smoke и исправления, 2026-10-02

Пользователь отклонил ограничение TextEdit/Chrome и popup при успешной коррекции, а также сообщил отказ word → Space → left Option. App-name/bundle allowlist удалён: проверяются Accessibility capabilities самого focused field, secure/read-only/unknown focus по-прежнему исключаются. `CorrectionToastController` удалён из Sources/PBX; Shell не показывает popup и не отправляет accessibility announcements, ошибка/причина отказа доступна только inline в Settings.

Найдена воспроизводимая metadata race: tap уже увеличил input epoch для Space, но AX sample ещё содержал курсор до обработки клавиши. Поздний native caret/count update при том же epoch считался навигацией и удалял baseline. `CorrectionWordProgress` сохраняет baseline только при монотонном согласованном росте count/caret в пределах агрегатного input budget; навигация, другой элемент и превышение budget отклоняются. Word coordinator повторно captures target после trigger-time metadata refresh, чтобы не сравнивать свежий sample с прежним caret. Две regression checks покрывают delayed Space и replacement/caret/space preservation. Option-navigation теперь сбрасывает word metadata без ложного composition latch; printable/dead-key Option input остаётся неопределённым для обоих Option, Cmd/Ctrl chords не объявляются composition.

Проверки после исправлений: full SwiftPM 314 tests / 0 failures / 0 skips; development-signed universal Debug и unsigned universal Release, strict codesign verification, PBX lint, diff check и Sparkle runtime linking прошли. Новая Dev сборка: `/private/tmp/qipli-s037-product-check/Build/Products/Debug/Qipli Dev.app`. Эти результаты не заменяют повторный пользовательский word → Space → Option smoke в исходном приложении; точное приложение отказа пока не установлено. Installed feature matrix остаётся открытой.

2026-10-01: подготовлен план по текущему коду, Apple documentation и локальным SDK headers. Runtime probe, реализация, тесты, установленная совместимость и release не выполнялись.


### 2026-10-02: начат development-signed platform probe

Рабочая ветка `feature/manual-layout-correction`, production correction ещё не реализован. Добавлен DEBUG-only `S037PlatformProbe`, opt-in arguments обходят обычный `ApplicationShell` и не запускают History/Stack/capture. Controlled self-fixture проверяется отдельно от внешних приложений. Synthetic browser fixture находится в `scripts/probes/s037-browser-fixture.html` и не содержит scripts, requests или storage.

Проверено на macOS 26.6.2 / Xcode 26.6:

- Signed Qipli Dev через LaunchServices: Accessibility trusted, Secure Input выключен. Прямой terminal launch дал другое TCC attribution; его `false` не означает выключенный Dev toggle.
- Две enabled/selectable static keyboard layouts: physical-key samples подтверждают RU/EN conversion, включая base/Shift/Caps/Shift+Caps. Это inventory/sample evidence, не полная mapping/IME/source-switch matrix.
- Own NSTextView: public selected range readable/settable, range round-trip и bounded `AXStringForRange` прошли. Tagged Unicode key-down заменил только synthetic range; полный synthetic sentinel и caret postcondition прошли.
- Secure/read-only self-fixtures классифицированы по metadata без чтения значений. Read-only value не settable; это не полная installed-app admission matrix.
- Own NSTextView: Undo зарегистрирован, один direct UndoManager undo восстанавливает fixture, но targeted tagged `⌘Z` не восстановил текст. Native keyboard Undo пока не принят; нужен внешний редактор с обычным menu command path.
- Luna harness review выполнен, найденные issues с Unicode key-up, protected fixtures, coarse mapping summary и auto-run completion исправлены. Внешний режим проходит отдельное ревью до запуска.
- SwiftPM: 286 tests, 0 failures, 0 skips. Release contracts: 13/13; version validator: 8/8; version/CI contracts прошли. Unsigned universal Release собран; DEBUG probe отсутствует в executable. Signed universal Debug probe собран. Это не installed-app acceptance или public release proof.

Открыты TextEdit/browser range + native Undo, standalone left/right Option и recovery, recent-word freshness, source switch/цикл, UTF-16/composition/races и budgets. macOS 14 baseline не подтверждён macOS 26.6.2 runtime. Probe status-only report хранится в `/private/tmp/qipli-s037-probe-result.txt`; каждый запуск перезаписывает его, поэтому operational результаты фиксируются здесь без пользовательских payloads.


Внешний TextEdit probe подготовлен с exact synthetic window/selection/sentinel guards, 0.15s AX messaging timeout, bounded reads и одним dispatch без retry. Первый запуск вернул `SKIPPED`, потому что frontmost target не совпал; `payloadReads=0`, replacement не отправлялся. После попытки native focus UI-инструмент сообщил, что Mac заблокирован. Пользователю предложено вручную разблокировать Mac. Browser `file://` fixture инструментом не открывался из-за URL policy; пользовательский manual-open шаг остаётся незавершённым. Эти environment blockers не являются доказательством отказа AX/Unicode в TextEdit или Chrome. Production реализация до завершения обязательного probe не начата.

Final static close-out 2026-10-02: последняя shared external-fixture версия probe прошла standalone DEBUG typecheck, signed universal Debug build, SwiftPM incremental build и `git diff --check`. Follow-up Luna review новых external guards и исправленного single-word dispatch не нашёл material issues. TextEdit и Chrome adapter compatibility по-прежнему не подтверждены runtime, native Undo не принят.


### 2026-10-02: TextEdit external range/Undo PASS после разблокировки

На controlled plain-text fixture подтверждены same-element native focus handoff, writable selected range, bounded selected/context read, tagged Unicode замена, exact neighboring-text/caret postcondition и восстановление исходного sentinel одним tagged native `⌘Z`. Event retry отсутствует. System-wide direct focused-element query оказался непригоден в этом run; проверенная public chain: system focused application → PID equals NSWorkspace frontmost → application focused UI element → element PID. Это подтверждает механизм TextEdit на macOS 26.6.2, а не весь S037 или поддержку других редакторов.

Browser probe перенесён на публичный HTTPS HTML input пример MDN вместо локального file URL. Parent создал отдельную вкладку, ввёл только synthetic sentinel и выделил synthetic слово в Basic example input. Навигация к локальному файлу не обходилась, форма не отправлялась. Browser runtime result пока ожидается.


MDN Chrome probe подготовлен, reviewed и включён в подписанную Dev сборку, но его запуск остановлен automatic approval review до выполнения: для активации браузера, tagged synthetic replacement и Undo требуется прямое пользовательское подтверждение готовности конкретного внешнего поля. User approval запрошен. Chrome AX compatibility пока не подтверждена; обходов блокировки не выполнялось. TextEdit PASS сохраняется. Остальные gesture, fresh-word, multi-source, UTF-16/race и budgets cases остаются отдельными незавершёнными probe/design/test obligations; отсутствие evidence не выдаётся за поддержку.

Пользователь прямо разрешил Chrome MDN focus/replacement/Undo. Повторные preflight runs остановились до payload read и dispatch. Native UI показал, что browser-tab DOM projection не совпадал с активной вкладкой Chrome; после выбора конкретной MDN вкладки native AX подтверждает PID, editable role и публичную подпись поля. HTML `id` не принимается за native AXIdentifier, а заголовок native окна включает название группы вкладок. Привязка iframe поля к этому окну проверяется через публичные AXWindow/AXTopLevelUIElement, с проверкой PID и точного наблюдаемого заголовка; общий обход дерева не расширяется.

Отдельный synthetic `CGEvent.keyboardSetUnicodeString` → `keyboardGetUnicodeString` round-trip без dispatch сохранил 6, 20, 21, 256 и 4096 UTF-16 units целиком. Это проверка хранения строки в событии, а не подтверждение приёма длинного текста редактором или native Undo. Предел replacement должен учитывать actual target acceptance.

### 2026-10-02: Chrome MDN input external range/Undo PASS

После прямого пользовательского разрешения и native выбора подготовленной вкладки публичный AXWindow связал focused editable field с точным synthetic окном. Checked metadata: PID, role, label и same-element focus; payload читается только после этих guards, через bounded ranges. Signed Dev подтвердил selected range readable/settable, replacement полного synthetic sentinel без изменения соседнего текста, caret и восстановление одним native `⌘Z`. Повторная отправка отсутствует. Chrome iframe input проверен на macOS 26.6.2; textarea/contenteditable, другие браузеры, macOS 14 и весь S037 этим run не подтверждены. External harness зафиксирован; дальше проверяются только ограниченные own-fixture prerequisites и основной input-контракт.

### 2026-10-02: bounded own-fixture prerequisites

Signed own matrix подтвердила Unicode selection с surrogate pair и combining mark, caret, восстановление corrected selection и один native Undo. Для собственных NSTextView fixture добавлен только DEBUG Edit → Undo menu с обычным responder-chain action; normal Qipli UI не меняется. Один Unicode event на 4096 UTF-16 units принят NSTextView целиком, bounded range postcondition и native Undo восстановили seed. Context budget 256 проверен; oversize 4097 отклонён до AX range read. Принятые пределы чтения: selected/replacement ≤4096 UTF-16 units, context ≤256; превышение означает отказ, без chunking или усечения.

`TISSelectInputSource` переключил один из двух уже enabled/selectable static sources и восстановил исходный, с проверкой текущего source ID. Ни один новый source не включался. Restore не выполняется поверх обнаруженной конкурентной смены пользователем. Runtime с тремя sources и режим запоминания раскладки для разных документов остаются отдельными gates.

Исправлен параметр `UCKeyTranslate`: `kUCKeyTranslateNoDeadKeysBit` — индекс бита 0, а нужная маска — `kUCKeyTranslateNoDeadKeysMask`. Dead-key admission проверяется отдельным вызовом с options 0; отключение dead-key generation не считается доказательством отсутствия composition. Source sample включает буквенные и punctuation physical positions; это не доказательство произвольного обратного mapping.

Own fresh-word self-post pilot пока не подтвердил ввод: targeted bare physical-key events не дали допустимого metadata ledger; диапазон нулевой длины был отклонён без payload read. Это ограничение synthetic event delivery path, а не доказательство невозможности tracking. Native Computer Use умеет chords, но отказывается от одиночного Alt_L/Alt_R. Поэтому нулевые counters observer не выдаются за проверку физического Option. Pure guards для preheld modifiers и neutral re-arm после recovery прошли; аппаратная проверка требует ручного ввода в own synthetic fixture.

Для аппаратного шага подготовлен persistent DEBUG mode `--s037-fresh-word-manual-probe`. Signed universal Debug build и standalone typecheck прошли; native UI подтвердил пустой собственный editor и видимый статус `ARMED` после pre-input AX baseline. Manual callback использует cached admission и aggregate counters, без последовательности keycodes; AX sampling и explicit bounded six-unit read выполняются в serial background queue. Закрытие окна отключает tap/таймер/observer. Пользователю передан один шаг: synthetic `ghbdtn` + три ASCII spaces, затем standalone left Option. Runtime результат этого шага ещё не получен; poll-based own harness не доказывает production notification support или всю gesture/race matrix.

Первый пользовательский hardware run закрыл окно через `INVALIDATED` с `payloadRead=false`; coarse status не позволял назвать конкретный guard. Harness исправлен: revision связывает AX sample с metadata generation, stale replies отбрасываются; recent keyDown допускает короткую задержку применения caret редактором, но explicit range требует точного delta. Pre-input baseline принимается только в пустом fixture, focus loss очищает его, post-trigger input отменяет pending check. Synthetic metadata checks для stale generation, target-application lag, шести букв/трёх spaces и post-trigger cancellation прошли. Добавлены fixed reason/count diagnostics без keycodes/символов. Повторная signed universal Debug сборка и native `ARMED` подтверждены; пользователю передан rerun, runtime PASS пока не заявляется.

Последующая диагностика собственного crash подтвердила HIToolbox `dispatch_assert_queue` в background TIS property access внутри post-trigger worker. Вызовы TIS перенесены на main queue; AX остаётся в worker. Crash stack показывает достижение gated worker после hardware trace, но complete manual PASS этим не заявляется. Report теперь получает status lines сразу. Последние review findings по live frontmost check, post-trigger revision и close cancellation исправлены; Backspace отменяет попытку в persistent окне, кнопка «Начать заново» очищает только owned synthetic editor. Для видимости manual mode использует regular activation policy (Dock/Cmd-Tab), floating окно во всех Spaces; production UI не меняется. Signed universal Debug после исправлений собран, status report подтверждает `ARMED`; UI-инструмент после crash возвращает timeout, это не выдаётся за визуальную приёмку пользователя.

### 2026-10-02: hardware metadata и queue regression — core feasibility закрыт

Немедленный report сохранил `METADATA_PASS`: baseline до ввода, 6 UTF-16 word units, 3 ASCII spaces и physical standalone left Option release. Следующий crash произошёл в self-process AX selection setter: entry point напрямую вызвал AppKit в worker, который затем вызвал main-only HIToolbox. Guarded six-unit range read уже прошёл перед setter. Own-fixture AX entry points marshaled на main; external AX adapter по-прежнему worker-only и запрещает Qipli UI. Отдельный development-signed automatic self-AX regression подтвердил background-requested bounded six-unit read/selection без crash и без отправки keyboard events. Повторять hardware ввод не требуется; это раздельные proof stages, а не complete manual gesture/installed feature matrix.

Standalone utility находится в `scripts/probes/s037`; ordinary Debug/Release больше не содержат probe files или launch hook. Воспроизводимая сборка: `S037_PROBE_SIGNING_IDENTITY='<available Apple Development identity>' bash scripts/probes/s037/build.sh`, затем LaunchServices `open -n '/private/tmp/qipli-s037-probe-standalone/Qipli Dev.app' --args --s037-self-ax-regression`. Подпись и strict codesign verification прошли; saved mode runtime report: `selfAXMainOwnership=PASS`, `boundedSixUnitReadAndSelection=true`, `noKeyboardDispatch=true`. Report status-only, без payload. Hardware proof сохранён отдельно в `/private/tmp/s037-hardware-metadata-pass.txt`. Производственная реализация S037 начата по D-051; external notification admission, 3+ sources/macOS 14 и installed feature matrix остаются незавершёнными gates.


### 2026-10-06: повторный отказ word path и диагностика

Пользователь подтвердил рабочее исправление выделения, но повторный word → Space → left Option по-прежнему не выполняет исправление. Предыдущее исправление delayed native caret race не считается runtime решением этого отказа.

Добавлена trigger-only unified logging category `LayoutCorrection` / subsystem `com.qipli.app`. Запись показывает этап отказа, фиксированный класс ошибки AX/mapping, blocked/composition flags, aggregate word units/spaces и состояние monitor baseline/sample/proof. Сам monitor сохраняет только fixed reason codes: отказ регистрации selected/value notifications, отсутствие или устаревание preinput sample, epoch/source/target mismatch, caret invalidation. Обработка текста и fail-closed admission сохранены. Нет payload, keycodes, source/PID/app identifiers, caret/document counts, clipboard данных или error descriptions; AX polling и каждое нажатие клавиши не логируются.

Проверка: focused LayoutCorrection suite `28/28`, development-signed universal Debug build, strict/deep codesign verification, `git diff --check` и update privacy boundary script прошли. Сборка: `/private/tmp/qipli-s037-diagnostics/Build/Products/Debug/Qipli Dev.app`. Codesign trust verification прошёл с доступом к host trust services; sandbox-only проверка вернула `CSSMERR_TP_NOT_TRUSTED`. Первоначальный sandbox запуск SwiftPM остановился на недоступном compiler cache; повтор с host cache access прошёл. Runtime trace проблемного поля ещё не получен; исправление пользовательского сценария пока не заявляется.

Воспроизведение: закрыть предыдущую Qipli, запустить новую подписанную Debug Qipli Dev с включённым correction и Accessibility. В прежнем проблемном editable field набрать synthetic `ghbdtn`, ASCII Space и отдельно левый Option. Прочитать только диагностическую категорию:

```sh
/usr/bin/log show --last 5m --style compact --predicate 'subsystem == "com.qipli.app" AND category == "LayoutCorrection"'
```

`stage=trigger` подтверждает получение жеста coordinator; следующая запись показывает отказ либо `stage=completed`. `stage=wordProof` с `proofStatus=noBaseline` и `baselineStatus` объясняет потерю provenance; `sampleStatus=selectionNotificationUnavailable`/`valueNotificationUnavailable` показывает notification admission. `stage=wordDelta` означает несогласованный aggregate caret/count delta. Следующее действие: получить runtime trace после пользовательского ввода и устранить именно подтверждённую причину.


### 2026-10-06: первый production trace word → Space → Option

Пользователь воспроизвёл сценарий в диагностической Dev сборке. В записи процесса Qipli, отдельно от xctest, trigger показал `wordUnits=6`, `spaces=1`, `blocked=false`, `composition=false`, `notifications=true`, `baseline=true`, `sample=true`; следующая запись — `stage=wordDelta`, `error=axStale`, `proofStatus=ready`. Это исключает неполученный Option, пустые input counters и отсутствие baseline/notification proof для данной попытки. Отказ произошёл до bounded payload read и replacement в проверке aggregate caret/count delta или соответствия sample/target identity. Вторая попытка отдельно дошла до `replacement` с `axVerification`; она не доказывает результат первой и не повторяется автоматически.

Из кода видно, что baseline может создаваться при ненулевом накопленном input count, а aggregate delta затем считается от всего run. Это гипотеза происхождения mismatch, пока без подтверждённых величин. Добавлена failure-only запись `wordDeltaDetail` с expected units, относительными caret/count deltas и booleans sample/element match; trigger records дополнены `baselineInputUnits`. Absolute caret offsets/document counts не публикуются. Admission и replacement не ослаблены. Повторный focused suite `28/28`, `git diff --check` прошли. Для следующего trace требуется перезапуск обновлённой Dev сборки и одно synthetic воспроизведение.


### 2026-10-06: ChatGPT trace, late baseline и initial-selection correction

Пользователь указал ChatGPT и подтвердил отказ без пробела. Второй production trace точно показал `baselineInputUnits=1`, `expectedUnits=7`, `caretDelta=6`, `countDelta=6` для слова с пробелом; без пробела `baselineInputUnits=2`, `expectedUnits=6`, `caretDelta=4`, `countDelta=4`. Sample и AX element совпадают. Значит, baseline действительно создан внутри run после первых символов. Причина пропуска первого preinput sample в прежней диагностике не сохранялась; не объявлять её доказанной.

Найден и исправлен конкретный metadata admission defect: preinput выделение раньше отвергалось, хотя первый обычный символ может заменить его. Начальный selected range теперь допускается только до первых aggregate input units, final sample требует пустого выделения; count growth корректно учитывает длину удалённого исходного выделения. Pending native selection и applied caret/count сохраняют этот baseline при прежних identity/source/input guards. Исходный payload не читается. Поздний baseline не восстанавливается вычитанием пропущенных units; whole-word validation остаётся fail-closed. Сохраняется первый reason code начала run в `firstInputStatus`, чтобы отличить selected-range defect от других sample timing failures.

Два regression tests проверяют initial-selection replacement при отрицательном net count delta, сохранение соседнего текста/курсор/ASCII Space, pending/applied AX updates и отказ при новой selection/caret movement или excess growth. Focused S037 `30/30`; полный SwiftPM `316/316`, без failures/skips. Development-signed universal Debug build, strict/deep codesign verification и `git diff --check` прошли. Runtime ChatGPT rerun после этой правки ещё требуется; полное исправление пользовательского сценария пока не подтверждено. Опубликованный релиз не менялся.


### 2026-10-06: initial-selection fix не закрыл ChatGPT, deferred reset race

Пользователь повторно сообщил тот же отказ. Новый production trace показал `firstInputStatus=ready`, но итоговый `baselineInputUnits=1/4` и delta дефицит ровно в эти units. Это означает, что начало run первоначально было допущено, затем baseline потерян и создан заново внутри run. Предыдущая гипотеза единственного initial-selection отказа не подтверждена; initial-selection support остаётся отдельно проверенным исправлением, а не runtime решением пользовательской проблемы. В другой попытке caret delta совпал, count delta был отрицательным; точный native AX переход этой попытки прежними logs не восстанавливается.

Найдена конкретная ordering race: invalidating mouse/nontext input объединялось с последующим обычным typing в отложенном main callback с `preserve=false`. Этот callback вызывал coordinator.invalidate(), стирая новый baseline, который последующий keyDown уже успел установить. Теперь tap синхронно вызывает metadata-only monitor invalidation для первоначального invalidating события. Отложенный callback не несёт preserve flag и через Shell инвалидирует только operation/cycle, сохраняя новый baseline. AX/TIS/payload work в tap не добавлен. Diagnostics сохраняет последний meaningful `baselineLossStatus` и aggregate input units его потери, чтобы отличить от native capture/caret failures.

Regression test проверяет немедленный metadata reset, последующий новый baseline admission attempt, coalesced callback и отсутствие его повторного сброса. Focused S037 `31/31`, full SwiftPM `317/317` без failures/skips, development-signed universal Debug build, strict/deep codesign verification, update privacy check и `git diff --check` прошли. Runtime rerun в ChatGPT после ordering fix открыт; installed acceptance не объявляется. Проверка процессов подтвердила одну запущенную Qipli Dev.


### 2026-10-06: GitHub research, D-052 и on-demand production path

После очередного отказа ChatGPT пользователь запросил изучение готовых GitHub implementations. Immutable refs LangSwitcher/UASwitcher/Punto закреплены в D-052. Их подходы используют explicit selection/typing counters и native transport без mandatory preinput AX baseline; сторонний код только прочитан, не запущен/не включён как dependency.

Production Shell больше не создаёт/start monitor до набора. Coordinator без monitor проверяет recent word/space counters, source/PID/freshness, current bounded range, actual trailing ASCII spaces, left/right token boundaries и focus/range/text generation. Нет восстановления baseline вычитанием units, постоянного payload/physical key buffer или whole AXValue read. Clipboard lease ограничен 64 items/256 representations/32MiB, сохраняет item representations в памяти, регистрирует временные/restored changeCounts, не перезаписывает newer external Copy. Transport выбирается один раз до selection mutation: native Cmd-V либо single Unicode event при unavailable/oversized clipboard snapshot. Нет fallback/retry после dispatch. Native selection setters ожидаются до exact range postcondition. Diagnostics production path пишет path=onDemand и fixed stage/error/aggregate counters без misleading baseline prerequisites.

Полный SwiftPM: 325 tests / 0 failures / 0 skips. Включены word без monitor с 0/1/3 spaces, old/pasted-only refusal и 6 clipboard tests: multi-item/binary preservation, empty restore, newer Copy, oversize/unreadable promises refusal before mutation и History self-write suppression. Подписанный universal Debug и unsigned universal Release собраны; strict/deep codesign и update-privacy/diff/project validation прошли. После финальной log-only правки полный 325-test suite и incremental signed Debug/codesign повторно прошли; новая Dev сборка запущена из /private/tmp/qipli-s037-main-build.

Двухпроцессный development-signed native probe scripts/probes/s037/S037NativePasteProbe.swift использует production coordinator/AX adapter в собственном NSTextView. Три cases PASS: word+3 spaces, word+0 spaces, selection; exact text/context/caret/selection, single native Undo и сохранность всех original clipboard representations (включая unreadable representation) подтверждены. Текущий system clipboard имеет unreadable representation, поэтому этот run выбрал Unicode, selfWriteRegistrations=0; actual general-clipboard Cmd-V transport этим run не подтверждён. Clipboard transaction проверена isolated named pasteboard tests. SourceSwitch mock и synthetic ledger counters не подтверждают полный global gesture/source path.

Ошибки раннего стенда (AXValue setup попал в Undo grouping между scenarios) устранены отдельным seeded fixture process для каждого case без AXValue setter. Отказ раннего probe не выдаётся за product failure/pass. ChatGPT/Codex bundle com.openai.codex закрыт для Computer Use: прямой installed acceptance не выполнен, этот запрет не обходился. S037 остаётся needs_verification; повторный ChatGPT smoke и полная matrix необходимы до релиза.


### 2026-10-06: пользовательская проверка ChatGPT перед выпуском

Пользователь явно подтвердил в новой Dev сборке: слово без выделения исправляется в ChatGPT без пробела и после пробелов; один native ⌘Z отменяет замену; clipboard сохраняется. Это подтверждение installed user path, отдельно от synthetic probe. Ручной основной gate, блокировавший публикацию 1.0.12/build13, закрыт. Полная matrix дополнительных sources, permission/focus races, VoiceOver/macOS14 и установленное Sparkle обновление этим подтверждением не закрываются; S037 не объявляется полностью done.


### 2026-10-06: удаление временной диагностики перед 1.0.13

По запросу пользователя удалены LayoutCorrectionDiagnostics, import OSLog, все вызовы logger и stage tracking в coordinator. Internal monitor proof status остаётся в памяти; guard checks, transport, clipboard lease и сообщения отказа пользователю не меняются. Полный SwiftPM 325/325, 0 failures/skips, source logging scan, update privacy boundary и diff check PASS. Полная installed-app matrix S037 остаётся открытой.


Удаление диагностики опубликовано в v1.0.13/build14, tag8be2a4c. Source scan и logging marker scan публичного executable PASS; signing/notarization/Gatekeeper и Sparkle PASS. Подробные workflow/PR pointers и public artifact checks находятся в STATE-HISTORY, актуальные открытые gates в STATE.

### Уточнение 2026-10-08: длинные выделения и видимый отказ

Пользователь разрешил увеличить selected/replacement ceiling втрое до 12 288 UTF-16 units и показывать отказ/ошибку correction в маленькой верхней панели в стиле Finder Cut. Панель не меняет focus или input ownership, раскрывается и сворачивается через три секунды; новая ошибка обновляет сообщение и timer. Успех не показывает панель. Контекст ≤256 и deadline 500 ms сохраняются.

Acceptance: выделение 12 288 преобразуется полностью с сохранением соседнего текста/selection и single native Undo в owned fixture; 12 289 отклоняется до payload read/mutation. Denied/failed показывают только фиксированное безопасное сообщение; completed не показывает notice. Повторный notice не закрывается старым timer/animation callback; closeAll отменяет timer. Дополнительные реальные редакторы проверяются отдельно.

Implementation report 2026-10-08: ceiling централизован в LayoutCorrectionLimits и применяется к selection, word, AX read и replacement. Отказ выше нового ceiling до payload read/mutation проверен synthetic regression. Shell передаёт denied/failed одновременно в Settings и отдельную notice presentation. Панель использует existing compact nonactivating NSPanel, safe-area geometry и TopNotch mask; mouse events проходят target. Generation token защищает timer/completion, task отменяется closeAll, completed не открывает сообщение, Reduce Motion использует fade.

Verification: full SwiftPM 333/333 без failures/skips; actual AppKit card mouseUp plain/rich callback, 3-second timer, old timer/animation и fixed 440×108 notice layout PASS. Signed universal Debug, strict/deep codesign, unsigned universal Release, version/privacy/diff checks PASS. Двухпроцессный development-signed native probe: cases word+3 spaces, word+0 spaces, small selection, 12 288 selection PASS отдельно для native paste и Unicode-only transport. В long case exact selected range, все соседние символы, one native Undo и исходный clipboard сохранены; source switch mock. Probe Unicode-only не настраивает optional pasteboard registration, поэтому выбирает production fallback без mutation clipboard. Installed global gesture/real-editor/visual animation acceptance не объявляется. Published v1.0.13/build14 не менялся.
