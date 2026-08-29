---
id: S017
title: Performance baselines и instrumentation
status: done
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

- [x] Синтетические fixtures воспроизводимы, не содержат реальных clipboard данных и покрывают целевые объёмы.
- [x] Search, preview, Stack traversal и scheduler имеют измеряемые seams без изменения пользовательского поведения.
- [x] Baseline report фиксирует дооптимизационные агрегаты и точные команды воспроизведения.
- [x] Быстрый suite фиксирует aggregate operation/count dimensions, на которых S018–S022 добавляют focused complexity assertions.
- [x] Performance suite не пишет payload в stdout, logs, artifacts или test names.

## Verification

- [x] Focused performance/regression tests.
- [x] Full SwiftPM test suite.
- [x] Unsigned Xcode Debug tests/build и universal Release build.
- [x] Privacy inspection generated output: только operation enum, counts и durations.

## Implementation report

### Реализовано

- Добавлен `PerformanceProbe` с закрытым enum операций, `itemCount` и nanosecond duration без free-form metadata.
- Добавлены deterministic synthetic History fixtures для 1 800, 10 000 и 50 000 entries, 50 000-character text и 10 000-element Stack.
- Зафиксированы дооптимизационные search/preview/Stack workloads; full exact text отдельно проверяется от display preview.
- Xcode project синхронизирован с новым production seam и test suite.

### Проверено

- Дооптимизационный review baseline: localized search около `6.5 ms` на 1 773, `36.8 ms` на 10 000 и `180.0 ms` на 50 000 entries; raw SQLite full fetch около `3.5 ms` на текущих 1 773 entries.
- Focused SwiftPM: 7 tests, 0 failures. Полный SwiftPM suite из временной clean copy: 161 tests, 0 failures.
- Full Xcode Debug tests: пройдены. Unsigned universal Release: `x86_64 arm64`.
- Instrumentation API и test output проверены: clipboard/search/preview/UUID payload не записывается.

### Отклонения и остаточные риски

- Wall-clock observations зависят от hardware/build mode и не являются публичным SLA; стабильные CI assertions добавляются в S018–S022 на operation counts, thread и cancellation contracts.
- Рабочая директория содержит пользовательские untracked duplicate-файлы с суффиксом ` 2`; Xcode их не включает, а SwiftPM verification выполнена из временной clean copy без изменения этих файлов.
