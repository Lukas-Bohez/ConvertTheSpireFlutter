import 'package:logging/logging.dart';
import 'torrent_queue_item.dart';

var _log = Logger('TorrentQueue');

/// Manages a priority queue of torrent items
class TorrentQueue {
  final List<TorrentQueueItem> _items = [];

  /// Get all items in the queue (sorted by priority)
  List<TorrentQueueItem> get items => List.unmodifiable(_items);

  /// Get the number of items in the queue
  int get length => _items.length;

  /// Check if the queue is empty
  bool get isEmpty => _items.isEmpty;

  /// Check if the queue is not empty
  bool get isNotEmpty => _items.isNotEmpty;

  /// Add an item to the queue
  ///
  /// The item will be inserted in the correct position based on priority
  /// (high priority items first, then normal, then low)
  void add(TorrentQueueItem item) {
    _items.add(item);
    _sort();
    _log.fine('Added item to queue: ${item.id} (priority: ${item.priority})');
  }

  /// Add multiple items to the queue
  void addAll(List<TorrentQueueItem> items) {
    _items.addAll(items);
    _sort();
    _log.fine('Added ${items.length} items to queue');
  }

  /// Remove an item from the queue by ID
  ///
  /// Returns true if the item was found and removed, false otherwise
  bool remove(String id) {
    final index = _items.indexWhere((item) => item.id == id);
    if (index != -1) {
      _items.removeAt(index);
      _log.fine('Removed item from queue: $id');
      return true;
    }
    return false;
  }

  /// Remove an item from the queue
  ///
  /// Returns true if the item was found and removed, false otherwise
  bool removeItem(TorrentQueueItem item) {
    return remove(item.id);
  }

  /// Get the next item from the queue (highest priority)
  ///
  /// Returns null if the queue is empty
  TorrentQueueItem? peek() {
    return _items.isNotEmpty ? _items.first : null;
  }

  /// Get and remove the next item from the queue (highest priority)
  ///
  /// Returns null if the queue is empty
  TorrentQueueItem? pop() {
    if (_items.isEmpty) return null;
    final item = _items.removeAt(0);
    _log.fine('Popped item from queue: ${item.id}');
    return item;
  }

  /// Get an item by ID
  TorrentQueueItem? getById(String id) {
    try {
      return _items.firstWhere((item) => item.id == id);
    } catch (e) {
      return null;
    }
  }

  /// Check if an item with the given ID exists in the queue
  bool contains(String id) {
    return _items.any((item) => item.id == id);
  }

  /// Update the priority of an item
  ///
  /// Returns true if the item was found and updated, false otherwise
  bool updatePriority(String id, QueuePriority newPriority) {
    final index = _items.indexWhere((item) => item.id == id);
    if (index != -1) {
      final item = _items[index];
      _items[index] = item.copyWith(priority: newPriority);
      _sort();
      _log.fine('Updated priority for item $id to $newPriority');
      return true;
    }
    return false;
  }

  /// Move an item to the top of its priority group
  ///
  /// Returns true if the item was found and moved, false otherwise
  bool moveToTop(String id) {
    final index = _items.indexWhere((item) => item.id == id);
    if (index != -1) {
      final item = _items.removeAt(index);
      // Find the first item with the same priority
      final samePriorityIndex = _items.indexWhere(
        (i) => i.priorityValue < item.priorityValue,
      );
      if (samePriorityIndex == -1) {
        _items.add(item);
      } else {
        _items.insert(samePriorityIndex, item);
      }
      _log.fine('Moved item $id to top of priority group');
      return true;
    }
    return false;
  }

  /// Move an item to the bottom of its priority group
  ///
  /// Returns true if the item was found and moved, false otherwise
  bool moveToBottom(String id) {
    final index = _items.indexWhere((item) => item.id == id);
    if (index != -1) {
      final item = _items.removeAt(index);
      // Find the last item with the same priority
      final samePriorityIndex = _items.lastIndexWhere(
        (i) => i.priorityValue == item.priorityValue,
      );
      if (samePriorityIndex == -1) {
        // No other items with same priority, add at end of same priority group
        final nextPriorityIndex = _items.indexWhere(
          (i) => i.priorityValue < item.priorityValue,
        );
        if (nextPriorityIndex == -1) {
          _items.add(item);
        } else {
          _items.insert(nextPriorityIndex, item);
        }
      } else {
        _items.insert(samePriorityIndex + 1, item);
      }
      _log.fine('Moved item $id to bottom of priority group');
      return true;
    }
    return false;
  }

  /// Clear all items from the queue
  void clear() {
    _items.clear();
    _log.fine('Queue cleared');
  }

  /// Get items by priority
  List<TorrentQueueItem> getByPriority(QueuePriority priority) {
    return _items.where((item) => item.priority == priority).toList();
  }

  /// Sort the queue by priority (high -> normal -> low)
  /// Within the same priority, items are sorted by addedAt timestamp (FIFO)
  void _sort() {
    _items.sort((a, b) {
      // First sort by priority (higher priority first)
      final priorityDiff = b.priorityValue.compareTo(a.priorityValue);
      if (priorityDiff != 0) return priorityDiff;
      // Within same priority, sort by addedAt (earlier first - FIFO)
      return a.addedAt.compareTo(b.addedAt);
    });
  }
}
