import Foundation

/// The text encodings the app can read and write.
public enum FileEncodingCatalog {
    /// The encodings offered first in encoding pickers.
    public static let curated: [String.Encoding] = {
        var list: [String.Encoding] = [
            .utf8, .utf16LittleEndian, .utf16BigEndian,
            .isoLatin1, .windowsCP1252, .macOSRoman,
            .isoLatin2, .windowsCP1250, .windowsCP1251, .windowsCP1253, .windowsCP1254,
            .shiftJIS, .japaneseEUC, .iso2022JP,
        ]
        for encoding in [
            CFStringEncodings.big5, .GB_18030_2000, .EUC_KR, .KOI8_R,
        ] {
            list.append(String.Encoding(
                rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(encoding.rawValue))
            ))
        }
        return list
    }()

    /// Every encoding the OS can convert, curated ones first, the rest
    /// sorted by localized name.
    public static let all: [String.Encoding] = {
        let curatedSet = Set(curated.map(\.rawValue))
        let rest = String.availableStringEncodings
            .filter { !curatedSet.contains($0.rawValue) }
            .sorted { String.localizedName(of: $0) < String.localizedName(of: $1) }
        return curated + rest
    }()

    private static let supportedRawValues: Set<UInt> = Set(all.map(\.rawValue) + [
        String.Encoding.utf8.rawValue,
        String.Encoding.utf16.rawValue,
        String.Encoding.utf16LittleEndian.rawValue,
        String.Encoding.utf16BigEndian.rawValue,
    ])

    public static func isSupported(rawValue: UInt) -> Bool {
        supportedRawValues.contains(rawValue)
    }
}
