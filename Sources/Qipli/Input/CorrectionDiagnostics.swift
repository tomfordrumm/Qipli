import Foundation

// Every string in the on-disk schema comes from these closed enums. Never add
// text, identifiers, hashes of payload, raw AX roles or error descriptions here.
enum DiagnosticStep: String, Codable, Sendable {
    case admission, capture, read, matches, validate, replacement, leftContext, rightContext
    case preDispatchValidation, selectReplacement, waitSelection, selectedText, dispatch
    case waitPaste, verifyContext, finalSelection, waitFinalSelection, clipboardSnapshot
    case clipboardWrite, clipboardRestore, clipboardFinish, sourceSelection, worker, completion
    case wordSpaceRead, wordLeftRead, wordRightRead, wordRead, cycleRead, selectedRead
}
enum DiagnosticAPI: String, Codable, Sendable {
    case setMessagingTimeout, copyAttribute, copyParameterizedNames, copyStringForRange
    case getPID, isAttributeSettable, setSelectedRange, decodeSelectedRange, createRange
    case selectInputSource
}
enum DiagnosticAXAttribute: String, Codable, Sendable {
    case focusedApplication, focusedElement, role, subrole, enabled, value, selectedRange, characterCount, stringForRange
}
enum DiagnosticCheck: String, Codable, Sendable {
    case wordBlocked, wordMissing, trailingSpaces, targetChanged, wordExpired, sourceChanged
    case caretBoundary, spaceBoundary, leftBoundary, rightBoundary, wordBoundary, contextChanged
    case targetProcess, permission, secureInput, roleSupported, fieldEnabled, valueSettable, selectionSettable
    case rangeReadSupported, resultType, rangeType, rangeDecode, rangeValid, readLength, readLimit
    case applicationMatches, elementMatches, selectionMatches, countMatches, operationFresh
    case replacementLimit, replacementSelection, expectedTextMatches, leftContextMatches, rightContextMatches
    case clipboardRegistration, clipboardItemLimit, clipboardRepresentationLimit, clipboardReadable
    case clipboardByteLimit, clipboardCopy, clipboardUnchanged, clipboardWrite, clipboardOwned, clipboardRestored
    case eventCreation, pasteCount, pasteCaret, pasteText, finalTarget, finalText, finalRange
    case inputEpoch, gateEpoch, compositionCertain, cycleAge, cycleSources, cycleSource, cycleTarget, cycleRange, cycleText
    case currentSource, mappingSource, sourceExists, sourceEnabled, sourceSelectable, sourceConfirmed, deadline
}
enum DiagnosticValueType: String, Codable, Sendable { case missing, string, number, boolean, array, axElement, axValue, data, other }
enum DiagnosticFieldRole: String, Codable, Sendable { case textArea, textField, secureTextField, other }
enum DiagnosticTargetKind: String, Codable, Sendable { case chrome, safari, firefox, edge, other }

struct DiagnosticDetails: Codable, Sendable {
    var step: DiagnosticStep? = nil
    var parentStep: DiagnosticStep? = nil
    var api: DiagnosticAPI? = nil
    var attribute: DiagnosticAXAttribute? = nil
    var check: DiagnosticCheck? = nil
    var expectedType: DiagnosticValueType? = nil
    var observedType: DiagnosticValueType? = nil
    var axError: Int32? = nil
    var osStatus: Int32? = nil
    var callMicroseconds: UInt64? = nil
    var remainingMilliseconds: UInt64? = nil
    var rangeLocation: Int? = nil
    var rangeLength: Int? = nil
    var selectionLocation: Int? = nil
    var selectionLength: Int? = nil
    var characterCount: Int? = nil
    var expected: Int? = nil
    var observed: Int? = nil
    var matches: Bool? = nil
    var iteration: Int? = nil
    var role: DiagnosticFieldRole? = nil
    var targetKind: DiagnosticTargetKind? = nil
    var sourceCount: Int? = nil
    var sourceIndex: Int? = nil
    var destinationIndex: Int? = nil
    var wordUnits: UInt32? = nil
    var trailingSpaces: UInt8? = nil
    var wordAgeMilliseconds: UInt64? = nil
    var inputGeneration: UInt64? = nil
    var gateGeneration: UInt64? = nil
    var blocked: Bool? = nil
    var compositionUncertain: Bool? = nil
    var dispatched: Bool? = nil
    var confirmed: Bool? = nil
    var droppedRecords: UInt64? = nil
    var inputReady: Bool? = nil
    var stackActive: Bool? = nil
    var finderActive: Bool? = nil
    var historyPasteActive: Bool? = nil
    var operationActive: Bool? = nil
    var ownTarget: Bool? = nil
    var lastFailure: DiagnosticFailure? = nil
    var osMajor: Int? = nil
    var osMinor: Int? = nil
    var osPatch: Int? = nil
}

