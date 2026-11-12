# AniDBKit maintenance

AniDBKit is a Foundation-only Swift package implementing the provider logic from
[pystardust/ani-cli](https://github.com/pystardust/ani-cli). Keep one native Swift
implementation, with no UI, persistence, playback engine, or download manager.

## Code map

- `Sources/AniDBKit/AniDBClient.swift`: networking, search/episode parsing, embed decoding, and HLS source resolution.
- `Sources/AniDBKit/Models.swift`: public Show, Translation, and VideoLink values.
- `Sources/AniDBKit/AniDBError.swift`: public provider errors.
- `Sources/AniDBKit/WireModels.swift`: internal response types.
- `Tests/AniDBKitTests/`: public API regression checks and opt-in live tests.
- `Tests/README.md`: upstream baseline, exact commit links, and verification limits.
- `README.md`: consumer setup, public API examples, and playback contract.

## Updating from ani-cli

1. Inspect git status and the existing client before editing. Preserve unrelated changes.
2. Fetch the current script from `https://raw.githubusercontent.com/pystardust/ani-cli/master/ani-cli` and inspect its version. Check `https://api.github.com/repos/pystardust/ani-cli/commits?path=ani-cli&per_page=20` and read exact patches for relevant fixes. Keep downloads and live responses outside the repository.
3. Compare hianime_curl, hianime_search, hianime_episodes, hianime_m3u8, and deobfuscate_blob with the Swift client. Follow changes to these function names and the provider when upstream changes them.
4. Trace live search, episode list, server list, embed configuration, and HLS master requests. Check status codes, formats, headers, and relative URLs. Reproduce the reported failure where possible; distinguish provider outages/challenges from parser or playback bugs.
5. Add a deterministic regression fixture for each confirmed behavior change. Observe its failure before fixing the client. Avoid expiring tokens and unnecessary copied site content.
6. Backport the smallest relevant Swift change. Keep tests importing AniDBKit without @testable, preserve public API and Codable compatibility, and assess AVPlayer, mpv, and FFmpeg consumers. Adapt upstream behavior rather than translating shell literally.
7. Run the checks below. Record upstream version, commit links, behavior changes, and verification limits in Tests/README.md. Leave unrelated upstream features out of the patch.

## Compatibility

- Validate episode watch slugs: numeric IDs collide across providers.
- Preserve the embed-host referer and browser user agent on stream requests.
- Match the actual embed decoder algorithm and payload; it already matched during the 5.1.8 review.
- Keep the HLS master when external audio is declared. Bare video variants can lose audio. Muxed streams retain fixed quality choices. Check all consumers before changing this policy.
- Public client and models must remain Sendable, with injectable URLSession and private parser/wire details.

## Verification and consumers

```sh
swift test
ANIDB_LIVE_TESTS=1 swift test --filter LiveProviderTests
git diff --check
```

Normal tests skip live checks. Report blocked checks explicitly. Source resolution
does not prove rendered video, audible sound, subtitles, or completed downloads.
A package build does not prove an integrating app or another platform builds.

When publishing a new version, use a semantic-version tag. Update AniMac's remote
package requirement/Package.resolved and verify its build against the published
revision. Never require consumers to reference a checkout-specific absolute path.
