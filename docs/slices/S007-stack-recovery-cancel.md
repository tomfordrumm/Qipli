---
id: S007
title: Повторная активация и отмена
status: planned
depends_on:
  - S006
covers:
  - FR-013
  - FR-015
  - BR-004
  - BR-006
  - NFR-005
  - NFR-006
  - NFR-008
---

# S007 — Повторная активация и отмена

## Пользовательский результат

Если значение было вставлено не туда, пользователь делает любой used-элемент следующим и повторяет его, либо безопасно отменяет незавершённый стек, не теряя историю.

## В scope

- действие Reactivate на любом used occurrence;
- одноразовый приоритет reactivated occurrence и возврат к прежнему traversal;
- повторные reactivation/paste циклы;
- `Esc` и close control на collecting/partially-used/reactivated session;
- cleanup event interception и сохранность общей истории.

## Вне scope

- undo в приложении назначения;
- автоматическое определение неправильного поля;
- восстановление завершённого/закрытого стека;
- сохранённые stack templates.

## Предусловия

- S006 завершён; used-state означает отправленную команду по D-011.

## Ожидаемое поведение

- Reactivation меняет только выбранный occurrence и next priority; остальные used/pending состояния не сбрасываются.
- После повторной вставки traversal продолжает тот элемент, который был next до reactivation.
- Можно реактивировать один и тот же элемент повторно, пока session открыта.
- Cancel немедленно прекращает stack-controlled paste, но не меняет history records.

## Состояния интерфейса

- used item with Reactivate action;
- reactivated-next marker;
- reactivated item processing/used again;
- partially completed cancel confirmation, если UI-исследование показывает его необходимость;
- canceled/closed.

## Данные и контракты

- State machine хранит не более одного `reactivationPriority` одновременно.
- Выбор другого used occurrence заменяет приоритет, не переводя предыдущий used в pending.
- После успешного повторного dispatch приоритет очищается; базовый traversal cursor не перескакивает.
- Cancel идемпотентен: повторный Esc/close после завершения ничего не меняет.

## Acceptance criteria

- [ ] Каждый used occurrence в открытой панели имеет доступное действие Reactivate; pending occurrence не предлагает это действие.
- [ ] Reactivate делает выбранный occurrence следующим и визуально отличает его, не изменяя состояния остальных used/pending элементов.
- [ ] Следующий `⌘V` отправляет reactivated text ровно один раз; после этого occurrence снова used, а прежний next pending снова становится следующим.
- [ ] Другой used occurrence можно выбрать до paste; он заменяет одноразовый приоритет без появления двух next items.
- [ ] Один и тот же occurrence можно повторно активировать несколько раз в рамках открытой session без создания новых history records.
- [ ] Глобальный `Esc` из приложения-источника/назначения и close control завершают пустую, collecting, partially-used или reactivated session, скрывают panel и полностью отключают stack interception.
- [ ] После cancel обычный `⌘V` снова системный, а все внешние копирования из отменённого стека доступны в общей истории с исходными text/date.
- [ ] После auto-finish из S006 прежний стек нельзя реактивировать; повторное значение берётся через общую историю, новый `⌘⇧C` начинает пустую session.

## Verification

- [ ] Unit tests reactivation priority, replacement, resume cursor и repeated reactivation.
- [ ] Unit tests cancel из каждого session state и idempotency.
- [ ] Integration test: reactivated paste не создаёт history duplicate.
- [ ] UI tests Reactivate availability/marker и cancel from partial progress.
- [ ] Ручной сценарий «два значения попали в одно поле»: reactivate первого/второго и продолжить traversal.
- [ ] После cancel/auto-finish проверить системный `⌘V` и history recovery.

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

Зависит от S006.
