import Carbon.HIToolbox
import Foundation

struct CorrectionSourceDescriptor: Equatable, Identifiable {
    let id: String
    let name: String
    let isCurrent: Bool
    let source: CorrectionSource?
    let unavailableReason: String?
}

/// All TIS access is confined to the main thread. Only immutable IDs and layout tables leave it.
@MainActor
final class LayoutCorrectionSourceCatalog {
    private(set) var sources: [CorrectionSourceDescriptor] = []
    private(set) var currentSourceID: String?
    var onChange: (() -> Void)?

    func refresh() {
        dispatchPrecondition(condition: .onQueue(.main))
        let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
        currentSourceID = current.flatMap(Self.sourceID)
        let list = TISCreateInputSourceList([
            kTISPropertyInputSourceIsEnabled: true
        ] as CFDictionary, false)?.takeRetainedValue() as? [TISInputSource] ?? []
        sources = list.compactMap { source in
            guard let id = Self.sourceID(source), let name = Self.stringProperty(source, kTISPropertyLocalizedName) else { return nil }
            let type = Self.stringProperty(source, kTISPropertyInputSourceType)
            guard Self.boolProperty(source, kTISPropertyInputSourceIsSelectCapable) == true,
                  type == (kTISTypeKeyboardLayout as String),
                  let layoutData = Self.dataProperty(source, kTISPropertyUnicodeKeyLayoutData),
                  let map = Self.buildMap(data: layoutData, keyboardType: UInt32(LMGetKbdType())), !map.isEmpty else {
                return CorrectionSourceDescriptor(id: id, name: name, isCurrent: id == currentSourceID,
                    source: nil, unavailableReason: "No supported static keyboard mapping")
            }
            let value = CorrectionSource(id: id, name: name, isCurrent: id == currentSourceID, keyMap: map)
            return CorrectionSourceDescriptor(id: id, name: name, isCurrent: id == currentSourceID,
                source: value, unavailableReason: nil)
        }.sorted { $0.id < $1.id }
        onChange?()
    }

    func refreshCurrentSelection() {
        dispatchPrecondition(condition: .onQueue(.main))
        let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
        let nextID = current.flatMap(Self.sourceID)
        guard nextID != currentSourceID else { return }
        currentSourceID = nextID
        sources = sources.map { descriptor in
            let selected = descriptor.id == nextID
            let source = descriptor.source.map {
                CorrectionSource(id: $0.id, name: $0.name, isCurrent: selected, keyMap: $0.keyMap)
            }
            return CorrectionSourceDescriptor(id: descriptor.id, name: descriptor.name,
                isCurrent: selected, source: source, unavailableReason: descriptor.unavailableReason)
        }
        onChange?()
    }

    func select(_ sourceID: String) -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        guard sources.contains(where: { $0.id == sourceID }) else { return false }
        let list = TISCreateInputSourceList([
            kTISPropertyInputSourceID: sourceID
        ] as CFDictionary, false)?.takeRetainedValue() as? [TISInputSource] ?? []
        guard let selected = list.first,
              Self.boolProperty(selected, kTISPropertyInputSourceIsEnabled) == true,
              Self.boolProperty(selected, kTISPropertyInputSourceIsSelectCapable) == true,
              TISSelectInputSource(selected) == noErr else { return false }
        refresh()
        return currentSourceID == sourceID
    }

    private static func sourceID(_ source: TISInputSource) -> String? {
        stringProperty(source, kTISPropertyInputSourceID)
    }

    private static func buildMap(data: Data, keyboardType: UInt32) -> [CorrectionPhysicalKey: String]? {
        data.withUnsafeBytes { bytes -> [CorrectionPhysicalKey: String]? in
        guard let base = bytes.baseAddress, bytes.count >= MemoryLayout<UCKeyboardLayout>.size else { return nil }
        let layout = base.assumingMemoryBound(to: UCKeyboardLayout.self)
        let noDeadKeysMask = UInt32(1 << kUCKeyTranslateNoDeadKeysBit)
        var result: [CorrectionPhysicalKey: String] = [:]
        for code in UInt16(0)..<UInt16(128) {
            for level in UInt8(0)..<UInt8(4) {
                let modifiers: UInt32 = ((level & 1) != 0 ? UInt32(shiftKey >> 8) : 0) |
                    ((level & 2) != 0 ? UInt32(alphaLock >> 8) : 0)
                var deadState: UInt32 = 0
                var chars = [UniChar](repeating: 0, count: 8)
                var length: Int = 0
                let status = chars.withUnsafeMutableBufferPointer {
                    UCKeyTranslate(layout, code, UInt16(kUCKeyActionDown), modifiers,
                        keyboardType, noDeadKeysMask, &deadState, $0.count, &length, $0.baseAddress!)
                }
                guard status == noErr, deadState == 0, length > 0, length <= chars.count else { continue }
                var zeroOptionsState: UInt32 = 0
                var zeroOptionsChars = [UniChar](repeating: 0, count: 8)
                var zeroOptionsLength: Int = 0
                let zeroOptionsStatus = zeroOptionsChars.withUnsafeMutableBufferPointer {
                    UCKeyTranslate(layout, code, UInt16(kUCKeyActionDown), modifiers,
                        keyboardType, 0, &zeroOptionsState, $0.count, &zeroOptionsLength, $0.baseAddress!)
                }
                guard zeroOptionsStatus == noErr, zeroOptionsState == 0,
                      zeroOptionsLength == length,
                      Array(zeroOptionsChars.prefix(zeroOptionsLength)) == Array(chars.prefix(length))
                else { continue }
                let value = String(utf16CodeUnits: chars, count: length)
                guard value.unicodeScalars.allSatisfy({ !$0.properties.isDefaultIgnorableCodePoint }),
                      value.rangeOfCharacter(from: .controlCharacters) == nil,
                      value != "\u{7f}" else { continue }
                result[CorrectionPhysicalKey(keyCode: code, level: level)] = value
            }
        }
        return result
        }
    }

    private static func stringProperty(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let raw = TISGetInputSourceProperty(source, key) else { return nil }
        return unsafeBitCast(raw, to: CFString.self) as String
    }

    private static func dataProperty(_ source: TISInputSource, _ key: CFString) -> Data? {
        guard let raw = TISGetInputSourceProperty(source, key) else { return nil }
        let value = unsafeBitCast(raw, to: CFData.self)
        return value as Data
    }

    private static func boolProperty(_ source: TISInputSource, _ key: CFString) -> Bool? {
        guard let raw = TISGetInputSourceProperty(source, key) else { return nil }
        return CFBooleanGetValue(unsafeBitCast(raw, to: CFBoolean.self))
    }
}
