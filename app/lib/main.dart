import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:localsend_app/config/init.dart';
import 'package:localsend_app/config/init_error.dart';
import 'package:localsend_app/config/theme.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/persistence/color_mode.dart';
import 'package:localsend_app/pages/home_page.dart';
import 'package:localsend_app/provider/app_arguments_provider.dart';
import 'package:localsend_app/provider/local_ip_provider.dart';
import 'package:localsend_app/provider/network/nearby_devices_provider.dart';
import 'package:localsend_app/provider/network/server/server_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/util/ui/dynamic_colors.dart';
import 'package:localsend_app/widget/watcher/background_receive_watcher.dart';
import 'package:localsend_app/widget/watcher/life_cycle_watcher.dart';
import 'package:localsend_app/widget/watcher/shortcut_watcher.dart';
import 'package:localsend_app/widget/watcher/tray_watcher.dart';
import 'package:localsend_app/widget/watcher/window_brightness_watcher.dart';
import 'package:localsend_app/widget/watcher/window_watcher.dart';
import 'package:localsend_isolates/isolate.dart';
import 'package:localsend_isolates/util/foreground_service.dart';
import 'package:localsend_isolates/util/transfer_notification.dart';
import 'package:logging/logging.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';
import 'package:system_date_time_format/system_date_time_format.dart';

Future<void> main(List<String> args) async {
  final bootStart = args.contains('--android-boot') && checkPlatform([TargetPlatform.android]);
  const bootChannel = MethodChannel('org.localsend.localsend_app/boot');
  final showBootUi = Completer<void>();
  if (bootStart) {
    WidgetsFlutterBinding.ensureInitialized();
    bootChannel.setMethodCallHandler((call) async {
      if (call.method == 'show' && !showBootUi.isCompleted) showBootUi.complete();
    });
  }
  final RefenaContainer container;
  try {
    container = await preInit(args);
    if (bootStart) {
      final settings = container.read(settingsProvider);
      if (!settings.quickSave && !settings.quickSaveFromFavorites) {
        container.redux(parentIsolateProvider).dispatch(IsolateDisposeAction());
        await bootChannel.invokeMethod<void>('ready', {'success': false});
        return;
      }
      await container.notifier(serverProvider).startServerFromSettings();
      // The discovery listener runs until the receiving engine is destroyed.
      // ignore: unawaited_futures
      container.redux(nearbyDevicesProvider).dispatchAsync(StartDiscoveryListener());
      TransferNotification.setBackgroundReceiving(
        enabled: true,
        title: 'LocalSend-x · ${t.receiveTab.title}',
        text: '${settings.quickSaveFromFavorites ? t.general.quickSaveFromFavorites : t.general.quickSave} · ${settings.alias}',
      );
      await const MethodChannel('org.localsend.localsend_app/localsend').invokeMethod<void>('setBackgroundReceiving', {'enabled': true});
      final ready = await ForegroundService.waitUntilReady();
      if (!ready) throw StateError('Could not start receiving foreground service');
      await bootChannel.invokeMethod<void>('ready', {'success': true});
      // Build the normal UI only when the user actually opens the Activity.
      if (await bootChannel.invokeMethod<bool>('hasActivity') != true) await showBootUi.future;
    }
  } catch (e, stackTrace) {
    if (bootStart) {
      Logger('AndroidBoot').severe('Could not initialize receiving after unlock', e, stackTrace);
      await bootChannel.invokeMethod<void>('ready', {'success': false});
      return;
    }
    showInitErrorApp(
      error: e,
      stackTrace: stackTrace,
    );
    return;
  }

  runApp(
    RefenaScope.withContainer(
      container: container,
      child: SDTFScope(
        child: TranslationProvider(
          child: const LocalSendApp(),
        ),
      ),
    ),
  );
}

class LocalSendApp extends StatelessWidget {
  const LocalSendApp();

  @override
  Widget build(BuildContext context) {
    final ref = context.ref;
    final (themeMode, colorMode, customColor) = ref.watch(
      settingsProvider.select((settings) => (settings.theme, settings.colorMode, settings.customColor)),
    );
    final dynamicColors = ref.watch(dynamicColorsProvider);
    return TrayWatcher(
      child: WindowWatcher(
        child: LifeCycleWatcher(
          onChangedState: (AppLifecycleState state) {
            switch (state) {
              case AppLifecycleState.resumed:
                ref.redux(localIpProvider).dispatch(InitLocalIpAction());
                if (checkPlatform([TargetPlatform.iOS, TargetPlatform.android])) {
                  // The OS may have invalidated the sockets of the suspended app without any error ever reaching the accept loop.
                  // ignore: discarded_futures
                  ref.notifier(serverProvider).ensureRunning();
                }
                if (checkPlatform([TargetPlatform.iOS])) {
                  // The multicast sockets die the same silent way but cannot be probed, so always rebind them.
                  ref.redux(parentIsolateProvider).dispatch(IsolateDiscoveryRestartAction());
                }
                break;
              case AppLifecycleState.detached:
                // An engine started at boot stays alive when its UI is detached.
                if (ref.read(appArgumentsProvider).contains('--android-boot')) break;
                // The main isolate is only exited when all child isolates are exited.
                // https://github.com/localsend/localsend/issues/1568
                ref.redux(parentIsolateProvider).dispatch(IsolateDisposeAction());
                break;
              default:
                break;
            }
          },
          child: ShortcutWatcher(
            child: MaterialApp(
              title: checkPlatform([TargetPlatform.android]) ? 'LocalSend-x' : t.appName,
              locale: TranslationProvider.of(context).flutterLocale,
              supportedLocales: AppLocaleUtils.supportedLocales,
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              debugShowCheckedModeBanner: false,
              theme: getTheme(colorMode, customColor, Brightness.light, dynamicColors),
              darkTheme: getTheme(colorMode, customColor, Brightness.dark, dynamicColors),
              themeMode: colorMode == ColorMode.oled ? ThemeMode.dark : themeMode,
              builder: (context, child) => BackgroundReceiveWatcher(child: WindowBrightnessWatcher(child: child!)),
              navigatorKey: context.read(navigationProvider).key,
              home: RouterinoHome(
                builder: () => const HomePage(
                  initialTab: HomeTab.receive,
                  appStart: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
