import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/widgets/weather_data.dart';
import 'package:flauncher/widgets/weather_details_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'weather_fixture.dart';

void main() {
  Future<void> open(
    WidgetTester tester,
    WeatherData? data, {
    bool fahrenheit = false,
    bool windKmh = false,
    Locale? locale,
  }) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => WeatherDetailsDialog(
                city: 'Казань',
                data: data,
                fahrenheit: fahrenheit,
                windKmh: windKmh,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows now, sunrise/sunset, hourly and 5 days', (tester) async {
    await open(
      tester,
      WeatherData.fromJson(weatherFixture()),
      fahrenheit: true,
      windKmh: true,
    );

    expect(find.text('Weather: Казань'), findsOneWidget);
    expect(find.text('81°F'), findsOneWidget);
    expect(find.text('feels 72°'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget); // humidity
    expect(find.text('45 km/h'), findsOneWidget);
    expect(find.text('1020 hPa'), findsOneWidget);
    expect(find.text('0.0 mm'), findsOneWidget);
    expect(find.text('06:48'), findsOneWidget);
    expect(find.text('16:20'), findsOneWidget);
    expect(find.text('Next hours'), findsOneWidget);
    expect(find.text('07:00'), findsOneWidget);
    expect(find.text('14:00'), findsOneWidget);
    expect(find.text('Next days'), findsOneWidget);
    // 5 daily rows: min … max
    expect(find.textContaining(' … '), findsNWidgets(5));
    expect(find.text('No weather data'), findsNothing);
  });

  testWidgets('wind in m/s uses one decimal and the m/s label', (tester) async {
    await open(tester, WeatherData.fromJson(weatherFixture()));

    expect(find.text('12.4 m/s'), findsOneWidget);
    expect(find.text('27°C'), findsOneWidget);
  });

  testWidgets('pressure: hPa by default', (tester) async {
    await open(tester, WeatherData.fromJson(weatherFixture()));
    expect(find.text('1020 hPa'), findsOneWidget);
  });

  testWidgets('pressure in mm Hg for the ru locale', (tester) async {
    await open(
      tester,
      WeatherData.fromJson(weatherFixture()),
      locale: const Locale('ru'),
    );
    expect(find.text('765 мм рт. ст.'), findsOneWidget);
  });

  testWidgets('no data: a clear message, no crash', (tester) async {
    await open(tester, null);

    expect(find.text('No weather data'), findsOneWidget);
  });

  testWidgets('current only: missing hourly and daily say "no data"', (
    tester,
  ) async {
    await open(
      tester,
      WeatherData.fromJson(weatherFixture(withHourly: false, withDaily: false)),
    );

    expect(find.text('No weather data'), findsNWidgets(2));
    expect(find.text('Next hours'), findsOneWidget);
  });

  testWidgets('BACK closes the panel', (tester) async {
    await open(tester, WeatherData.fromJson(weatherFixture()));
    expect(find.byType(WeatherDetailsDialog), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byType(WeatherDetailsDialog), findsNothing);
  });

  testWidgets('D-pad: down scrolls, then reaches Close; up goes back; OK closes', (
    tester,
  ) async {
    // Small screen so the content needs scrolling.
    await open(tester, WeatherData.fromJson(weatherFixture()));
    tester.view.physicalSize = const Size(1000, 500);
    await tester.pumpAndSettle();

    final scrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byType(WeatherDetailsDialog),
        matching: find.byType(Scrollable),
      ),
    );
    expect(scrollable.position.maxScrollExtent, greaterThan(0));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(scrollable.position.pixels, greaterThan(0));

    for (var i = 0; i < 20; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
    }
    final closeButton = tester.widget<TextButton>(
      find.descendant(
        of: find.byType(WeatherDetailsDialog),
        matching: find.byType(TextButton),
      ),
    );
    expect(closeButton.focusNode!.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(closeButton.focusNode!.hasFocus, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(closeButton.focusNode!.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.byType(WeatherDetailsDialog), findsNothing);
  });
}
