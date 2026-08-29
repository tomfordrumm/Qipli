---
id: S017
title: Performance baselines и instrumentation
status: ready
depends_on: []
covers:
  - NFR-008
  - NFR-018
  - NFR-019
  - NFR-020
---

# S017: Performance baselines и instrumentation

## Результат

Команда может воспроизводимо измерить ключевые performance boundaries Qipli на безопасных синтетических данных и обнаружить алгоритмическую регрессию до изменения storage, concurrency, search, Stack или polling.

## В scope

- deterministic payload-free fixture factory для History entries, длинного текста и Paste Stack;
- focused benchmark seams для storage fetch, localized search, preview construction, Stack next-state и pasteboard scheduling;
- счётчики числа fetch, полного text traversal, Stack traversal и scheduled work там, где wall-clock threshold был бы нестабилен;
- baseline report с реальным локальным объёмом только в агрегатах без clipboard payload;
- отдельная команда/набор performance tests и быстрые regression tests, пригодные для обычного suite.

## Вне scope

- оптимизация production code, изменение Core Data schema или concurrency;
- публичный SLA или абсолютный KPI на shared CI runner;
- чтение реального пользовательского clipboard/store из автоматических tests;
- telemetry, network upload или логирование текстов, запросов, previews и UUID.

## Контракты

- Fixtures генерируют очевидно искусственные строки по размеру/индексу и никогда не импортируют production store.
- Baselines охватывают примерно 1 800, 10 000 и 50 000 History entries, отдельный большой text и большие Stack sizes; тяжёлые wall-clock runs можно запускать отдельно от быстрого CI.
- Обычный suite проверяет детерминированные operation counts, cancellation seams и сложность. Timing используется как наблюдение или с достаточно широким калибруемым budget, а не как flaky pass/fail на любой машине.
- Instrumentation публикует только operation name, duration/count и size bucket; payload и пользовательские identifiers запрещены.

## Acceptance criteria

- [ ] Синтетические fixtures воспроизводимы, не содержат реальных clipboard данных и покрывают целевые объёмы.
- [ ] Search, preview, Stack traversal и scheduler имеют измеряемые seams без изменения пользовательского поведения.
- [ ] Baseline report фиксирует дооптимизационные агрегаты и точные команды воспроизведения.
- [ ] Быстрый suite обнаруживает добавление лишнего full fetch/traversal там, где это можно проверить счётчиком.
- [ ] Performance suite не пишет payload в stdout, logs, artifacts или test names.

## Verification

- [ ] Focused performance/regression tests.
- [ ] Full SwiftPM test suite.
- [ ] Unsigned Xcode Debug tests/build и universal Release build.
- [ ] Privacy inspection generated output: только counts/durations/size buckets.

## Implementation report

### Реализовано

Не заполнено.

### Проверено

Не заполнено.

### Отклонения и остаточные риски

Не заполнено.
