# Convert the Spire Reborn v14.2.0

## Watch Together — your library, in sync, on every screen

### Added

- **Watch Together.** Start a room on one device, share the six-character code, and everyone watches in step: play, pause and seek all propagate. Phone, PC, Mac and the TV, in any combination.

  It runs entirely on your own network. There is no server, no account and no sign-up — the host device *is* the server, and guests find it automatically over the LAN, so the code is the only thing anyone has to type. If a network blocks discovery (guest wifi often does), you can join with the host's address instead.

  Keeping devices in step across a network is not as simple as "send play" — the clocks disagree and messages take time to arrive. The host stamps every update with its own clock; each guest measures the round-trip delay the way NTP does, keeping the fastest sample so one slow packet cannot skew it, then works out where playback *should* be right now. Drift under ¾ of a second is left alone, because correcting it is more jarring than living with it. Someone joining halfway through gets the current position immediately instead of a black screen.

### Improved

- **The ad blocker is now covered by tests.** It had none. The rules that matter most are now pinned down: subdomains of a blocked domain are blocked, a bare TLD never is (a single bad list entry could otherwise have taken down every `.com` site), and a lookalike domain such as `nottracker.net` is not blocked just because it ends with a blocked name.

### Build Notes

- Android Play AAB built with `--flavor play` (version 14.2.0+1293).
- `flutter analyze` clean; 212 tests pass (was 163), including 39 covering Watch Together — clock-offset estimation, drift handling, and two real services talking over live sockets.
