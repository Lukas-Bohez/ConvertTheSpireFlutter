# Store listing in 18 languages

The Microsoft Store listing for every language the app speaks. The package
declares all 18 (`msix_config: languages` in `pubspec.yaml`), so Partner
Center shows a Store listing for each one under the submission's **Store
listings**.

The texts are in [`listings.json`](listings.json); the pages below are made
from it by `python scripts/store_listing.py pages`. To change a text, edit
`listings.json` and run that again.

## Filling them in

**All at once (CSV):** in the submission, **Store listings** →
**Import/export Store listings** → **Export listings**. Then, on Windows,

    scripts\make_store_upload.cmd -ListingsOnly -ListingCsv <the exported .csv>

writes the folder `microsoft-upload\store-import\`: the export filled with
the short description, description, what's new, features, search terms,
copyright and licence terms of every language, plus the screenshots and the
app tile, which go in the `default` column so every language uses them. Back
in Partner Center, **Import listings** → **Import folder** and pick that
folder. (`python scripts/store_listing.py fill` fills only the texts.)

**By hand:** open a language below and copy each box into the field of the
same name.

| Language | Code |
|---|---|
| [English](en-us.md) | `en-us` |
| [العربية](ar.md) | `ar` |
| [Deutsch](de.md) | `de` |
| [Español](es.md) | `es` |
| [Français](fr.md) | `fr` |
| [हिन्दी](hi.md) | `hi` |
| [Bahasa Indonesia](id.md) | `id` |
| [Italiano](it.md) | `it` |
| [日本語](ja.md) | `ja` |
| [한국어](ko.md) | `ko` |
| [Nederlands](nl.md) | `nl` |
| [Polski](pl.md) | `pl` |
| [Português (Brasil)](pt-br.md) | `pt-br` |
| [Русский](ru.md) | `ru` |
| [Türkçe](tr.md) | `tr` |
| [Українська](uk.md) | `uk` |
| [Tiếng Việt](vi.md) | `vi` |
| [简体中文](zh-cn.md) | `zh-cn` |
