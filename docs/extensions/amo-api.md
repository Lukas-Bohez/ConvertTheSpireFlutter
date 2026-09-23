# addons.mozilla.org API: what the app uses

The AMO v5 API is not frozen (issue #10), so every endpoint and field the app
reads is listed here with what a live response looked like. Checked against
live responses on 2026-09-23. Client: `lib/src/browser/extensions/amo_catalog.dart`.
Recorded responses, trimmed to these fields, are the test fixtures in
`test/fixtures/amo/`.

Base URL: `https://addons.mozilla.org/api/v5`

## Search

    GET /addons/search/?type=extension&app=firefox&lang=en-US&page=1&page_size=20&q=<query>

- `app=android` limits results to add-ons whose current version declares
  Firefox for Android, and returns Android download URLs.
- With no `q`, the app sends `sort=users` to show the most used extensions.

Top level: `count`, `next` (a URL or null), `previous`, `page_size`,
`page_count`, `results`.

## Details

    GET /addons/addon/<guid-or-slug>/?lang=en-US&app=firefox

The same object as one search result. An unknown add-on returns 404 with
`{"detail":"Not found."}`.

## Fields read from an add-on

| Field | Used for | Example |
|---|---|---|
| `guid` | identity, updates, "Installed" badge | `addon@darkreader.org` |
| `slug` | the AMO page link | `darkreader` |
| `name` | title | `{"en-US": "Dark Reader"}` |
| `summary` | description line | locale map, as `name` |
| `icon_url` | icon | `https://addons.mozilla.org/user-media/addon_icons/855/855413-64.png?...` |
| `average_daily_users` | "N users" | `1324137` |
| `ratings.average` | kept for sorting | `4.48` |
| `promoted[].category` | "Recommended" badge when `recommended` | `[{"category": "recommended", "apps": ["firefox", "android"]}]` |
| `url` | the add-on's AMO page | |
| `current_version.version` | version, update check | `4.9.131` |
| `current_version.compatibility` | Android support: the `android` key is present | `{"firefox": {"min": "78.0", "max": "*"}, "android": {"min": "113.0", "max": "*"}}` |
| `current_version.file.url` | the signed .xpi | `https://addons.mozilla.org/firefox/downloads/file/5029993/darkreader-4.9.131.xpi` |
| `current_version.file.hash` | download verification | `sha256:<64 hex>` |
| `current_version.file.size` | | `842484` |
| `current_version.file.permissions` | the permission prompt | `["storage"]` |
| `current_version.file.host_permissions` | the permission prompt | `[]` |

## Translated fields

Translated fields are **always** a locale map, even with `lang` set, and the
requested locale can be `null`. For an add-on whose default locale is Dutch:

    "name": {"nl": "Lofi Player", "en-US": null, "_default": "nl"}

The client reads the requested locale, then its base language, then the
locale named by `_default`, then any non-empty value.

## Errors the client maps to sentences

| Status | Message |
|---|---|
| 404 | That extension is not on addons.mozilla.org. |
| 429 | addons.mozilla.org is rate limiting requests. Try again in a minute. |
| other non-200 | addons.mozilla.org returned an error (NNN). |
| timeout (15 s) or no connection | Could not reach addons.mozilla.org. Check your connection. |
| unparseable body | addons.mozilla.org sent a response the app could not read. |

Responses are cached in memory for 10 minutes.
