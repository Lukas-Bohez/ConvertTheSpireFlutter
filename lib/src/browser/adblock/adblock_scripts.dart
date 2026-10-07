import 'dart:convert';

import 'filter_list.dart';

/// The scripts the ad blocker runs in pages.
///
/// Like uBlock Origin, elements are hidden with a style sheet of the filter
/// lists' selectors rather than removed, so a page's own scripts don't
/// break on a missing element. The sheet is a constructed one, adopted by
/// the document: it needs no element in the page and is in place before
/// the page's own scripts run.

/// Runs in every page before the page's own scripts: hides the elements of
/// the generic rules and defines `window.__ctsHide`, which the per-site
/// script ([siteHideScriptFor]) uses. With [skipYouTubeAds], an ad that plays
/// on YouTube anyway is skipped: run to its end, Skip pressed.
String documentStartScript(FilterSet filters, {required bool skipYouTubeAds}) {
  final data = jsonEncode({
    'generic': filters.genericHide,
    'except': filters.hideExceptions,
    'off': [...filters.allowedPages, ...filters.noHide],
    'offGeneric': filters.noGenericHide.toList(),
  });
  return '''
(function () {
  if (window.__ctsAdblock) return;
  window.__ctsAdblock = true;
  var host = location.hostname.toLowerCase();
  function on(d) {
    if (d.slice(-2) === '.*') {
      var b = d.slice(0, -1);
      return host.indexOf(b) === 0 || host.indexOf('.' + b) >= 0;
    }
    return host === d || host.slice(-d.length - 1) === '.' + d;
  }
  function onAny(list) {
    for (var i = 0; i < list.length; i++) if (on(list[i])) return true;
    return false;
  }
  function hide(selectors) {
    if (!selectors.length) return;
    try {
      var sheet = new CSSStyleSheet();
      // One rule per selector: one the browser can't parse drops only itself.
      sheet.replaceSync(selectors.map(function (s) {
        return s + '{display:none!important}';
      }).join('\\n'));
      var adopt = function () {
        try {
          var list = document.adoptedStyleSheets;
          if (list.indexOf(sheet) < 0) {
            document.adoptedStyleSheets = list.concat([sheet]);
          }
        } catch (e) {}
      };
      adopt();
      // A page that sets its own adopted sheets replaces the list.
      document.addEventListener('DOMContentLoaded', adopt);
      window.addEventListener('load', adopt);
    } catch (e) {}
  }
  var F = $data;
  var off = onAny(F.off);
  window.__ctsHide = function (selectors) { if (!off) hide(selectors); };
  if (!off && !onAny(F.offGeneric)) {
    var skip = {};
    for (var d in F.except) {
      if (on(d)) F.except[d].forEach(function (s) { skip[s] = 1; });
    }
    hide(F.generic.filter(function (s) { return !skip[s]; }));
  }
${skipYouTubeAds ? _youTubeSkip : ''}
})();
''';
}

const _youTubeSkip = r'''
  if (on('youtube.com') && !window.__ctsYouTube) {
    window.__ctsYouTube = true;
    setInterval(function () {
      var player = document.querySelector('.html5-video-player.ad-showing');
      if (!player) return;
      var video = player.querySelector('video');
      if (video && isFinite(video.duration) && video.currentTime < video.duration) {
        video.currentTime = video.duration;
      }
      var button = document.querySelector(
          '.ytp-ad-skip-button, .ytp-ad-skip-button-modern, .ytp-skip-ad-button');
      if (button) button.click();
    }, 250);
  }
''';

/// Hides the elements the filter lists name for [url]'s site, once per
/// page. Null when they name none.
String? siteHideScriptFor(FilterSet filters, String url) {
  final host = FilterSet.splitUrl(url)?.$1;
  if (host == null) return null;
  final selectors = filters.selectorsFor(host);
  if (selectors.isEmpty) return null;
  return '''
(function () {
  if (window.__ctsSiteHidden || !window.__ctsHide) return;
  window.__ctsSiteHidden = true;
  window.__ctsHide(${jsonEncode(selectors)});
})();
''';
}
