import 'package:flauncher/providers/network_service.dart';
import 'package:flauncher/providers/settings_service.dart';
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
  late http.Client client;

  setUp(() {
    settings = MockSettingsService();
    network = _FakeNetwork();
    weatherRequests = 0;
    when(settings.showCpuInStatusBar).thenReturn(true);
    when(settings.showWeatherInStatusBar).thenReturn(true);
    when(settings.weatherCity).thenReturn('Казань');
    when(settings.weatherLatitude).thenReturn(55.79);
    when(settings.weatherLongitude).thenReturn(49.12);
    client = MockClient((request) async {
      weatherRequests++;
      return http.Response(
        '{"current":{"temperature_2m":7.4,"weather_code":3}}',
        200,
      );
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
}
