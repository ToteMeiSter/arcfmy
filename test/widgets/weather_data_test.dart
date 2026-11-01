import 'package:flauncher/widgets/weather_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'weather_fixture.dart';

void main() {
  test('parses current, hourly and daily (always °C, m/s, hPa)', () {
    final data = WeatherData.fromJson(weatherFixture());

    expect(data.temperature, 27.2);
    expect(data.feelsLike, 22.1);
    expect(data.humidity, 100);
    expect(data.windSpeed, 12.4);
    expect(data.windDirection, 141);
    expect(data.pressure, 1019.9);
    expect(data.precipitation, 0.0);
    expect(data.code, 45);
    expect(data.isDay, isTrue);
    expect(data.sunrise, DateTime(2026, 11, 1, 6, 48));
    expect(data.sunset, DateTime(2026, 11, 1, 16, 20));
  });

  test('hourly starts with the current hour and keeps 8 entries', () {
    final data = WeatherData.fromJson(weatherFixture());

    expect(data.hourly, hasLength(8));
    expect(data.hourly.first.time, DateTime(2026, 11, 1, 7));
    expect(data.hourly.last.time, DateTime(2026, 11, 1, 14));
    // 05:00 and 06:00 (index 0, 1) are in the past and skipped.
    expect(data.hourly.first.temperature, 28.0);
    expect(data.hourly.first.isDay, isTrue);
    expect(data.hourly.first.precipitationProbability, 10);
  });

  test('daily has 7 days with min, max, code and rain chance', () {
    final data = WeatherData.fromJson(weatherFixture());

    expect(data.daily, hasLength(7));
    expect(data.daily[1].date, DateTime(2026, 11, 2));
    expect(data.daily[1].min, 29.0);
    expect(data.daily[1].max, 34.5);
    expect(data.daily[1].code, 61);
    expect(data.daily[1].precipitationProbability, 80);
  });

  test('response with current only parses; hourly and daily stay empty', () {
    final data = WeatherData.fromJson({
      'current': {'temperature_2m': 7.4, 'weather_code': 3},
    });

    expect(data.temperature, 7.4);
    expect(data.feelsLike, isNull);
    expect(data.humidity, isNull);
    expect(data.hourly, isEmpty);
    expect(data.daily, isEmpty);
    expect(data.sunrise, isNull);
  });

  test('query is one request for current, hourly and daily in °C and m/s', () {
    final query = weatherQuery(latitude: 55.79, longitude: 49.12);

    expect(query['temperature_unit'], 'celsius');
    expect(query['wind_speed_unit'], 'ms');
    expect(query['timezone'], 'auto');
    expect(query['forecast_days'], '7');
    expect(query['current'], contains('apparent_temperature'));
    expect(query['current'], contains('is_day'));
    expect(query['hourly'], contains('precipitation_probability'));
    expect(query['daily'], contains('sunrise'));
  });

  test('local unit conversion', () {
    expect(celsiusToFahrenheit(27.2), closeTo(80.96, 0.001));
    expect(celsiusToFahrenheit(-40), closeTo(-40, 0.001));
    expect(msToKmh(10), closeTo(36, 0.001));
    expect(hpaToMmHg(1013.25), closeTo(760, 0.1));
  });

  test('night icons follow is_day', () {
    expect(weatherIconFor(0, true), Icons.wb_sunny_outlined);
    expect(weatherIconFor(0, false), Icons.nightlight_outlined);
    expect(weatherIconFor(2, false), Icons.nights_stay_outlined);
    expect(weatherIconFor(61, false), Icons.water_drop_outlined);
  });
}
