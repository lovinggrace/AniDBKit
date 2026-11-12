import Foundation

/// Errors reported while requesting or decoding provider responses.
public enum AniDBError: LocalizedError, Sendable {
    case badURL
    case http(Int)
    case blocked
    case noSources
    case decodeFailed

    public var errorDescription: String? {
        switch self {
        case .badURL: return "Could not build a valid request URL."
        case .http(let code): return "Server returned HTTP \(code)."
        case .blocked: return "Blocked by Cloudflare. Try again in a moment."
        case .noSources: return "No playable sources were found for this episode."
        case .decodeFailed: return "Couldn't read the response from hianime.at."
        }
    }
}
