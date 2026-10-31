import 'dart:io';

import 'package:flauncher/providers/network_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/widgets/focus_aware_app_bar.dart';
import 'package:flauncher/widgets/header_metrics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../mocks.mocks.dart';

class _FakeNetwork extends ChangeNotifier implements NetworkService {
  @override
  bool get hasInternetAccess => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late MockSettingsService settings;
  late _FakeNetwork network;
  late int weatherRequests;
  late String weatherBody;
  late bool weatherFails;
  late http.Client client;

  setUp(() {
    settings = MockSettingsService();
    network = _FakeNetwork();
    weatherRequests = 0;
    weatherBody = '{"current":{"temperature_2m":7.4,"weather_code":3}}';
    weatherFails = false;
    when(settings.showCpuInStatusBar).thenReturn(true);
    when(settings.showWeatherInStatusBar).thenReturn(true);
    when(settings.weatherCity).thenReturn('Казань');
    when(settings.weatherLatitude).thenReturn(55.79);
    when(settings.weatherLongitude).thenReturn(49.12);
    client = MockClient((request) async {
      weatherRequests++;
      if (weatherFails) throw const SocketException('No route to host');
      return http.Response(weatherBody, 200);
    });
  });

  Future<void> pumpMetrics(WidgetTester tester, CpuStatReader reader) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsService>.value(value: settings),
          ChangeNotifierProvider<NetworkService>.value(value: network),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: HeaderMetrics(readCpuStat: reader, httpClient: client),
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

  testWidgets('/proc/stat unreadable: CPU widget is hidden, not 0', (
    tester,
  ) async {
    await pumpMetrics(tester, () async => null);
    await tester.pump(const Duration(seconds: 3));

    expect(find.textContaining('CPU'), findsNothing);
    await unmount(tester);
  });

  testWidgets('/proc/stat not a number: CPU widget is hidden', (tester) async {
    await pumpMetrics(tester, () async => 'cpu  denied x y z');
    await tester.pump(const Duration(seconds: 3));

    expect(find.textContaining('CPU'), findsNothing);
    await unmount(tester);
  });

  testWidgets('two snapshots give the load percent', (tester) async {
    final lines = [
      'cpu  100 0 100 800 0 0 0 0 0 0',
      'cpu  200 0 200 1000 0 0 0 0 0 0',
    ];
    var i = 0;
    await pumpMetrics(tester, () async => lines[i < 1 ? i++ : 1]);
    await tester.pump(const Duration(seconds: 3));

    // total delta 400, idle delta 200 -> 50 %
    expect(find.text('CPU 50%'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('switches off: no /proc/stat reads and no weather requests', (
    tester,
  ) async {
    when(settings.showCpuInStatusBar).thenReturn(false);
    when(settings.showWeatherInStatusBar).thenReturn(false);
    var reads = 0;
    await pumpMetrics(tester, () async {
      reads++;
      return 'cpu  1 1 1 1 1 1 1 1 1 1';
    });
    await tester.pump(const Duration(seconds: 10));

    expect(reads, 0);
    expect(weatherRequests, 0);
    expect(find.textContaining('CPU'), findsNothing);
    await unmount(tester);
  });

  testWidgets('switch on: weather is requested and shown', (tester) async {
    await pumpMetrics(tester, () async => null);

    expect(weatherRequests, 1);
    expect(find.text('Казань 7°'), findsOneWidget);
    await unmount(tester);
  });

  Future<void> expectIcon(
    WidgetTester tester,
    String current,
    IconData icon,
  ) async {
    weatherBody = '{"current":{"temperature_2m":4,$current}}';
    await pumpMetrics(tester, () async => null);

    expect(find.byIcon(icon), findsOneWidget);
    await unmount(tester);
  }

  testWidgets('clear day: sun icon', (tester) async {
    await expectIcon(
      tester,
      '"weather_code":0,"is_day":1',
      Icons.wb_sunny_outlined,
    );
  });

  testWidgets('clear night: moon icon, not the sun', (tester) async {
    await expectIcon(
      tester,
      '"weather_code":0,"is_day":0',
      Icons.nightlight_outlined,
    );
    expect(find.byIcon(Icons.wb_sunny_outlined), findsNothing);
  });

  testWidgets('cloudy night: cloudy moon icon', (tester) async {
    await expectIcon(
      tester,
      '"weather_code":2,"is_day":0',
      Icons.nights_stay_outlined,
    );
  });

  testWidgets('rain at night keeps the rain icon', (tester) async {
    await expectIcon(
      tester,
      '"weather_code":61,"is_day":0',
      Icons.water_drop_outlined,
    );
  });

  testWidgets('failed request is retried in 2 min until success', (
    tester,
  ) async {
    weatherFails = true;
    await pumpMetrics(tester, () async => null);
    expect(weatherRequests, 1);
    expect(find.textContaining('Казань'), findsNothing);

    await tester.pump(const Duration(minutes: 2));
    await tester.pump();
    expect(weatherRequests, 2);

    weatherFails = false;
    await tester.pump(const Duration(minutes: 2));
    await tester.pump();
    expect(weatherRequests, 3);
    expect(find.text('Казань 7°'), findsOneWidget);

    // After success only the regular 45-min refresh remains.
    await tester.pump(const Duration(minutes: 10));
    expect(weatherRequests, 3);
    await unmount(tester);
  });

  testWidgets('weather and CPU use the header style on one centre line', (
    tester,
  ) async {
    final lines = [
      'cpu  100 0 100 800 0 0 0 0 0 0',
      'cpu  200 0 200 1000 0 0 0 0 0 0',
    ];
    var i = 0;
    await pumpMetrics(tester, () async => lines[i < 1 ? i++ : 1]);
    await tester.pump(const Duration(seconds: 3));

    final weather = find.text('Казань 7°');
    final cpu = find.text('CPU 50%');
    final icon = find.byType(Icon);
    expect(tester.widget<Text>(weather).style, HeaderStyle.text);
    expect(tester.widget<Text>(cpu).style, HeaderStyle.text);
    expect(tester.widget<Icon>(icon).size, HeaderStyle.iconSize);
    final centre = tester.getCenter(weather).dy;
    expect(tester.getCenter(cpu).dy, closeTo(centre, 0.5));
    expect(tester.getCenter(icon).dy, closeTo(centre, 0.5));
    await unmount(tester);
  });
}
