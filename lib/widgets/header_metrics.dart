import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/network_service.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

/// Reads only while the launcher is in the foreground. No background service.
class HeaderMetrics extends StatefulWidget {
  const HeaderMetrics({super.key});

  @override
  State<HeaderMetrics> createState() => _HeaderMetricsState();
}

class _HeaderMetricsState extends State<HeaderMetrics>
    with WidgetsBindingObserver {
  Timer? _cpuTimer;
  Timer? _weatherTimer;
  int? _lastTotal;
  int? _lastIdle;
  int? _cpuPercent;
  int? _temperature;
  int? _weatherCode;
  String? _city;
  String? _locationKey;
  DateTime? _weatherFetchedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _start();
    } else {
      _stop();
    }
  }

  void _start() {
    if (!mounted || _cpuTimer != null) return;
    _readCpu();
    _fetchWeather();
    _cpuTimer = Timer.periodic(const Duration(seconds: 3), (_) => _readCpu());
    _weatherTimer = Timer.periodic(
      const Duration(minutes: 45),
      (_) => _fetchWeather(),
    );
  }

  void _stop() {
    _cpuTimer?.cancel();
    _weatherTimer?.cancel();
    _cpuTimer = null;
    _weatherTimer = null;
    _lastTotal = null;
    _lastIdle = null;
  }

  Future<void> _readCpu() async {
    try {
      final line = (await File('/proc/stat').readAsLines()).first;
      final fields = line
          .trim()
          .split(RegExp(r'\s+'))
          .skip(1)
          .map(int.parse)
          .toList();
      if (fields.length < 5) return;
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
      if (mounted && _cpuPercent != null) setState(() => _cpuPercent = null);
      _cpuTimer?.cancel();
      _cpuTimer = null;
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
    if (_temperature != null &&
        _weatherFetchedAt != null &&
        DateTime.now().difference(_weatherFetchedAt!) <
            const Duration(minutes: 45))
      return;
    try {
      final response = await http
          .get(
            Uri.https('api.open-meteo.com', '/v1/forecast', {
              'latitude': settings.weatherLatitude.toString(),
              'longitude': settings.weatherLongitude.toString(),
              'current': 'temperature_2m,weather_code',
            }),
          )
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
          _city = settings.weatherCity;
          _weatherFetchedAt = DateTime.now();
        });
      }
    } catch (_) {
      if (mounted) setState(() => _temperature = null);
    }
  }

  IconData get _weatherIcon {
    final code = _weatherCode ?? 0;
    if (code == 0) return Icons.wb_sunny_outlined;
    if (code <= 3) return Icons.cloud_outlined;
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
    if (key != _locationKey) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fetchWeather());
    }
    const style = TextStyle(
      color: Colors.white,
      fontSize: 18,
      shadows: [Shadow(blurRadius: 4)],
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (online && _temperature != null) ...[
          Icon(_weatherIcon, color: Colors.white, size: 20),
          const SizedBox(width: 4),
          Text('${_city ?? settings.weatherCity} $_temperature°', style: style),
          const SizedBox(width: 16),
        ],
        if (_cpuPercent != null) ...[
          Text('CPU $_cpuPercent%', style: style),
          const SizedBox(width: 16),
        ],
      ],
    );
  }
}
