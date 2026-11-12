//
//  Models.swift
//  AniDBKit
//
//  Public provider models, independent of playback engines.
//

import Foundation

/// Whether we want the original Japanese audio or the English dub. hianime's
/// server list is keyed directly by this flag (`data-type="sub"|"dub"`).
public enum Translation: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case sub
    case dub

    public var id: String { rawValue }
    public var label: String { rawValue.uppercased() }

    /// The `data-type` hianime's episode-servers markup uses. Mirrors
    /// ani-cli's `mode="sub"` / `"dub"`.
    var languageCode: String {
        rawValue
    }
}

/// A show returned by a search query.
public struct Show: Identifiable, Hashable, Codable, Sendable {
    /// hianime's slug, which carries the numeric id in its last component —
    /// e.g. "frieren-beyond-journeys-end-481".
    public let id: String
    public let name: String
    public let thumbnail: String?

    public init(id: String, name: String, thumbnail: String? = nil) {
        self.id = id
        self.name = name
        self.thumbnail = thumbnail
    }

    /// Best-effort poster URL. hianime serves absolute CDN URLs, but fall
    /// back to resolving a site-relative path.
    public var thumbnailURL: URL? {
        guard let thumbnail, !thumbnail.isEmpty else { return nil }
        if thumbnail.hasPrefix("http") {
            return URL(string: thumbnail)
        }
        if thumbnail.hasPrefix("/") {
            return URL(string: AniDBClient.base + thumbnail)
        }
        return nil
    }
}

/// A single playable stream resolved for an episode.
public struct VideoLink: Identifiable, Hashable, Sendable {
    public let id = UUID()
    public let url: URL
    /// Vertical resolution as a string ("1080", "720") when known.
    public let resolution: String?
    public let isHLS: Bool
    public let sourceName: String?
    /// Headers the player must send for the CDN to serve the stream.
    public let headers: [String: String]

    public init(
        url: URL, resolution: String? = nil, isHLS: Bool,
        sourceName: String? = nil, headers: [String: String] = [:]
    ) {
        self.url = url
        self.resolution = resolution
        self.isHLS = isHLS
        self.sourceName = sourceName
        self.headers = headers
    }

    public var qualityLabel: String {
        if let resolution, Int(resolution) != nil {
            return "\(resolution)p"
        }
        return isHLS ? "Auto (HLS)" : "Source"
    }

    /// Higher is better. Adaptive HLS (no fixed resolution) is treated as the
    /// best option since it lets the player pick per-bandwidth.
    public var rank: Int {
        if let resolution, let n = Int(resolution) { return n }
        return isHLS ? 10_000 : 0
    }
}
