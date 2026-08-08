---
id: S006
title: Последовательная вставка и прогресс
status: done
depends_on:
  - S001
  - S005
covers:
  - FR-011
  - FR-012
  - FR-014
  - FR-016
  - BR-007
  - BR-008
  - NFR-004
  - NFR-006
  - NFR-008
---

# S006 — Последовательная вставка и прогресс

## Пользовательский результат

В приложении назначения пользователь нажимает обычное `⌘V` несколько раз и получает элементы стека в выбранной последовательности, видя прогресс до автоматического закрытия.

## В scope

- активный event tap только для `⌘V` во время непустой stack session;
- atomic next selection, self-write, dispatch и state transition;
- pending/next/used-disabled UI;
- direct/reverse traversal из S005;
- auto-finish после последнего активного occurrence;
- permission/event-tap failure, race и reentrancy protection.

## Вне scope

- повторная активация used item;
- подтверждение фактического изменения поля назначения;
- поддержка non-standard paste commands;
- редактирование порядка после начала вставки.

## Предусловия

- S001 подтвердил event tap и synthetic event tagging на macOS 14.
- S005 завершён; session next contract стабилен.
- Accessibility разрешён для ручного end-to-end сценария.

## Ожидаемое поведение

- Без активного непустого стека `⌘V` полностью системный.
- При активном стеке каждое пользовательское `⌘V` обрабатывает ровно один occurrence.
- Qipli self-write не возвращается в history/stack capture.
- Used означает отправленную paste-команду; целевое приложение может её отклонить.
- При ошибке до dispatch occurrence остаётся pending/next; при успешном dispatch становится used.

## Состояния интерфейса

- ready with next;
- processing короткое недублирующее состояние;
- used-disabled + next pending;
- permission lost/event tap disabled;
- paste preparation/dispatch error с retry;
- completed/closed.

## Данные и контракты

- Input boundary synchronously delegates admission to `StackSessionController`/`StackSession`; UUID reservation serializes paste transactions and does not permit two simultaneous dispatches.
- Synthetic event имеет отличимый marker; callback не обрабатывает его повторно.
- Writer синхронно возвращает exact final pasteboard `changeCount`; оно регистрируется как self-write сразу после записи и до следующего run-loop poll, затем подавляется ровно один раз.
- State transition pending→used происходит только после успешной подготовки и отправки стандартного paste event.

## Acceptance criteria

- [x] При неактивном/пустом стеке обычный `⌘V` не меняется Qipli и вставляет текущее содержимое system pasteboard как обычно.
- [x] При активном стеке каждое отдельное пользовательское `⌘V` отправляет точный текст ровно одного next occurrence согласно direct/reverse traversal; быстрый key repeat не пропускает и не дублирует элементы.
- [x] После dispatch обработанный occurrence остаётся в панели как visibly disabled/used, а следующий pending получает явный marker.
- [x] Внутреннее изменение pasteboard и synthetic event не создают новые history/stack items и не вызывают рекурсивную вторую вставку.
- [x] Если подготовка pasteboard или dispatch завершается ошибкой до отправки, occurrence не становится used, сессия остаётся открытой и пользователь видит возможность повтора.
- [x] Потеря Accessibility или отключение event tap блокирует дальнейшее продвижение без пропуска элементов и показывает действие восстановления.
- [x] После dispatch последнего активного occurrence все элементы кратко имеют консистентное used-state, затем session завершается, panel закрывается и дальнейший `⌘V` снова полностью системный.
- [x] Unicode, пробелы, переводы строк и одинаковые occurrence вставляются без изменения text и в правильном количестве.

## Verification

- [x] Unit tests state transitions, direct/reverse sequence, atomic failure и finish.
- [x] Integration tests с fake event/pasteboard adapters: self-write, synthetic marker, recursion и rapid events.
- [x] UI state coverage for used/next/error/completed states through deterministic controller/executor seams.
- [x] Ручной end-to-end в TextEdit, браузере и редакторе кода с direct/reverse, duplicates и multiline text.
- [x] Ручная проверка key repeat и потери разрешения/event tap во время активной session.
- [x] После auto-finish проверены обычный system `⌘V` и наличие всех исходных записей в истории.

## Definition of Done

- [x] Все acceptance criteria выполнены.
- [x] Автоматические и ручные проверки пройдены.
- [x] Приложение собирается без новой регрессии.
- [x] `STATE.md` и frontmatter синхронно обновлены.
- [x] Новые значимые решения записаны в `DECISIONS.md`.
- [x] Implementation report заполнен.

## Implementation report

### Реализовано

- Active event tap admits only exact untagged ordinary `⌘V` for an active Stack with a pending/reserved occurrence. It reserves one exact UUID synchronously; key repeat during that reservation is consumed without another dispatch.
- Deferred `StackSequentialPasteExecutor` checks permission, writes immutable exact text, registers the returned final pasteboard `changeCount`, posts tagged `⌘V`, then converts only that UUID to `used` after dispatch success. Permission/writer/dispatch/input failure returns it to pending with a retryable non-payload error.
- Stack rows now display processing and used-disabled states; the next marker skips used occurrences. Direction and order lock on first accepted paste. After the final used state is published, a deterministic deferred finish closes the panel and restores the Start menu state without target reactivation.
- Added deterministic seams/tests for event classification, recursion marker, direct/reverse 0/1/N, duplicates/Unicode/multiline fixtures, repeat admission, rollback/retry, cancellation/append races, monitor suppression and disabled input.
- Исправлена manual-console layout regression native `List`: processing publication теперь получает отдельный common-mode run-loop turn до paste production/used publication, а unchanged `@Published` values больше не создают лишний render invalidation. Deterministic test проверяет эту границу; existing deferred auto-finish сохранён отдельным следующим turn.

### Изменённые файлы

- `Sources/Qipli/Input/GlobalInput.swift`
- `Sources/Qipli/Input/CGEventTapAdapter.swift`
- `Sources/Qipli/PasteStack/StackSession.swift`
- `Sources/Qipli/PasteStack/StackSequentialPasteExecutor.swift`
- `Sources/Qipli/App/ApplicationShell.swift`
- `Sources/Qipli/UI/PanelController.swift`
- `Sources/Qipli/UI/PlaceholderViews.swift`
- `Tests/QipliTests/InputCoordinatorTests.swift`
- `Tests/QipliTests/PasteStackTests.swift`
- `Qipli.xcodeproj/project.pbxproj`
- `docs/TECHNICAL.md`, `docs/DECISIONS.md`, `docs/STATE.md`

### Выполненная проверка

- `swift test`: 80 tests, 0 failures.
- Xcode Debug XCTest (`platform=macOS, arch=arm64`): passed.
- Universal Xcode Release (`ARCHS=arm64 x86_64`, `ONLY_ACTIVE_ARCH=NO`): passed; `lipo` confirms `x86_64 arm64`.
- `plutil -lint` passed for plist, entitlements and Xcode project; `git diff --check` passed.
- Static privacy/log/network scan found no production logging or network client; the sole `https://` match is an existing synthetic test string.

### Отклонения от плана

Нет. S007 target reactivation/reactivation and persistence are not included.

### Оставшиеся проблемы

Нет. User подтвердил post-fix clean-console macOS matrix, включая отсутствие native `List` layout-recursion warning.
