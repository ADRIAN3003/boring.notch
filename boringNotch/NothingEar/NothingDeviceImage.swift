import Defaults
import SwiftUI

/// A Nothing / CMF product we have art for.
///
/// The images come from the NothingBar project (bestK1ngArthur/nothing-bar,
/// GPL-3.0) and live in `Assets.xcassets/NothingDevices`. The protocol doesn't
/// report the colour, so the user picks it (see `Defaults[.nothingDeviceColors]`)
/// and the first entry of `colours` is the default.
struct NothingDeviceModel: Equatable {
    /// Asset name prefix. Also the key the chosen colour is stored under.
    let key: String
    /// Colourways with art, default first. Empty when the model has a single look.
    let colours: [String]
    /// Earbuds have a left and a right image, headphones have one.
    let isPair: Bool

    private static func pair(_ key: String, _ colours: String...) -> Self {
        Self(key: key, colours: colours, isPair: true)
    }

    private static func single(_ key: String, _ colours: String...) -> Self {
        Self(key: key, colours: colours, isPair: false)
    }

    func colour(chosen: String?) -> String? {
        if let chosen, colours.contains(chosen) { return chosen }
        return colours.first
    }

    func assetNames(colour: String?) -> [String] {
        let base = colour.map { "\(key)_\($0)" } ?? key
        return isPair ? ["\(base)_left", "\(base)_right"] : [base]
    }

    static func colourTitle(_ colour: String) -> String {
        let words = colour.replacingOccurrences(of: "_", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    static func resolve(name: String?) -> NothingDeviceModel? {
        guard let name else { return nil }
        // "Nothing Ear (3a)" -> " nothing ear 3a ", so model checks match whole words.
        let normalized = " " + name.lowercased()
            .map { $0.isLetter || $0.isNumber ? String($0) : " " }
            .joined()
            .split(separator: " ")
            .joined(separator: " ") + " "

        func has(_ words: String...) -> Bool {
            words.allSatisfy { normalized.contains(" \($0) ") }
        }

        if has("cmf") {
            if has("headphone") { return single("cmf_headphone_pro_1", "dark_grey", "light_green", "light_grey") }
            if has("neckband") { return single("cmf_neckband_pro", "black", "orange", "white") }
            if has("clip") { return pair("cmf_clip_pro", "dark_grey", "coral", "light_grey") }
            guard has("buds") else { return nil }
            if has("pro", "2") { return pair("cmf_buds_pro_2", "black", "blue", "orange", "white") }
            if has("pro") { return pair("cmf_buds_pro", "black", "orange", "white") }
            if has("2", "plus") || has("2", "+") { return pair("cmf_buds_2_plus", "light_grey", "blue") }
            if has("2a") { return pair("cmf_buds_2a", "black", "light_grey", "orange") }
            if has("2") { return pair("cmf_buds_2", "black", "green", "orange") }
            if has("neo") { return pair("cmf_buds_neo", "dark_grey", "blue", "orange") }
            return pair("cmf_buds", "black", "orange", "white")
        }

        if has("headphone") {
            if has("pro") { return single("headphone_1_pro", "black", "silver") }
            if has("a") { return single("headphone_a", "black", "white", "yellow", "pink") }
            return single("headphone_1", "black", "grey")
        }

        guard has("ear") || has("nothing") else { return nil }
        if has("stick") { return pair("ear_stick") }
        if has("open") { return pair("ear_open", "white", "blue") }
        if has("3a") { return pair("ear_3a", "black", "white", "pink", "yellow") }
        if has("3") { return pair("ear_3", "black", "white") }
        if has("2") { return pair("ear_2", "black", "white") }
        if has("1") { return pair("ear_1", "black", "white") }
        if has("a") { return pair("ear_a", "black", "white", "yellow") }
        if has("ear") { return pair("ear", "black", "white") }
        return nil
    }
}

/// Shows the device art for `name`, or an SF Symbol when the model isn't one
/// we have art for. Size it from the outside with `.frame`.
struct NothingDeviceImage: View {
    let name: String?
    var fallbackSymbol = "airpodspro"

    @Default(.nothingDeviceColors) private var chosenColours

    var body: some View {
        if let model = NothingDeviceModel.resolve(name: name) {
            let colour = model.colour(chosen: chosenColours[model.key])
            HStack(spacing: 0) {
                ForEach(model.assetNames(colour: colour), id: \.self) { asset in
                    Image(asset)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                }
            }
        } else {
            Image(systemName: fallbackSymbol)
        }
    }
}
