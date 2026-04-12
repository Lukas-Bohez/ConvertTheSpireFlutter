const bool kPlayStoreBuild = bool.fromEnvironment(
  'PLAY_STORE_BUILD',
  defaultValue: false,
);

const bool kYouTubeConversionEnabled = bool.fromEnvironment(
  'ENABLE_YOUTUBE_CONVERSION',
  defaultValue: !kPlayStoreBuild,
);
