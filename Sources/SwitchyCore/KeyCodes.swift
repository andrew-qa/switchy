import Foundation

/// Virtual key codes (Carbon `kVK_*`) and their display names.
///
/// Names are fixed to the US/ABC positions on purpose: a shortcut is a physical key, and showing
/// "⌥ф" while Ukrainian is active would be more confusing than helpful.
public enum KeyCode {
    public static let escape: UInt16 = 53

    /// F1–F20. These are the only keys allowed as shortcuts without a modifier,
    /// because a bare letter shortcut would make that letter impossible to type.
    public static let functionKeys: Set<UInt16> = [
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90,
    ]

    public static func name(for keyCode: UInt16) -> String {
        names[keyCode] ?? "Key \(keyCode)"
    }

    static let names: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        10: "§", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7",
        27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
        36: "↩", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
        45: "N", 46: "M", 47: ".", 48: "⇥", 49: "Space", 50: "`", 51: "⌫", 52: "⌤", 53: "⎋",
        64: "F17", 65: "Keypad .", 67: "Keypad *", 69: "Keypad +", 71: "⌧", 75: "Keypad /",
        76: "⌤", 78: "Keypad -", 79: "F18", 80: "F19", 81: "Keypad =",
        82: "Keypad 0", 83: "Keypad 1", 84: "Keypad 2", 85: "Keypad 3", 86: "Keypad 4",
        87: "Keypad 5", 88: "Keypad 6", 89: "Keypad 7", 90: "F20", 91: "Keypad 8", 92: "Keypad 9",
        93: "¥", 94: "_", 95: "Keypad ,", 96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8",
        101: "F9", 102: "英数", 103: "F11", 104: "かな", 105: "F13", 106: "F16", 107: "F14",
        109: "F10", 110: "☰", 111: "F12", 113: "F15", 114: "Help", 115: "↖", 116: "⇞", 117: "⌦",
        118: "F4", 119: "↘", 120: "F2", 121: "⇟", 122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑",
    ]
}
