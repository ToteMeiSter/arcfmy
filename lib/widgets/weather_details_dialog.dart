import 'dart:math' as math;

import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/widgets/focus_aware_app_bar.dart';
import 'package:flauncher/widgets/weather_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Detailed weather from the data the header already fetched. It makes no
/// network request. D-pad: up/down scroll, the last down reaches «Close»,
/// BACK closes (HOME closes it through the root navigator in FLauncher).
class WeatherDetailsDialog extends StatefulWidget {
  const WeatherDetailsDialog({super.key, required this.city, this.data});

  final String city;
  final WeatherData? data;

  @override
  State<WeatherDetailsDialog> createState() => _WeatherDetailsDialogState();
}

class _WeatherDetailsDialogState extends State<WeatherDetailsDialog> {
  final _scroll = ScrollController();
  final _bodyFocus = FocusNode(debugLabel: 'weatherDetailsBody');
  final _closeFocus = FocusNode(debugLabel: 'weatherDetailsClose');

  @override
  void dispose() {
    _scroll.dispose();
    _bodyFocus.dispose();
    _closeFocus.dispose();
    super.dispose();
  }

  KeyEventResult _onBodyKey(FocusNode _, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final down = event.logicalKey == LogicalKeyboardKey.arrowDown;
    final up = event.logicalKey == LogicalKeyboardKey.arrowUp;
    if (!down && !up) return KeyEventResult.ignored;
    if (!_scroll.hasClients) {
      if (down) _closeFocus.requestFocus();
      return KeyEventResult.handled;
    }
    final position = _scroll.position;
    if (down && position.pixels >= position.maxScrollExtent - 0.5) {
      _closeFocus.requestFocus();
    } else {
      _scroll.animateTo(
        (position.pixels + (down ? 120 : -120)).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final primary = Theme.of(context).colorScheme.primary;
    final data = widget.data;
    return AlertDialog(
      title: Text(l.weatherDetailsTitle(widget.city)),
      content: SizedBox(
        width: 640,
        child: Focus(
          focusNode: _bodyFocus,
          autofocus: true,
          onKeyEvent: _onBodyKey,
          child: SingleChildScrollView(
            controller: _scroll,
            child: data == null
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(l.weatherNoData),
                  )
                : _Body(data: data),
          ),
        ),
      ),
      actions: [
        Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: (_, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.arrowUp) {
              _bodyFocus.requestFocus();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: TextButton(
            focusNode: _closeFocus,
            onPressed: () => Navigator.pop(context),
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.focused)
                    ? primary.withValues(alpha: 0.25)
                    : null,
              ),
              side: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.focused)
                    ? BorderSide(color: primary, width: 2)
                    : null,
              ),
            ),
            child: Text(l.weatherClose),
          ),
        ),
      ],
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.data});

  final WeatherData data;

  String _temp(double value) => '${value.round()}°';

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final material = MaterialLocalizations.of(context);
    final theme = Theme.of(context).textTheme;
    final tempUnit = data.fahrenheit ? '°F' : '°C';
    final windUnit = data.windKmh ? l.weatherWindKmh : l.weatherWindMs;
    String time(DateTime t) => material.formatTimeOfDay(
      TimeOfDay.fromDateTime(t),
      alwaysUse24HourFormat: true,
    );

    Widget fact(String label, String value, {Widget? lead}) => SizedBox(
      width: 190,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.bodySmall),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (lead != null) ...[lead, const SizedBox(width: 4)],
                Flexible(child: Text(value, style: theme.bodyLarge)),
              ],
            ),
          ],
        ),
      ),
    );

    final wind = data.windSpeed;
    final facts = <Widget>[
      if (data.humidity != null)
        fact(l.weatherHumidity, '${data.humidity}%'),
      if (wind != null)
        fact(
          l.weatherWind,
          '${wind.toStringAsFixed(data.windKmh ? 0 : 1)} $windUnit',
          lead: data.windDirection == null
              ? null
              // Open-Meteo gives the direction the wind comes FROM.
              : Transform.rotate(
                  angle: (data.windDirection! + 180) * math.pi / 180,
                  child: const Icon(Icons.arrow_upward, size: 18),
                ),
        ),
      if (data.pressure != null)
        fact(
          l.weatherPressure,
          l.weatherPressureValue(data.pressure!.round().toString()),
        ),
      if (data.precipitation != null)
        fact(
          l.weatherPrecipitation,
          l.weatherPrecipitationValue(data.precipitation!.toStringAsFixed(1)),
        ),
      if (data.sunrise != null)
        fact(l.weatherSunrise, time(data.sunrise!)),
      if (data.sunset != null) fact(l.weatherSunset, time(data.sunset!)),
    ];

    Widget section(String title, Widget child) => Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.titleSmall),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(data.icon, size: 48, color: Colors.white),
            const SizedBox(width: 12),
            Text('${data.temperature.round()}$tempUnit', style: theme.headlineMedium),
            if (data.feelsLike != null) ...[
              const SizedBox(width: 12),
              Text(
                l.weatherFeelsShort(data.feelsLike!.round().toString()),
                style: theme.bodyMedium,
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        if (facts.isEmpty)
          Text(l.weatherNoData)
        else
          Wrap(children: facts),
        section(
          l.weatherHourly,
          data.hourly.isEmpty
              ? Text(l.weatherNoData)
              : Wrap(
                  children: [
                    for (final h in data.hourly)
                      SizedBox(
                        width: 76,
                        child: Column(
                          children: [
                            Text(time(h.time), style: theme.bodySmall),
                            Icon(weatherIconFor(h.code, h.isDay), size: HeaderStyle.iconSize),
                            Text(_temp(h.temperature)),
                            if (h.precipitationProbability != null)
                              Text(
                                '${h.precipitationProbability}%',
                                style: theme.bodySmall,
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
        section(
          l.weatherDaily,
          data.daily.isEmpty
              ? Text(l.weatherNoData)
              : Column(
                  children: [
                    for (final d in data.daily)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 120,
                              child: Text(material.formatShortMonthDay(d.date)),
                            ),
                            Icon(weatherIconFor(d.code, true), size: HeaderStyle.iconSize),
                            const SizedBox(width: 12),
                            SizedBox(
                              width: 120,
                              child: Text('${_temp(d.min)} … ${_temp(d.max)}'),
                            ),
                            if (d.precipitationProbability != null)
                              Text(
                                '${d.precipitationProbability}%',
                                style: theme.bodySmall,
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
