import AniDBKit
import Foundation
import Testing

private struct Response: Sendable {
    let status: Int
    let data: Data

    init(_ text: String, status: Int = 200) {
        self.status = status
        self.data = Data(text.utf8)
    }

    static func html(_ html: String) throws -> Response {
        let data = try JSONSerialization.data(withJSONObject: ["html": html])
        return Response(String(decoding: data, as: UTF8.self))
    }
}

private final class FixtureProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> Response
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: Handler?

    static func install(_ handler: @escaping Handler) {
        lock.lock()
        defer { lock.unlock() }
        self.handler = handler
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let handler = Self.handler
        Self.lock.unlock()
        do {
            let handler = try #require(handler)
            let reply = try handler(request)
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: nil, headerFields: nil))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: reply.data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

@Suite(.serialized)
struct ProviderTests {
    private static let episode = #"<a data-number="1" data-id="9227" href="/watch/frieren-481?ep=9227">1</a>"#
    private static let muxed = "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=5000000,RESOLUTION=1920x1080\n1080/index.m3u8\n"

    private func session(responses: [String: Response]) -> URLSession {
        FixtureProtocol.install { request in
            let url = try #require(request.url)
            #expect(request.value(forHTTPHeaderField: "User-Agent") == AniDBClient.userAgent)
            let expectedReferer = url.host == "cdn.test" ? "https://embed.test/" : AniDBClient.referer
            #expect(request.value(forHTTPHeaderField: "Referer") == expectedReferer)
            return try #require(responses[url.absoluteString], "Unexpected request: \(url)")
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func sourcesResponses(
        playlist: String = Self.muxed, language: Translation = .sub
    ) throws -> [String: Response] {
        let embed = "https://embed.test/\(language.rawValue)"
        let hash = Data(embed.utf8).base64EncodedString()
        let json = Array(#"{"src":"https://cdn.test/master.m3u8"}"#.utf8)
        let key = Array("otaku-embed-v1".utf8)
        let blob = Data(json.enumerated().map { $0.element ^ key[$0.offset % key.count] }).base64EncodedString()
        return [
            AniDBClient.base + "/api/theme/episode/list/481": try .html(Self.episode),
            AniDBClient.base + "/api/theme/episode/servers?episodeId=9227": try .html("<div data-type=\"\(language.rawValue)\" data-server-name=\"ZokoAnime\" data-hash=\"\(hash)\">"),
            embed: Response("window.__P=\"\(blob)\""),
            "https://cdn.test/master.m3u8": Response(playlist),
        ]
    }

    @Test func separateAudioStaysAttachedThroughMasterPlaylist() async throws {
        let playlist = """
        #EXTM3U
        #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",DEFAULT=YES,URI="audio/index.m3u8"
        #EXT-X-STREAM-INF:BANDWIDTH=5000000,RESOLUTION=1920x1080,AUDIO="audio"
        1080/index.m3u8
        """
        let session = session(responses: try sourcesResponses(playlist: playlist))
        defer { session.invalidateAndCancel() }
        let links = try await AniDBClient(session: session).sources(showId: "frieren-481", episode: "1", translation: .sub)
        #expect(links.count == 1)
        #expect(links.first?.url.absoluteString == "https://cdn.test/master.m3u8")
    }

    @Test(arguments: Translation.allCases)
    func muxedVariantsRetainQualityRelativeURLsAndPlaybackHeaders(language: Translation) async throws {
        let session = session(responses: try sourcesResponses(language: language))
        defer { session.invalidateAndCancel() }
        let links = try await AniDBClient(session: session).sources(showId: "frieren-481", episode: "1", translation: language)
        #expect(links.count == 2)
        #expect(links.first?.qualityLabel == "Auto (HLS)")
        #expect(links.last?.resolution == "1080")
        #expect(links.last?.url.absoluteString == "https://cdn.test/1080/index.m3u8")
        for link in links {
            #expect(link.headers == ["Referer": "https://embed.test/", "User-Agent": AniDBClient.userAgent])
        }
    }

    @Test func staleSlugCannotResolveAnotherShowsEpisodes() async throws {
        let session = session(responses: [AniDBClient.base + "/api/theme/episode/list/481": try .html(Self.episode)])
        defer { session.invalidateAndCancel() }
        let episodes = try await AniDBClient(session: session).episodes(showId: "old-provider-481")
        #expect(episodes.isEmpty)
    }

    @Test func episodeAttributesMayHaveInterveningMarkupAndSortNumerically() async throws {
        let html = """
        <a data-number="10.5" class="ep-item" data-id="3" href="/watch/frieren-481?ep=3">Special</a>
        <a data-number="2" class="ep-item" data-id="2" href="/watch/frieren-481?ep=2">2</a>
        \(Self.episode)
        """
        let session = session(responses: [AniDBClient.base + "/api/theme/episode/list/481": try .html(html)])
        defer { session.invalidateAndCancel() }
        let episodes = try await AniDBClient(session: session).episodes(showId: "frieren-481")
        #expect(episodes == ["1", "2", "10.5"])
    }

    @Test func searchEncodesQueryDecodesTitlesAndExcludesSidebarDuplicates() async throws {
        let card = """
        <div class="flw-item"><img src="https://cdn.test/poster.jpg">
        <h3 class="film-name"><a href="https://hianime.at/frieren-481" title="Frieren &amp; Friends">Frieren</a></h3></div>
        """
        let html = card + card + #"<aside id="main-sidebar">"# + card.replacingOccurrences(of: "frieren-481", with: "sidebar-9")
        let session = session(responses: [AniDBClient.base + "/search?keyword=Frieren%20%26%20Friends": Response(html)])
        defer { session.invalidateAndCancel() }
        let shows = try await AniDBClient(session: session).search("Frieren & Friends")
        #expect(shows == [Show(id: "frieren-481", name: "Frieren & Friends", thumbnail: "https://cdn.test/poster.jpg")])
    }

    @Test func httpFailuresKeepTheirStatusCode() async throws {
        let session = session(responses: [AniDBClient.base + "/search?keyword=test": Response("Unavailable", status: 503)])
        defer { session.invalidateAndCancel() }
        do {
            _ = try await AniDBClient(session: session).search("test")
            Issue.record("Expected an HTTP error")
        } catch AniDBError.http(let status) {
            #expect(status == 503)
        }
    }

    @Test func challengeIsReportedAsBlocked() async throws {
        let session = session(responses: [AniDBClient.base + "/search?keyword=test": Response("<title>Just a moment</title>", status: 403)])
        defer { session.invalidateAndCancel() }
        do {
            _ = try await AniDBClient(session: session).search("test")
            Issue.record("Expected a blocked error")
        } catch AniDBError.blocked {}
    }

    @Test func malformedEpisodeResponseIsReportedAsDecodeFailure() async throws {
        let session = session(responses: [AniDBClient.base + "/api/theme/episode/list/481": Response("not JSON")])
        defer { session.invalidateAndCancel() }
        do {
            _ = try await AniDBClient(session: session).episodes(showId: "frieren-481")
            Issue.record("Expected a decoding error")
        } catch AniDBError.decodeFailed {}
    }

    @Test func missingTranslationIsReportedAsNoSources() async throws {
        let session = session(responses: try sourcesResponses(language: .sub))
        defer { session.invalidateAndCancel() }
        do {
            _ = try await AniDBClient(session: session).sources(showId: "frieren-481", episode: "1", translation: .dub)
            Issue.record("Expected no dub sources")
        } catch AniDBError.noSources {}
    }
}
