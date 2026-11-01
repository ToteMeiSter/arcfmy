import 'dart:convert';

/// Open-Meteo forecast response (Kazan, 2026-11-01 07:45), requested with
/// temperature_unit=fahrenheit and wind_speed_unit=kmh. Hourly is cut to 12
/// entries from 05:00, daily to 7 days.
Map<String, dynamic> weatherFixture({bool withHourly = true, bool withDaily = true}) {
  final hours = [for (var h = 5; h < 17; h++) '2026-11-01T${h.toString().padLeft(2, '0')}:00'];
  return {
    'latitude': 55.79,
    'longitude': 49.1,
    'timezone': 'Europe/Moscow',
    'current': {
      'time': '2026-11-01T07:45',
      'temperature_2m': 27.2,
      'apparent_temperature': 22.1,
      'relative_humidity_2m': 100,
      'weather_code': 45,
      'is_day': 1,
      'wind_speed_10m': 12.4,
      'wind_direction_10m': 141,
      'surface_pressure': 1019.9,
      'precipitation': 0.0,
    },
    if (withHourly)
      'hourly': {
        'time': hours,
        'temperature_2m': [for (var i = 0; i < hours.length; i++) 26.0 + i],
        'weather_code': [for (var i = 0; i < hours.length; i++) i < 2 ? 0 : 3],
        'precipitation_probability': [for (var i = 0; i < hours.length; i++) i * 5],
        'is_day': [for (var i = 0; i < hours.length; i++) i < 2 ? 0 : 1],
      },
    if (withDaily)
      'daily': {
        'time': ['2026-11-01', '2026-11-02', '2026-11-03', '2026-11-04', '2026-11-05', '2026-11-06', '2026-11-07'],
        'weather_code': [45, 61, 3, 71, 0, 2, 95],
        'temperature_2m_max': [30.0, 34.5, 28.0, 25.0, 23.0, 22.0, 20.0],
        'temperature_2m_min': [24.0, 29.0, 21.0, 19.0, 15.0, 12.0, 10.0],
        'precipitation_probability_max': [10, 80, 20, 60, 0, 5, 90],
        'sunrise': ['2026-11-01T06:48', '2026-11-02T06:50', '2026-11-03T06:52', '2026-11-04T06:54', '2026-11-05T06:56', '2026-11-06T06:58', '2026-11-07T07:00'],
        'sunset': ['2026-11-01T16:20', '2026-11-02T16:18', '2026-11-03T16:16', '2026-11-04T16:14', '2026-11-05T16:12', '2026-11-06T16:10', '2026-11-07T16:08'],
      },
  };
}

String weatherFixtureJson({bool withHourly = true, bool withDaily = true}) =>
    jsonEncode(weatherFixture(withHourly: withHourly, withDaily: withDaily));
