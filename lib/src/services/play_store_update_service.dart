import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart';

import '../config/build_flags.dart';

class PlayStoreUpdateService {
  static Future<void> checkForUpdate() async {
    if (!kPlayStoreBuild || !Platform.isAndroid) return;

    try {
      final updateInfo = await InAppUpdate.checkForUpdate();
      if (updateInfo.updateAvailability != UpdateAvailability.updateAvailable) {
        return;
      }

      if (updateInfo.immediateUpdateAllowed) {
        await InAppUpdate.performImmediateUpdate();
        return;
      }

      if (updateInfo.flexibleUpdateAllowed) {
        await InAppUpdate.startFlexibleUpdate();
        await InAppUpdate.completeFlexibleUpdate();
      }
    } catch (e) {
      debugPrint('PlayStoreUpdateService.checkForUpdate failed: $e');
    }
  }
}