/// One operation owns this trace, including delayed clipboard restoration.
/// The sink only accepts typed structural evidence and never retains AX payload.
struct DiagnosticFailure: Codable, Sendable {
    let stage: DiagnosticStage
    let reason: DiagnosticReason
    let step: DiagnosticStep?
    let api: DiagnosticAPI?
    let attribute: DiagnosticAXAttribute?
    let check: DiagnosticCheck?
    let axError: Int32?
    let osStatus: Int32?
    let expectedType: DiagnosticValueType?
    let observedType: DiagnosticValueType?
    let expected: Int?
    let observed: Int?
    let callMicroseconds: UInt64?
    let remainingMilliseconds: UInt64?
    let rangeLocation: Int?
    let rangeLength: Int?
    let selectionLocation: Int?
    let selectionLength: Int?
    let characterCount: Int?
}

final class CorrectionDiagnosticTrace: @unchecked Sendable {
    private let lock = NSLock()
    private var lastFailure: DiagnosticFailure?
    let sink: @Sendable (DiagnosticStage, DiagnosticReason, DiagnosticDetails?) -> Void
    init(sink: @escaping @Sendable (DiagnosticStage, DiagnosticReason, DiagnosticDetails?) -> Void) { self.sink = sink }

    func callAsFunction(_ stage: DiagnosticStage, _ reason: DiagnosticReason, _ details: DiagnosticDetails? = nil) {
        var details = details
        lock.withLock {
            // Keep the concrete cause in memory until the terminal record. Parent
            // scope unwinding must never replace an AX error with 'unavailable'.
            if stage == .finished {
                if reason != .completed, let lastFailure {
                    if details == nil { details = DiagnosticDetails() }
                    details?.lastFailure = lastFailure
                }
            } else if stage != .checkpoint && reason != .started && reason != .passed &&
                reason != .restored && reason != .restoreSkipped && reason != .restoreDeferred {
                if lastFailure == nil || details?.api != nil || details?.check != nil {
                    lastFailure = DiagnosticFailure(stage: stage, reason: reason, step: details?.step,
                        api: details?.api, attribute: details?.attribute, check: details?.check,
                        axError: details?.axError, osStatus: details?.osStatus,
                        expectedType: details?.expectedType, observedType: details?.observedType,
                        expected: details?.expected, observed: details?.observed,
                        callMicroseconds: details?.callMicroseconds, remainingMilliseconds: details?.remainingMilliseconds,
                        rangeLocation: details?.rangeLocation, rangeLength: details?.rangeLength,
                        selectionLocation: details?.selectionLocation, selectionLength: details?.selectionLength,
                        characterCount: details?.characterCount)
                }
            }
        }
        sink(stage, reason, details)
    }
}

extension DiagnosticTargetKind {
    init(bundleIdentifier: String?) {
        switch bundleIdentifier {
        case "com.google.Chrome": self = .chrome
        case "com.apple.Safari": self = .safari
        case "org.mozilla.firefox": self = .firefox
        case "com.microsoft.edgemac": self = .edge
        default: self = .other
        }
    }
}
