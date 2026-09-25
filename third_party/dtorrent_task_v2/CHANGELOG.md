## 0.4.9
- improve test reliability and coverage for peer communication, fast extension, and metadata flows
- add mock socket test infrastructure (`MockSocket`, `MockServerSocket`) for deterministic TCP peer tests
- add new regression test suites:
  - `peer_message_validation_test.dart` for invalid/oversized/fragmented message handling
  - `metadata_messenger_test.dart` for `ut_metadata` message encoding validation
  - `debug_peer_test.dart` and `mock_socket_test.dart` for handshake/data-flow stability checks
- refactor fragile tests to event-driven synchronization (reduce fixed-delay race conditions)
- improve magnet parsing robustness:
  - case-insensitive `magnet:?` / `xt=urn:btih:` handling
  - case-insensitive query keys (`xt`, `dn`, `tr`, `ws`, `as`, `so`)
  - stable multi-value parsing for duplicate and numbered params (`tr.N`, `ws.N`, `as.N`, `so.N`)
- harden metadata download validation and safety:
  - validate info hash via `ArgumentError` (not assert-only)
  - verify cached metadata hash before emitting completion
  - add guards for malformed metadata payload boundaries and stopped downloader states
- improve logging and diagnostics:
  - replace noisy debug prints with structured logger calls in peer/metadata paths
  - keep malformed metadata messages non-fatal
- improve parser compatibility in torrent parsing for mixed bencoded value types
- add public API documentation for key exported symbols/events and exceptions
- add official minimal `example/example.dart` for pub.dev package layout compliance
- add `.pubignore` to exclude local artifacts and keep publish archives small/clean

## 0.4.8
- add BEP 16 Superseeding support with `SuperSeeder` class and `enableSuperseeding()`/`disableSuperseeding()` methods in `TorrentTask`
- add superseeding algorithm implementation that masquerades seeder as peer with no data to improve seeding efficiency
- add piece rarity tracking and distribution monitoring for superseeding mode
- add automatic superseeding activation when download completes (if enabled before completion)
- add file priority management system with `FilePriorityManager` class and `FilePriority` enum (skip, low, normal, high)
- add `setFilePriority()` and `setFilePriorities()` methods for individual and batch file priority management
- add `getFilePriority()` method to retrieve current file priority
- add `autoPrioritizeFiles()` method for automatic priority assignment based on file extensions (video/audio files get high priority, subtitles get normal, others get low)
- add piece prioritization based on file priorities (high priority files download first)
- add file priority persistence in state file (StateFileV2) for resume support
- add `TorrentParser` class to replace external `dtorrent_parser` dependency
- add `TorrentModel` class as replacement for `Torrent` class from `dtorrent_parser`
- add full BEP 52 (v2) support in built-in parser with automatic version detection
- add support for parsing v1, v2, and hybrid torrents in `TorrentParser`
- add `TorrentModel.parse()` static method for backward compatibility with `Torrent.parse()`
- add `TorrentParser.parseBytes()` and `TorrentParser.parseFromMap()` for flexible parsing
- remove dependency on `dtorrent_parser` package (now built-in)
- add comprehensive superseeding example (`superseeding_example.dart`) with CLI interface
- add file validation and bitfield update functionality in superseeding example
- improve piece distribution logic in `SuperSeeder` for better efficiency
- improve state file handling with file priorities support
- improve temporary file cleanup during state file operations
- export `FilePriority` and `FilePriorityManager` in public API
- export `SuperSeeder` in public API (via seeding module)
- add comprehensive test suite for superseeding functionality
- update all examples and tests to use `TorrentModel` instead of `Torrent` from `dtorrent_parser`

