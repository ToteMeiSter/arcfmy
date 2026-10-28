import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/widgets/settings/weather_city_dialog.dart';
import 'package:flauncher/widgets/weather_geocoding.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  Future<WeatherCity?> openDialog(
    WidgetTester tester,
    WeatherCitySearch search,
  ) async {
    WeatherCity? result;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showDialog<WeatherCity>(
              context: context,
              builder: (_) => WeatherCityDialog(search: search),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('has no latitude/longitude fields; picking a match returns it', (
    tester,
  ) async {
    const kazan = WeatherCity(
      name: 'Казань',
      region: 'Татарстан',
      country: 'Россия',
      latitude: 55.79,
      longitude: 49.12,
    );
    await openDialog(tester, (q, lang) async => [kazan]);
    expect(find.byType(TextField), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Казань');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('Казань, Татарстан, Россия'), findsOneWidget);

    await tester.tap(find.text('Казань, Татарстан, Россия'));
    await tester.pumpAndSettle();
    expect(find.byType(WeatherCityDialog), findsNothing);
  });

  testWidgets('D-pad: down from the field focuses the list, OK picks a city', (
    tester,
  ) async {
    const kazan = WeatherCity(
      name: 'Kazan',
      region: 'Tatarstan',
      country: 'Russia',
      latitude: 55.79,
      longitude: 49.12,
    );
    const moscow = WeatherCity(
      name: 'Moscow',
      region: 'Moscow',
      country: 'Russia',
      latitude: 55.75,
      longitude: 37.62,
    );
    WeatherCity? picked;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => picked = await showDialog<WeatherCity>(
              context: context,
              builder: (_) =>
                  WeatherCityDialog(search: (q, l) async => [kazan, moscow]),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'k');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    FocusNode? primary() => FocusManager.instance.primaryFocus;
    String? focused() => primary()?.debugLabel;

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(focused(), 'weatherCity0');
    final tile = tester.widget<ListTile>(
      find.byWidgetPredicate((w) => w is ListTile && w.focusNode == primary()),
    );
    expect(tile.tileColor, isNotNull, reason: 'focused row is highlighted');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(focused(), 'weatherCity1');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(
      primary()?.context?.findAncestorWidgetOfExactType<EditableText>(),
      isNotNull,
      reason: 'up from the first row returns to the field',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.byType(WeatherCityDialog), findsNothing);
    expect(picked, kazan);
  });

  testWidgets('no results and network error show a message', (tester) async {
    var fail = false;
    await openDialog(tester, (q, lang) async {
      if (fail) throw Exception('offline');
      return const [];
    });
    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('No cities found'), findsOneWidget);

    fail = true;
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    expect(
      find.text('Search failed. Check the network connection.'),
      findsOneWidget,
    );
  });

  test('searchWeatherCities parses geocoding response', () async {
    late Uri requested;
    final client = MockClient((request) async {
      requested = request.url;
      return http.Response(
        '{"results":[{"name":"Казань","admin1":"Татарстан","country":"Россия",'
        '"latitude":55.78874,"longitude":49.12214}]}',
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final found = await searchWeatherCities('Казань', 'ru', client: client);

    expect(requested.host, 'geocoding-api.open-meteo.com');
    expect(requested.queryParameters['language'], 'ru');
    expect(found.single.label, 'Казань, Татарстан, Россия');
    expect(found.single.latitude, 55.78874);
  });

  test('searchWeatherCities: no results key gives an empty list', () async {
    final client = MockClient((_) async => http.Response('{}', 200));
    expect(await searchWeatherCities('zzzz', 'en', client: client), isEmpty);
  });
}
