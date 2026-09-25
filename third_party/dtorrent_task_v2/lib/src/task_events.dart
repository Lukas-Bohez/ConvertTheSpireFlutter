import 'package:dtorrent_task_v2/src/file/download_file.dart';
import 'package:dtorrent_task_v2/src/file/download_file_manager_events.dart';

/// Base interface for torrent task lifecycle and progress events.
abstract class TaskEvent {}

/// Emitted when a task is fully stopped.
class TaskStopped implements TaskEvent {}

/// Emitted when a task finishes downloading all required data.
class TaskCompleted implements TaskEvent {}

/// Emitted when a task is paused.
class TaskPaused implements TaskEvent {}

/// Emitted when a paused task resumes.
class TaskResumed implements TaskEvent {}

/// Emitted when a task starts.
class TaskStarted implements TaskEvent {}

/// Emitted when an individual file from the torrent is completed.
class TaskFileCompleted implements TaskEvent {
  /// Completed file descriptor.
  final DownloadFile file;

  /// Creates a file completion event.
  TaskFileCompleted(
    this.file,
  );
}

/// Emitted after the task state file is flushed/updated.
class StateFileUpdated implements DownloadFileManagerEvent, TaskEvent {}

/// Emitted when every file in the task is complete.
class AllComplete implements TaskEvent {}
