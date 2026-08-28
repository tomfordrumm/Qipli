---
id: S011
title: Опциональный first-run onboarding
status: needs_verification
depends_on:
  - S010
covers:
  - FR-021
  - BR-013
  - BR-014
  - NFR-002
  - NFR-003
  - NFR-010
  - NFR-011
---

# S011 — Опциональный first-run onboarding

## Пользовательский результат

При первом запуске пользователь до начала чтения pasteboard понимает назначение Qipli, локальное хранение и риск чувствительного текста, по собственному выбору выдаёт Accessibility и включает автозапуск, узнаёт основные shortcuts и может сразу начать работу или пропустить настройку.

## В scope

- one-time first-run decision до старта pasteboard monitor;
- короткий опциональный onboarding с Welcome/Privacy, Accessibility, Launch at Login и Shortcuts/Finish;
- явные Continue, Back, Skip/close и Finish;
- использование S010 services и текущих фактических states без дублирования логики;
- локальный completion marker и повторный запуск из Settings;
- degraded completion без Accessibility или login item;
- keyboard/VoiceOver accessibility и manual clean-profile verification.

## Вне scope

- обязательная выдача Accessibility;
- автоматическое включение Launch at Login;
- обязательное переназначение shortcuts;
- tutorial с реальным clipboard payload или записью тестового текста в history;
- аккаунт, telemetry, analytics, remote content или повторный показ на каждом update;
- реализация Settings/shortcut/login-item services: это S010.

## Предусловия

- S010 завершён и предоставляет единые permission, shortcut и launch-at-login state/actions.
- Existing Core Data store и settings сохраняются независимо от onboarding completion.
- Apple HIG Onboarding/Privacy guidance перепроверена 2026-08-12: flow должен быть быстрым и опциональным, permission request — контекстным и user-triggered, необязательная кастомизация — отложенной.

## Ожидаемое поведение

- На первом запуске текущего local profile onboarding становится первой пользовательской поверхностью, а pasteboard monitor не начинает чтение до Finish, Skip или явного close.
- Первый экран кратко объясняет 30-дневную локальную историю, отсутствие сети/аккаунта и риск сохранения паролей, токенов и другого чувствительного текста.
- Accessibility prompt вызывается только кнопкой `Allow Access`. Deny, закрытие System Settings или Skip не блокируют flow; UI показывает фактический state, а granted-state обозначается зелёной галочкой.
- Launch at Login показан выключенным, если service не enabled; onboarding не вызывает register без явного toggle/action пользователя и честно показывает requires-approval/error.
- Shortcuts screen показывает текущие bindings и основные History/Paste Stack/Reactivate Previous flows, но не требует кастомизации.
- Finish, Skip и close сохраняют completion и запускают обычный shell/monitor ровно один раз. Crash/force quit до сохранения completion приводит к повторному показу.
- `Show Onboarding Again` из Settings открывает тот же flow, но не останавливает уже работающий monitor, не сбрасывает completion/settings и не вызывает permission/login actions автоматически.

## Состояния интерфейса

- first launch pending;
- Welcome/Privacy;
- Accessibility notRequested/denied/granted;
- Launch at Login off/enabled/requires approval/error;
- Shortcuts summary with defaults/custom values;
- skipped/completed;
- manually reopened from Settings;
- interrupted before completion.

## Данные и контракты

- Completion marker хранит только факт завершения для текущего application preferences domain; удаление app bundle без удаления preferences не обещает новый onboarding.
- Privacy screen не читает и не отображает pasteboard. Clipboard monitoring starts only after first-run dismissal boundary.
- Onboarding использует те же injected services, что Settings; у permission, shortcuts и login item остаётся один source of truth.
- Finish/Skip/close должны быть idempotent: повторные callbacks не запускают второй monitor, timer или event tap.
- Manual re-open не меняет completion marker и не блокирует текущие product flows.

## Acceptance criteria

- [ ] На чистом preferences profile onboarding показывается до первого pasteboard read; без чистого профиля обычный запуск не показывает его автоматически.
- [x] Welcome/Privacy ясно сообщает локальную 30-дневную историю, отсутствие передачи содержимого и риск чувствительного текста до разрешения и capture.
- [x] Accessibility запрашивается только после явной кнопки; grant, deny, Skip и возврат из System Settings оставляют flow управляемым и показывают фактическое состояние, включая зелёную галочку после grant.
- [x] Launch at Login выключен по умолчанию и меняется только явным действием; enabled/requires-approval/error соответствуют S010/system status.
- [x] Текущие default/custom shortcuts и три основные команды объяснены без обязательного recorder step; ordinary `⌘V` и `Esc` обозначены как неизменяемые Stack actions.
- [x] Finish, Skip и close атомарно сохраняют completion и запускают обычный monitoring один раз; interruption до completion приводит к повторному onboarding.
- [x] Повторный запуск из Settings не сбрасывает настройки/completion, не останавливает monitor и не вызывает системные prompts без действия пользователя.
- [ ] Flow полностью доступен с клавиатуры и VoiceOver, корректен в Light/Dark и не использует реальный clipboard content в UI, tests или logs.

## Verification

