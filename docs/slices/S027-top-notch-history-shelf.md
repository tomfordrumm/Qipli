---
id: S027
title: Top Notch History shelf
status: done
depends_on:
  - S016
  - S024
covers:
  - FR-003
  - FR-004
  - FR-005
  - FR-017
  - FR-026
  - FR-033
  - BR-022
  - BR-025
  - BR-027
  - NFR-005
  - NFR-009
  - NFR-021
  - NFR-026
  - NFR-027
  - NFR-028
---

# S027: Top Notch History shelf

## Пользовательский результат

По default `⌘⇧V` пользователь получает быстрый History shelf, который раскрывается сверху текущего экрана, сразу принимает поисковый запрос и показывает недавние occurrences карточками. Из него можно выбрать и вставить text или typed item, не открывая обычное окно и не меняя поведение `⌘V` вне active Paste Stack.

## В scope

- reusable borderless Top Notch `NSPanel`, привязанный к верхней safe/camera area текущего display;
- top-center fallback ниже menu bar для display без camera housing;
- состояния `hidden`, `appearing`, `visible`, `dismissing` с раскрытием вниз и стабильным top anchor;
- Search внутри панели с focus по shortcut;
- horizontal virtualized shelf type-aware карточек для text, URL, image и file/video reference;
- bounded previews и thumbnails только для видимых карточек;
- leading/trailing keyboard selection, `Enter`/double-click paste и existing Delete/click-away/Escape contracts;
- существующий custom History shortcut: `⌘⇧V` остаётся default, а валидное переназначение продолжает вызывать ту же Top Notch;
- Light/Dark, Reduce Transparency, Increase Contrast, Reduce Motion и VoiceOver.

## Вне scope

- действие `Развернуть` и новое полноценное окно — S028;
- Favorites и другая навигация — S029;
- положение справа, слева или снизу и Settings для него — BL-002;
- hover activation, drag-and-drop, remote URL preview, OCR и media content analysis;
- изменение typed capture, persistence, retention, Paste Stack или ordinary `⌘V`.

## Системные и UI-контракты

- Target application и presentation session фиксируются до активации Qipli. Panel становится key только по явному History action, потому что Search должен принять ввод.
- Screen выбирается по user target window, затем по mouse screen, main/first screen как bounded fallback. Геометрия использует `safeAreaInsets`, auxiliary top areas и `visibleFrame`; physical notch dimensions не зашиваются.
- На camera-housing display анимация начинается из geometry физической челки и раскрывается вниз и в стороны. Состояние `hidden` не рисует Qipli surface или hit area: после обратного схлопывания panel вызывает `orderOut`, и на экране остаётся только физический вырез. На notchless display панель центрирована у верхней границы доступной рабочей области и не перекрывает menu bar.
- `NSCollectionView` переиспользует item views. Data source получает только bounded descriptors; exact payload materialized только после single paste reservation.
- Text card показывает несколько bounded строк, image — local thumbnail, URL — local URL/domain, file/video — local metadata и availability. Карточка не инициирует network request.
- Selection принадлежит общей History presentation state. Visual animation не откладывает synchronous selection/scroll/paste path.
- Click-away/Command-Tab скрывает только Top Notch пассивно и не возвращает stale target. Explicit Escape сохраняет существующий cancel contract.

## Acceptance criteria

- [x] Default `⌘⇧V` раскрывает одну Top Notch panel на экране текущего target и фокусирует Search без дополнительного click.
- [x] Camera-housing и notchless placement не перекрывают menu bar, не выходят за visible screen и корректно пересчитываются после смены display geometry.
- [x] Панель раскрывается вниз от стабильного top anchor; при Reduce Motion используется bounded fade/resize без spatial spring.
- [x] Закрытие схлопывает surface обратно к camera housing, затем полностью скрывает окно; постоянной compact-плашки Qipli нет.
- [x] Search, empty/no-results/loading/error states используют existing bounded database-backed History contract.
- [x] Horizontal карточки корректно различают text, URL, image и file/video reference; длинный text и thumbnail не материализуют полный retention window.
- [x] Стрелки меняют selection и viewport синхронно, `Enter`/double-click создаёт ровно одну paste transaction, Delete и Escape сохраняют S016 semantics.
- [x] Click-away или Command-Tab скрывает Top Notch без вставки и без возврата фокуса поверх нового user target.
- [x] Custom History shortcut продолжает работать, а ordinary `⌘V` вне active Paste Stack не меняется.
- [x] VoiceOver сообщает Search, тип/состояние карточки и selection; Light/Dark и accessibility appearance сохраняют читаемость.

