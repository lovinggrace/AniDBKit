# AniDBKit

A Foundation-only Swift library for searching anime, listing episodes, and resolving
playback URLs. The implementation follows ani-cli's current HiAnime provider;
`AniDBClient` retains its historical name. No playback engine, UI, persistence,
or download manager is included.

Requires Swift 6.2 or later. Declared minimum platforms are macOS 12, iOS 15,
tvOS 15, and visionOS 1. The package has no external dependencies.

## Add to another app

Add `https://github.com/lovinggrace/AniDBKit.git` as a package dependency in Xcode
and link its `AniDBKit` product. For a Swift package consumer:

```swift
// In Package(...):
dependencies: [
    .package(url: "https://github.com/lovinggrace/AniDBKit.git", from: "0.1.0"),
],
targets: [
    .target(
        name: "MyPlayer",
        dependencies: [.product(name: "AniDBKit", package: "AniDBKit")]
    ),
]
```

```swift
import AniDBKit

let client = AniDBClient()
let shows = try await client.search("frieren")
if let show = shows.first {
    let episodes = try await client.episodes(showId: show.id)
    if let episode = episodes.first {
        let sources = try await client.sources(
            showId: show.id, episode: episode, translation: .sub
        )
        if let source = sources.first {
            // Give both values to your playback engine:
            let url = source.url
            let headers = source.headers
        }
    }
}
```

`AniDBClient(session:)` accepts a URLSession for custom networking or fixture tests;
the default is `.shared`. The client and public models are Sendable and can be used
outside the main actor. The API throws `AniDBError` for provider failures and
propagates URLSession transport errors and cancellation.

`Show`, `Translation`, and `VideoLink` are public value types. `Show` and
`Translation` preserve AniMac's existing Codable representations. Provider wire
types and parser helpers are implementation details.

## Playback contract

- Sources are ranked best first. Adaptive HLS is preferred over fixed qualities.
- Always send each `VideoLink.headers` with playback and download requests.
- Resolve URLs when playback starts: provider links can expire.
- Episode labels are strings, including specials such as `10.5`.
- Only the supported ZokoAnime server is resolved; unavailable translations throw
  `AniDBError.noSources`.
- Streams declaring external HLS audio return the master only, keeping audio
  attached for AVPlayer, mpv, and FFmpeg. Muxed streams also offer fixed qualities.

The package depends on an external site's availability and response formats. Source
resolution alone does not verify rendered video, sound, subtitles, or downloads.

## Development

From the repository root:

```sh
swift test
ANIDB_LIVE_TESTS=1 swift test --filter LiveProviderTests
```

Normal tests use an injected ephemeral URLSession and URLProtocol fixtures, without
network access. Live tests are skipped unless explicitly enabled. See
[provider maintenance notes](Tests/README.md) for upstream references.

For provider update instructions, see [AGENTS.md](AGENTS.md). AniMac consumes this
repository as a versioned SwiftPM dependency; other players can use the same API.