- [x] Unit tests completion state machine для fresh/completed/interrupted/reopened и idempotent shell start.
- [x] Unit tests, что pasteboard monitor не стартует до dismissal и стартует ровно один раз для Finish/Skip/close.
- [x] Injected permission/login-item tests доказывают отсутствие implicit request/register и корректные degraded/requires-approval/error states.
- [x] Presentation tests фиксируют зелёный success tint только для granted Accessibility и сохраняют accent tint для остальных состояний.
- [x] AppKit window lifecycle tests для first-run и Settings re-open без duplicate.
- [x] Полный SwiftPM/Xcode XCTest suite, Debug и universal Release builds.
- [ ] Manual clean-profile matrix: grant, deny, Skip, close, quit mid-flow, relaunch, custom shortcuts и Show Onboarding Again.
- [ ] Manual privacy/log inspection подтверждает отсутствие pasteboard read до dismissal и отсутствие clipboard/search/previews в logs.
- [ ] VoiceOver/keyboard, Light/Dark, Reduce Transparency и Increase Contrast smoke.

## Definition of Done

- [ ] Все acceptance criteria выполнены.
- [ ] Автоматические и ручные проверки пройдены.
- [x] Приложение собирается без новой регрессии.
- [x] `STATE.md` и frontmatter синхронно обновлены.
- [x] Реализация следует D-019 и D-021; новых значимых решений не потребовалось.
- [x] Implementation report заполнен.

## Implementation report

### Реализовано

- Добавлен `OnboardingCoordinator` с локальным completion marker, режимами first run/reopen и idempotent startup gate. Fresh profile показывает onboarding, completed profile сразу запускает product services, а прерванный до dismissal flow остаётся pending.
- `ApplicationShell` больше не создаёт видимый status item и не запускает input, history reload, retention timer или pasteboard monitor до Finish, Skip или пользовательского закрытия onboarding. `PasteboardMonitor` не читает даже `changeCount` в `init`; baseline берётся только в `start()`.
- Singleton `OnboardingWindowController` показывает четыре шага: локальная privacy/value информация, Accessibility, Launch at Login и текущие shortcuts. Все permission и login-item действия остаются явными и используют services S010.
- Finish, Skip и close сохраняют completion и открывают startup gate один раз. Programmatic close при termination не считается завершением, поэтому force quit до dismissal повторит onboarding.
- Settings General получил рабочее действие `Show Onboarding Again`. Reopen не меняет completion, shortcuts или launch-at-login state и не останавливает уже запущенные services.
- Onboarding получил light modern split-card presentation: прозрачный native title bar с сохранёнными traffic lights, единый cold-blue accent, semantic progress dots, адаптивные system colors/materials и компактные content surfaces. Четыре продуктовых шага и их действия не менялись.
- Переходы Continue/Back используют direction-aware opacity/transform animation длительностью 220 ms. При Reduce Motion positional movement заменяется 200 ms crossfade; primary action получает 120 ms press-feedback. Clipboard text, search queries и previews в UI, preferences, tests или logs не добавлены.
- Follow-up 2026-08-27 использует уже существующий polling `AccessibilityPermissionService`: после публикации `.granted` onboarding автоматически перерисовывает checkmark с семантическим зелёным tint, не добавляя второй источник permission state.

### Изменённые файлы

- `Sources/Qipli/App/ApplicationShell.swift`
- `Sources/Qipli/Clipboard/PasteboardMonitor.swift`
- `Sources/Qipli/Onboarding/OnboardingCoordinator.swift`
- `Sources/Qipli/UI/OnboardingWindowController.swift`
- `Sources/Qipli/UI/SettingsWindowController.swift`
- `Tests/QipliTests/OnboardingTests.swift`
- `Tests/QipliTests/PasteboardMonitorTests.swift`
- `Tests/QipliTests/PasteStackTests.swift`
- `Qipli.xcodeproj/project.pbxproj`
- `docs/PLAN.md`
- `docs/STATE.md`
- `docs/slices/S011-first-run-onboarding.md`

### Выполненная проверка

- Полный SwiftPM suite: 132 tests, 0 failures.
- Xcode Debug XCTest: 132 tests, 0 failures.
- Universal Release с deployment target macOS 14 и `CODE_SIGNING_ALLOWED=NO` собран; `lipo -info` подтвердил `x86_64 arm64`.
- `plutil -lint Qipli.xcodeproj/project.pbxproj` и `git diff --check` прошли.
- Unit/AppKit проверки покрывают fresh/completed/interrupted/reopened, idempotent startup, direction reset, Skip/Finish/close, termination close, singleton full-size-content window, отсутствие implicit permission/register и нулевое чтение pasteboard при создании monitor.
- Временная Debug-сборка из `/tmp` повторно визуально проверена в Light appearance после редизайна: все четыре split-card экрана помещаются в окно, тексты и controls не обрезаны, Accessibility tree видит progress, status, actions и shortcuts. Системные permission/login-item state не менялись; приложение закрыто через Quit до completion.
- Follow-up 2026-08-27: focused success-tint tests `2/2`, полный SwiftPM suite `142/142` и Xcode Debug XCTest `142/142` прошли.

### Отклонения от плана

Ручная clean-profile, VoiceOver и appearance/accessibility матрица не выполнялась автоматически. Поэтому срез имеет статус `needs_verification`, а не `done`.

### Оставшиеся проблемы

Product-code blockers не обнаружены. Для завершения S011 нужна пользовательская ручная проверка fresh/completed/interrupted/reopened, реальных Accessibility и Launch at Login states, keyboard/VoiceOver, Light/Dark, Reduce Transparency, Increase Contrast и отсутствия раннего clipboard capture. Signed clean-machine install/upgrade verification остаётся в S008.
