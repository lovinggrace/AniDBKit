//
//  AniDBClient.swift
//  AniDBKit
//
//  Talks to hianime.at the same way ani-cli v5.1 does: search page ->
//  episode list -> episode servers -> ZokoAnime embed (XOR-obfuscated blob)
//  -> HLS master playlist -> concrete playable variants.
//
//  This replaces the anidb.app path from v5.0, which upstream dropped in
//  v5.1.0 ("fix: replace anidb with hianime provider") after anidb started
//  hard-failing search with HTTP 503. The type is still called `AniDBClient`
//  because it's wired through the rest of the app under that name; only the
//  provider it scrapes has changed.
//

import Foundation

/// Searches shows, lists episodes, and resolves short-lived playback URLs.
/// Returned HTTP headers must also be supplied to the playback engine.
public struct AniDBClient: Sendable {
    private let session: URLSession

    /// Creates a client using the supplied session for all provider requests.
    public init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: Endpoints & headers

    public static let base = "https://hianime.at"
    /// Sent on every request; the embed pages 403 without a browser agent.
    public static let userAgent =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
    public static let referer = base + "/"

    /// The key hianime's embed config is XOR'd against, base64-wrapped.
    /// ani-cli's `deobfuscate_blob` rotates the same bytes through the blob.
    private static let embedKey = Array("otaku-embed-v1".utf8)

    // MARK: Public API

    /// Search shows by title. hianime's search page has no sub/dub filter —
    /// the language choice only decides which server we pick at playback time.
    public func search(_ text: String) async throws -> [Show] {
        guard var components = URLComponents(string: Self.base + "/search") else {
            throw AniDBError.badURL
        }
        components.queryItems = [URLQueryItem(name: "keyword", value: text)]
        guard let url = components.url else { throw AniDBError.badURL }
        return Self.parseSearchResults(try await fetchText(url))
    }

    /// List the show's episode identifiers, numerically sorted.
    public func episodes(showId: String) async throws -> [String] {
        try await episodeList(showId: showId).map(\.label)
    }

