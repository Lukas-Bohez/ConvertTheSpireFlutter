import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show debugPrint;

// ─────────────────────────────────────────────────────────────────────────────
// Data models
// ─────────────────────────────────────────────────────────────────────────────

enum ComputeJobType {
  sha256Batch,
  primeSearch,
  matrixMultiply,
  crc32Verify,
  qubicMining,
}

class ComputeJob {
  final String id;
  final ComputeJobType type;
  final Map<String, dynamic> payload;
  final DateTime receivedAt;

  const ComputeJob({
    required this.id,
    required this.type,
    required this.payload,
    required this.receivedAt,
  });

  factory ComputeJob.fromJson(Map<String, dynamic> json) {
    return ComputeJob(
      id: json['id'] as String,
      type: ComputeJobType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => ComputeJobType.sha256Batch,
      ),
      payload: Map<String, dynamic>.from(json['payload'] as Map? ?? {}),
      receivedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'payload': payload,
      };
}

class ComputeResult {
  final String jobId;
  final ComputeJobType type;
  final Map<String, dynamic> result;
  final Duration elapsed;

  const ComputeResult({
    required this.jobId,
    required this.type,
    required this.result,
    required this.elapsed,
  });

  Map<String, dynamic> toJson() => {
        'job_id': jobId,
        'type': type.name,
        'result': result,
        'elapsed_ms': elapsed.inMilliseconds,
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// Isolate entry points — top-level functions for Isolate.run
// ─────────────────────────────────────────────────────────────────────────────

/// SHA-256 batch: hash a list of input strings.
Map<String, dynamic> _sha256Batch(Map<String, dynamic> payload) {
  final inputs = (payload['inputs'] as List?)?.cast<String>() ?? [];
  final hashes = <String>[];
  for (final input in inputs) {
    final bytes = utf8.encode(input);
    hashes.add(sha256.convert(bytes).toString());
  }
  return {'hashes': hashes, 'count': hashes.length};
}

/// Prime search: find all primes in [start, end].
Map<String, dynamic> _primeSearch(Map<String, dynamic> payload) {
  final start = (payload['start'] as num?)?.toInt() ?? 2;
  final end = (payload['end'] as num?)?.toInt() ?? 1000;
  final primes = <int>[];
  for (int n = start.clamp(2, end); n <= end; n++) {
    if (_isPrime(n)) primes.add(n);
  }
  return {'primes': primes, 'count': primes.length};
}

bool _isPrime(int n) {
  if (n < 2) return false;
  if (n < 4) return true;
  if (n % 2 == 0 || n % 3 == 0) return false;
  for (int i = 5; i * i <= n; i += 6) {
    if (n % i == 0 || n % (i + 2) == 0) return false;
  }
  return true;
}

/// Matrix multiplication: multiply two NxN matrices.
Map<String, dynamic> _matrixMultiply(Map<String, dynamic> payload) {
  final aRaw = (payload['a'] as List?)?.map((r) => (r as List).cast<num>()).toList() ?? [];
  final bRaw = (payload['b'] as List?)?.map((r) => (r as List).cast<num>()).toList() ?? [];

  if (aRaw.isEmpty || bRaw.isEmpty) {
    return {'error': 'Empty matrices'};
  }

  final n = aRaw.length;
  final m = bRaw[0].length;
  final p = aRaw[0].length;

  final result = List.generate(n, (_) => List.filled(m, 0.0));
  for (int i = 0; i < n; i++) {
    for (int j = 0; j < m; j++) {
      double sum = 0;
      for (int k = 0; k < p; k++) {
        sum += aRaw[i][k].toDouble() * bRaw[k][j].toDouble();
      }
      result[i][j] = sum;
    }
  }
  return {'result': result, 'dimensions': '${n}x$m'};
}

/// CRC-32 verification: compute CRC-32 of data and compare with expected.
Map<String, dynamic> _crc32Verify(Map<String, dynamic> payload) {
  final data = payload['data'] as String? ?? '';
  final expected = (payload['expected'] as num?)?.toInt();
  final bytes = utf8.encode(data);
  final crc = _computeCrc32(bytes);
  return {
    'crc32': crc,
    'hex': '0x${crc.toRadixString(16).padLeft(8, '0')}',
    'matches': expected != null ? crc == expected : null,
  };
}

int _computeCrc32(List<int> bytes) {
  // Standard CRC-32 (ISO 3309 / ITU-T V.42)
  const polynomial = 0xEDB88320;
  int crc = 0xFFFFFFFF;
  for (final b in bytes) {
    crc ^= b;
    for (int i = 0; i < 8; i++) {
      if ((crc & 1) != 0) {
        crc = (crc >> 1) ^ polynomial;
      } else {
        crc >>= 1;
      }
    }
  }
  return crc ^ 0xFFFFFFFF;
}

/// Dispatch within isolate.
Map<String, dynamic> _runJobSync(ComputeJob job) {
  switch (job.type) {
    case ComputeJobType.sha256Batch:
      return _sha256Batch(job.payload);
    case ComputeJobType.primeSearch:
      return _primeSearch(job.payload);
    case ComputeJobType.matrixMultiply:
      return _matrixMultiply(job.payload);
    case ComputeJobType.crc32Verify:
      return _crc32Verify(job.payload);
    case ComputeJobType.qubicMining:
      return _qubicMining(job.payload);
  }
}

/// Qubic-style proof-of-work mining.
///
/// Searches for a nonce such that SHA-256(walletId + epoch + nonce) starts
/// with at least [difficulty] leading zero-bits.  This is analogous to the
/// actual Qubic Aigarth PoW system where miners search for solutions that
/// satisfy a difficulty threshold, contributing hash-power to the network.
Map<String, dynamic> _qubicMining(Map<String, dynamic> payload) {
  final walletId = payload['wallet_id'] as String? ?? '';
  final epoch = (payload['epoch'] as num?)?.toInt() ?? 0;
  final difficulty = (payload['difficulty'] as num?)?.toInt() ?? 16;
  final maxIterations = (payload['max_iterations'] as num?)?.toInt() ?? 500000;

  final prefix = utf8.encode('$walletId:$epoch:');
  int bestZeroBits = 0;
  String bestNonce = '';
  String bestHash = '';
  int iterations = 0;
  bool solved = false;

  for (int nonce = 0; nonce < maxIterations; nonce++) {
    iterations++;
    final nonceBytes = utf8.encode(nonce.toString());
    final input = [...prefix, ...nonceBytes];
    final digest = sha256.convert(input);
    final zeroBits = _countLeadingZeroBits(digest.bytes);

    if (zeroBits > bestZeroBits) {
      bestZeroBits = zeroBits;
      bestNonce = nonce.toString();
      bestHash = digest.toString();
    }

    if (zeroBits >= difficulty) {
      solved = true;
      bestNonce = nonce.toString();
      bestHash = digest.toString();
      bestZeroBits = zeroBits;
      break;
    }
  }

  return {
    'solved': solved,
    'nonce': bestNonce,
    'hash': bestHash,
    'leading_zero_bits': bestZeroBits,
    'target_difficulty': difficulty,
    'iterations': iterations,
    'wallet_id': walletId,
    'epoch': epoch,
  };
}

/// Count leading zero-bits in a hash digest.
int _countLeadingZeroBits(List<int> bytes) {
  int count = 0;
  for (final byte in bytes) {
    if (byte == 0) {
      count += 8;
    } else {
      // Count leading zeros of this byte
      int b = byte;
      for (int i = 7; i >= 0; i--) {
        if ((b & (1 << i)) == 0) {
          count++;
        } else {
          return count;
        }
      }
      return count;
    }
  }
  return count;
}

// ─────────────────────────────────────────────────────────────────────────────
// ComputationService — manages an isolate pool
// ─────────────────────────────────────────────────────────────────────────────

class ComputationService {
  int _maxConcurrent;
  int _activeCount = 0;
  bool _enabled = false;
  final _queue = <ComputeJob>[];
  final _results = <ComputeResult>[];

  /// Currently running job IDs (for UI display).
  final Set<String> runningJobIds = {};

  /// Stream of completed results for the coordinator to pick up.
  final StreamController<ComputeResult> _resultStream =
      StreamController.broadcast();
  Stream<ComputeResult> get results => _resultStream.stream;

  /// Notifier for UI refresh.
  void Function()? onStateChanged;

  int get maxConcurrent => _maxConcurrent;
  int get activeCount => _activeCount;
  int get queuedCount => _queue.length;
  bool get enabled => _enabled;
  List<ComputeResult> get completedResults => List.unmodifiable(_results);

  ComputationService({int maxConcurrent = 2})
      : _maxConcurrent = maxConcurrent.clamp(1, 4);

  void setMaxConcurrent(int value) {
    _maxConcurrent = value.clamp(1, 4);
    _processQueue();
  }

  void setEnabled(bool value) {
    _enabled = value;
    if (!_enabled) {
      _queue.clear();
    }
    onStateChanged?.call();
  }

  /// Enqueue a job for execution.
  void enqueue(ComputeJob job) {
    if (!_enabled) return;
    _queue.add(job);
    debugPrint('ComputationService: enqueued job ${job.id} (${job.type.name})');
    _processQueue();
  }

  /// Process queued jobs up to the concurrency limit.
  void _processQueue() {
    while (_activeCount < _maxConcurrent && _queue.isNotEmpty && _enabled) {
      final job = _queue.removeAt(0);
      _runJob(job);
    }
  }

  Future<void> _runJob(ComputeJob job) async {
    _activeCount++;
    runningJobIds.add(job.id);
    onStateChanged?.call();

    final sw = Stopwatch()..start();
    try {
      final resultData = await Isolate.run(() => _runJobSync(job));
      sw.stop();

      final result = ComputeResult(
        jobId: job.id,
        type: job.type,
        result: resultData,
        elapsed: sw.elapsed,
      );
      _results.add(result);
      if (_results.length > 100) _results.removeAt(0); // keep bounded
      if (!_resultStream.isClosed) _resultStream.add(result);
      debugPrint(
          'ComputationService: completed ${job.id} in ${sw.elapsedMilliseconds}ms');
    } catch (e) {
      sw.stop();
      debugPrint('ComputationService: job ${job.id} failed: $e');
      final errorResult = ComputeResult(
        jobId: job.id,
        type: job.type,
        result: {'error': e.toString()},
        elapsed: sw.elapsed,
      );
      _results.add(errorResult);
      if (!_resultStream.isClosed) _resultStream.add(errorResult);
    } finally {
      _activeCount--;
      runningJobIds.remove(job.id);
      onStateChanged?.call();
      _processQueue();
    }
  }

  void dispose() {
    _resultStream.close();
  }
}
