import 'dart:async';
import 'package:dtorrent_task_v2/src/task.dart';
import 'package:dtorrent_task_v2/src/task_events.dart';
import 'package:events_emitter2/events_emitter2.dart';
import 'package:logging/logging.dart';
import 'torrent_queue.dart';
import 'torrent_queue_item.dart';
import 'queue_events.dart';

var _log = Logger('QueueManager');

/// Manages torrent download queue with priority support and concurrent download limits
class QueueManager {
  final TorrentQueue _queue = TorrentQueue();
  final Map<String, TorrentTask> _activeTasks = {};
  final Map<String, EventsListener<TaskEvent>> _taskListeners = {};
  int _maxConcurrentDownloads;

  /// Events emitted by the queue manager
  final EventsEmitter<QueueEvent> events = EventsEmitter<QueueEvent>();

  /// Get the queue
  TorrentQueue get queue => _queue;

  /// Get the maximum number of concurrent downloads
  int get maxConcurrentDownloads => _maxConcurrentDownloads;

  /// Set the maximum number of concurrent downloads
  ///
  /// If the new limit is lower than the current number of active downloads,
  /// no new downloads will start until the count drops below the limit.
  set maxConcurrentDownloads(int value) {
    if (value < 1) {
      throw ArgumentError('maxConcurrentDownloads must be at least 1');
    }
    _maxConcurrentDownloads = value;
    _log.info('Max concurrent downloads set to $value');
    // Try to start more downloads if we have capacity now
    _processQueue();
  }

  /// Get the number of active downloads
  int get activeDownloadsCount => _activeTasks.length;

  /// Get all active tasks
  Map<String, TorrentTask> get activeTasks => Map.unmodifiable(_activeTasks);

  /// Get a task by queue item ID
  TorrentTask? getTask(String queueItemId) {
    return _activeTasks[queueItemId];
  }

  /// Check if a task is currently active
  bool isTaskActive(String queueItemId) {
    return _activeTasks.containsKey(queueItemId);
  }

  QueueManager({int maxConcurrentDownloads = 3})
      : _maxConcurrentDownloads = maxConcurrentDownloads {
    _log.info(
        'QueueManager initialized with maxConcurrentDownloads: $_maxConcurrentDownloads');
  }

  /// Add a torrent to the queue
  ///
  /// Returns the queue item ID
  String addToQueue(TorrentQueueItem item) {
    _queue.add(item);
    events.emit(QueueItemAdded(item));
    _log.info('Added torrent to queue: ${item.metaInfo.name} (ID: ${item.id})');
    _processQueue();
    return item.id;
  }

  /// Add multiple torrents to the queue
  ///
  /// Returns list of queue item IDs
  List<String> addAllToQueue(List<TorrentQueueItem> items) {
    final ids = <String>[];
    for (final item in items) {
      _queue.add(item);
      ids.add(item.id);
      events.emit(QueueItemAdded(item));
    }
    _log.info('Added ${items.length} torrents to queue');
    _processQueue();
    return ids;
  }

  /// Remove a torrent from the queue (if not started)
  ///
  /// Returns true if the item was removed, false if it was already started or not found
  Future<bool> removeFromQueue(String queueItemId) async {
    final task = _activeTasks[queueItemId];
    if (task != null) {
      _log.warning('Cannot remove active task from queue: $queueItemId');
      return false;
    }

    final item = _queue.getById(queueItemId);
    if (item != null) {
      _queue.remove(queueItemId);
      events.emit(QueueItemRemoved(queueItemId));
      _log.info('Removed torrent from queue: $queueItemId');
      return true;
    }
    return false;
  }

  /// Update priority of a queued item
  ///
  /// Returns true if the priority was updated, false if the item was not found or is already active
  bool updatePriority(String queueItemId, QueuePriority newPriority) {
    if (_activeTasks.containsKey(queueItemId)) {
      _log.warning('Cannot update priority of active task: $queueItemId');
      return false;
    }

    if (_queue.updatePriority(queueItemId, newPriority)) {
      events.emit(QueueItemPriorityUpdated(queueItemId, newPriority));
      _log.info(
          'Updated priority for queue item: $queueItemId to $newPriority');
      return true;
    }
    return false;
  }

  /// Move a queued item to the top of its priority group
  bool moveToTop(String queueItemId) {
    if (_activeTasks.containsKey(queueItemId)) {
      return false;
    }
    return _queue.moveToTop(queueItemId);
  }

