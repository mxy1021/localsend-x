import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_foreground_task/flutter_foreground_task_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_isolates/util/foreground_service.dart';
import 'package:localsend_isolates/util/notification_strings.dart';
import 'package:localsend_isolates/util/transfer_notification.dart';

Future<void> drainQueue() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void background(bool enabled) => TransferNotification.setBackgroundReceiving(enabled: enabled, title: 'Ready', text: 'Device');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _ForegroundPlatform platform;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    platform = _ForegroundPlatform();
    FlutterForegroundTaskPlatform.instance = platform;
    FlutterForegroundTask.skipServiceResponseCheck = true;
    TransferNotification.init(
      NotificationStrings(
        titleReceiving: 'Receiving',
        titleSending: 'Sending',
        remainingTimeMinutes: ({required m, required ss}) => '$m:$ss',
        remainingTimeLong: ({required h, required m}) => '$h:$m',
      ),
    );
  });

  tearDown(() async {
    TransferNotification.stop('receive');
    TransferNotification.stop('send');
    background(false);
    await drainQueue();
    debugDefaultTargetPlatformOverride = null;
  });

  test('idle receiver survives repeated transfers without stopping its service', () async {
    background(true);
    await drainQueue();
    expect(platform.running, true);
    expect(platform.types, [ForegroundServiceTypes.connectedDevice]);
    expect(platform.options?.allowWakeLock, true);
    expect(platform.options?.allowWifiLock, true);
    expect(platform.options?.stopWithTask, isNull);
    expect(platform.options?.autoRunOnBoot, false);

    for (var i = 0; i < 2; i++) {
      TransferNotification.start(sessionId: 'receive', receiving: true);
      await drainQueue();
      expect(platform.title, 'Receiving');
      TransferNotification.stop('receive');
      await drainQueue();
      expect(platform.title, 'Ready');
      expect(platform.stops, 0);
    }
    background(false);
    await drainQueue();
    expect(platform.running, false);
    expect(platform.stops, 1);
  });

  test('disabling idle receiving preserves concurrent transfers until both finish', () async {
    background(true);
    TransferNotification.start(sessionId: 'receive', receiving: true);
    TransferNotification.start(sessionId: 'send', receiving: false);
    background(false);
    await drainQueue();
    expect(platform.running, true);
    TransferNotification.stop('receive');
    await drainQueue();
    expect(platform.running, true);
    expect(platform.title, 'Sending');
    TransferNotification.stop('send');
    await drainQueue();
    expect(platform.running, false);
  });

  test('disabling while a service start is pending still stops after it starts', () async {
    platform.startGate = Completer<void>();
    background(true);
    await drainQueue();
    background(false);
    platform.startGate!.complete();
    await drainQueue();
    expect(platform.running, false);
    expect(platform.stops, 1);
  });

  test('retry after a failed start and after the native service disappears', () async {
    platform.failStart = true;
    background(true);
    await drainQueue();
    expect(ForegroundService.isRunning, false);
    platform.failStart = false;
    background(true);
    await drainQueue();
    expect(platform.running, true);
    platform.running = false;
    background(true);
    await drainQueue();
    expect(platform.running, true);
    expect(platform.starts, 3);
  });

  test('desktop does not start an Android service', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    background(true);
    await drainQueue();
    expect(platform.starts, 0);
  });
}

class _ForegroundPlatform extends FlutterForegroundTaskPlatform {
  bool running = false;
  bool failStart = false;
  int starts = 0;
  int stops = 0;
  String? title;
  List<ForegroundServiceTypes>? types;
  ForegroundTaskOptions? options;
  Completer<void>? startGate;

  @override
  Future<bool> get isRunningService async => running;

  @override
  Future<NotificationPermission> checkNotificationPermission() async => NotificationPermission.granted;

  @override
  Future<void> startService({
    required AndroidNotificationOptions androidNotificationOptions,
    required IOSNotificationOptions iosNotificationOptions,
    required ForegroundTaskOptions foregroundTaskOptions,
    int? serviceId,
    List<ForegroundServiceTypes>? serviceTypes,
    required String notificationTitle,
    required String notificationText,
    NotificationIcon? notificationIcon,
    List<NotificationButton>? notificationButtons,
    String? notificationInitialRoute,
    Function? callback,
  }) async {
    starts++;
    if (failStart) throw StateError('Service start rejected');
    if (startGate != null) await startGate!.future;
    types = serviceTypes;
    options = foregroundTaskOptions;
    title = notificationTitle;
    running = true;
  }

  @override
  Future<void> updateService({
    ForegroundTaskOptions? foregroundTaskOptions,
    String? notificationTitle,
    String? notificationText,
    NotificationIcon? notificationIcon,
    List<NotificationButton>? notificationButtons,
    String? notificationInitialRoute,
    Function? callback,
  }) async {
    title = notificationTitle;
  }

  @override
  Future<void> stopService() async {
    stops++;
    running = false;
  }
}