## 0.4.7
- add BEP 48 Tracker Scrape support with `scrapeTracker()` method in `TorrentTask`
- add `ScrapeClient` class for retrieving torrent statistics (seeders, leechers, downloads) without full announce
- add UPnP and NAT-PMP port forwarding support with `PortForwardingManager` class
- add `NATPMPClient` and `UPnPClient` for automatic port mapping and gateway discovery
- add IP filtering functionality with `IPFilter` class supporting blacklist and whitelist modes
- add eMule dat format parser (`EmuleDatParser`) for loading IP filters from .dat files
- add PeerGuardian format parser (`PeerGuardianParser`) for loading IP filters from .p2p files
- add HTTP proxy support with `ProxyConfig` and `ProxyManager` classes
- add SOCKS5 proxy support with `Socks5Client` class
- add HTTP proxy client (`HttpProxyClient`) for HTTP/HTTPS proxy connections
- add torrent queue management system with `QueueManager` and `TorrentQueue` classes
- add priority-based queue system with `QueuePriority` enum (low, normal, high, urgent)
- add concurrent download limit support in queue manager
- add queue events (`QueueItemAdded`, `QueueItemCompleted`, `QueueItemFailed`, etc.)
- add enhanced state file format (StateFileV2) with versioning and validation
- add magic bytes ("DTSF") for state file format identification
- add automatic migration from v1 to v2 state file format
- add gzip compression support for bitfield storage (reduces file size for large torrents)
- add sparse storage format for partially downloaded torrents (optimizes storage for <10% completion)
- add CRC32 checksums for header and bitfield validation
- add state file integrity validation with `validate()` method
- add `StateRecovery` class for automatic recovery from corrupted state files
- add `FileValidator` class for validating downloaded files against piece hashes
- add quick validation mode (checks file existence and sizes without hash verification)
- add full validation mode (validates all pieces with SHA-1/SHA-256 hashes)
- add per-file validation support for selective file verification
- add automatic file validation on resume with `validateOnResume` option in `DownloadFileManager`
- add state file metadata tracking (version, last modified timestamp, storage flags)
- add dynamic storage format switching (sparse/full based on completion ratio)
- add state file backup functionality before recovery operations
- export new classes in public API (`StateFileV2`, `StateRecovery`, `FileValidator`, `ProxyConfig`, `ProxyManager`, `QueueManager`, `IPFilter`, `PortForwardingManager`)
- add comprehensive examples (`proxy_example.dart`, `torrent_queue_example.dart`, `fast_resume_example.dart`, `ip_filtering_example.dart`, `port_forwarding_example.dart`, `simple_integration_example.dart`)
- add comprehensive test suites for all new features

## 0.4.6
- add BitTorrent Protocol v2 (BEP 52) support
- add v2 info hash support (32 bytes SHA-256 instead of 20 bytes SHA-1)
- add v2 piece hashing with SHA-256 algorithm
- add hybrid torrent support (v1 + v2 compatibility)
- add torrent version detection via meta version field
- add file tree structure support (BEP 52) with `FileTreeHelper` class
- add piece layers support with `PieceLayersHelper` class
- add Merkle tree validation for v2 files with `MerkleTreeHelper` class
- add hash request/hashes/hash reject messages (ID 21, 22, 23) for v2 protocol
- add hybrid torrent handshake upgrade (4th bit in reserved bytes)
- add v2 info hash calculation (SHA-256 from bencoded info dict)
- add `TorrentVersionHelper` for version detection and hash algorithm selection
- update handshake protocol to support v2 extension bit
- update piece validation to support both SHA-1 (v1) and SHA-256 (v2)
- update `PieceManager` to handle piece layers for v2 torrents
- update `DownloadFileManager` to support file tree structure
- add comprehensive test suite for BEP 52 features (33 new tests)
- export BEP 52 helper classes in public API (`FileTreeHelper`, `PieceLayersHelper`, `MerkleTreeHelper`)

## 0.4.5
- add advanced sequential download support for streaming
- add `SequentialConfig` class for flexible streaming configuration
- add `AdvancedSequentialPieceSelector` with look-ahead buffer
- add `SequentialStats` for download metrics and health monitoring
- add look-ahead buffer for smooth playback (configurable size)
- add critical piece prioritization (moov atom for MP4 files)
- add adaptive strategy (automatic switching between sequential and rarest-first)
- add seek operation support with fast priority rebuilding
- add auto-detection of moov atom for MP4 files
- add peer priority optimization (BEP 40 - Canonical Peer Priority)
- add fast piece resumption support (BEP 53 - Partial data)
- add sequential statistics API (`getSequentialStats()`)
- add playback position tracking (`setPlaybackPosition()`)
- add factory methods for common use cases (`forVideoStreaming()`, `forAudioStreaming()`)
- add comprehensive streaming examples
- export sequential download classes in public API

