import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:provider/provider.dart';

import '../services/ad_service.dart';
import '../services/purchase_service.dart';

/// An anchored adaptive banner as wide as the space it is given.
///
/// It takes no room until an ad has loaded, so there is no spinner or empty
/// box, and it appears by itself once ads are ready (after the consent check
/// at startup) and goes away during an ad break or after the ad-free
/// purchase. A failed load is retried after a minute; a new width (the phone
/// was turned) loads a banner that fits.
class AdBannerSlot extends StatefulWidget {
  const AdBannerSlot({super.key});

  @override
  State<AdBannerSlot> createState() => _AdBannerSlotState();
}

class _AdBannerSlotState extends State<AdBannerSlot> {
  static const Duration _retryAfter = Duration(minutes: 1);

  BannerAd? _ad;
  int? _requestedWidth;
  Timer? _retry;

  @override
  void initState() {
    super.initState();
    AdService.instance.addListener(_onAdsChanged);
  }

  @override
  void dispose() {
    AdService.instance.removeListener(_onAdsChanged);
    _retry?.cancel();
    _ad?.dispose();
    super.dispose();
  }

  void _onAdsChanged() {
    if (!mounted) return;
    if (!AdService.instance.adsReady) _drop();
    setState(() {});
  }

  void _drop() {
    _retry?.cancel();
    _requestedWidth = null;
    final ad = _ad;
    _ad = null;
    // Dispose after the frame that removes its AdWidget.
    if (ad != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => ad.dispose());
    }
  }

  Future<void> _load(int width) async {
    _requestedWidth = width;
    final ad = await AdService.instance.loadBanner(width: width);
    if (!mounted || _requestedWidth != width) {
      if (ad != null) unawaited(ad.dispose());
      return;
    }
    if (ad == null) {
      _retry?.cancel();
      _retry = Timer(_retryAfter, () {
        if (!mounted) return;
        setState(() => _requestedWidth = null);
      });
      return;
    }
    final old = _ad;
    setState(() => _ad = ad);
    if (old != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdFree = context.watch<PurchaseService>().isAdFree;
    if (isAdFree || !AdService.instance.adsReady) {
      if (_ad != null || _requestedWidth != null) _drop();
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : MediaQuery.sizeOf(context).width)
            .truncate();
        if (_requestedWidth != width) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _requestedWidth != width) unawaited(_load(width));
          });
        }
        final ad = _ad;
        if (ad == null) return const SizedBox.shrink();
        return Center(
          child: SizedBox(
            width: ad.size.width.toDouble(),
            height: ad.size.height.toDouble(),
            child: AdWidget(key: ObjectKey(ad), ad: ad),
          ),
        );
      },
    );
  }
}

/// Reusable native ad slot that uses the built-in template renderer.
class AdNativeSlot extends StatefulWidget {
  const AdNativeSlot({super.key});

  @override
  State<AdNativeSlot> createState() => _AdNativeSlotState();
}

class _AdNativeSlotState extends State<AdNativeSlot> {
  Future<NativeAd?>? _nativeFuture;
  NativeAd? _nativeAd;

  @override
  void initState() {
    super.initState();
    if (AdService.instance.adsAvailable) {
      _nativeFuture = AdService.instance.loadNativeAd();
    }
  }

  @override
  void dispose() {
    _nativeAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAdFree = context.watch<PurchaseService>().isAdFree;
    if (isAdFree || !AdService.instance.adsAvailable) {
      if (_nativeAd != null) {
        final nativeAd = _nativeAd;
        _nativeAd = null;
        unawaited(nativeAd!.dispose());
      }
      return const SizedBox.shrink();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    _nativeFuture ??= AdService.instance.loadNativeAd(isDark: isDark);
    return FutureBuilder<NativeAd?>(
      future: _nativeFuture,
      builder: (context, snapshot) {
        final ad = snapshot.data;
        if (ad != null) {
          _nativeAd = ad;
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 6),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              height: 320,
              child: AdWidget(ad: ad),
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}
