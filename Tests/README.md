# Provider regression checks

Run `swift test` from the repository root. Tests import the public AniDBKit module
without @testable and use injected ephemeral URLSession/URLProtocol fixtures.
They cover search, sub/dub selection, required headers, external HLS audio, muxed
quality variants, stale provider slugs, episode attribute changes, stored model
compatibility, and provider errors. No network access is needed for normal tests.

Run the opt-in live test separately:

```sh
ANIDB_LIVE_TESTS=1 swift test --filter LiveProviderTests
```

This checks live search, episode listing, and sub/dub source resolution. It does
not verify rendered video, audible sound, subtitles, or completed downloads.

## Upstream baseline

The implementation was compared with ani-cli 5.1.8:

- Episode slug validation: https://github.com/pystardust/ani-cli/commit/c99221dcecb3
- Separate HLS audio: https://github.com/pystardust/ani-cli/commit/0301d67d5768

The embed decoder already matched upstream and needed no change. External-audio
streams return the master playlist so playback engines can resolve audio groups;
muxed streams also offer fixed qualities.

For future updates, record the reviewed version and exact commit links here,
along with changed behavior and verification limits. See ../AGENTS.md for the
full update workflow.
