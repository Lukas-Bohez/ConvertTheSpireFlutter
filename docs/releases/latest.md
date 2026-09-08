# Release Notes - v13.0.14

## Player / empty-state UI fixes

## Fixes

* **Torrents empty state — Add Magnet is now `OutlinedButton.icon`** matching its three siblings (was the emphasized `FilledButton.icon`), and all four empty-state action buttons plus "Go to Settings" now use 18 px icons so they sit cleanly inside the 40-tall unified button theme with no height clamp / glitch.
* **Player — first row / scrollbar hidden behind the pinned TabBar + search bar.** The `NestedScrollView` pinned headers overlapped the grid body, so the first media row and the scrollbar's top drew behind them (the classic overlap gotcha). Added the canonical `SliverOverlapAbsorber` / `SliverOverlapInjector` pair and consolidated the TabBar + search bar into a single pinned sliver, so the grid (and its scrollbar) now render below the pinned header instead of behind it.
* **Player — Share button crowding the now-playing row on phones.** The inline Share `IconButton` is now hidden on phones (`width < 600`); Share is instead the first action in the existing 3-dot track menu, freeing the tight thumbnail / title / favourite / dislike / overflow row and removing the overlap glitch. Tablet / desktop keep the inline Share button.
* **Player empty tabs** (empty library / no search results) now also align below the pinned header via the same overlap-injector scroll view.

## Build Notes

* GitHub release tag: v13.0.14
* Release page: [v13.0.14](https://github.com/Lukas-Bohez/ConvertTheSpireFlutter/releases/tag/v13.0.14)
* flutter analyze passes cleanly; all 30 tests pass; Windows release and Play AAB (flavor `play`, `com.torrentspire.ai`, v13.0.14+1277) built locally and verified.
