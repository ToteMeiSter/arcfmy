import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/network_service.dart';
import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/widgets/app_bar_focus_ring.dart';
import 'package:flauncher/widgets/focus_aware_app_bar.dart';
import 'package:flauncher/widgets/weather_data.dart';
import 'package:flauncher/widgets/weather_details_dialog.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

/// First line of /proc/stat, or null when it cannot be read.
typedef CpuStatReader = Future<String?> Function();

Future<String?> readProcStat() async {
  try {
    return (await File('/proc/stat').readAsLines()).first;
  } catch (_) {
    return null;
  }
}

/// Numeric fields of a /proc/stat cpu line; throws when null or not numbers.
List<int> parseCpuStat(String? line) {
  if (line == null) throw const FormatException('/proc/stat unreadable');
  final fields =
      line.trim().split(RegExp(r'\s+')).skip(1).map(int.parse).toList();
  if (fields.length < 5) throw const FormatException('/proc/stat short');
  return fields;
}

/// True when /proc/stat is readable and numeric (false under SELinux).
Future<bool> isCpuStatAvailable(CpuStatReader read) async {
  try {
    parseCpuStat(await read());
    return true;
  } catch (_) {
    return false;
  }
}

/// Reads only while the launcher is in the foreground and the widget is
/// switched on in the settings. No background service.
class HeaderMetrics extends StatefulWidget {
  const HeaderMetrics({
    super.key,
    this.readCpuStat = readProcStat,
    this.httpClient,
  });

  final CpuStatReader readCpuStat;
  final http.Client? httpClient;

  @override
  State<HeaderMetrics> createState() => _HeaderMetricsState();
}

