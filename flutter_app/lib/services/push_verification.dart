// push_verification.dart is called from DClixApp.initState in main.dart.
// Debug-only OneSignal verification; safe to keep in the project.
// onesignal:managed v1
import 'package:flutter/foundation.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

import 'push_notification_service.dart';

class PushVerification {
  static bool _installed = false;
  static bool _logged = false;

  static Future<void> install() async {
    if (!kDebugMode || _installed || !PushNotificationService.isAvailable) return;
    _installed = true;

    void check(String? id) {
      if (_logged || !PushNotificationService.isServerSubscriptionId(id)) return;
      _logged = true;
      debugPrint('[OneSignal] Push subscription registered: $id');
    }

    OneSignal.User.pushSubscription.addObserver((state) {
      check(state.current.id);
      debugPrint('[OneSignal] Push opted in: ${state.current.optedIn}');
    });
    check(OneSignal.User.pushSubscription.id);
    // Only debug builds request permission here. Members are asked after sign-in.
    try {
      await PushNotificationService.requestPermission();
    } catch (e) {
      debugPrint('[OneSignal] Verification permission failed: ${e.runtimeType}');
    }
  }
}
