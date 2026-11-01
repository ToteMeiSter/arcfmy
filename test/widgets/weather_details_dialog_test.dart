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
    Size size = const Size(1920, 1080),
  }) async {
    tester.view.physicalSize = size;
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

  testWidgets('shows now, sunrise/sunset, hourly and 7 days', (tester) async {
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
    // 7 daily columns: min … max
    expect(find.textContaining(' … '), findsNWidgets(7));
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

  testWidgets('«Close» is focused on open; OK closes', (tester) async {
    await open(tester, WeatherData.fromJson(weatherFixture()));

    final closeElement = find
        .descendant(
          of: find.byType(WeatherDetailsDialog),
          matching: find.byType(TextButton),
        )
        .evaluate()
        .single;
    final focused = FocusManager.instance.primaryFocus!;
    expect(
      focused.context!.findAncestorWidgetOfExactType<TextButton>(),
      same(closeElement.widget),
      reason: 'primary focus sits inside the Close button',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.byType(WeatherDetailsDialog), findsNothing);
  });

  testWidgets('days: 7 columns in one row, dates as DD.MM', (tester) async {
    await open(tester, WeatherData.fromJson(weatherFixture()));

    final dates = find.textContaining(RegExp(r'^\d\d\.\d\d$'));
    expect(dates, findsNWidgets(7));
    final ys = {
      for (var i = 0; i < 7; i++) tester.getTopLeft(dates.at(i)).dy,
    };
    expect(ys.length, 1, reason: 'all day columns share one y');
    final xs = [for (var i = 0; i < 7; i++) tester.getTopLeft(dates.at(i)).dx];
    expect(xs, orderedEquals([...xs]..sort()));
    final first = WeatherData.fromJson(weatherFixture()).daily.first.date;
    final text =
        '${first.day.toString().padLeft(2, '0')}.${first.month.toString().padLeft(2, '0')}';
    expect(find.text(text), findsOneWidget);
    expect(find.byType(Scrollable), findsNothing);
  });

  // Logical sizes (px / density): projector 1920x1080 @240 = 1280x720,
  // TCL G07 1920x1080 @320 = 960x540 (wm size / wm density, read-only);
  // #ozmsk was unreachable, covered by the strictest 960x540 and 1920x1080.
  for (final (name, size) in const [
    ('projector', Size(1280, 720)),
    ('tclmsk', Size(960, 540)),
    ('ozmsk (assumed)', Size(1920, 1080)),
  ]) {
    testWidgets('fits $name $size without overflow or scrolling', (
      tester,
    ) async {
      await open(tester, WeatherData.fromJson(weatherFixture()), size: size);

      expect(tester.takeException(), isNull);
      expect(find.byType(Scrollable), findsNothing);
      // The panel itself (the Dialog widget spans the route area).
      final rect = tester.getRect(
        find.descendant(
          of: find.byType(WeatherDetailsDialog),
          matching: find.byType(FittedBox),
        ),
      );
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(size.height));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(size.width));
      expect(
        tester
            .getRect(
              find.descendant(
                of: find.byType(WeatherDetailsDialog),
                matching: find.byType(TextButton),
              ),
            )
            .bottom,
        lessThanOrEqualTo(size.height),
      );
      expect(tester.getRect(find.text('Weather: Казань')).top, greaterThan(0));
      // 7 day columns on one y, 8 hour columns, same column pitch.
      final dates = find.textContaining(RegExp(r'^\d\d\.\d\d$'));
      expect(dates, findsNWidgets(7));
      expect({
        for (var i = 0; i < 7; i++) tester.getTopLeft(dates.at(i)).dy,
      }, hasLength(1));
      final dayPitch =
          tester.getTopLeft(dates.at(1)).dx - tester.getTopLeft(dates.at(0)).dx;
      final hours = find.textContaining(RegExp(r'^\d\d:\d\d$'));
      final hx = [
        for (final t in ['07:00', '08:00'])
          tester.getTopLeft(find.text(t)).dx,
      ];
      expect((hx[1] - hx[0]) - dayPitch, closeTo(0, 0.01));
      expect(hours, findsWidgets);
      // Primary focus is «Close».
      expect(
        FocusManager.instance.primaryFocus!.context!
            .findAncestorWidgetOfExactType<TextButton>(),
        isNotNull,
      );
      // Panel top is below the header bar.
      expect(rect.top, greaterThanOrEqualTo(kToolbarHeight));
      // ignore: avoid_print
      print('PANEL $name ${size.width.toInt()}x${size.height.toInt()}: '
          '${rect.width.toStringAsFixed(0)}x${rect.height.toStringAsFixed(0)} '
          'area=${(rect.width * rect.height).toStringAsFixed(0)} '
          'top=${rect.top.toStringAsFixed(0)}');
      expect(
        tester.getRect(find.text('14:00')).right,
        lessThanOrEqualTo(size.width),
      );
    });
  }
}
