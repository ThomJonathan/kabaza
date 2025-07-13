  // lib/app_lifecycle_observer.dart
  import 'package:flutter/widgets.dart';
  import 'package:supabase_flutter/supabase_flutter.dart';
  import 'service.dart';

    class AppLifecycleObserver with WidgetsBindingObserver {
    final UserActivityService _userActivityService;
    bool _isLoggedIn = false;

    AppLifecycleObserver(this._userActivityService);

    void initialize() {
      WidgetsBinding.instance.addObserver(this);
    }

    void dispose() {
      WidgetsBinding.instance.removeObserver(this);
    }

    void setLoggedIn(bool loggedIn) {
      _isLoggedIn = loggedIn;
    }

    @override
    void didChangeAppLifecycleState(AppLifecycleState state) async {
      if (!_isLoggedIn) return;

      switch (state) {
        case AppLifecycleState.resumed:
        // App came to foreground
          await _userActivityService.setUserActive();
          break;
        case AppLifecycleState.paused:
        case AppLifecycleState.detached:
        case AppLifecycleState.inactive:
        // App went to background or closed
          await _userActivityService.setUserInactive();
          break;
        case AppLifecycleState.hidden:
        // New in Flutter 3.x - app is still running but not visible
          await _userActivityService.setUserInactive();
          break;
      }
    }
  }