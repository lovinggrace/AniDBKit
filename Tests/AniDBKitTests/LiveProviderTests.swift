import AniDBKit
import Foundation
import Testing

struct LiveProviderTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ANIDB_LIVE_TESTS"] == "1"))
    func searchEpisodesAndSubDubSources() async throws {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let client = AniDBClient(session: session)
        let shows = try await client.search("frieren")
        let show = try #require(shows.first { $0.id == "frieren-beyond-journeys-end-481" })
        let episodes = try await client.episodes(showId: show.id)
        #expect(episodes.contains("1"))
        for translation in Translation.allCases {
            let links = try await client.sources(showId: show.id, episode: "1", translation: translation)
            #expect(!links.isEmpty)
            #expect(links.allSatisfy { $0.url.scheme == "https" && $0.headers["Referer"] != nil })
            print("Live \(translation.label): \(shows.count) search results, \(episodes.count) episodes, \(links.count) sources")
        }
    }
}
