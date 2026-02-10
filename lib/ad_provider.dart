import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdProvider {
  // Test IDs (Verified for development)
  static const String bannerId = 'ca-app-pub-3940256099942544/6300978111';
  static const String interstitialId = 'ca-app-pub-3940256099942544/1033173712';
  static const String appOpenId = 'ca-app-pub-3940256099942544/9257395915';

  /* REAL IDs (Swap back for production):
  static const String bannerId = 'ca-app-pub-8717873369685826/8912091116';
  static const String interstitialId = 'ca-app-pub-8717873369685826/6693121881';
  static const String appOpenId = 'ca-app-pub-8717873369685826/8932272419';
  */

  static InterstitialAd? _interstitialAd;
  static bool _isInterstitialLoading = false;

  static Future<void> init() async {
    await MobileAds.instance.initialize();
    
    /* 
    // OPTIONAL: Register your physical device as a test device to avoid "No Fill" (Code 3)
    // You can find your device ID in the logcat: "Ads: Use RequestConfiguration.Builder().setTestDeviceIds(Arrays.asList("HASH_ID"))"
    await MobileAds.instance.updateRequestConfiguration(
      RequestConfiguration(testDeviceIds: ['YOUR_DEVICE_HASH_ID']),
    );
    */
  }

  static void loadInterstitial() {
    if (_isInterstitialLoading || _interstitialAd != null) return;
    _isInterstitialLoading = true;

    InterstitialAd.load(
      adUnitId: interstitialId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _isInterstitialLoading = false;
        },
        onAdFailedToLoad: (error) {
          debugPrint('InterstitialAd failed to load: $error');
          _isInterstitialLoading = false;
          _interstitialAd = null;
        },
      ),
    );
  }

  static Future<void> showInterstitial() async {
    if (_interstitialAd == null) {
      loadInterstitial();
      return;
    }
    _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _interstitialAd = null;
        loadInterstitial();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _interstitialAd = null;
        loadInterstitial();
      },
    );
    await _interstitialAd!.show();
  }

  static AppOpenAd? _appOpenAd;
  static bool _isAppOpenLoading = false;

  static void loadAppOpen() {
    if (_isAppOpenLoading || _appOpenAd != null) return;
    _isAppOpenLoading = true;

    AppOpenAd.load(
      adUnitId: appOpenId,
      request: const AdRequest(),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) {
          _appOpenAd = ad;
          _isAppOpenLoading = false;
        },
        onAdFailedToLoad: (error) {
          debugPrint('AppOpenAd failed to load: $error');
          _isAppOpenLoading = false;
          _appOpenAd = null;
        },
      ),
    );
  }

  static bool get isAppOpenAdAvailable => _appOpenAd != null;

  static Future<void> showAppOpen() async {
    if (_appOpenAd == null) {
      loadAppOpen();
      return;
    }
    final completer = Completer<void>();
    _appOpenAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _appOpenAd = null;
        loadAppOpen();
        if (!completer.isCompleted) completer.complete();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _appOpenAd = null;
        loadAppOpen();
        if (!completer.isCompleted) completer.complete();
      },
    );
    await _appOpenAd!.show();
    return completer.future;
  }
}

class BannerAdWidget extends StatefulWidget {
  final AdSize size;
  
  const BannerAdWidget({
    super.key, 
    this.size = AdSize.banner,
  });

  @override
  State<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<BannerAdWidget> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadAd();
  }

  void _loadAd() {
    _bannerAd = BannerAd(
      adUnitId: AdProvider.bannerId,
      request: const AdRequest(),
      size: widget.size,
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          setState(() {
            _isLoaded = true;
          });
        },
        onAdFailedToLoad: (ad, err) {
          debugPrint('BannerAd failed to load: $err');
          ad.dispose();
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoaded && _bannerAd != null) {
      return Container(
        alignment: Alignment.center,
        width: _bannerAd!.size.width.toDouble(),
        height: _bannerAd!.size.height.toDouble(),
        child: AdWidget(ad: _bannerAd!),
      );
    }
    return const SizedBox.shrink();
  }
}
