import AniDBKit
import Foundation
import Testing

struct PublicAPITests {
    @Test func modelsPreserveStoredValuesAcrossModuleBoundary() throws {
        let show = try JSONDecoder().decode(Show.self, from: Data(#"{"id":"frieren-481","name":"Frieren","thumbnail":"/poster.jpg"}"#.utf8))
        #expect(show == Show(id: "frieren-481", name: "Frieren", thumbnail: "/poster.jpg"))
        #expect(show.thumbnailURL?.absoluteString == "https://hianime.at/poster.jpg")
        #expect(try JSONEncoder().encode(Translation.dub) == Data(#""dub""#.utf8))
        let link = VideoLink(url: URL(string: "https://cdn.test/master.m3u8")!, resolution: nil, isHLS: true, sourceName: "Test", headers: ["Referer": "https://embed.test/"])
        #expect(link.qualityLabel == "Auto (HLS)")
        #expect(link.headers["Referer"] == "https://embed.test/")
        func acceptsSendable<T: Sendable>(_ value: T) {}
        acceptsSendable(show)
        acceptsSendable(link)
        acceptsSendable(Translation.sub)
        acceptsSendable(AniDBClient())
        acceptsSendable(AniDBError.noSources)
    }
}
