import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/network_service.dart';
import 'package:flauncher/widgets/focus_aware_app_bar.dart';
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
  int? _temperature;
  int? _weatherCode;
  bool _isDay = true;
  String? _city;
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
      _weatherTimer = Timer.periodic(
        const Duration(minutes: 45),
        (_) => _fetchWeather(),
      );
    } else if (!_wantWeather && _weatherTimer != null) {
      _stopWeather();
    }
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

  Future<void> _fetchWeather() async {
    if (!mounted) return;
    final settings = context.read<SettingsService>();
    final key =
        '${settings.weatherCity}|${settings.weatherLatitude},${settings.weatherLongitude}';
    if (_locationKey != key) {
      _locationKey = key;
      _weatherFetchedAt = null;
      setState(() => _temperature = null);
    }
    if (_fetchingKey == key) return;
    if (_temperature != null &&
        _weatherFetchedAt != null &&
        DateTime.now().difference(_weatherFetchedAt!) <
            const Duration(minutes: 45))
      return;
    _fetchingKey = key;
    try {
      final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
        'latitude': settings.weatherLatitude.toString(),
        'longitude': settings.weatherLongitude.toString(),
        'current': 'temperature_2m,weather_code,is_day',
      });
      final response = await (widget.httpClient?.get(uri) ?? http.get(uri))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200)
        throw const HttpException('Weather unavailable');
      final current =
          (jsonDecode(response.body) as Map<String, dynamic>)['current']
              as Map<String, dynamic>;
      if (mounted && _locationKey == key) {
        setState(() {
          _temperature = (current['temperature_2m'] as num).round();
          _weatherCode = (current['weather_code'] as num).toInt();
          _isDay = (current['is_day'] as num?)?.toInt() != 0;
          _city = settings.weatherCity;
          _weatherFetchedAt = DateTime.now();
        });
        _weatherRetryTimer?.cancel();
        _weatherRetryTimer = null;
      }
    } catch (_) {
      if (mounted) setState(() => _temperature = null);
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

  IconData get _weatherIcon {
    final code = _weatherCode ?? 0;
    if (code == 0) {
      return _isDay ? Icons.wb_sunny_outlined : Icons.nightlight_outlined;
    }
    if (code <= 3) {
      return _isDay ? Icons.cloud_outlined : Icons.nights_stay_outlined;
    }
    if (code >= 71 && code <= 77) return Icons.ac_unit;
    if (code >= 95) return Icons.thunderstorm_outlined;
    return Icons.water_drop_outlined;
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
    final key =
        '${settings.weatherCity}|${settings.weatherLatitude},${settings.weatherLongitude}';
    final wantCpu = settings.showCpuInStatusBar && !_cpuUnavailable;
    if (wantCpu != (_cpuTimer != null) ||
        settings.showWeatherInStatusBar != (_weatherTimer != null)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncTimers());
    }
    if (settings.showWeatherInStatusBar && key != _locationKey) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fetchWeather());
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (settings.showWeatherInStatusBar && online && _temperature != null) ...[
          Icon(
            _weatherIcon,
            color: Colors.white,
            size: HeaderStyle.iconSize,
            shadows: HeaderStyle.shadows,
          ),
          const SizedBox(width: HeaderStyle.iconGap),
          Text(
            '${_city ?? settings.weatherCity} $_temperature°',
            style: HeaderStyle.text,
          ),
          const SizedBox(width: HeaderStyle.gap),
        ],
        if (settings.showCpuInStatusBar && _cpuPercent != null) ...[
          Text('CPU $_cpuPercent%', style: HeaderStyle.text),
          const SizedBox(width: HeaderStyle.gap),
        ],
      ],
    );
  }
}
