import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum PasteStackPresentationSource {
    case hover
    case click
    case accessibility
}

enum PasteStackPresentationIntent {
    case expand(token: Int, preservesCurrentAlpha: Bool)
    case collapse(token: Int)
    case dismiss(token: Int)
}

@MainActor
final class PasteStackPresentationModel: ObservableObject {
    @Published private(set) var state: PasteStackPresentationState = .hidden
    @Published private(set) var compactGeometry: PasteStackCompactGeometry?

    var onIntent: ((PasteStackPresentationIntent) -> Void)?

    private(set) var generation = 0
    private var expandWorkItem: DispatchWorkItem?
    private var collapseWorkItem: DispatchWorkItem?
    private var pointerIsInside = false
    private var accessibilityHold = false
    private var interactionHoldCount = 0

    deinit {
        expandWorkItem?.cancel()
        collapseWorkItem?.cancel()
    }

    func beginSession(geometry: PasteStackCompactGeometry) {
        compactGeometry = geometry
        cancelScheduledTransitions()
        generation &+= 1
        state = PasteStackPresentationStateMachine.transition(state, event: .show)
        pointerIsInside = false
        accessibilityHold = false
        interactionHoldCount = 0
    }

    func close() {
        cancelScheduledTransitions()
        generation &+= 1
        state = .hidden
        compactGeometry = nil
        pointerIsInside = false
        accessibilityHold = false
        interactionHoldCount = 0
    }

    func updateGeometry(_ geometry: PasteStackCompactGeometry) {
        guard compactGeometry != geometry else { return }
        compactGeometry = geometry
        // A screen change invalidates both the old tracking region and any
        // hover decision made against it. A new region must receive a fresh
        // pointer-enter event before it can expand.
        cancelScheduledTransitions()
        generation &+= 1
        pointerIsInside = false

        switch state {
        case .expanding:
            // The old frame's animation completion is now stale. Restart the
            // reveal against the new frame with the new generation token.
            onIntent?(.expand(token: generation, preservesCurrentAlpha: false))
        case .collapsing:
            // A collapse that was interrupted by relocation can safely finish
            // at the new compact destination; leaving it in the old frame
            // would strand an invisible panel after its old completion fails.
            state = PasteStackPresentationStateMachine.transition(
                state,
                event: .collapseFinished
            )
        case .dismissing:
            // Re-arm dismissal so a stale completion cannot leave the panel
            // ordered on-screen after its display disappears.
            onIntent?(.dismiss(token: generation))
        case .hidden, .compact, .expanded:
            break
        }
    }

    func pointerEntered() {
        pointerIsInside = true
        collapseWorkItem?.cancel()
        collapseWorkItem = nil
        if state == .collapsing {
            requestExpand(source: .hover)
            return
        }
        guard state == .compact else { return }
        scheduleExpand()
    }

    func pointerExited() {
        pointerIsInside = false
        expandWorkItem?.cancel()
        expandWorkItem = nil
        guard !accessibilityHold, interactionHoldCount == 0 else { return }
        guard state == .expanded || state == .expanding else { return }
        scheduleCollapse()
    }

    func beginInteractionHold() {
        interactionHoldCount += 1
        collapseWorkItem?.cancel()
        collapseWorkItem = nil
    }

    func endInteractionHold() {
        interactionHoldCount = max(0, interactionHoldCount - 1)
        guard interactionHoldCount == 0,
              !pointerIsInside,
              !accessibilityHold,
              state == .expanded
        else { return }
        scheduleCollapse()
    }

    func requestExpand(source: PasteStackPresentationSource) {
        expandWorkItem?.cancel()
        expandWorkItem = nil
        guard state == .compact || state == .collapsing else { return }
        let reversesCollapse = state == .collapsing
        if source == .accessibility {
            accessibilityHold = true
        }
        generation &+= 1
        state = PasteStackPresentationStateMachine.transition(state, event: .expand)
        onIntent?(.expand(
            token: generation,
            preservesCurrentAlpha: reversesCollapse
        ))
    }

    func requestExplicitCollapse() {
        accessibilityHold = false
        requestCollapse(force: true)
    }

    func requestCollapse() {
        requestCollapse(force: false)
    }

    func finishExpansion(token: Int) {
        guard generation == token, state == .expanding else { return }
        state = PasteStackPresentationStateMachine.transition(state, event: .expansionFinished)
        if !pointerIsInside, !accessibilityHold {
            scheduleCollapse()
        }
    }

    func finishCollapse(token: Int) {
        guard generation == token, state == .collapsing else { return }
        state = PasteStackPresentationStateMachine.transition(state, event: .collapseFinished)
        if pointerIsInside {
            scheduleExpand()
        }
    }

    func requestDismissal() {
        guard state != .hidden else { return }
        cancelScheduledTransitions()
        accessibilityHold = false
        generation &+= 1
        state = PasteStackPresentationStateMachine.transition(state, event: .dismiss)
        onIntent?(.dismiss(token: generation))
    }

    func finishDismissal(token: Int) {
        guard generation == token, state == .dismissing else { return }
        state = PasteStackPresentationStateMachine.transition(state, event: .dismissalFinished)
    }

    func isCurrent(token: Int, state expectedState: PasteStackPresentationState) -> Bool {
        generation == token && state == expectedState
    }

    private func requestCollapse(force: Bool) {
        collapseWorkItem?.cancel()
        collapseWorkItem = nil
        guard force || (!accessibilityHold && interactionHoldCount == 0) else { return }
        guard state == .expanded || state == .expanding else { return }
        generation &+= 1
        state = PasteStackPresentationStateMachine.transition(state, event: .collapse)
        onIntent?(.collapse(token: generation))
    }

    private func scheduleExpand() {
        expandWorkItem?.cancel()
        let expectedGeneration = generation
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  self.generation == expectedGeneration,
                  self.state == .compact,
                  self.pointerIsInside
            else { return }
            self.requestExpand(source: .hover)
        }
        expandWorkItem = workItem
        DispatchQueue.main.async(execute: workItem)
    }

    private func scheduleCollapse() {
        collapseWorkItem?.cancel()
        let expectedGeneration = generation
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  self.generation == expectedGeneration,
                  !self.pointerIsInside,
                  !self.accessibilityHold,
                  self.interactionHoldCount == 0
            else { return }
            self.requestCollapse()
        }
        collapseWorkItem = workItem
        DispatchQueue.main.async(execute: workItem)
    }

    private func cancelScheduledTransitions() {
        expandWorkItem?.cancel()
        collapseWorkItem?.cancel()
        expandWorkItem = nil
        collapseWorkItem = nil
    }
}
