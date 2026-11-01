import 'dart:convert';

import 'package:flauncher/flauncher.dart';
import 'package:flauncher/flauncher_channel.dart';
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
  bool online = true;

  @override
  bool get hasInternetAccess => online;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late SettingsService settings;
  late List<Uri> requests;
  late http.Client client;
  late _FakeNetwork network;
  late FocusNode gear;
  var failRequests = false;
  var responseDelay = Duration.zero;
  Map<String, dynamic> body = weatherFixture();

  Future<void> pump(
    WidgetTester tester, [
    Map<String, Object> prefs = const {},
    void Function(Map<String, dynamic> body)? tweak,
  ]) async {
    SharedPreferences.setMockInitialValues(prefs);
    settings = SettingsService(
      (await tester.runAsync(SharedPreferences.getInstance))!,
    );
    requests = [];
    failRequests = false;
    responseDelay = Duration.zero;
    body = weatherFixture();
    tweak?.call(body);
    network = _FakeNetwork();
    gear = FocusNode(debugLabel: 'gear');
    addTearDown(gear.dispose);
    client = MockClient((request) async {
      requests.add(request.url);
      if (responseDelay > Duration.zero) await Future<void>.delayed(responseDelay);
      if (failRequests) return http.Response('boom', 500);
      return http.Response(jsonEncode(body), 200);
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsService>.value(value: settings),
          ChangeNotifierProvider<NetworkService>.value(value: network),
          ChangeNotifierProvider<LauncherState>(create: (_) => LauncherState()),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Focus(focusNode: gear, child: const SizedBox(width: 20, height: 20)),
                  HeaderMetrics(
                    readCpuStat: () async => null,
                    httpClient: client,
                  ),
                ],
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

  testWidgets('one request carries current, hourly, daily; always °C and m/s', (
    tester,
  ) async {
    await pump(tester, {'weather_fahrenheit': true, 'weather_wind_kmh': true});

    expect(requests, hasLength(1));
    final q = requests.single.queryParameters;
    expect(q['temperature_unit'], 'celsius');
    expect(q['wind_speed_unit'], 'ms');
    expect(q['hourly'], isNotEmpty);
    expect(q['daily'], isNotEmpty);
    expect(find.text('Казань 81°'), findsOneWidget);
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

  testWidgets('changing the units: no request, no blink, new value at once', (
    tester,
  ) async {
    await pump(tester, {'weather_show_feels_like': true});
    expect(find.text('Казань 27° feels 22°'), findsOneWidget);

    await settings.setWeatherFahrenheit(true);
    await tester.pump();
    expect(find.text('Казань 81° feels 72°'), findsOneWidget);
    await settings.setWeatherWindKmh(true);
    await settings.setWeatherFahrenheit(false);
    await tester.pump();
    await tester.pump();

    expect(find.text('Казань 27° feels 22°'), findsOneWidget);
    expect(requests, hasLength(1));
    await unmount(tester);
  });

  testWidgets('city change at minute 44: next refresh one interval later', (
    tester,
  ) async {
    await pump(tester);
    await tester.pump(const Duration(minutes: 44));
    expect(requests, hasLength(1));

    await settings.setWeatherLocation('Москва', 55.75, 37.62);
    await tester.pump();
    await tester.pump();
    expect(requests, hasLength(2));

    // The old timer would fire at minute 45: it must not.
    await tester.pump(const Duration(minutes: 1));
    await tester.pump();
    expect(requests, hasLength(2));
    await tester.pump(const Duration(minutes: 43));
    expect(requests, hasLength(2));
    await tester.pump(const Duration(minutes: 1));
    await tester.pump();
    expect(requests, hasLength(3));
    await unmount(tester);
  });

  testWidgets('a failed scheduled refresh keeps the previous weather', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Казань 27°'), findsOneWidget);

    failRequests = true;
    await tester.pump(const Duration(minutes: 45));
    await tester.pump();
    expect(requests, hasLength(2));
    expect(find.text('Казань 27°'), findsOneWidget);
    await unmount(tester);
  });

  // ---- focus and content --------------------------------------------------

  Future<void> focusWeather(WidgetTester tester) async {
    Focus.of(tester.element(find.byType(InkWell).first)).requestFocus();
    await tester.pump();
  }

  testWidgets('focused weather disappears: focus moves to the neighbour', (
    tester,
  ) async {
    await pump(tester);
    await focusWeather(tester);
    expect(gear.hasFocus, isFalse);

    await settings.setShowWeatherInStatusBar(false);
    await tester.pump();
    await tester.pump();

    expect(find.byType(InkWell), findsNothing);
    expect(gear.hasFocus, isTrue);
    await unmount(tester);
  });

  testWidgets('focused weather hidden by lost network: focus to the neighbour', (
    tester,
  ) async {
    await pump(tester);
    await focusWeather(tester);

    network.online = false;
    network.notifyListeners();
    await tester.pump();
    await tester.pump();

    expect(gear.hasFocus, isTrue);
    await unmount(tester);
  });

  testWidgets('focused weather, city change: focus to the neighbour', (
    tester,
  ) async {
    await pump(tester);
    await focusWeather(tester);

    // Slow answer: the old city is cleared before the new data arrives.
    responseDelay = const Duration(seconds: 5);
    await settings.setWeatherLocation('Москва', 55.75, 37.62);
    await tester.pump();
    await tester.pump();

    expect(find.byType(InkWell), findsNothing);
    expect(gear.hasFocus, isTrue);
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    await unmount(tester);
  });

  testWidgets('only feels-like selected but missing: the icon is shown', (
    tester,
  ) async {
    await pump(tester, {
      'weather_show_icon': false,
      'weather_show_city': false,
      'weather_show_temperature': false,
      'weather_show_feels_like': true,
    }, (body) => (body['current'] as Map).remove('apparent_temperature'));

    expect(find.byType(InkWell), findsOneWidget);
    expect(find.byType(Icon), findsOneWidget);
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

  testWidgets('HOME closes the panel opened from the header (focus + OK)', (
    tester,
  ) async {
    await pump(tester);
    FLauncherChannel.setHomePressedHandler(
      () => closeRoutesAboveHome(tester.element(find.byType(HeaderMetrics))),
    );
    addTearDown(() => FLauncherChannel.setHomePressedHandler(null));

    await focusWeather(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.byType(WeatherDetailsDialog), findsOneWidget);

    tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'me.efesser.flauncher/method',
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('homePressed'),
      ),
      (_) {},
    );
    await tester.pumpAndSettle();

    expect(find.byType(WeatherDetailsDialog), findsNothing);
    expect(requests, hasLength(1));
    await unmount(tester);
  });
}
