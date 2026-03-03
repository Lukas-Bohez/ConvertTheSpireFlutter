# Volunteer Distributed Computing — Architecture & Usage

## Overview

This module implements a **transparent, opt-in** volunteer computing client embedded in the Convert the Spire Reborn Flutter app. Users can donate spare CPU cycles to help process academic workloads. All computation runs locally in sandboxed Dart Isolates — nothing touches the network except WebSocket messages to the coordinator.

## Architecture

```
┌─────────────────────────────────────────────┐
│  Flutter App (Windows / Android)            │
│                                             │
│  ┌───────────────┐   ┌──────────────────┐   │
│  │  ComputeScreen │   │ CoordinatorService│  │
│  │  (UI / Toggle) │◄──│ (WebSocket client)│  │
│  └───────┬───────┘   └────────┬─────────┘  │
│          │                    │              │
│          ▼                    ▼              │
│  ┌──────────────────────────────────────┐   │
│  │  ComputationService                  │   │
│  │  ┌────────┐  ┌────────┐  max 2-4    │   │
│  │  │Isolate │  │Isolate │  concurrent  │   │
│  │  │(SHA256)│  │(Primes)│              │   │
│  │  └────────┘  └────────┘              │   │
│  └──────────────────────────────────────┘   │
└─────────────────────────────────────────────┘
              ▲  WebSocket (JSON)
              │
              ▼
┌─────────────────────────────────────────────┐
│  Coordinator Server (mock_coordinator.py)    │
│  - Registers devices                         │
│  - Dispatches jobs                           │
│  - Collects results                          │
│  - Heartbeat monitoring                      │
└─────────────────────────────────────────────┘
```

## Job Types

| Type             | Description                                      |
|------------------|--------------------------------------------------|
| `sha256Batch`    | Hash a list of input strings with SHA-256         |
| `primeSearch`    | Find all prime numbers in a given range [a, b]    |
| `matrixMultiply` | Multiply two NxN matrices                         |
| `crc32Verify`    | Compute CRC-32 of data, optionally verify match   |

## Files

| File | Purpose |
|------|---------|
| `lib/src/services/computation_service.dart` | Isolate pool, job execution, result streaming |
| `lib/src/services/coordinator_service.dart` | WebSocket client, reconnection, message routing |
| `lib/src/screens/compute_screen.dart` | Full UI: toggle, dashboard, settings, Buy Me a Coffee |
| `tools/mock_coordinator.py` | Python mock server for testing |

## Running the Mock Coordinator

```bash
# Install dependency
pip install websockets

# Start on default port 8765, dispatching jobs every 10 seconds
python tools/mock_coordinator.py

# Custom port and interval
python tools/mock_coordinator.py --port 9000 --interval 5
```

## Using in the App

1. Open the app and navigate to the **Compute** tab in the sidebar.
2. The feature is **OFF by default** — flip the toggle to opt in.
3. Enter the coordinator URL (default: `ws://localhost:8765`).
4. The dashboard shows: running jobs, completed results, battery status, and power state.
5. Computation automatically **pauses below 30% battery** on battery power.
6. Adjust the concurrency slider (1–4 isolates).

## Protocol Specification

All messages are JSON over WebSocket.

### Client → Server

```json
// Registration
{"type": "register", "device_id": "abc123", "capabilities": ["sha256Batch", "primeSearch", "matrixMultiply", "crc32Verify"]}

// Heartbeat (every 30s)
{"type": "heartbeat", "device_id": "abc123", "active_jobs": 1}

// Result submission
{"type": "result", "job_id": "job-0001", "type": "sha256Batch", "result": {"hashes": ["..."], "count": 10}, "elapsed_ms": 42}
```

### Server → Client

```json
// Job dispatch
{"type": "job", "id": "job-0001", "type": "sha256Batch", "payload": {"inputs": ["hello", "world"]}}

// Acknowledgement
{"type": "ack", "job_id": "job-0001"}

// Error
{"type": "error", "message": "Unknown job type"}
```

## Energy Management

- Battery level monitored every 15 seconds via `battery_plus`
- Compute **pauses** when battery < 30% AND device is on battery power
- Compute **resumes** automatically when plugged in or battery recovers
- On desktop (no battery API), assumes AC power

## Design Principles

- **Opt-in by default** — toggle is OFF, user must explicitly enable
- **Fully transparent** — coordinator URL is visible and editable, all jobs shown in dashboard
- **Auditable** — clean Dart code, no obfuscation, standard WebSocket protocol
- **Sandboxed** — computation runs in Dart Isolates (separate memory, no shared state)
- **Graceful** — exponential backoff reconnection (max 120s), offline message queue
