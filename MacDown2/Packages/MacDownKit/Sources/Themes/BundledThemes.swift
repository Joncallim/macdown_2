import Foundation

/// Loads the shipped themes from `Bundle.module`.
public enum BundledThemes {
    public static let light: Theme = load("Tomorrow Light")
    public static let dark: Theme = load("Tomorrow Dark")
    public static let all: [Theme] = [light, dark]

    static func load(_ resource: String) -> Theme {
        guard let url = Bundle.module.url(forResource: resource, withExtension: "json") else {
            preconditionFailure("Missing bundled theme: \(resource).json")
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            return try decoder.decode(Theme.self, from: data)
        } catch {
            preconditionFailure("Failed to decode bundled theme \(resource).json: \(error)")
        }
    }
}