## 0.4.4
- add Base32 infohash support in magnet links (RFC 4648)
- integrate trackers from magnet links into MetadataDownloader for peer discovery
- add automatic retry mechanism (up to 3 attempts) when metadata verification fails
- implement parallel metadata download from multiple peers for faster completion
- improve timeout handling with exponential backoff (10s base, +5s per retry, max 30s)
- add TrackerTier class for grouping trackers by tiers (BEP 0012)
- support parsing numbered tracker parameters (tr.1, tr.2, etc.) as separate tiers
- announce to trackers tier by tier for better reliability
- detect private torrent flag in metadata handshake (BEP 0027)
- automatically disable DHT announce for private torrents
- block PEX peer exchange for private torrents
- parse ws (Web Seed) parameter from magnet links (BEP 0019)
- parse as (Acceptable Source) parameter from magnet links
- support multiple web seed URLs
- implement WebSeedDownloader class for HTTP/FTP seeding (BEP 0019)
- support HTTP Range requests for efficient piece downloading
- integrate web seed URLs from magnet links into TorrentTask
- automatic fallback to P2P when web seeds are unavailable
- support multiple web seed URLs with retry mechanism (max 3 attempts per URL)
- handle both Partial Content (206) and Full Content (200) HTTP responses
- proper resource cleanup and HttpClient management
- web seed download triggered when no peers available for a piece
- update TorrentTask.newTask() to accept webSeeds and acceptableSources parameters
- parse so (select only) parameter from magnet links (BEP 0053)
- add applySelectedFiles() method to TorrentTask for prioritizing selected files
- add metadata caching to avoid re-downloading metadata for same infohash
- add configurable cache directory (defaults to system temp + metadata_cache)
- enhance error handling and logging throughout metadata download process
- improve timeout management with per-piece retry tracking
- update example showing all new magnet link features
- fix magnet parser to properly handle multiple parameters with same key (so, ws, as)
- improve LSD port conflict handling in TorrentTask.start() to gracefully continue without LSD
- add early validation for empty piece size in WebSeedDownloader to prevent unnecessary HTTP requests
- fix PieceManager tests to properly set remote bitfield for peer selection
- fix PieceManager test for writeComplete to check isCompletelyWritten instead of flushed flag
- improve streaming isolate tests to handle ReceivePort reuse errors gracefully
- fix torrent creator tests to accept both ArgumentError and PathNotFoundException for empty directories
- fix torrent client tests to skip when required torrent file is missing
- enhance web seeding integration tests with better port conflict detection
- improve test reliability by handling resource conflicts in parallel test execution
- fix critical bug: "Invalid message buffer size: length=1" error for messages without payload (choke, unchoke, interested, not interested)
- fix peer transfer from MetadataDownloader to TorrentTask after metadata download completes
- transfer active peers from metadata download phase to actual download phase to avoid reconnection delays
- add trackers from magnet link to TorrentTask to ensure all trackers are used even if not in metadata
- improve bitfield handling: properly support messages without payload according to BEP 0003
- enhance test example with comprehensive diagnostics and automatic completion detection

## 0.4.3
- fix critical bug where downloads don't start despite connected peers (fixes #4)
- fix race condition in bitfield processing when peer sends unchoke before interested
- optimize progress event emission with debouncing to reduce UI update frequency
- improve uTP congestion control with optimized initial window size
- add streaming isolate support for better performance during video streaming
- export magnet parser and torrent creator in public API

## 0.4.2
- update mime dependency from ^1.0.6 to ^2.0.0
- optimize lookupMimeType usage to avoid duplicate calls
- update lints dev dependency from ^2.1.1 to ^6.0.0
- fix linter warnings for new lint rules (unnecessary_library_name, strict_top_level_inference, unintended_html_in_doc_comment)
- fix uTP RangeError crashes with comprehensive protection:
  - add buffer bounds validation before all setRange operations
  - add message length validation (negative, oversized, and overflow values)
  - add integer overflow protection for message length calculations
  - wrap all critical uTP operations in try-catch blocks with RangeError handling
  - add RangeError metrics tracking (Peer.rangeErrorCount, Peer.utpRangeErrorCount)
  - add detailed logging for uTP debugging (buffer sizes, message parsing)
  - extract magic numbers to constants (MAX_MESSAGE_SIZE, BUFFER_SIZE_WARNING_THRESHOLD)
- create comprehensive test suite for uTP RangeError protection:
  - utp_range_error_protection_test.dart: basic validation tests
  - utp_stress_test.dart: stress tests with 50+ parallel peers
  - utp_reorder_test.dart: packet reordering and burst ACK tests
  - utp_extreme_values_test.dart: extreme value tests (large seq/ack, overflows)
  - utp_long_session_test.dart: long session stability tests

## 0.4.1
- update dependencies to latest compatible versions
- upgrade SDK constraint to >=3.0.0
- fix dead code warnings in examples
- remove unused code (_hookUTP method, unused imports)
- fix TCPConnectException to properly use exception field
- update analysis options to disable constant naming checks

## 0.4.0
- enable utp
- decouple some parts of the code
- use logging package
- select pieces when stream is seeking
- cache piece in memory until it is validated then write to disk
- enable lsd
- fixes for PEX
- emit useful events
- add simple binary for testing
- optimizing
- fix memory leaks
- some refactoring and cleanup

## 0.3.5
- use more broad collection constraints

## 0.3.4
- use events_emitter and streams when possible
- video streaming fixes
- fix tests
- validate completed pieces
- add task start, task stop, task resume events
- move more dynamic types to explicit types
- update deps and sdk constraints

## 0.3.3
- migrate to events_emitter2

## 0.3.2
- pub.dev fixes

## 0.3.1
- nullsafety

## 0.3.0
- Add Send Metadata extension (BEP0009)

## 0.2.1
- Change congestion control

## 0.2.0
- Add UTP support
- Add holepunch extension
- Add LSD extension
- Fix PEX extension bugs

## 0.1.4
- Fix some issues
- Fix peer download slow issue

## 0.1.2
- Support peer reconnect
- Fix some bugs

## 0.1.1
- Add DHT support
- Add PEX support
- Change Tracker
- Fix some bugs

## 0.0.2

- Fix license file error
- Fix example error

## 0.0.1

- Initial version