  /// Move a queued item to the bottom of its priority group
  bool moveToBottom(String queueItemId) {
    if (_activeTasks.containsKey(queueItemId)) {
      return false;
    }
    return _queue.moveToBottom(queueItemId);
  }

  /// Pause an active download
  ///
  /// Returns true if the task was paused, false if not found
  bool pauseDownload(String queueItemId) {
    final task = _activeTasks[queueItemId];
    if (task != null) {
      task.pause();
      events.emit(QueueItemPaused(queueItemId));
      _log.info('Paused download: $queueItemId');
      return true;
    }
    return false;
  }

  /// Resume a paused download
  ///
  /// Returns true if the task was resumed, false if not found
  bool resumeDownload(String queueItemId) {
    final task = _activeTasks[queueItemId];
    if (task != null) {
      task.resume();
      events.emit(QueueItemResumed(queueItemId));
      _log.info('Resumed download: $queueItemId');
      return true;
    }
    return false;
  }

  /// Stop an active download
  ///
  /// This will remove the task from active downloads and start the next queued item
  Future<bool> stopDownload(String queueItemId) async {
    final task = _activeTasks[queueItemId];
    if (task != null) {
      await task.stop();
      _removeActiveTask(queueItemId);
      events.emit(QueueItemStopped(queueItemId));
      _log.info('Stopped download: $queueItemId');
      _processQueue();
      return true;
    }
    return false;
  }

  /// Process the queue and start downloads up to the concurrent limit
  Future<void> _processQueue() async {
    while (_activeTasks.length < _maxConcurrentDownloads && _queue.isNotEmpty) {
      final item = _queue.pop();
      if (item == null) break;

      try {
        _log.info('Starting download: ${item.metaInfo.name} (ID: ${item.id})');
        final task = TorrentTask.newTask(
          item.metaInfo,
          item.savePath,
          item.stream,
          item.webSeeds,
          item.acceptableSources,
          item.sequentialConfig,
          item.proxyConfig,
        );

        _activeTasks[item.id] = task;
        events.emit(QueueItemStarted(item.id, task));

        // Set up event listeners to handle task completion/stopping
        final listener = task.createListener();
        _taskListeners[item.id] = listener;

        listener
          ..on<TaskCompleted>((event) {
            _log.info('Download completed: ${item.id}');
            _removeActiveTask(item.id);
            events.emit(QueueItemCompleted(item.id));
            _processQueue();
          })
          ..on<TaskStopped>((event) {
            // Only process queue if this was a manual stop (not from completion)
            // TaskCompleted already handles queue processing
            if (!_activeTasks.containsKey(item.id)) {
              // Already removed by TaskCompleted
              return;
            }
            _log.info('Download stopped: ${item.id}');
            _removeActiveTask(item.id);
            events.emit(QueueItemStopped(item.id));
            _processQueue();
          });

        // Start the task
        await task.start();
        _log.info('Download started: ${item.id}');
      } catch (e, stackTrace) {
        _log.severe('Failed to start download: ${item.id}', e, stackTrace);
        _removeActiveTask(item.id);
        events.emit(QueueItemFailed(item.id, e.toString()));
        // Continue processing queue even if one task fails
      }
    }
  }

  /// Remove an active task and clean up its listeners
  void _removeActiveTask(String queueItemId) {
    final listener = _taskListeners.remove(queueItemId);
    listener?.dispose();
    _activeTasks.remove(queueItemId);
  }

  /// Stop all active downloads
  Future<void> stopAll() async {
    _log.info('Stopping all active downloads...');
    final tasks = List<TorrentTask>.from(_activeTasks.values);
    for (final task in tasks) {
      await task.stop();
    }
    _activeTasks.clear();
    for (final listener in _taskListeners.values) {
      listener.dispose();
    }
    _taskListeners.clear();
    _log.info('All downloads stopped');
  }

  /// Clear the queue (only queued items, not active downloads)
  void clearQueue() {
    _queue.clear();
    events.emit(QueueCleared());
    _log.info('Queue cleared');
  }

  /// Dispose the queue manager and clean up all resources
  Future<void> dispose() async {
    _log.info('Disposing QueueManager...');
    await stopAll();
    clearQueue();
    events.dispose();
    _log.info('QueueManager disposed');
  }
}
