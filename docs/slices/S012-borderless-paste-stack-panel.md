---
id: S012
title: Edge-to-edge Paste Stack с кастомным header
status: done
depends_on:
  - S007
  - S009
covers:
  - FR-017
  - NFR-005
  - NFR-009
---

# S012 — Edge-to-edge Paste Stack с кастомным header

## Пользовательский результат

Paste Stack выглядит как компактная самостоятельная overlay-панель: material заполняет окно до краёв, header содержит Close, центрированный заголовок и direction toggle, а список начинается сразу под header и занимает всю доступную ширину.

## В scope

- borderless chrome только для Paste Stack;
- кастомный header с доступной Cancel action, заголовком и существующим direction intent;
- отдельная drag-зона header через системный `NSWindow.performDrag(with:)`;
- один существующий adaptive material surface со скруглением и системной тенью;
- edge-to-edge plain List с полноширинными separators и внутренними row paddings;
- сохранение последнего положения панели между открытиями и relaunch с center fallback при недоступных координатах;
- сохранение empty/error/next/processing/used/reactivation состояний.

## Вне scope

- изменение History или Permission chrome;
- изменение размеров панели, stack state machine, clipboard или global input;
- дополнительный blur/material на header, строках или controls;
- изменение обычного `⌘V`, `Esc`, drag reorder или VoiceOver Move Up/Move Down.

## Acceptance criteria

- [x] Paste Stack не показывает native title bar или traffic lights.
- [x] Close в header отменяет незавершённый стек через существующий cancel path.
- [x] Header перетаскивает окно, не превращая весь List в drag-зону окна.
- [x] Direction toggle сохраняет current direction semantics и traversal lock.
- [x] List и separators занимают полную ширину окна; row content сохраняет читаемые внутренние отступы.
- [x] Panel остаётся nonactivating, floating, доступной во всех Spaces/full-screen и не забирает focus у source/target app.
- [x] После drag и повторного открытия или relaunch Paste Stack восстанавливает последнее доступное положение; после отключения owning display открывается по центру доступного экрана.
- [x] Light/Dark, Reduce Transparency, Increase Contrast, empty/error и длинный multiline content остаются читаемыми.

## Verification

- [x] Deterministic AppKit tests для custom/native chrome split, nonactivation, geometry и rounded material clipping.
- [x] Deterministic tests для сохранения координат, восстановления полностью видимого frame и center fallback при отключённом display или частично недоступном frame.
- [x] Полный SwiftPM XCTest suite.
- [x] `git diff --check` и scoped privacy/network scan.
- [x] Manual macOS smoke: Close, header drag, direction, row reorder, sequential paste, Esc, auto-finish и source/target focus.
- [x] Manual visual matrix: Light/Dark, long rows, empty/error, Reduce Transparency и Increase Contrast.

## Implementation report

- Paste Stack переведён на borderless `.nonactivatingPanel`; History и Permission сохранили native chrome.
- SwiftUI content заполняет material edge to edge; surface получил continuous radius `18 pt` и system shadow.
- Custom header содержит доступный Cancel, центрированный title, direction toggle и отдельную AppKit drag-region через `performDrag(with:)`.
- List использует plain edge-to-edge layout, нулевые scroll-content margins и внутренние row paddings `14 pt`.
- Custom Close вызывает существующий `cancelPasteStack()`, поэтому session cleanup и menu state не дублируются.
- Последняя позиция сохраняется как две конечные координаты в `UserDefaults` через injected store. `PanelController` принимает её только внутри текущих `NSScreen.visibleFrame`; недоступная позиция заменяется существующим центрированием на экране под курсором.
- SwiftPM: 110 tests, 0 failures. Focused PanelMaterialProviderTests: 8 tests, 0 failures.
- Follow-up 2026-08-27: focused placement/store tests `7/7`, полный SwiftPM suite `142/142` и Xcode Debug XCTest `142/142` прошли.
- 2026-08-30 пользователь подтвердил visual/interaction matrix на двух машинах. Срез переведён в `done`.
