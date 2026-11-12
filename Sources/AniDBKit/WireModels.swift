import Foundation

// MARK: - hianime wire types

/// Both `/api/theme/episode/list/{id}` and `/api/theme/episode/servers`
/// wrap their real payload as an HTML fragment inside otherwise-trivial JSON.
struct AniDBHTMLFragment: Decodable {
    let html: String
}

/// One entry from `/api/theme/episode/list/{id}`, parsed out of its `html`.
struct AniDBEpisode {
    let id: Int
    let number: Double

    /// The identifier the rest of the app uses ("1", "12", "10.5").
    var label: String {
        number == number.rounded()
            ? String(Int(number))
            : String(number)
    }
}
