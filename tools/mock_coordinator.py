#!/usr/bin/env python3
"""
Mock Coordinator Server for the distributed computing volunteer client.

Runs a WebSocket server on port 8765 (configurable) that:
  1. Accepts device registrations
  2. Dispatches sample jobs at regular intervals
  3. Collects and logs results
  4. Responds to heartbeats

Usage:
    pip install websockets
    python mock_coordinator.py [--port 8765] [--interval 10]

Protocol (JSON over WebSocket):
    Client -> Server:
        {"type": "register", "device_id": "abc123", "capabilities": ["sha256Batch", ...]}
        {"type": "heartbeat", "device_id": "abc123", "active_jobs": 1}
        {"type": "result", "job_id": "...", "type": "sha256Batch", "result": {...}, "elapsed_ms": 42}
    Server -> Client:
        {"type": "job", "id": "job-001", "type": "sha256Batch", "payload": {...}}
        {"type": "ack", "job_id": "job-001"}
        {"type": "error", "message": "..."}
"""

import argparse
import asyncio
import json
import logging
import random
import string
import time
import uuid
from typing import Dict, Set

try:
    import websockets
except ImportError:
    print("Install websockets: pip install websockets")
    raise SystemExit(1)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
log = logging.getLogger("coordinator")

# ─── Connected devices ─────────────────────────────────────────────────────
devices: Dict[str, websockets.WebSocketServerProtocol] = {}  # device_id -> ws
device_caps: Dict[str, list] = {}  # device_id -> capabilities

# ─── Job tracking ──────────────────────────────────────────────────────────
pending_jobs: Dict[str, dict] = {}  # job_id -> job dict
completed_results: list = []
job_counter = 0


def make_job_id() -> str:
    global job_counter
    job_counter += 1
    return f"job-{job_counter:04d}"


# ─── Sample job generators ────────────────────────────────────────────────

def gen_sha256_batch() -> dict:
    """Generate a SHA-256 batch hashing job with random strings."""
    count = random.randint(5, 50)
    inputs = [
        "".join(random.choices(string.ascii_letters + string.digits, k=random.randint(10, 100)))
        for _ in range(count)
    ]
    return {
        "id": make_job_id(),
        "type": "sha256Batch",
        "payload": {"inputs": inputs},
    }


def gen_prime_search() -> dict:
    """Generate a prime search job in a random range."""
    start = random.randint(2, 10_000)
    end = start + random.randint(500, 5_000)
    return {
        "id": make_job_id(),
        "type": "primeSearch",
        "payload": {"start": start, "end": end},
    }


def gen_matrix_multiply() -> dict:
    """Generate a matrix multiplication job with random NxN matrices."""
    n = random.randint(3, 10)
    a = [[random.uniform(-10, 10) for _ in range(n)] for _ in range(n)]
    b = [[random.uniform(-10, 10) for _ in range(n)] for _ in range(n)]
    return {
        "id": make_job_id(),
        "type": "matrixMultiply",
        "payload": {"a": a, "b": b},
    }


def gen_crc32_verify() -> dict:
    """Generate a CRC-32 verification job."""
    data = "".join(random.choices(string.printable, k=random.randint(20, 200)))
    return {
        "id": make_job_id(),
        "type": "crc32Verify",
        "payload": {"data": data, "expected": None},
    }


JOB_GENERATORS = [gen_sha256_batch, gen_prime_search, gen_matrix_multiply, gen_crc32_verify]


def random_job() -> dict:
    return random.choice(JOB_GENERATORS)()


# ─── WebSocket handlers ───────────────────────────────────────────────────

async def handle_client(ws: websockets.WebSocketServerProtocol, path: str = "/"):
    device_id = None
    try:
        async for raw in ws:
            try:
                msg = json.loads(raw)
            except json.JSONDecodeError:
                await ws.send(json.dumps({"type": "error", "message": "Invalid JSON"}))
                continue

            msg_type = msg.get("type")

            if msg_type == "register":
                device_id = msg.get("device_id", str(uuid.uuid4()))
                caps = msg.get("capabilities", [])
                devices[device_id] = ws
                device_caps[device_id] = caps
                log.info("Device registered: %s (capabilities: %s)", device_id, caps)

            elif msg_type == "heartbeat":
                device_id = msg.get("device_id", device_id)
                active = msg.get("active_jobs", 0)
                log.debug("Heartbeat from %s (active: %d)", device_id, active)

            elif msg_type == "result":
                job_id = msg.get("job_id", "?")
                elapsed = msg.get("elapsed_ms", 0)
                result_data = msg.get("result", {})
                completed_results.append(msg)
                pending_jobs.pop(job_id, None)
                log.info(
                    "Result from %s: job=%s type=%s elapsed=%dms",
                    device_id, job_id, msg.get("type", "?"), elapsed,
                )
                # Send acknowledgement
                await ws.send(json.dumps({"type": "ack", "job_id": job_id}))

            else:
                log.warning("Unknown message type from %s: %s", device_id, msg_type)

    except websockets.exceptions.ConnectionClosed:
        log.info("Device disconnected: %s", device_id)
    finally:
        if device_id and device_id in devices:
            del devices[device_id]
            device_caps.pop(device_id, None)


async def dispatch_jobs(interval: float):
    """Periodically dispatch random jobs to connected devices."""
    while True:
        await asyncio.sleep(interval)
        if not devices:
            continue

        # Pick a random connected device
        device_id = random.choice(list(devices.keys()))
        ws = devices[device_id]

        # Generate a job matching the device's capabilities
        job = random_job()
        job_id = job["id"]

        try:
            await ws.send(json.dumps({"type": "job", **job}))
            pending_jobs[job_id] = job
            log.info("Dispatched %s (%s) -> %s", job_id, job["type"], device_id)
        except Exception as e:
            log.error("Failed to dispatch to %s: %s", device_id, e)


async def status_logger():
    """Print server status every 30 seconds."""
    while True:
        await asyncio.sleep(30)
        log.info(
            "Status: %d devices, %d pending jobs, %d completed",
            len(devices), len(pending_jobs), len(completed_results),
        )


# ─── Main ──────────────────────────────────────────────────────────────────

async def main(port: int, interval: float):
    log.info("Starting mock coordinator on ws://0.0.0.0:%d", port)
    log.info("Job dispatch interval: %.1fs", interval)

    async with websockets.serve(handle_client, "0.0.0.0", port):
        await asyncio.gather(
            dispatch_jobs(interval),
            status_logger(),
            asyncio.Future(),  # run forever
        )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Mock Distributed Computing Coordinator")
    parser.add_argument("--port", type=int, default=8765, help="WebSocket port (default: 8765)")
    parser.add_argument(
        "--interval", type=float, default=10.0,
        help="Seconds between job dispatches (default: 10)",
    )
    args = parser.parse_args()

    try:
        asyncio.run(main(args.port, args.interval))
    except KeyboardInterrupt:
        log.info("Shutting down")
