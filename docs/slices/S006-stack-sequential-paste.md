---
id: S006
title: Последовательная вставка и прогресс
status: planned
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

- InputCoordinator сериализует paste transactions и не допускает двух одновременно.
- Synthetic event имеет отличимый marker; callback не обрабатывает его повторно.
- Pasteboard self-write регистрируется до изменения contents и погашается ровно один раз.
- State transition pending→used происходит только после успешной подготовки и отправки стандартного paste event.

## Acceptance criteria

- [ ] При неактивном/пустом стеке обычный `⌘V` не меняется Qipli и вставляет текущее содержимое system pasteboard как обычно.
- [ ] При активном стеке каждое отдельное пользовательское `⌘V` отправляет точный текст ровно одного next occurrence согласно direct/reverse traversal; быстрый key repeat не пропускает и не дублирует элементы.
- [ ] После dispatch обработанный occurrence остаётся в панели как visibly disabled/used, а следующий pending получает явный marker.
- [ ] Внутреннее изменение pasteboard и synthetic event не создают новые history/stack items и не вызывают рекурсивную вторую вставку.
- [ ] Если подготовка pasteboard или dispatch завершается ошибкой до отправки, occurrence не становится used, сессия остаётся открытой и пользователь видит возможность повтора.
- [ ] Потеря Accessibility или отключение event tap блокирует дальнейшее продвижение без пропуска элементов и показывает действие восстановления.
- [ ] После dispatch последнего активного occurrence все элементы кратко имеют консистентное used-state, затем session завершается, panel закрывается и дальнейший `⌘V` снова полностью системный.
- [ ] Unicode, пробелы, переводы строк и одинаковые occurrence вставляются без изменения text и в правильном количестве.

## Verification

- [ ] Unit tests state transitions, direct/reverse sequence, atomic failure и finish.
- [ ] Integration tests с fake event/pasteboard adapters: self-write, synthetic marker, recursion и rapid events.
- [ ] UI tests used/next/error/completed states.
- [ ] Ручной end-to-end в TextEdit, браузере и редакторе кода с direct/reverse, duplicates и multiline text.
- [ ] Ручная проверка key repeat и потери разрешения/event tap во время активной session.
- [ ] После auto-finish проверить обычный system `⌘V` и наличие всех исходных записей в истории.

## Definition of Done

- [ ] Все acceptance criteria выполнены.
- [ ] Автоматические и ручные проверки пройдены.
- [ ] Приложение собирается без новой регрессии.
- [ ] `STATE.md` и frontmatter синхронно обновлены.
- [ ] Новые значимые решения записаны в `DECISIONS.md`.
- [ ] Implementation report заполнен.

## Implementation report

### Реализовано

Не начато.

### Изменённые файлы

Не начато.

### Выполненная проверка

Не начато.

### Отклонения от плана

Нет.

### Оставшиеся проблемы

Зависит от S001 и S005.
