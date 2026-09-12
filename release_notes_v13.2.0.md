## Highlights

- **Fixed:** downloads could start failing repeatedly on lower-end hardware
  after a large number of songs had already been downloaded. The download
  queue was being fully rewritten to disk on every progress update of the
  song currently downloading, including every previously-completed song -
  it's now only written when a download's status actually changes.
- **Fixed:** the automatic cooldown after a burst of download errors
  wasn't actually being honored by every retry path, so a failing download
  could keep retrying every few seconds instead of actually backing off.
- **New:** the playlist Extras tab now tells you what it actually found,
  not just a flat list. It separates leftover incomplete-download files,
  files in the wrong format for their folder, and files that just aren't
  in this playlist - each with a one-tap fix and a "resolve all" option
  for the whole category.

## Known issues

- Now-playing artwork may appear stretched rather than cropped in some
  views - under investigation.
- The low-end download fix (queue persistence no longer rewrites on every
  progress tick) is code-verified and analyze/test-clean, but the live
  confirmation on the affected low-end hardware is still pending - that
  machine is not available from this session. The fix is in `_updateQueue`
  (only persists on status change, not progress ticks) and `_saveQueue`
  (logs `[_saveQueue] persisted N items in Xms` for live verification).
  Until that machine confirms it, treat this fix as code-reviewed but
  not field-confirmed.
