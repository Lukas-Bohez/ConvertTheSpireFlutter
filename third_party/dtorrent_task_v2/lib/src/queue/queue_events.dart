import 'torrent_queue_item.dart';

/// Base class for queue events
abstract class QueueEvent {}

/// Emitted when an item is added to the queue
class QueueItemAdded implements QueueEvent {
  final TorrentQueueItem item;

  QueueItemAdded(this.item);
}

/// Emitted when an item is removed from the queue
class QueueItemRemoved implements QueueEvent {
  final String queueItemId;

  QueueItemRemoved(this.queueItemId);
}

/// Emitted when an item's priority is updated
class QueueItemPriorityUpdated implements QueueEvent {
  final String queueItemId;
  final QueuePriority newPriority;

  QueueItemPriorityUpdated(this.queueItemId, this.newPriority);
}

/// Emitted when a queued item starts downloading
class QueueItemStarted implements QueueEvent {
  final String queueItemId;
  final dynamic
      task; // TorrentTask, but using dynamic to avoid circular dependency

  QueueItemStarted(this.queueItemId, this.task);
}

/// Emitted when a download is paused
class QueueItemPaused implements QueueEvent {
  final String queueItemId;

  QueueItemPaused(this.queueItemId);
}

/// Emitted when a download is resumed
class QueueItemResumed implements QueueEvent {
  final String queueItemId;

  QueueItemResumed(this.queueItemId);
}

/// Emitted when a download is stopped
class QueueItemStopped implements QueueEvent {
  final String queueItemId;

  QueueItemStopped(this.queueItemId);
}

/// Emitted when a download completes
class QueueItemCompleted implements QueueEvent {
  final String queueItemId;

  QueueItemCompleted(this.queueItemId);
}

/// Emitted when a download fails to start
class QueueItemFailed implements QueueEvent {
  final String queueItemId;
  final String error;

  QueueItemFailed(this.queueItemId, this.error);
}

/// Emitted when the queue is cleared
class QueueCleared implements QueueEvent {}
