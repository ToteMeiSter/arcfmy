import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/widgets/settings/focusable_settings_tile.dart';
import 'package:flauncher/widgets/settings/general_settings_page.dart';
import 'package:flauncher/widgets/settings/settings_panel.dart';
import 'package:flauncher/widgets/settings/weather_city_dialog.dart';
import 'package:flauncher/widgets/settings/weather_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SettingsService settings;

  Future<void> pumpPanel(
    WidgetTester tester,
    String route, [
    Map<String, Object> prefs = const {},
  ]) async {
    SharedPreferences.setMockInitialValues(prefs);
    settings = SettingsService(
      (await tester.runAsync(SharedPreferences.getInstance))!,
    );
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsService>.value(
        value: settings,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: SettingsPanel(initialRoute: route)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapTile(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text));
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  testWidgets('route is registered; defaults match the previous header', (
    tester,
  ) async {
    await pumpPanel(tester, WeatherSettingsPage.routeName);

    expect(find.byType(WeatherSettingsPage), findsOneWidget);
    expect(settings.weatherFahrenheit, isFalse);
    expect(settings.weatherWindKmh, isFalse);
    expect(settings.weatherRefreshMinutes, 45);
    expect(settings.weatherShowIcon, isTrue);
    expect(settings.weatherShowCity, isTrue);
    expect(settings.weatherShowTemperature, isTrue);
    expect(settings.weatherShowFeelsLike, isFalse);
  });

  testWidgets('System page has a Weather item that opens the page', (
    tester,
  ) async {
    await pumpPanel(tester, GeneralSettingsPage.routeName);

    await tapTile(tester, 'Weather');

    expect(find.byType(WeatherSettingsPage), findsOneWidget);
    expect(find.text('Weather location'), findsOneWidget);
  });

  testWidgets('city tile reuses WeatherCityDialog and shows the saved city', (
    tester,
  ) async {
    await pumpPanel(tester, WeatherSettingsPage.routeName);

    expect(find.text('Казань'), findsOneWidget);
    await tapTile(tester, 'Weather location');

    expect(find.byType(WeatherCityDialog), findsOneWidget);
  });

  testWidgets('units: temperature and wind toggle and are saved', (
    tester,
  ) async {
    await pumpPanel(tester, WeatherSettingsPage.routeName);
    expect(find.text('°C'), findsOneWidget);
    expect(find.text('m/s'), findsOneWidget);

    await tapTile(tester, 'Temperature unit');
    await tapTile(tester, 'Wind speed unit');

    expect(settings.weatherFahrenheit, isTrue);
    expect(settings.weatherWindKmh, isTrue);
    expect(find.text('°F'), findsOneWidget);
    expect(find.text('km/h'), findsOneWidget);
  });

  testWidgets('interval cycles 45 -> 60 -> 15 -> 30 and is saved', (
    tester,
  ) async {
    await pumpPanel(tester, WeatherSettingsPage.routeName);
    expect(find.text('45 min'), findsOneWidget);

    final seen = <int>[];
    for (var i = 0; i < 3; i++) {
      await tapTile(tester, 'Update interval');
      seen.add(settings.weatherRefreshMinutes);
    }

    expect(seen, [60, 15, 30]);
  });

  testWidgets('header fields are saved', (tester) async {
    await pumpPanel(tester, WeatherSettingsPage.routeName);

    await tapTile(tester, 'Feels like');
    await tapTile(tester, 'City');

    expect(settings.weatherShowFeelsLike, isTrue);
    expect(settings.weatherShowCity, isFalse);
    expect(settings.weatherShowIcon, isTrue);
    expect(settings.weatherShowTemperature, isTrue);
  });

  testWidgets('the last enabled field cannot be turned off, with a message', (
    tester,
  ) async {
    await pumpPanel(tester, WeatherSettingsPage.routeName, {
      'weather_show_icon': false,
      'weather_show_city': false,
      'weather_show_temperature': true,
      'weather_show_feels_like': false,
    });
    expect(find.text('At least one field must stay on'), findsNothing);

    await tapTile(tester, 'Temperature');

    expect(settings.weatherShowTemperature, isTrue);
    expect(find.text('At least one field must stay on'), findsOneWidget);

    // Turning another one on lifts the restriction and clears the message.
    await tapTile(tester, 'Icon');
    expect(settings.weatherShowIcon, isTrue);
    expect(find.text('At least one field must stay on'), findsNothing);
    await tapTile(tester, 'Temperature');
    expect(settings.weatherShowTemperature, isFalse);
  });

  testWidgets('D-pad down reaches every item of the page', (tester) async {
    await pumpPanel(tester, WeatherSettingsPage.routeName);
    final visited = <String>[];
    for (var i = 0; i < 9; i++) {
      final tile = FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<FocusableSettingsTile>();
      if (tile != null) visited.add((tile.title as Text).data ?? '');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
    }

    for (final title in [
      'Weather location',
      'Temperature unit',
      'Wind speed unit',
      'Update interval',
      'Icon',
      'City',
      'Temperature',
      'Feels like',
    ]) {
      expect(visited, contains(title), reason: 'focus never reached $title');
    }
  });
}
