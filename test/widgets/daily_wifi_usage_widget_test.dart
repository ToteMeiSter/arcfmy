import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/providers/launcher_state.dart';
import 'package:flauncher/providers/network_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/widgets/daily_wifi_usage_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../mocks.mocks.dart';

class _FakeNetwork extends ChangeNotifier implements NetworkService {
  _FakeNetwork({required bool hasPermission}) : _hasPermission = hasPermission;

  bool _hasPermission;
  int usage = 51234;
  int refreshCalls = 0;

  @override
  bool get hasUsageStatsPermission => _hasPermission;

  @override
  int get dailyWifiUsage => usage;

  @override
  Future<int> getWifiUsageForPeriod(String period) async => usage;

  @override
  Future<void> refreshPermissionAndUsage() async {
    refreshCalls++;
    _hasPermission = true;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late MockSettingsService settingsService;
  late LauncherState launcherState;

  setUp(() {
    settingsService = MockSettingsService();
    launcherState = LauncherState();
    when(settingsService.accentColorHex).thenReturn('6750A4');
    when(settingsService.wifiUsagePeriod).thenReturn('daily');
  });

  Widget createTestWidget(NetworkService network, {Locale locale = const Locale('en')}) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<NetworkService>.value(value: network),
        ChangeNotifierProvider<SettingsService>.value(value: settingsService),
        ChangeNotifierProvider<LauncherState>.value(value: launcherState),
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: DailyWifiUsageWidget()),
      ),
    );
  }

  testWidgets('without permission shows the localized grant-access chip, not usage', (
    tester,
  ) async {
    final network = _FakeNetwork(hasPermission: false);

    await tester.pumpWidget(createTestWidget(network));
    await tester.pump();

    expect(find.text('Usage Access'), findsOneWidget);
    expect(find.textContaining('Daily:'), findsNothing);
  });

  testWidgets('grant-access chip is localized in Russian', (tester) async {
    final network = _FakeNetwork(hasPermission: false);

    await tester.pumpWidget(createTestWidget(network, locale: const Locale('ru')));
    await tester.pump();

    expect(find.text('Доступ к статистике'), findsOneWidget);
    expect(find.text('Usage Access'), findsNothing);
  });

  testWidgets('after the permission is granted and the app resumes, usage is shown', (
    tester,
  ) async {
    final network = _FakeNetwork(hasPermission: false);

    await tester.pumpWidget(createTestWidget(network));
    await tester.pump();
    expect(find.text('Usage Access'), findsOneWidget);

    // didChangeAppLifecycleState(resumed) calls refreshPermissionAndUsage().
    await network.refreshPermissionAndUsage();
    await tester.pump();

    expect(network.refreshCalls, 1);
    expect(find.textContaining('Daily:'), findsOneWidget);
    expect(find.text('Usage Access'), findsNothing);
  });

  testWidgets('usage label follows the selected period, localized in Russian', (
    tester,
  ) async {
    when(settingsService.wifiUsagePeriod).thenReturn('weekly');
    final network = _FakeNetwork(hasPermission: true);

    await tester.pumpWidget(createTestWidget(network, locale: const Locale('ru')));
    await tester.pump();

    expect(find.textContaining('За неделю:'), findsOneWidget);
    expect(find.textContaining('50.03 KB'), findsOneWidget);
  });
}
