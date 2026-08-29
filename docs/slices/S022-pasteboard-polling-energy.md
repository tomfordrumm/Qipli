---
id: S022
title: Энергоэффективный pasteboard polling
status: ready
depends_on:
  - S021
covers:
  - FR-001
  - NFR-004
  - NFR-020
---

# S022: Энергоэффективный pasteboard polling

## Результат

PasteboardMonitor сохраняет текущую capture latency и reliability, но пустой polling tick выполняет один дешёвый scheduler callback без создания отдельной Task и допускает системную timer tolerance.

## В scope

- injectable scheduler/timer lifecycle с interval и tolerance;
- direct actor-safe poll callback без nested Task allocation на каждый tick;
- start/stop/idempotence и explicit fresh poll/drain contracts;
- tests частоты, tolerance, cancellation, self-write и rapid changes;
- до/после idle wakeup/CPU observation без clipboard payload.

## Вне scope

- снижение текущей polling frequency без отдельного manual copy-loss/latency proof;
- distributed notifications, helper process или новый system permission;
- изменение capture/history/Stack semantics;
- telemetry или energy upload.

## Контракты

- Production interval остаётся `0.35 s` в этом срезе; tolerance может coalesce wakeups, но explicit fresh show poll остаётся немедленным.
- Каждый timer fire вызывает максимум один poll и не создаёт unstructured Task, когда changeCount не изменился.
- Start/stop идемпотентны, stop invalidates scheduler, onboarding gate по-прежнему запрещает pasteboard read до завершения.
- Self-write registry, exact observed changeCount, serialization и rapid external capture order сохраняются.

## Acceptance criteria

- [ ] Scheduler получает документированные interval/tolerance; один fire приводит к одному poll.
- [ ] Пустой tick не создаёт Task; async work начинается только при реальном capture pipeline или explicit drain.
- [ ] Stop отменяет future ticks, repeated start не создаёт второй timer.
- [ ] Self-write suppression и rapid duplicate external changes сохраняют поведение.
- [ ] Immediate History show poll/drain S019 не зависит от timer tolerance.
- [ ] Idle observation не показывает регрессию CPU/wakeups относительно S017 baseline.

## Verification

- [ ] Focused scheduler lifecycle/one-fire-one-poll tests с fake pasteboard.
- [ ] Rapid capture, self-write, onboarding baseline и fresh-show integration tests.
- [ ] S017 polling instrumentation до/после; локальный idle observation.
- [ ] Full SwiftPM/Xcode suite и unsigned universal Release build.
- [ ] Manual быстрые копирования, duplicate, History immediate show и sleep/wake smoke.

## Implementation report

### Реализовано

Не заполнено.

### Проверено

Не заполнено.

### Отклонения и остаточные риски

Не заполнено.
