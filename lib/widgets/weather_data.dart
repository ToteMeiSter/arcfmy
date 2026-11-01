import 'package:flutter/material.dart';

/// Icon for a WMO weather code. At night (isDay false) clear and partly
/// cloudy skies get a moon; other codes look the same day and night.
IconData weatherIconFor(int code, bool isDay) {
  if (code == 0) {
    return isDay ? Icons.wb_sunny_outlined : Icons.nightlight_outlined;
  }
  if (code <= 3) {
    return isDay ? Icons.cloud_outlined : Icons.nights_stay_outlined;
  }
  if (code >= 71 && code <= 77) return Icons.ac_unit;
  if (code >= 95) return Icons.thunderstorm_outlined;
  return Icons.water_drop_outlined;
}

double celsiusToFahrenheit(double celsius) => celsius * 9 / 5 + 32;

double msToKmh(double ms) => ms * 3.6;

double hpaToMmHg(double hpa) => hpa * 0.750062;

/// Query of the one Open-Meteo forecast request that feeds both the header
/// and the details panel. Always °C and m/s: units are converted locally, so
/// changing them needs no request.
Map<String, String> weatherQuery({
  required double latitude,
  required double longitude,
}) => {
  'latitude': latitude.toString(),
  'longitude': longitude.toString(),
  'current':
      'temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,'
      'is_day,wind_speed_10m,wind_direction_10m,surface_pressure,precipitation',
  'hourly': 'temperature_2m,weather_code,precipitation_probability,is_day',
  'daily':
      'weather_code,temperature_2m_max,temperature_2m_min,'
      'precipitation_probability_max,sunrise,sunset',
  'timezone': 'auto',
  'forecast_days': '5',
  'temperature_unit': 'celsius',
  'wind_speed_unit': 'ms',
};

class HourlyWeather {
  final DateTime time;
  final double temperature;
  final int code;
  final bool isDay;
  final int? precipitationProbability;

  const HourlyWeather({
    required this.time,
    required this.temperature,
    required this.code,
    required this.isDay,
    this.precipitationProbability,
  });
}

class DailyWeather {
  final DateTime date;
  final int code;
  final double min;
  final double max;
  final int? precipitationProbability;

  const DailyWeather({
    required this.date,
    required this.code,
    required this.min,
    required this.max,
    this.precipitationProbability,
  });
}

/// Parsed forecast response in °C, m/s, hPa. Only [temperature] and [code] are required;
/// every other part may be missing and is then shown as «no data».
class WeatherData {
  final double temperature;
  final double? feelsLike;
  final int code;
  final bool isDay;
  final int? humidity;
  final double? windSpeed;
  final int? windDirection;
  final double? pressure;
  final double? precipitation;
  final DateTime? sunrise;
  final DateTime? sunset;
  final List<HourlyWeather> hourly;
  final List<DailyWeather> daily;

  const WeatherData({
    required this.temperature,
    this.feelsLike,
    required this.code,
    this.isDay = true,
    this.humidity,
    this.windSpeed,
    this.windDirection,
    this.pressure,
    this.precipitation,
    this.sunrise,
    this.sunset,
    this.hourly = const [],
    this.daily = const [],
  });

  /// [hours] hourly entries are kept, starting with the hour of `current.time`
  /// (both in the location's time zone, so the device clock is not used).
  factory WeatherData.fromJson(
    Map<String, dynamic> json, {
    int hours = 8,
  }) {
    final current = json['current'] as Map<String, dynamic>;
    final currentTime = DateTime.tryParse('${current['time']}');
    final startHour = currentTime == null
        ? null
        : DateTime(
            currentTime.year,
            currentTime.month,
            currentTime.day,
            currentTime.hour,
          );

    final hourly = <HourlyWeather>[];
    final h = json['hourly'];
    if (h is Map<String, dynamic>) {
      final times = (h['time'] as List?) ?? const [];
      for (var i = 0; i < times.length && hourly.length < hours; i++) {
        final time = DateTime.tryParse('${times[i]}');
        final t = _at<num>(h, 'temperature_2m', i);
        if (time == null || t == null) continue;
        if (startHour != null && time.isBefore(startHour)) continue;
        hourly.add(
          HourlyWeather(
            time: time,
            temperature: t.toDouble(),
            code: _at<num>(h, 'weather_code', i)?.toInt() ?? 0,
            isDay: (_at<num>(h, 'is_day', i)?.toInt() ?? 1) != 0,
            precipitationProbability: _at<num>(
              h,
              'precipitation_probability',
              i,
            )?.toInt(),
          ),
        );
      }
    }

    final daily = <DailyWeather>[];
    DateTime? sunrise;
    DateTime? sunset;
    final d = json['daily'];
    if (d is Map<String, dynamic>) {
      final dates = (d['time'] as List?) ?? const [];
      for (var i = 0; i < dates.length; i++) {
        final date = DateTime.tryParse('${dates[i]}');
        final min = _at<num>(d, 'temperature_2m_min', i);
        final max = _at<num>(d, 'temperature_2m_max', i);
        if (date == null || min == null || max == null) continue;
        daily.add(
          DailyWeather(
            date: date,
            code: _at<num>(d, 'weather_code', i)?.toInt() ?? 0,
            min: min.toDouble(),
            max: max.toDouble(),
            precipitationProbability: _at<num>(
              d,
              'precipitation_probability_max',
              i,
            )?.toInt(),
          ),
        );
      }
      sunrise = DateTime.tryParse('${_at<String>(d, 'sunrise', 0)}');
      sunset = DateTime.tryParse('${_at<String>(d, 'sunset', 0)}');
    }

    return WeatherData(
      temperature: (current['temperature_2m'] as num).toDouble(),
      feelsLike: (current['apparent_temperature'] as num?)?.toDouble(),
      code: (current['weather_code'] as num).toInt(),
      isDay: (current['is_day'] as num?)?.toInt() != 0,
      humidity: (current['relative_humidity_2m'] as num?)?.round(),
      windSpeed: (current['wind_speed_10m'] as num?)?.toDouble(),
      windDirection: (current['wind_direction_10m'] as num?)?.round(),
      pressure: (current['surface_pressure'] as num?)?.toDouble(),
      precipitation: (current['precipitation'] as num?)?.toDouble(),
      sunrise: sunrise,
      sunset: sunset,
      hourly: hourly,
      daily: daily,
    );
  }

  IconData get icon => weatherIconFor(code, isDay);
}

T? _at<T>(Map<String, dynamic> map, String key, int index) {
  final list = map[key];
  if (list is! List || index >= list.length) return null;
  final value = list[index];
  return value is T ? value : null;
}
