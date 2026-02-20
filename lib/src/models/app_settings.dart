class AppSettings {
  final String downloadDir;
  final int maxWorkers;
  final bool showNotifications;
  final int previewMaxEntries;
  final bool previewExpandPlaylist;
  final String? ffmpegPath;
  final bool autoInstallFfmpeg;
  final bool autoRetryInstall;
  final int retryBackoffSeconds;
  final int retryCount;
  final int convertMaxMb;
  final int convertCleanupMinutes;
  final int convertMaxAgeHours;

  final String themeMode;             // 'system', 'light', 'dark'

  // ── New feature settings ─────────────────────────────────────────────
  final String defaultAudioFormat;   // mp3, m4a
  final int defaultBitrate;          // kbps (0 = format default)
  final int minimumBitrate;          // quality gate; 0 = disabled
  final String namingTemplate;       // file organisation template
  final String? soundcloudClientId;  // optional SoundCloud API key

  const AppSettings({
    required this.downloadDir,
    required this.maxWorkers,
    required this.showNotifications,
    required this.previewMaxEntries,
    required this.previewExpandPlaylist,
    required this.ffmpegPath,
    required this.autoInstallFfmpeg,
    required this.autoRetryInstall,
    required this.retryBackoffSeconds,
    required this.retryCount,
    required this.convertMaxMb,
    required this.convertCleanupMinutes,
    required this.convertMaxAgeHours,
    this.themeMode = 'system',
    this.defaultAudioFormat = 'mp3',
    this.defaultBitrate = 0,
    this.minimumBitrate = 0,
    this.namingTemplate = '{artist}/{title}',
    this.soundcloudClientId,
  });

  factory AppSettings.defaults({required String downloadDir}) {
    return AppSettings(
      downloadDir: downloadDir,
      maxWorkers: 3,
      showNotifications: true,
      previewMaxEntries: 25,
      previewExpandPlaylist: false,
      ffmpegPath: null,
      autoInstallFfmpeg: true,
      autoRetryInstall: false,
      retryBackoffSeconds: 3,
      retryCount: 2,
      convertMaxMb: 0,
      convertCleanupMinutes: 15,
      convertMaxAgeHours: 2,
      themeMode: 'system',
      defaultAudioFormat: 'mp3',
      defaultBitrate: 0,
      minimumBitrate: 0,
      namingTemplate: '{artist}/{title}',
      soundcloudClientId: null,
    );
  }

  AppSettings copyWith({
    String? downloadDir,
    int? maxWorkers,
    bool? showNotifications,
    int? previewMaxEntries,
    bool? previewExpandPlaylist,
    String? ffmpegPath,
    bool? autoInstallFfmpeg,
    bool? autoRetryInstall,
    int? retryBackoffSeconds,
    int? retryCount,
    int? convertMaxMb,
    int? convertCleanupMinutes,
    int? convertMaxAgeHours,
    String? themeMode,
    String? defaultAudioFormat,
    int? defaultBitrate,
    int? minimumBitrate,
    String? namingTemplate,
    String? soundcloudClientId,
  }) {
    return AppSettings(
      downloadDir: downloadDir ?? this.downloadDir,
      maxWorkers: maxWorkers ?? this.maxWorkers,
      showNotifications: showNotifications ?? this.showNotifications,
      previewMaxEntries: previewMaxEntries ?? this.previewMaxEntries,
      previewExpandPlaylist: previewExpandPlaylist ?? this.previewExpandPlaylist,
      ffmpegPath: ffmpegPath ?? this.ffmpegPath,
      autoInstallFfmpeg: autoInstallFfmpeg ?? this.autoInstallFfmpeg,
      autoRetryInstall: autoRetryInstall ?? this.autoRetryInstall,
      retryBackoffSeconds: retryBackoffSeconds ?? this.retryBackoffSeconds,
      retryCount: retryCount ?? this.retryCount,
      convertMaxMb: convertMaxMb ?? this.convertMaxMb,
      convertCleanupMinutes: convertCleanupMinutes ?? this.convertCleanupMinutes,
      convertMaxAgeHours: convertMaxAgeHours ?? this.convertMaxAgeHours,
      themeMode: themeMode ?? this.themeMode,
      defaultAudioFormat: defaultAudioFormat ?? this.defaultAudioFormat,
      defaultBitrate: defaultBitrate ?? this.defaultBitrate,
      minimumBitrate: minimumBitrate ?? this.minimumBitrate,
      namingTemplate: namingTemplate ?? this.namingTemplate,
      soundcloudClientId: soundcloudClientId ?? this.soundcloudClientId,
    );
  }

  factory AppSettings.fromJson(Map<String, dynamic> json, {required String fallbackDownloadDir}) {
    return AppSettings(
      downloadDir: (json['download_dir'] as String?)?.trim().isNotEmpty == true
          ? json['download_dir'] as String
          : fallbackDownloadDir,
      maxWorkers: (json['max_workers'] as num?)?.toInt() ?? 3,
      showNotifications: json['show_notifications'] as bool? ?? true,
      previewMaxEntries: (json['preview_max_entries'] as num?)?.toInt() ?? 25,
      previewExpandPlaylist: json['preview_expand_playlist'] as bool? ?? false,
      ffmpegPath: (json['ffmpeg_path'] as String?)?.trim(),
      autoInstallFfmpeg: json['auto_install_ffmpeg'] as bool? ?? true,
      autoRetryInstall: json['auto_retry_install'] as bool? ?? false,
      retryBackoffSeconds: (json['retry_backoff'] as num?)?.toInt() ?? 3,
      retryCount: (json['retry_count'] as num?)?.toInt() ?? 2,
      convertMaxMb: (json['convert_max_mb'] as num?)?.toInt() ?? 0,
      convertCleanupMinutes: (json['convert_cleanup_minutes'] as num?)?.toInt() ?? 15,
      convertMaxAgeHours: (json['convert_max_age_hours'] as num?)?.toInt() ?? 2,
      themeMode: json['theme_mode'] as String? ?? 'system',
      defaultAudioFormat: json['default_audio_format'] as String? ?? 'mp3',
      defaultBitrate: (json['default_bitrate'] as num?)?.toInt() ?? 0,
      minimumBitrate: (json['minimum_bitrate'] as num?)?.toInt() ?? 0,
      namingTemplate: json['naming_template'] as String? ?? '{artist}/{title}',
      soundcloudClientId: json['soundcloud_client_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'download_dir': downloadDir,
      'max_workers': maxWorkers,
      'show_notifications': showNotifications,
      'preview_max_entries': previewMaxEntries,
      'preview_expand_playlist': previewExpandPlaylist,
      'ffmpeg_path': ffmpegPath,
      'auto_install_ffmpeg': autoInstallFfmpeg,
      'auto_retry_install': autoRetryInstall,
      'retry_backoff': retryBackoffSeconds,
      'retry_count': retryCount,
      'convert_max_mb': convertMaxMb,
      'convert_cleanup_minutes': convertCleanupMinutes,
      'convert_max_age_hours': convertMaxAgeHours,
      'theme_mode': themeMode,
      'default_audio_format': defaultAudioFormat,
      'default_bitrate': defaultBitrate,
      'minimum_bitrate': minimumBitrate,
      'naming_template': namingTemplate,
      'soundcloud_client_id': soundcloudClientId,
    };
  }
}
