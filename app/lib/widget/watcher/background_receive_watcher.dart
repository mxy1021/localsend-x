import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/provider/network/server/server_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_isolates/util/transfer_notification.dart';
import 'package:logging/logging.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Android keeps the existing receiver alive while Quick Save is enabled.
/// Battery optimization exemption is still required for network access during Doze.
class BackgroundReceiveWatcher extends StatefulWidget {
  final Widget child;

  const BackgroundReceiveWatcher({required this.child, super.key});

  @override
  State<BackgroundReceiveWatcher> createState() => _BackgroundReceiveWatcherState();
}

class _BackgroundReceiveWatcherState extends State<BackgroundReceiveWatcher> with WidgetsBindingObserver {
  static const _channel = MethodChannel('org.localsend.localsend_app/localsend');
  static final _logger = Logger('BackgroundReceive');
  ({bool enabled, String title, String text})? _last;
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  Widget build(BuildContext context) {
    if (checkPlatform([TargetPlatform.android])) {
      context.watch(settingsProvider.select((s) => (s.quickSave, s.quickSaveFromFavorites, s.alias)));
      context.watch(serverProvider.select((s) => s != null));
      _scheduleSync();
    }
    return widget.child;
  }

  void _scheduleSync() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) _sync();
    });
  }

  void _sync() {
    if (!checkPlatform([TargetPlatform.android])) return;
    final settings = context.ref.read(settingsProvider);
    final enabled = (settings.quickSave || settings.quickSaveFromFavorites) && context.ref.read(serverProvider) != null;
    final next = (
      enabled: enabled,
      title: 'LocalSend-x · ${t.receiveTab.title}',
      text: '${settings.quickSaveFromFavorites ? t.general.quickSaveFromFavorites : t.general.quickSave} · ${settings.alias}',
    );
    if (_last == next) return;
    // New foreground services must start while the activity is visible. Disabling is always allowed.
    if (enabled && WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) return;
    _last = next;
    TransferNotification.setBackgroundReceiving(enabled: enabled, title: next.title, text: next.text);
    unawaited(_setMulticast(enabled));
  }

  Future<void> _setMulticast(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setBackgroundReceiving', {'enabled': enabled});
    } catch (e, st) {
      _logger.warning('Could not update the background multicast lock', e, st);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _last = null;
      _sync();
    } else if (state == AppLifecycleState.detached) {
      _stop();
    }
  }

  void _stop() {
    if (!checkPlatform([TargetPlatform.android])) return;
    TransferNotification.setBackgroundReceiving(enabled: false, title: '', text: '');
    unawaited(_setMulticast(false));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stop();
    super.dispose();
  }
}
