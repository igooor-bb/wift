import Foundation

struct CacheStatistics: Equatable {
    let executableCount: Int
    let executableBytes: UInt64
    let moduleCacheBytes: UInt64
    let supportModuleBytes: UInt64
    let totalBytes: UInt64
}

enum ByteSizeFormatter {
    private static let units: [UnitInformationStorage] = [
        .bytes,
        .kibibytes,
        .mebibytes,
        .gibibytes,
        .tebibytes,
    ]

    static func string(fromByteCount byteCount: UInt64) -> String {
        let locale = Locale(identifier: "en_US_POSIX")
        guard byteCount >= 1024 else {
            return "\(byteCount.formatted(.number.locale(locale))) B"
        }

        var value = Double(byteCount)
        var unitIndex = 0
        while value >= 1024, unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }
        let style = Measurement<UnitInformationStorage>.FormatStyle(
            width: .abbreviated,
            locale: locale,
            usage: .asProvided,
            numberFormatStyle: .number.precision(.fractionLength(1))
        )
        return Measurement(value: value, unit: units[unitIndex]).formatted(style)
    }
}
