/// Resolution of Android `intent:` URLs inside the browser.
///
/// Video results and share links on Android routinely navigate to
/// `intent://...;package=com.google.android.youtube;...`. The browser used to
/// hand every one of those straight to the system, which is why typing a
/// search and tapping a result "just opened YouTube" (issue #7).
///
/// Anything that can be expressed as a normal web page is turned back into one
/// and loaded in the webview. Whatever is left is offered to the user as a
/// choice, never launched behind their back.
library;

/// What the browser should do with an `intent:` URL.
class IntentUrlResolution {
  /// A web URL to load in the webview, or null when there is nothing to load.
  final String? webUrl;

  /// The Android package the intent targeted, if it named one.
  final String? package;

  const IntentUrlResolution({this.webUrl, this.package});

  /// True when the browser can handle this itself, with no external app.
  bool get canOpenInBrowser => webUrl != null && webUrl!.isNotEmpty;
}

/// Hosts that have a usable mobile web page, so the app is never needed.
const _youTubeHosts = {
  'youtube.com',
  'www.youtube.com',
  'm.youtube.com',
  'music.youtube.com',
  'youtu.be',
};

/// Turns an `intent:` URL into something the webview can load.
///
/// Returns a resolution whose [IntentUrlResolution.webUrl] is null when the
/// intent genuinely needs another app, in which case the caller should ask.
IntentUrlResolution resolveIntentUrl(String url) {
  if (!url.toLowerCase().startsWith('intent:')) {
    return const IntentUrlResolution();
  }

  final hashIndex = url.indexOf('#Intent;');
  final body = hashIndex == -1 ? url : url.substring(0, hashIndex);
  final params = hashIndex == -1
      ? const <String, String>{}
      : _parseIntentParams(url.substring(hashIndex + '#Intent;'.length));

  // An explicit fallback URL is the page the site wants non-app users to see.
  final fallback = params['S.browser_fallback_url'];
  if (fallback != null && fallback.isNotEmpty) {
    final decoded = _tryDecode(fallback);
    if (decoded.startsWith('http://') || decoded.startsWith('https://')) {
      return IntentUrlResolution(
        webUrl: _preferMobileWeb(decoded),
        package: params['package'],
      );
    }
  }

  // Otherwise rebuild the plain URL: intent://<rest>#Intent;scheme=https;...
  var rest = body.substring('intent:'.length);
  if (rest.startsWith('//')) rest = rest.substring(2);
  final scheme = params['scheme'] ?? 'https';
  if (rest.isNotEmpty && (scheme == 'http' || scheme == 'https')) {
    return IntentUrlResolution(
      webUrl: _preferMobileWeb('$scheme://$rest'),
      package: params['package'],
    );
  }

  return IntentUrlResolution(package: params['package']);
}

/// Rewrites YouTube links to the mobile site, which plays in the webview.
String _preferMobileWeb(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return url;
  final host = uri.host.toLowerCase();
  if (!_youTubeHosts.contains(host)) return url;

  if (host == 'youtu.be') {
    final id = uri.pathSegments.isEmpty ? '' : uri.pathSegments.first;
    if (id.isEmpty) return 'https://m.youtube.com/';
    return 'https://m.youtube.com/watch?v=$id';
  }
  if (host == 'music.youtube.com') return url;
  return uri.replace(scheme: 'https', host: 'm.youtube.com').toString();
}

Map<String, String> _parseIntentParams(String fragment) {
  final params = <String, String>{};
  for (final part in fragment.split(';')) {
    if (part.isEmpty || part == 'end') continue;
    final eq = part.indexOf('=');
    if (eq <= 0) continue;
    params[part.substring(0, eq)] = part.substring(eq + 1);
  }
  return params;
}

String _tryDecode(String value) {
  try {
    return Uri.decodeFull(value);
  } on ArgumentError {
    return value;
  } on FormatException {
    return value;
  }
}
