import AppKit

// "3 miles to km", "72 f to c", "16 gb in mb", "100 usd to inr".
// Units use Foundation's Measurement machinery, currency uses the cached
// daily rates.
final class ConversionProvider: SearchProvider {
    let name = "Convert"

    private static let pattern = try! NSRegularExpression(
        pattern: #"^([\d.,]+)\s*([a-zµ°$€£₹¥₩/]+)\s+(?:to|in|as)\s+([a-zµ°/]+)$"#,
        options: .caseInsensitive
    )

    // Token -> Foundation unit. Lowercased keys.
    private static let units: [String: Dimension] = {
        var map: [String: Dimension] = [:]
        func add(_ names: [String], _ unit: Dimension) {
            for n in names { map[n] = unit }
        }
        // Length
        add(["mm", "millimeter", "millimeters"], UnitLength.millimeters)
        add(["cm", "centimeter", "centimeters"], UnitLength.centimeters)
        add(["m", "meter", "meters", "metre", "metres"], UnitLength.meters)
        add(["km", "kilometer", "kilometers", "kms"], UnitLength.kilometers)
        add(["in", "inch", "inches"], UnitLength.inches)
        add(["ft", "foot", "feet"], UnitLength.feet)
        add(["yd", "yard", "yards"], UnitLength.yards)
        add(["mi", "mile", "miles"], UnitLength.miles)
        // Mass
        add(["mg"], UnitMass.milligrams)
        add(["g", "gram", "grams"], UnitMass.grams)
        add(["kg", "kilogram", "kilograms", "kilo", "kilos"], UnitMass.kilograms)
        add(["oz", "ounce", "ounces"], UnitMass.ounces)
        add(["lb", "lbs", "pound", "pounds"], UnitMass.pounds)
        add(["ton", "tons", "tonne", "tonnes"], UnitMass.metricTons)
        // Temperature
        add(["c", "°c", "celsius"], UnitTemperature.celsius)
        add(["f", "°f", "fahrenheit"], UnitTemperature.fahrenheit)
        add(["k", "kelvin"], UnitTemperature.kelvin)
        // Data
        add(["b", "byte", "bytes"], UnitInformationStorage.bytes)
        add(["kb"], UnitInformationStorage.kilobytes)
        add(["mb"], UnitInformationStorage.megabytes)
        add(["gb"], UnitInformationStorage.gigabytes)
        add(["tb"], UnitInformationStorage.terabytes)
        add(["kib"], UnitInformationStorage.kibibytes)
        add(["mib"], UnitInformationStorage.mebibytes)
        add(["gib"], UnitInformationStorage.gibibytes)
        // Time
        add(["ms", "millisecond", "milliseconds"], UnitDuration.milliseconds)
        add(["s", "sec", "secs", "second", "seconds"], UnitDuration.seconds)
        add(["min", "mins", "minute", "minutes"], UnitDuration.minutes)
        add(["h", "hr", "hrs", "hour", "hours"], UnitDuration.hours)
        // Speed
        add(["kmh", "km/h", "kph"], UnitSpeed.kilometersPerHour)
        add(["mph"], UnitSpeed.milesPerHour)
        add(["m/s", "ms/s", "mps"], UnitSpeed.metersPerSecond)
        add(["knot", "knots", "kn"], UnitSpeed.knots)
        // Volume
        add(["ml"], UnitVolume.milliliters)
        add(["l", "liter", "liters", "litre", "litres"], UnitVolume.liters)
        add(["gal", "gallon", "gallons"], UnitVolume.gallons)
        add(["cup", "cups"], UnitVolume.cups)
        add(["floz"], UnitVolume.fluidOunces)
        // Area
        add(["sqft"], UnitArea.squareFeet)
        add(["sqm"], UnitArea.squareMeters)
        add(["acre", "acres"], UnitArea.acres)
        add(["hectare", "hectares", "ha"], UnitArea.hectares)
        return map
    }()

    func results(for query: Query) -> [ResultItem] {
        let text = query.trimmed.lowercased()
        let range = NSRange(text.startIndex..., in: text)
        guard let match = Self.pattern.firstMatch(in: text, range: range),
              let amountRange = Range(match.range(at: 1), in: text),
              let fromRange = Range(match.range(at: 2), in: text),
              let toRange = Range(match.range(at: 3), in: text),
              let amount = Double(text[amountRange].replacingOccurrences(of: ",", with: ""))
        else { return [] }

        var fromToken = String(text[fromRange])
        let toToken = String(text[toRange])

        // "$100 to inr" style: symbol glued to the number handled by regex
        // group 2 capturing the symbol.
        if let mapped = CurrencyService.symbolMap[fromToken] { fromToken = mapped }

        // Currency first: both tokens are ISO codes.
        if CurrencyService.knownCodes.contains(fromToken), CurrencyService.knownCodes.contains(toToken) {
            return currencyItem(amount: amount, from: fromToken, to: toToken)
        }

        // Units.
        guard let fromUnit = Self.units[fromToken], let toUnit = Self.units[toToken],
              type(of: fromUnit) == type(of: toUnit) else { return [] }

        let measurement = Measurement(value: amount, unit: fromUnit)
        let converted = measurement.converted(to: toUnit)
        let formatted = CalculatorProvider.format(converted.value)

        return [ResultItem(
            id: "convert:unit",
            title: "\(formatted) \(toToken)",
            subtitle: "\(CalculatorProvider.format(amount)) \(fromToken) = \(formatted) \(toToken)",
            icon: .symbol("arrow.left.arrow.right.circle.fill"),
            kind: .conversion,
            score: 3.0,
            accessory: "⏎ copies",
            action: { _ in
                ClipboardManager.shared.ignoreNextChange = true
                PasteHelper.copy(text: formatted)
                return .toast("Copied \(formatted)")
            }
        )]
    }

    private func currencyItem(amount: Double, from: String, to: String) -> [ResultItem] {
        guard AppConfig.shared.currencyEnabled else { return [] }

        guard let converted = CurrencyService.shared.convert(amount: amount, from: from, to: to) else {
            CurrencyService.shared.refreshIfStale()
            return [ResultItem(
                id: "convert:currency:pending",
                title: "Fetching exchange rates...",
                subtitle: "Rates load once a day from frankfurter.app",
                icon: .symbol("arrow.triangle.2.circlepath"),
                kind: .conversion,
                score: 3.0,
                action: { _ in .stay }
            )]
        }

        let formatted = CalculatorProvider.format(converted)
        let dateNote = CurrencyService.shared.ratesDate.map { "ECB rates \($0)" } ?? ""

        return [ResultItem(
            id: "convert:currency",
            title: "\(formatted) \(to.uppercased())",
            subtitle: "\(CalculatorProvider.format(amount)) \(from.uppercased()) = \(formatted) \(to.uppercased())  ·  \(dateNote)",
            icon: .symbol("dollarsign.arrow.circlepath"),
            kind: .conversion,
            score: 3.0,
            accessory: "⏎ copies",
            action: { _ in
                ClipboardManager.shared.ignoreNextChange = true
                PasteHelper.copy(text: formatted)
                return .toast("Copied \(formatted)")
            }
        )]
    }
}
