---
id: S022
title: Энергоэффективный pasteboard polling
status: needs_verification
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
- Освобождение production cancellation token также invalidates timer, даже если future owner забудет явный `cancel()`.
- Self-write registry, exact observed changeCount, serialization и rapid external capture order сохраняются.

## Acceptance criteria

- [x] Scheduler получает документированные interval/tolerance; один fire приводит к одному poll.
- [x] Пустой tick не создаёт Task; async work начинается только при реальном capture pipeline или explicit drain.
- [x] Stop отменяет future ticks, repeated start не создаёт второй timer.
- [x] Self-write suppression и rapid duplicate external changes сохраняют поведение.
- [x] Immediate History show poll/drain S019 не зависит от timer tolerance.
- [ ] Idle observation не показывает регрессию CPU/wakeups относительно S017 baseline.

## Verification

- [x] Focused scheduler lifecycle/one-fire-one-poll tests с fake pasteboard.
- [x] Rapid capture, self-write, onboarding baseline и fresh-show integration tests.
- [x] S017 polling instrumentation до/после.
- [ ] Локальный idle observation реального приложения.
- [x] Full SwiftPM/Xcode suite и unsigned universal Release build.
- [ ] Manual быстрые копирования, duplicate, History immediate show и sleep/wake smoke.

## Implementation report

### Реализовано

Добавлен injectable `PasteboardPollScheduling`: production scheduler создаёт repeating main-run-loop timer с interval `0.35 s` и tolerance `0.05 s`. Callback вызывает actor-isolated `poll()` напрямую, поэтому неизменившийся `changeCount` больше не создаёт unstructured `Task` на каждом tick.

Lifecycle стал явно идемпотентным: repeated `start()` не создаёт второй scheduler, `stop()` отменяет future fires, а restart снова фиксирует baseline. Explicit `poll()`/capture drain S019 остаются независимыми от timer cadence. Self-write suppression, exact `changeCount` и onboarding baseline не менялись.

Corrective hardening 2026-08-29 добавил defensive timer invalidation в `TimerPasteboardPollCancellation.deinit`; основной explicit `stop()` contract остаётся прежним.

### Проверено

Focused corrective run: `PasteboardMonitorTests` 10/10 и `PerformanceBaselineTests` 10/10. Lifecycle test подтверждает invalidation при освобождении cancellation token без явного cancel. Operation-count baseline выполнил 10 000 scheduler fires: один callback на fire, `10 001` чтение `changeCount` с учётом start baseline и `0` чтений clipboard text.

Полные SwiftPM и unsigned Xcode Debug suites: 175 тестов, 0 failures. Unsigned universal Release build прошёл; executable содержит `x86_64 arm64`.

Финальный corrective HEAD прошёл обновлённые полные Xcode и clean-copy SwiftPM suites: по 179 tests, 0 failures; unsigned universal Release снова содержит `x86_64 arm64`.

### Отклонения и остаточные риски

Реальный idle CPU/wakeup observation, быстрые копирования/duplicate, immediate History show и sleep/wake smoke не выполнялись автоматически. До их ручного прохождения срез остаётся `needs_verification`; polling frequency намеренно не снижалась.
