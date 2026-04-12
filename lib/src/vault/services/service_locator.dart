import 'package:get_it/get_it.dart';
import 'package:convert_the_spire_reborn/src/vault/services/identity_service.dart';
import 'package:convert_the_spire_reborn/src/vault/services/settings_service.dart';
import 'package:convert_the_spire_reborn/src/vault/services/theme_service.dart';
import 'package:convert_the_spire_reborn/src/vault/services/startup_service.dart';
import 'package:convert_the_spire_reborn/src/vault/services/tray_service.dart';

final GetIt sl = GetIt.instance;

Future<void> setupServiceLocator() async {
  sl.registerLazySingleton<IdentityService>(() => IdentityService.instance);
  sl.registerLazySingleton<SettingsService>(() => SettingsService.instance);
  sl.registerLazySingleton<ThemeService>(() => ThemeService.instance);
  sl.registerLazySingleton<StartupService>(() => StartupService());
  sl.registerLazySingleton<TrayService>(
    () => TrayService(
      shouldMinimiseToTray: () =>
          SettingsService.instance.minimizeToTrayOnClose,
      onTrayShow: () async {
        await Future.value();
      },
      onTrayQuit: () async {
        await Future.value();
      },
    ),
  );
}
