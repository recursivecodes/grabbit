import AppKit

// MARK: - Preference keys

enum Prefs {
    static let borderWeight      = "grabbit.borderWeight"
    static let borderColor       = "grabbit.borderColor"
    static let shadowX           = "grabbit.shadowX"
    static let shadowY           = "grabbit.shadowY"
    static let shadowBlur        = "grabbit.shadowBlur"
    static let shadowColor       = "grabbit.shadowColor"
    static let shadowOpacity     = "grabbit.shadowOpacity"
    static let arrowWeight       = "grabbit.arrowWeight"
    static let arrowColor        = "grabbit.arrowColor"
    static let borderEnabled     = "grabbit.borderEnabled"
    static let shadowEnabled     = "grabbit.shadowEnabled"
    static let textFontName      = "grabbit.textFontName"
    static let textFontSize      = "grabbit.textFontSize"
    static let textFontColor     = "grabbit.textFontColor"
    static let textOutlineColor  = "grabbit.textOutlineColor"
    static let textOutlineWeight = "grabbit.textOutlineWeight"
    static let shapeBorderWeight = "grabbit.shapeBorderWeight"
    static let shapeBorderColor  = "grabbit.shapeBorderColor"
    static let shapeFillColor    = "grabbit.shapeFillColor"
    static let stepDiameter      = "grabbit.stepDiameter"
    static let stepFillColor     = "grabbit.stepFillColor"
    static let stepTextColor     = "grabbit.stepTextColor"
}

// MARK: - UserDefaults helpers

func loadDouble(_ key: String, default def: Double) -> Double {
    UserDefaults.standard.object(forKey: key) != nil
        ? UserDefaults.standard.double(forKey: key) : def
}

func loadColor(_ key: String, default def: NSColor) -> NSColor {
    guard let data = UserDefaults.standard.data(forKey: key),
          let c = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data)
    else { return def }
    return c
}

func loadString(_ key: String, default def: String) -> String {
    UserDefaults.standard.string(forKey: key) ?? def
}

func saveDouble(_ value: Double, key: String) {
    UserDefaults.standard.set(value, forKey: key)
}

func saveColor(_ color: NSColor, key: String) {
    if let data = try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: true) {
        UserDefaults.standard.set(data, forKey: key)
    }
}

func saveString(_ value: String, key: String) {
    UserDefaults.standard.set(value, forKey: key)
}

// MARK: - Tool mode

enum ToolMode { case none, arrow, text, shape, crop, blur, highlight, ocr, spotlight, step }
