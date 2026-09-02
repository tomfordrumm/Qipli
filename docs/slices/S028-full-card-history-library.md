---
id: S028
title: Полноценная карточная History
status: planned
depends_on:
  - S027
covers:
  - FR-004
  - FR-005
  - FR-017
  - FR-026
  - FR-034
  - BR-022
  - BR-025
  - BR-027
  - NFR-005
  - NFR-009
  - NFR-027
  - NFR-028
---

# S028: Полноценная карточная History

## Пользовательский результат

Пользователь нажимает `Развернуть` в Top Notch и получает отдельное полноценное окно History с тем же запросом и выбранной occurrence. Окно использует площадь для сетки ровно из трёх карточек в ряду и остаётся доступным для просмотра, поиска и повторных вставок до явного закрытия.

## В scope

- действие `Развернуть` в Top Notch;
- singleton resizable full History window с ordinary window lifecycle и minimum content width;
- атомарный transfer query, exact selected ID и captured paste target;
- hiding Top Notch после подтверждённого появления full window;
- отдельный Search, связанный с той же presentation state;
- vertical virtualized `NSCollectionView` layout ровно из трёх карточек в ряду;
- type-aware карточки с общим renderer contract S027 и более полным bounded preview;
- двухмерная keyboard navigation, selection visibility, `Enter`/double-click paste, Delete и Clear All;
- normal close/reopen behavior без passive stale-target activation.

## Вне scope

- Favorites/navigation destinations — S029;
- edge-placement Settings — BL-002;
- remote URL previews, drag/drop, bulk actions, tags, folders, sync или indefinite pins;
- изменение capture/persistence/retention/paste payload contracts.

## Контракты перехода и окна

- Во время `transitioningToFull` оба окна могут быть нарисованы, но input admission принадлежит только одному state owner; Enter/double-click временно заблокирован до завершения handoff.
- Full window получает query/selection/target до `orderFront`; Top Notch скрывается только после того, как full content готов принять keyboard input.
- Full window является отдельным normal/resizable window, не floating shelf. Resign-key не закрывает его. Explicit close не активирует сохранённый target.
- Три колонки являются продуктовым контрактом первой версии. Window не сжимается ниже минимальной ширины, необходимой для трёх читаемых карточек; на большей ширине меняются card width/gaps, но не число колонок.
- Arrow keys перемещаются по row/column с детерминированным поведением на неполной последней строке. Selection остаётся exact UUID при page append или search completion, пока occurrence присутствует.

## Acceptance criteria

- [ ] `Развернуть` создаёт/показывает ровно одно full History window и сохраняет query, selected occurrence и scroll-to-selection context.
- [ ] После появления full window Top Notch скрыт, не hit-testable и не принимает keyboard input.
- [ ] Full History показывает ровно три карточки в каждом полном ряду на минимальной и большей поддерживаемой ширине; resize не создаёт clipped controls или четвёртую колонку.
- [ ] Search использует full-retention bounded backend; load-more не сбрасывает selection и не загружает media payload невидимых карточек.
- [ ] Arrow navigation, Enter/double-click, Delete и Clear All работают для text и typed occurrences без duplicate paste transaction.
- [ ] Full window переживает resign-key, возвращается из status menu/Top Notch как singleton и закрывается только явно.
- [ ] Passive close не активирует stale target; paste из текущей presentation session возвращается только в captured non-Qipli target.
- [ ] Карточки доступны VoiceOver и остаются читаемыми в appearance/accessibility matrix; Reduce Motion не влияет на готовность input.

## Verification

- transition state-machine tests на delayed show, close during transition, repeated Expand и paste admission;
- pure three-column layout tests для minimum/typical/wide frames и incomplete last row;
- 2D keyboard/selection/scroll tests, включая paging/search mutation и unavailable occurrence;
- singleton lifecycle и captured-target regression tests;
- card reuse/thumbnail visibility/performance tests на synthetic 1 800/10 000/50 000 descriptor sets;
- full SwiftPM/Xcode suite, universal Release build, privacy/network scan и `git diff --check`;
- manual transition/resize/keyboard/paste/VoiceOver matrix на camera-housing MacBook и external display в двух target apps.

## Implementation report

Не начато.
