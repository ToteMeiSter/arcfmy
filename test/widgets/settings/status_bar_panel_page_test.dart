import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/widgets/header_metrics.dart';
import 'package:flauncher/widgets/rounded_switch_list_tile.dart';
import 'package:flauncher/widgets/settings/status_bar_panel_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../../mocks.mocks.dart';

void main() {
  group('StatusBarPanelPage', () {
    late MockSettingsService settingsService;

    setUp(() {
      settingsService = MockSettingsService();
      when(settingsService.autoHideAppBarEnabled).thenReturn(false);
      when(settingsService.hideStatusBarInGrid).thenReturn(false);
      when(settingsService.showDateInStatusBar).thenReturn(false);
      when(settingsService.showTimeInStatusBar).thenReturn(true);
      when(settingsService.showWifiWidgetInStatusBar).thenReturn(false);
      when(settingsService.showNetworkIndicatorInStatusBar).thenReturn(true);
      when(settingsService.showWeatherInStatusBar).thenReturn(true);
      when(settingsService.showCpuInStatusBar).thenReturn(true);
      when(settingsService.weatherCity).thenReturn('Казань');
      when(settingsService.setShowWeatherInStatusBar(any)).thenAnswer((_) async {});
      when(settingsService.setShowCpuInStatusBar(any)).thenAnswer((_) async {});
      when(settingsService.setAutoHideAppBarEnabled(any)).thenAnswer((_) async {});
      when(settingsService.setHideStatusBarInGrid(any)).thenAnswer((_) async {});
    });

    Widget createTestWidget({CpuStatReader? readCpuStat}) {
      return ChangeNotifierProvider<SettingsService>.value(
        value: settingsService,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: StatusBarPanelPage(
              readCpuStat: readCpuStat ?? () async => 'cpu  1 2 3 4 5 6 7 0',
            ),
          ),
        ),
      );
    }

    testWidgets('renders hideStatusBarInGrid switch tile', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Hide status bar in grid'), findsOneWidget);
      expect(find.text('Automatically hide status bar'), findsOneWidget);
    });

    testWidgets('toggling hideStatusBarInGrid calls setHideStatusBarInGrid', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Hide status bar in grid'));
      await tester.pumpAndSettle();

      verify(settingsService.setHideStatusBarInGrid(true)).called(1);
    });

    testWidgets('weather and CPU rows use l10n names and toggle', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Show weather'), findsOneWidget);
      expect(find.text('Weather location'), findsOneWidget);
      expect(find.text('Show CPU load'), findsOneWidget);

      await tester.ensureVisible(find.text('Show CPU load'));
      await tester.tap(find.text('Show CPU load'));
      await tester.pumpAndSettle();
      verify(settingsService.setShowCpuInStatusBar(false)).called(1);

      await tester.tap(find.text('Show weather'));
      await tester.pumpAndSettle();
      verify(settingsService.setShowWeatherInStatusBar(false)).called(1);
    });

    for (final entry in {
      'null (SELinux)': () async => null,
      'not a number': () async => 'cpu  a b c d e',
    }.entries) {
      testWidgets('CPU switch disabled with caption when /proc/stat is ${entry.key}',
          (tester) async {
        await tester.pumpWidget(createTestWidget(readCpuStat: entry.value));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Show CPU load'));

        expect(find.text('Unavailable on this device'), findsOneWidget);
        final tile = tester.widget<RoundedSwitchListTile>(
          find.widgetWithText(RoundedSwitchListTile, 'Show CPU load'),
        );
        expect(tile.onChanged, isNull);
        expect(tile.value, isFalse);

        await tester.tap(find.text('Show CPU load'));
        await tester.pumpAndSettle();
        verifyNever(settingsService.setShowCpuInStatusBar(any));
      });
    }

    testWidgets('CPU switch enabled without caption when /proc/stat is readable',
        (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Unavailable on this device'), findsNothing);
      final tile = tester.widget<RoundedSwitchListTile>(
        find.widgetWithText(RoundedSwitchListTile, 'Show CPU load'),
      );
      expect(tile.onChanged, isNotNull);
      expect(tile.value, isTrue);
    });
  });
}
