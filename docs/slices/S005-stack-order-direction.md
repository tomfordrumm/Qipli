---
id: S005
title: Порядок и направление обхода
status: planned
depends_on:
  - S004
covers:
  - FR-009
  - FR-010
  - BR-005
  - NFR-005
  - NFR-008
---

# S005 — Порядок и направление обхода

## Пользовательский результат

До начала вставки пользователь видит будущую последовательность, может переставить элементы и выбрать прямой или обратный обход без изменения их текста.

## В scope

- drag-and-drop либо эквивалентная нативная перестановка pending occurrences;
- direct/reverse control, direct по умолчанию;
- явная маркировка следующего элемента и визуальное объяснение обхода;
- чистые state-machine transitions и accessibility/keyboard fallback для reorder;
- блокировка изменения базового порядка после первого обработанного paste event как согласованное предположение MVP.

## Вне scope

- фактический перехват `⌘V` и used-state;
- reactivation;
- сохранённые пользовательские настройки направления;
- произвольное редактирование текста элемента.

## Предусловия

- S004 завершён и occurrence identity стабилен.
- Предположение BR-005 не отклонено по результатам UX-проверки S004.

## Ожидаемое поведение

- Видимый список — базовый порядок, а маркер направления объясняет traversal.
- Direct выбирает первый pending сверху, reverse — последний pending снизу.
- Перестановка и смена направления мгновенно пересчитывают next, но не создают/удаляют записи истории.
- Одинаковые элементы переставляются по occurrence ID, а не по text.

## Состояния интерфейса

- direct/reverse selected;
- drag/reorder active;
- next marker;
- single item;
- controls locked после начала вставки (используется с S006).

## Данные и контракты

- `position` описывает базовый видимый порядок и уникален внутри текущей сессии.
- Направление — session-level enum, default `.direct`.
- State machine возвращает deterministic next occurrence для любого списка и направления.
- Reorder API принимает occurrence IDs и отклоняет отсутствующие/повторяющиеся ID без частичной мутации.

## Acceptance criteria

- [ ] При двух и более элементах пользователь может изменить базовый порядок; после операции каждый occurrence присутствует ровно один раз, а full text и history records не меняются.
- [ ] Direct выбран по умолчанию и маркирует верхний pending occurrence следующим; reverse маркирует нижний pending occurrence следующим.
- [ ] После перестановки в direct/reverse next и визуальная последовательность соответствуют BR-005, включая несколько одинаковых текстов.
- [ ] Один элемент корректно показывается следующим в обоих направлениях; пустой стек не предлагает reorder.
- [ ] Есть keyboard/accessibility fallback для перемещения элемента без обязательного drag gesture, а направление имеет понятные label/state.
- [ ] Reorder с некорректным occurrence ID отклоняется атомарно и не портит session state.
- [ ] После сигнала «вставка началась» controls порядка/направления становятся недоступными и не меняют уже выбранный traversal; до S006 это проверяется state-machine contract test.

## Verification

- [ ] Property/unit tests: reorder сохраняет набор ID и уникальность positions.
- [ ] Unit tests direct/reverse для 0/1/N элементов и одинаковых текстов.
- [ ] Unit test invalid reorder не выполняет частичную мутацию.
- [ ] UI tests drag reorder, keyboard fallback, direction toggle и next marker.
- [ ] Ручная проверка длинных/multiline previews и VoiceOver labels основных controls.

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

Зависит от S004.
