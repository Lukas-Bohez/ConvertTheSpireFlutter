import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:provider/provider.dart';

import '../services/ad_service.dart';
import '../services/purchase_service.dart';

/// Small reusable banner placement that hides itself when ads are removed.
class AdBannerSlot extends StatefulWidget {
  const AdBannerSlot({super.key});

  @override
  State<AdBannerSlot> createState() => _AdBannerSlotState();
}

class _AdBannerSlotState extends State<AdBannerSlot> {
  Future<BannerAd?>? _bannerFuture;
  BannerAd? _bannerAd;

  @override
  void initState() {
    super.initState();
    if (AdService.instance.adsAvailable) {
      _bannerFuture = AdService.instance.loadBanner();
    }
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAdFree = context.watch<PurchaseService>().isAdFree;
    if (isAdFree || !AdService.instance.adsAvailable) {
      if (_bannerAd != null) {
        final banner = _bannerAd;
        _bannerAd = null;
        unawaited(banner!.dispose());
      }
      return const SizedBox.shrink();
    }

    _bannerFuture ??= AdService.instance.loadBanner();
    return FutureBuilder<BannerAd?>(
      future: _bannerFuture,
      builder: (context, snapshot) {
        final ad = snapshot.data;
        if (ad != null) {
          _bannerAd = ad;
          return Center(
            child: SizedBox(
              width: ad.size.width.toDouble(),
              height: ad.size.height.toDouble(),
              child: AdWidget(ad: ad),
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 60,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        return const SizedBox.shrink();
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

    _nativeFuture ??= AdService.instance.loadNativeAd();
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
