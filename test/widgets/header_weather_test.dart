import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/providers/launcher_state.dart';
import 'package:flauncher/providers/network_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/widgets/focus_aware_app_bar.dart';
import 'package:flauncher/widgets/header_metrics.dart';
import 'package:flauncher/widgets/weather_details_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'weather_fixture.dart';

class _FakeNetwork extends ChangeNotifier implements NetworkService {
  @override
  bool get hasInternetAccess => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late SettingsService settings;
  late List<Uri> requests;
  late http.Client client;

  Future<void> pump(
    WidgetTester tester, [
    Map<String, Object> prefs = const {},
  ]) async {
    SharedPreferences.setMockInitialValues(prefs);
    settings = SettingsService(
      (await tester.runAsync(SharedPreferences.getInstance))!,
    );
    requests = [];
    client = MockClient((request) async {
      requests.add(request.url);
      return http.Response(weatherFixtureJson(), 200);
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsService>.value(value: settings),
          ChangeNotifierProvider<NetworkService>.value(value: _FakeNetwork()),
          ChangeNotifierProvider<LauncherState>(create: (_) => LauncherState()),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: HeaderMetrics(
                readCpuStat: () async => null,
                httpClient: client,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
  }

  // ---- fields -------------------------------------------------------------

  testWidgets('default fields: icon, city and temperature', (tester) async {
    await pump(tester);

    expect(find.text('Казань 27°'), findsOneWidget);
    expect(find.byType(Icon), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('only temperature selected: no icon, no city', (tester) async {
    await pump(tester, {
      'weather_show_icon': false,
      'weather_show_city': false,
    });

    expect(find.text('27°'), findsOneWidget);
    expect(find.byType(Icon), findsNothing);
    expect(find.textContaining('Казань'), findsNothing);
    await unmount(tester);
  });

  testWidgets('only the icon selected: no text', (tester) async {
    await pump(tester, {
      'weather_show_city': false,
      'weather_show_temperature': false,
    });

    expect(find.byType(Icon), findsOneWidget);
    expect(find.byType(Text), findsNothing);
    await unmount(tester);
  });

  testWidgets('feels like is appended when selected', (tester) async {
    await pump(tester, {
      'weather_show_icon': false,
      'weather_show_feels_like': true,
    });

    expect(find.text('Казань 27° feels 22°'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('selected elements share one centre line (±2 px)', (
    tester,
  ) async {
    await pump(tester, {'weather_show_feels_like': true});

    final text = tester.getCenter(find.textContaining('Казань')).dy;
    final icon = tester.getCenter(find.byType(Icon)).dy;
    expect(icon, closeTo(text, 2));
    expect(
      tester.widget<Text>(find.textContaining('Казань')).style,
      HeaderStyle.text,
    );
    expect(tester.widget<Icon>(find.byType(Icon)).size, HeaderStyle.iconSize);
    await unmount(tester);
  });

  // ---- requests -----------------------------------------------------------

  testWidgets('one request carries current, hourly, daily and the units', (
    tester,
  ) async {
    await pump(tester, {'weather_fahrenheit': true, 'weather_wind_kmh': true});

    expect(requests, hasLength(1));
    final q = requests.single.queryParameters;
    expect(q['temperature_unit'], 'fahrenheit');
    expect(q['wind_speed_unit'], 'kmh');
    expect(q['hourly'], isNotEmpty);
    expect(q['daily'], isNotEmpty);
    await unmount(tester);
  });

  testWidgets('refresh interval from settings: 1 request per tick', (
    tester,
  ) async {
    await pump(tester, {'weather_refresh_minutes': 15});
    expect(requests, hasLength(1));

    await tester.pump(const Duration(minutes: 14));
    expect(requests, hasLength(1));
    await tester.pump(const Duration(minutes: 1));
    await tester.pump();
    expect(requests, hasLength(2));

    await tester.pump(const Duration(minutes: 15));
    await tester.pump();
    expect(requests, hasLength(3));
    await unmount(tester);
  });

  testWidgets('changing the interval restarts the timer, no extra request', (
    tester,
  ) async {
    await pump(tester, {'weather_refresh_minutes': 15});
    expect(requests, hasLength(1));

    await settings.setWeatherRefreshMinutes(60);
    await tester.pump();
    await tester.pump();
    expect(requests, hasLength(1), reason: 'interval change must not fetch');

    // The old 15-min timer is gone ...
    await tester.pump(const Duration(minutes: 59));
    await tester.pump();
    expect(requests, hasLength(1));
    // ... the new one fires after 60 min.
    await tester.pump(const Duration(minutes: 1));
    await tester.pump();
    expect(requests, hasLength(2));
    await unmount(tester);
  });

  testWidgets('changing the units fetches once in the new units', (
    tester,
  ) async {
    await pump(tester);
    expect(requests.single.queryParameters['temperature_unit'], 'celsius');

    await settings.setWeatherFahrenheit(true);
    await tester.pump();
    await tester.pump();

    expect(requests, hasLength(2));
    expect(requests.last.queryParameters['temperature_unit'], 'fahrenheit');
    await unmount(tester);
  });

  // ---- details panel ------------------------------------------------------

  testWidgets('OK on the weather element opens the panel without a request', (
    tester,
  ) async {
    await pump(tester);
    expect(requests, hasLength(1));

    // Reach the element with the remote: focus it, press select.
    final element = find.byType(InkWell).first;
    Focus.of(tester.element(element)).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();

    expect(find.byType(WeatherDetailsDialog), findsOneWidget);
    expect(find.text('Weather: Казань'), findsOneWidget);
    expect(requests, hasLength(1), reason: 'opening the panel must not fetch');
    await unmount(tester);
  });
}
