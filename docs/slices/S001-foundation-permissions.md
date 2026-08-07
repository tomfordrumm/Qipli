---
id: S001
title: Скелет приложения и системное разрешение
status: needs_verification
depends_on: []
covers:
  - FR-016
  - NFR-001
  - NFR-004
  - NFR-008
---

# S001 — Скелет приложения и системное разрешение

## Пользовательский результат

Пользователь может запустить нативную Qipli на macOS 14, увидеть понятное состояние в menu bar, узнать зачем требуется Accessibility, выдать или отклонить разрешение и открыть тестовые поверхности истории/стека глобальными сочетаниями после успешной настройки.

## В scope

- минимальный Xcode-проект/targets и deployment target macOS 14;
- menu bar shell, команды открытия заглушек истории/стека и Quit;
- SwiftUI content внутри управляемых AppKit panels;
- сервис проверки Accessibility trust и понятный onboarding;
- platform spike для глобальных `⌘⇧V`, `⌘⇧C`, event tap и synthetic `⌘V`;
- безопасная реакция на отказ и системное отключение event tap;
- протоколы/адаптеры, позволяющие тестировать доменную логику без реального глобального ввода.

## Вне scope

- чтение и хранение реальной истории;
- полнофункциональные history/stack UI;
- перехват обычного `⌘V` как продуктовая функция;
- release signing и notarization.

## Предусловия

- Решения D-001–D-005 и D-007 приняты как рабочая архитектура.
- Не требуется Apple Developer credential: локальная development-сборка достаточна.

## Ожидаемое поведение

- До разрешения пользователь может открыть Qipli из menu bar и прочитать локальное объяснение.
- Системный prompt вызывается только после понятного пользовательского действия.
- При отказе приложение остаётся управляемым и не показывает ложное состояние готовности.
- После разрешения тестовый event tap видит целевые сочетания, не меняя ввод остальных приложений.
- Если macOS отключает event tap, приложение обнаруживает состояние и либо восстанавливает tap, либо сообщает проблему.

## Состояния интерфейса

- permission unknown/not requested;
- permission denied;
- permission granted / global input ready;
- event tap unavailable/disabled;
- placeholder history panel;
- placeholder empty stack panel.

## Данные и контракты

- Persistent product data отсутствуют.
- Permission service возвращает наблюдаемое состояние, не содержит UI.
- Event adapter предоставляет start/stop/status и различает пользовательские и собственные synthetic events.
- Текст буфера не читается и не логируется в этом срезе.

## Acceptance criteria

- [ ] Проект собирается и запускается с deployment target macOS 14.
- [ ] После запуска доступен status item с командами History, Start Paste Stack, Permission status и Quit; постоянное основное окно не создаётся.
- [ ] При отсутствии Accessibility пользователь видит назначение разрешения и явную кнопку перехода к системной выдаче; отказ не завершает приложение аварийно.
- [ ] После выдачи разрешения `⌘⇧V` и `⌘⇧C` открывают соответствующую placeholder panel поверх активного приложения и не оставляют две копии одной панели.
- [ ] При закрытом Paste Stack обычный `⌘V` проходит без модификации; platform spike доказывает возможность распознать и безопасно пометить собственный synthetic event.
- [ ] Системное событие отключения event tap обрабатывается без busy loop: выполняется ограниченная попытка восстановления, а при неуспехе виден статус ошибки.
- [ ] Команда Quit освобождает event tap и закрывает приложение штатно.
- [ ] В логах тестовой сессии нет содержимого pasteboard; App Sandbox не включён, Hardened Runtime настроен для release configuration без необоснованных exceptions.

## Verification

- [x] Запустить unit tests permission/event adapter с fake implementations.
- [x] Собрать Debug и Release configurations для macOS 14 target.
- [ ] На профиле без разрешения проверить запуск, отказ, переход в System Settings и сохранение управляемого состояния.
- [ ] Выдать разрешение, перезапустить приложение и проверить оба глобальных сочетания из другого приложения.
- [ ] Убедиться в TextEdit и браузере, что обычный `⌘V` без активного стека не изменён.
- [ ] Принудительно смоделировать disabled event tap через adapter test hook и проверить восстановление/ошибку.