    /// Resolve all playable links for one episode, best quality first.
    public func sources(
        showId: String,
        episode: String,
        translation: Translation
    ) async throws -> [VideoLink] {
        // The servers endpoint is keyed by hianime's numeric episode id, so we
        // need the show's episode list to map the episode number onto it.
        let episodes = try await episodeList(showId: showId)
        guard let match = episodes.first(where: { $0.label == episode }) else {
            throw AniDBError.noSources
        }

        guard let embed = try await zokoAnimeEmbed(episodeId: match.id, translation: translation)
        else { throw AniDBError.noSources }

        // The stream host wants the embed site itself as referer, matching
        // ani-cli's `refr="$(scheme://host/ of the embed url)"`.
        guard
            let embedHost = embed.host,
            let refererURL = URL(string: "\(embed.scheme ?? "https")://\(embedHost)/")
        else { throw AniDBError.noSources }
        let headers: [String: String] = [
            "Referer": refererURL.absoluteString,
            "User-Agent": Self.userAgent,
        ]

        let blob = try await deobfuscatedEmbedConfig(embed: embed)
        guard
            let masterString = Self.firstCapture(#""src":"([^"]*\.m3u8[^"]*)""#, in: blob),
            let master = URL(string: masterString.replacingOccurrences(of: "\\/", with: "/"))
        else { throw AniDBError.noSources }

        let links = try await variants(master: master, sourceName: "ZokoAnime", headers: headers)

        guard !links.isEmpty else { throw AniDBError.noSources }
        return links.sorted { $0.rank > $1.rank }
    }

    // MARK: Search parsing

    /// Pull `(id, title, poster)` out of the search page's anime cards.
    /// Mirrors ani-cli's `hianime_search`: cut the "top 10" sidebar (which
    /// repeats the result markup) before splitting on each `flw-item` card.
    private static func parseSearchResults(_ html: String) -> [Show] {
        var shows: [Show] = []
        var seen = Set<String>()

        let sidebarRange = html.range(of: #"id="main-sidebar""#, options: .regularExpression)
        let results = sidebarRange.map { String(html[html.startIndex..<$0.lowerBound]) } ?? html

        for card in results.components(separatedBy: "<div class=\"flw-item").dropFirst() {
            guard
                let id = firstCapture(#"<h3 class="film-name">\s*<a href="[^"]*/([^"/]+)"\s*title="([^"]*)""#, in: card, group: 1),
                let title = firstCapture(#"<h3 class="film-name">\s*<a href="[^"]*/([^"/]+)"\s*title="([^"]*)""#, in: card, group: 2),
                seen.insert(id).inserted
            else { continue }

            shows.append(
                Show(
                    id: id,
                    name: htmlUnescape(title),
                    thumbnail: firstCapture(#"<img[^>]+src="(https://[^"]+)""#, in: card)
                )
            )
        }
        return shows
    }

    // MARK: Episodes & sources

    private func episodeList(showId: String) async throws -> [AniDBEpisode] {
        // Slugs carry the numeric id in their last component — ani-cli's `${1##*-}`.
        guard
            let numericId = showId.split(separator: "-").last,
            let url = URL(string: "\(Self.base)/api/theme/episode/list/\(numericId)")
        else { throw AniDBError.badURL }

        let data = try await fetchData(url)
        guard let decoded = try? JSONDecoder().decode(AniDBHTMLFragment.self, from: data) else {
            throw AniDBError.decodeFailed
        }

        // Upstream v5.1.0 also checks the watch slug: older providers used
        // the same numeric-id shape, but those ids refer to different shows.
        // Parse each element independently so attributes cannot bleed between
        // episodes, and allow other attributes between number and id.
        let tags = Self.allCaptures(#"(<a\b[^>]*>)"#, in: decoded.html)
        let parsed = tags.compactMap { groups -> AniDBEpisode? in
            let tag = groups[0]
            guard
                let numberText = Self.firstCapture(#"data-number="([^"]*)""#, in: tag),
                let idText = Self.firstCapture(#"data-id="(\d+)""#, in: tag),
                let href = Self.firstCapture(#"href="([^"]*)""#, in: tag),
                let link = URL(string: Self.htmlUnescape(href), relativeTo: URL(string: Self.base)),
                link.path == "/watch/" + showId,
                let number = Double(numberText), number.isFinite,
                let id = Int(idText)
            else { return nil }
            return AniDBEpisode(id: id, number: number)
        }
        return parsed.sorted { $0.number < $1.number }
    }

    /// Fetch the episode's server list and decode the ZokoAnime entry for
    /// `translation` into its embed URL. Other servers (HD-1, Vidstream-2,
    /// …) use players ani-cli doesn't understand either, so they're skipped.
    private func zokoAnimeEmbed(episodeId: Int, translation: Translation) async throws -> URL? {
        guard let url = URL(string: "\(Self.base)/api/theme/episode/servers?episodeId=\(episodeId)")
        else { throw AniDBError.badURL }

        let data = try await fetchData(url)
        guard let decoded = try? JSONDecoder().decode(AniDBHTMLFragment.self, from: data) else {
            throw AniDBError.decodeFailed
        }

        let hash = Self.allCaptures(
            #"data-type="(sub|dub)"\s*data-server-name="([^"]*)"\s*data-hash="([^"]*)""#,
            in: decoded.html
        ).first { $0[0] == translation.languageCode && $0[1] == "ZokoAnime" }?[2]

        guard
            let hash,
            let embedData = Data(base64Encoded: hash),
            let embedString = String(data: embedData, encoding: .utf8)
        else { return nil }
        return URL(string: embedString)
    }

    /// Fetch the embed page and undo its `base64(json XOR "otaku-embed-v1")`
    /// obfuscation, returning the plain JSON text. Mirrors ani-cli's
    /// `deobfuscate_blob`.
    private func deobfuscatedEmbedConfig(embed: URL) async throws -> String {
        let html = try await fetchText(embed)
        guard let blob = Self.firstCapture(#"window\.__P="([^"]*)""#, in: html),
              let data = Data(base64Encoded: blob)
        else { throw AniDBError.noSources }

        let key = Self.embedKey
        let decoded = data.enumerated().map { index, byte in byte ^ key[index % key.count] }
        guard let json = String(bytes: decoded, encoding: .utf8) else { throw AniDBError.noSources }
        return json
    }

    /// Expand a master playlist into per-resolution variants. The master itself
    /// is kept as the top-ranked entry so the player can adapt to bandwidth;
    /// the fixed-resolution variants back it up in the quality picker.
    private func variants(
        master: URL, sourceName: String?, headers: [String: String]
    ) async throws -> [VideoLink] {
        var links = [
            VideoLink(url: master, resolution: nil, isHLS: true, sourceName: sourceName, headers: headers)
        ]

        let playlist = try await fetchText(master, headers: headers)
        // ani-cli v5.1.6 adds the external audio as a second input. Keeping
        // the master lets AVPlayer, mpv and FFmpeg resolve the audio group
        // themselves. A bare video variant loses that group (silent playback
        // and downloads), so only offer the complete master in this case.
        if playlist.components(separatedBy: .newlines).contains(where: {
            $0.hasPrefix("#EXT-X-MEDIA:") && $0.contains("TYPE=AUDIO") && $0.contains("URI=")
        }) {
            return links
        }
        var pendingResolution: String?
        for rawLine in playlist.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            // `#EXT-X-I-FRAME-STREAM-INF` carries its URI inline and isn't
            // playable, so it falls through to the comment check below.
            if line.hasPrefix("#EXT-X-STREAM-INF") {
                pendingResolution = Self.firstCapture(#"RESOLUTION=\d+x(\d+)"#, in: line)
                continue
            }
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }

            defer { pendingResolution = nil }
            guard
                let resolution = pendingResolution,
                let url = URL(string: line, relativeTo: master)?.absoluteURL
            else { continue }

            links.append(
                VideoLink(url: url, resolution: resolution, isHLS: true, sourceName: sourceName, headers: headers)
            )
        }
        return links
    }

    // MARK: Networking helpers

    private func makeRequest(_ url: URL, headers: [String: String]? = nil) -> URLRequest {
        var request = URLRequest(url: url)
        for (field, value) in headers ?? ["User-Agent": Self.userAgent, "Referer": Self.referer] {
            request.setValue(value, forHTTPHeaderField: field)
        }
        request.timeoutInterval = 15
        return request
    }

    private func fetchData(_ url: URL, headers: [String: String]? = nil) async throws -> Data {
        let (data, response) = try await session.data(for: makeRequest(url, headers: headers))
        guard let http = response as? HTTPURLResponse else { throw AniDBError.http(-1) }
        guard (200..<300).contains(http.statusCode) else {
            // ani-cli pins TLS ciphers to get past this; URLSession's own
            // handshake passes today, but the site can still challenge us.
            if Self.looksLikeChallenge(data) { throw AniDBError.blocked }
            throw AniDBError.http(http.statusCode)
        }
        return data
    }

    private func fetchText(_ url: URL, headers: [String: String]? = nil) async throws -> String {
        let data = try await fetchData(url, headers: headers)
        if Self.looksLikeChallenge(data) { throw AniDBError.blocked }
        return String(decoding: data, as: UTF8.self)
    }

    private static func looksLikeChallenge(_ data: Data) -> Bool {
        String(decoding: data.prefix(4096), as: UTF8.self)
            .localizedCaseInsensitiveContains("just a moment")
    }

    // MARK: Text helpers

    /// First capture group of `pattern` in `text`, or nil.
    fileprivate static func firstCapture(_ pattern: String, in text: String, group: Int = 1) -> String? {
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
            let range = Range(match.range(at: group), in: text)
        else { return nil }
        return String(text[range])
    }

    /// Every match of `pattern` in `text`, as its capture groups (excluding
    /// the full match). Used where a page repeats one card/entry per item.
    fileprivate static func allCaptures(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        return matches.map { match in
            (1..<match.numberOfRanges).map { index in
                guard let range = Range(match.range(at: index), in: text) else { return "" }
                return String(text[range])
            }
        }
    }

    /// Decode the handful of entities hianime's markup actually emits. `&amp;`
    /// goes last so an encoded entity isn't decoded twice.
    private static func htmlUnescape(_ text: String) -> String {
        let entities = [
            ("&#039;", "'"), ("&#39;", "'"), ("&quot;", "\""),
            ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " "), ("&amp;", "&"),
        ]
        return entities.reduce(text) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
    }
}