## Verification

- pure geometry tests: camera-safe frame, notchless fallback, narrow/wide/moved displays, menu-bar clearance и frame clamp;
- presentation-state tests: repeated show, animation interruption, resign-key, explicit Escape, stale session и one-visible-panel invariant;
- collection adapter tests: item reuse, selected exact UUID, bounded thumbnail requests и no full-payload snapshot;
- focused Search/arrow/Enter/Delete/click-away/paste target regression suite из S016/S023/S024;
- full SwiftPM/Xcode suite, Debug/Release universal build, privacy/network scan и `git diff --check`;
- manual MacBook camera-housing + external notchless display matrix, включая full-screen Space, second display, Light/Dark, Reduce Motion/Transparency, VoiceOver и две target apps.

## Implementation report

Реализовано в текущем рабочем срезе:

- добавлены borderless `TopNotchHistoryPanel`, screen/safe-area geometry и presentation state machine с раскрытием вниз, стабильным верхним anchor, Reduce Motion fallback и bounded frame clamp;
- `PanelController` переиспользует существующие History target/paste/failure/click-away contracts, а default и configurable History shortcut открывают одну Top Notch presentation с фокусом Search;
- добавлен переиспользуемый горизонтальный `NSCollectionView` с type-aware text/URL/image/file-video cards, bounded previews, lazy thumbnails, keyboard selection, Enter/double-click paste и Delete handling;
- Top Notch surface получил непрозрачный чёрный фон и единый непрерывный путь: вогнутые верхние curl переходят в прямые боковые стенки, а крупные выпуклые нижние дуги продолжаются внутрь от тех же стенок без острых «крыльев». Panel поднят на `mainMenu + 3`, notch mode якорится верхним краем экрана и центрируется по auxiliary-area gap, пересчитывается при изменении параметров дисплея, а Search/cards получают динамический inset ниже физической челки с компенсацией высоты панели, поэтому viewport карточек не обрезается; keyboard hint использует `←/→`, Search получает focus после показа панели;
- opening держит окно и SwiftUI content в конечной ширине, а из фактической auxiliary-area camera gap за 200 ms раскрывает только центрированную shape mask и проявляет уже разложенный content. Поэтому карточки не перераскладываются и не «выезжают» сбоку. Closing анимирует ту же mask обратно за 160 ms и только после этого вызывает `orderOut`; скрытого compact-состояния и постоянного hit area нет. Reduce Motion оставляет короткий opacity transition без spatial resize;
- expanded shelf увеличен до 1 080 pt; Search, footer и начало carousel используют 46-pt safe horizontal inset за 32-pt вогнутыми верхними переходами, поэтому интерактивный content не попадает под shape mask, а дальний край carousel по-прежнему обрезается viewport;
- collection selection теперь заменяется строго одним active item без накопления синего highlight при повторной навигации;
- exact-entry materialization теперь возвращает явный `entryUnavailable` вместо silent no-op и оставляет пользователю retryable error state;
- обновлены material/panel contracts, Xcode project membership и focused geometry/state/card tests.

До корректировки контура полный SwiftPM suite и подписанный native Xcode Debug suite прошли `233/233`. После финальных visual/layout изменений focused geometry/material suite прошёл `19/19`, подписанная universal Xcode Debug сборка завершилась успешно, `git diff --check` чист. Повторный полный SwiftPM suite получил environment failure `insufficientDiskSpace` при заполнении системного диска на 97%; это не кодовый failure. Пользователь подтвердил ручную display/appearance/accessibility/focus/paste matrix, поэтому срез закрыт как `done` на основании scoped user acceptance.