## Definition of Done

- [ ] Все acceptance criteria выполнены.
- [ ] Автоматические и ручные проверки пройдены.
- [ ] Приложение собирается без новой регрессии.
- [ ] `STATE.md` и frontmatter синхронно обновлены.
- [ ] Новые значимые решения записаны в `DECISIONS.md`.
- [ ] Implementation report заполнен.

## Implementation report

### Реализовано

- Добавлены минимальные `Qipli.xcodeproj` (application target и `QipliTests`) и Swift Package configuration с deployment target macOS 14.
- Добавлен явный programmatic AppKit bootstrap, который создаёт и удерживает app delegate до завершения event loop; это гарантирует запуск menu bar shell без storyboard/nib.
- Реализована menu bar оболочка без постоянного main window: команды `History`, `Start Paste Stack`, permission status и штатный `Quit`.
- Status item использует фиксированную видимую ширину и template-иконку clipboard с текстовым fallback.
- Добавлены singleton AppKit panels c SwiftUI placeholder content для History, Paste Stack и Accessibility onboarding.
- Добавлен инъецируемый `AccessibilityPermissionService`: проверка trust, явный user-triggered системный prompt и переход в System Settings. При отсутствии trust global input не запускается.
- Добавлены изолированные `InputCoordinator` и `GlobalInputEventAdapting`. Production adapter использует listen-only `CGEvent` tap для `⌘⇧V`/`⌘⇧C`, поэтому не модифицирует обычный `⌘V`.
- Platform spike включает отправку synthetic `⌘V` с process marker, распознавание marker во входящем событии и bounded recovery (две попытки с проверкой результата) после системного отключения event tap.
- После исчерпания recovery пользовательский повтор через Permission Status пересоздаёт adapter вместо сохранения нерабочего tap.
- Добавлены XCTest с fake permission/input adapters и чистой классификацией keyboard events; они проверяют permission states, retry, hotkeys, неизменность обычного `⌘V`, synthetic marker и recovery policy без Accessibility или clipboard data.
- Debug app target настроен как testable и без оптимизации; test target получил стабильные product/module names, поэтому XCTest bundle корректно собирается и загружается.
- Для release target задан Hardened Runtime. Entitlements намеренно пусты: App Sandbox и необоснованные exceptions отсутствуют.

### Изменённые файлы

- `.gitignore`
- `Package.swift`
- `Qipli.xcodeproj/project.pbxproj`, scheme и workspace metadata
- `Sources/Qipli/App/*`, `Sources/Qipli/Input/*`, `Sources/Qipli/UI/*`, `Sources/Qipli/Resources/*`
- `Tests/QipliTests/InputCoordinatorTests.swift`
- `docs/STATE.md` и этот slice

### Выполненная проверка

- `swift build` (Debug) — успешно.
- `swift build -c release` — успешно.
- Xcode Debug build для macOS 14 target с `CODE_SIGNING_ALLOWED=NO` — успешно.
- Xcode Release build для macOS 14 target с `CODE_SIGNING_ALLOWED=NO` — успешно.
- Xcode XCTest — успешно: 9 тестов, 0 ошибок.
- `plutil -lint` для `.pbxproj`, `Info.plist` и entitlements — успешно.
- `git diff --check` — успешно.
- Статически подтверждено: deployment target 14.0, Hardened Runtime включён, App Sandbox entitlement отсутствует, product code не содержит pasteboard read/logging или network/telemetry API.

### Отклонения от плана

- Первоначальный programmatic AppKit target полагался на автоматическое создание `NSApplicationDelegate`, но без storyboard/nib delegate не инстанцировался. Во время ручного запуска это обнаружено и исправлено явной точкой входа.
- Ручная проверка Accessibility/event tap пока не выполнена, поэтому функциональный статус среза остаётся `needs_verification`.

### Оставшиеся проблемы

- Перезапустить приложение из Xcode и подтвердить появление status item/menu и onboarding.
- На чистом или поддерживаемом профиле macOS вручную проверить отказ/выдачу Accessibility, оба global shortcuts из другого приложения, неизменность обычного `⌘V`, singleton panels, synthetic event marker и exhausted event-tap recovery.