class _HeaderMetricsState extends State<HeaderMetrics>
    with WidgetsBindingObserver {
  Timer? _cpuTimer;
  Timer? _weatherTimer;
  Timer? _weatherRetryTimer;
  bool _foreground = true;
  bool _cpuUnavailable = false;
  int? _lastTotal;
  int? _lastIdle;
  int? _cpuPercent;
  WeatherData? _weather;
  String? _city;
  int _timerMinutes = WEATHER_REFRESH_DEFAULT;
  String? _locationKey;
  DateTime? _weatherFetchedAt;
  String? _fetchingKey;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncTimers());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncTimers();
  }

  bool get _wantCpu =>
      _foreground &&
      !_cpuUnavailable &&
      context.read<SettingsService>().showCpuInStatusBar;

  bool get _wantWeather =>
      _foreground && context.read<SettingsService>().showWeatherInStatusBar;

  /// Starts or stops each timer so that it runs only for an enabled widget.
  void _syncTimers() {
    if (!mounted) return;
    if (_wantCpu && _cpuTimer == null) {
      _readCpu();
      _cpuTimer = Timer.periodic(const Duration(seconds: 3), (_) => _readCpu());
    } else if (!_wantCpu && _cpuTimer != null) {
      _stopCpu();
    }
    if (_wantWeather && _weatherTimer == null) {
      _fetchWeather();
      _startWeatherTimer();
    } else if (!_wantWeather && _weatherTimer != null) {
      _stopWeather();
    }
  }

  /// Periodic refresh at the configured interval. A tick always fetches: the
  /// cached data is younger than the interval by the request latency.
  void _startWeatherTimer() {
    _timerMinutes = context.read<SettingsService>().weatherRefreshMinutes;
    _weatherTimer?.cancel();
    _weatherTimer = Timer.periodic(
      Duration(minutes: _timerMinutes > 0 ? _timerMinutes : WEATHER_REFRESH_DEFAULT),
      (_) => _fetchWeather(force: true),
    );
  }

  void _stopCpu() {
    _cpuTimer?.cancel();
    _cpuTimer = null;
    _lastTotal = null;
    _lastIdle = null;
  }

  void _stopWeather() {
    _weatherTimer?.cancel();
    _weatherTimer = null;
    _weatherRetryTimer?.cancel();
    _weatherRetryTimer = null;
  }

  void _stop() {
    _stopCpu();
    _stopWeather();
  }

  Future<void> _readCpu() async {
    try {
      final fields = parseCpuStat(await widget.readCpuStat());
      final total = fields.fold<int>(0, (sum, value) => sum + value);
      final idle = fields[3] + fields[4];
      final deltaTotal = total - (_lastTotal ?? total);
      final deltaIdle = idle - (_lastIdle ?? idle);
      _lastTotal = total;
      _lastIdle = idle;
      if (deltaTotal > 0 && mounted) {
        setState(
          () => _cpuPercent = ((deltaTotal - deltaIdle) * 100 / deltaTotal)
              .round()
              .clamp(0, 100)
              .toInt(),
        );
      }
    } catch (_) {
      // Unreadable (SELinux) or not a number: hide the widget, never show 0.
      _cpuUnavailable = true;
      _stopCpu();
      if (mounted && _cpuPercent != null) setState(() => _cpuPercent = null);
    }
  }

  /// Location and units: a change of any of them needs a new request.
  String _requestKey(SettingsService settings) =>
      '${settings.weatherCity}|${settings.weatherLatitude},${settings.weatherLongitude}'
      '|${settings.weatherFahrenheit}|${settings.weatherWindKmh}';

  Future<void> _fetchWeather({bool force = false}) async {
    if (!mounted) return;
    final settings = context.read<SettingsService>();
    final key = _requestKey(settings);
    if (_locationKey != key) {
      _locationKey = key;
      _weatherFetchedAt = null;
      setState(() => _weather = null);
    }
    if (_fetchingKey == key) return;
    if (!force &&
        _weather != null &&
        _weatherFetchedAt != null &&
        DateTime.now().difference(_weatherFetchedAt!) <
            Duration(minutes: settings.weatherRefreshMinutes)) {
      return;
    }
    _fetchingKey = key;
    try {
      final fahrenheit = settings.weatherFahrenheit;
      final windKmh = settings.weatherWindKmh;
      final uri = Uri.https(
        'api.open-meteo.com',
        '/v1/forecast',
        weatherQuery(
          latitude: settings.weatherLatitude,
          longitude: settings.weatherLongitude,
          fahrenheit: fahrenheit,
          windKmh: windKmh,
        ),
      );
      final response = await (widget.httpClient?.get(uri) ?? http.get(uri))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200)
        throw const HttpException('Weather unavailable');
      final weather = WeatherData.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
        fahrenheit: fahrenheit,
        windKmh: windKmh,
      );
      if (mounted && _locationKey == key) {
        setState(() {
          _weather = weather;
          _city = settings.weatherCity;
          _weatherFetchedAt = DateTime.now();
        });
        _weatherRetryTimer?.cancel();
        _weatherRetryTimer = null;
      }
    } catch (_) {
      if (mounted) setState(() => _weather = null);
      // No network at load time: retry soon instead of waiting 45 min.
      if (mounted && _wantWeather) {
        _weatherRetryTimer ??= Timer(const Duration(minutes: 2), () {
          _weatherRetryTimer = null;
          _fetchWeather();
        });
      }
    } finally {
      if (_fetchingKey == key) _fetchingKey = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final online = context.select<NetworkService, bool>(
      (service) => service.hasInternetAccess,
    );
    final key = _requestKey(settings);
    final wantCpu = settings.showCpuInStatusBar && !_cpuUnavailable;
    if (wantCpu != (_cpuTimer != null) ||
        settings.showWeatherInStatusBar != (_weatherTimer != null)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncTimers());
    }
    if (settings.showWeatherInStatusBar && key != _locationKey) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fetchWeather());
    }
    if (_weatherTimer != null &&
        settings.weatherRefreshMinutes != _timerMinutes) {
      // New interval: restart the timer only, the data is still fresh.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _weatherTimer != null) _startWeatherTimer();
      });
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (settings.showWeatherInStatusBar && online && _weather != null)
          _buildWeather(context, settings, _weather!),
        if (settings.showCpuInStatusBar && _cpuPercent != null) ...[
          Text('CPU $_cpuPercent%', style: HeaderStyle.text),
          const SizedBox(width: HeaderStyle.gap),
        ],
      ],
    );
  }

  /// Focusable weather element: OK opens the details panel (no new request).
  Widget _buildWeather(
    BuildContext context,
    SettingsService settings,
    WeatherData weather,
  ) {
    final city = _city ?? settings.weatherCity;
    final parts = <String>[
      if (settings.weatherShowCity) city,
      if (settings.weatherShowTemperature) '${weather.temperature.round()}°',
      if (settings.weatherShowFeelsLike && weather.feelsLike != null)
        AppLocalizations.of(context)!.weatherFeelsShort(
          weather.feelsLike!.round().toString(),
        ),
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppBarFocusRing(
          semanticLabel: city,
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => WeatherDetailsDialog(city: city, data: weather),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (settings.weatherShowIcon) ...[
                Icon(
                  weather.icon,
                  color: Colors.white,
                  size: HeaderStyle.iconSize,
                  shadows: HeaderStyle.shadows,
                ),
                if (parts.isNotEmpty) const SizedBox(width: HeaderStyle.iconGap),
              ],
              if (parts.isNotEmpty)
                Text(parts.join(' '), style: HeaderStyle.text),
            ],
          ),
        ),
        // The focus ring adds 6 px on its right: visible gap stays 16 px.
        const SizedBox(width: HeaderStyle.gap - 6),
      ],
    );
  }
}
