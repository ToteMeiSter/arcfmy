import 'dart:math' as math;

import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/widgets/focus_aware_app_bar.dart';
import 'package:flauncher/widgets/weather_data.dart';
import 'package:flutter/material.dart';

/// Detailed weather from the data the header already fetched. It makes no
/// network request. Everything fits the screen without scrolling; «Close» is
/// focused on open. BACK closes (HOME closes it through the root navigator in
/// FLauncher).
class WeatherDetailsDialog extends StatefulWidget {
  const WeatherDetailsDialog({
    super.key,
    required this.city,
    this.data,
    this.fahrenheit = false,
    this.windKmh = false,
  });

  final String city;
  final WeatherData? data;

  /// Display units; the data itself is always °C, m/s, hPa.
  final bool fahrenheit;
  final bool windKmh;

  @override
  State<WeatherDetailsDialog> createState() => _WeatherDetailsDialogState();
}

class _WeatherDetailsDialogState extends State<WeatherDetailsDialog> {
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final primary = Theme.of(context).colorScheme.primary;
    final theme = Theme.of(context);
    final data = widget.data;
    final bodyWidth = _bodyWidth(data);
    // The panel starts below the header bar (status bar + toolbar), so it
    // never covers the header.
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight + 8;
    // No scrolling on a TV: the whole panel is scaled down to the screen
    // (MediaQuery size and text scale) instead of being cut or scrolled.
    return Dialog(
      insetPadding: EdgeInsets.fromLTRB(12, top, 12, 12),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: SizedBox(
            width: bodyWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.weatherDetailsTitle(widget.city),
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                if (data == null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(l.weatherNoData),
                  )
                else
                  _Body(
                    data: data,
                    fahrenheit: widget.fahrenheit,
                    windKmh: widget.windKmh,
                    width: bodyWidth,
                  ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    autofocus: true,
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
            ),
          ),
        ),
      ),
    );
  }
}

/// One width for every forecast column (hours and days). The content is as
/// wide as the longer of the two rows, so there is no empty strip on the right.
const double _columnWidth = 66;

double _bodyWidth(WeatherData? data) {
  final slots = data == null
      ? 6
      : math.max(6, math.max(data.hourly.length, data.daily.length));
  return _columnWidth * slots;
}

/// One forecast column: label (hour or date), icon, then text lines. Hours
/// and days are both built from it.
class _ForecastColumn extends StatelessWidget {
  const _ForecastColumn({
    required this.label,
    required this.icon,
    required this.lines,
  });

  final String label;
  final IconData icon;
  final List<Widget> lines;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: _columnWidth,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Icon(icon, size: HeaderStyle.iconSize),
        ...lines.map(
          (w) => DefaultTextStyle.merge(
            style: Theme.of(context).textTheme.bodySmall,
            child: w,
          ),
        ),
      ],
    ),
  );
}

class _Body extends StatelessWidget {
  const _Body({
    required this.data,
    required this.fahrenheit,
    required this.windKmh,
    required this.width,
  });

  final double width;
  final WeatherData data;
  final bool fahrenheit;
  final bool windKmh;

  double _convert(double celsius) =>
      fahrenheit ? celsiusToFahrenheit(celsius) : celsius;

  /// DD.MM with a leading zero, independent of the locale.
  String _shortDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';

  String _temp(double value) => '${_convert(value).round()}°';

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final material = MaterialLocalizations.of(context);
    final theme = Theme.of(context).textTheme;
    final tempUnit = fahrenheit ? '°F' : '°C';
    final windUnit = windKmh ? l.weatherWindKmh : l.weatherWindMs;
    // Russian forecasts give pressure in mm Hg, other locales in hPa.
    final mmHg = Localizations.localeOf(context).languageCode == 'ru';
    String time(DateTime t) => material.formatTimeOfDay(
      TimeOfDay.fromDateTime(t),
      alwaysUse24HourFormat: true,
    );

    Widget fact(String label, String value, {Widget? lead}) => SizedBox(
      width: width / 3,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.bodySmall),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (lead != null) ...[lead, const SizedBox(width: 4)],
                Flexible(child: Text(value, style: theme.bodyMedium)),
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
          '${(windKmh ? msToKmh(wind) : wind).toStringAsFixed(windKmh ? 0 : 1)} $windUnit',
          lead: data.windDirection == null
              ? null
              // Open-Meteo gives the direction the wind comes FROM.
              : Transform.rotate(
                  angle: (data.windDirection! + 180) * math.pi / 180,
                  child: const Icon(Icons.arrow_upward, size: 14),
                ),
        ),
      if (data.pressure != null)
        fact(
          l.weatherPressure,
          l.weatherPressureValue(
            (mmHg ? hpaToMmHg(data.pressure!) : data.pressure!)
                .round()
                .toString(),
          ),
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
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.titleSmall),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(data.icon, size: 32, color: Colors.white),
            const SizedBox(width: 8),
            Text('${_convert(data.temperature).round()}$tempUnit', style: theme.headlineSmall),
            if (data.feelsLike != null) ...[
              const SizedBox(width: 8),
              Text(
                l.weatherFeelsShort(_convert(data.feelsLike!).round().toString()),
                style: theme.bodyMedium,
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        if (facts.isEmpty)
          Text(l.weatherNoData)
        else
          Wrap(children: facts),
        section(
          l.weatherHourly,
          data.hourly.isEmpty
              ? Text(l.weatherNoData)
              : Row(
                  children: [
                    for (final h in data.hourly)
                      _ForecastColumn(
                        label: time(h.time),
                        icon: weatherIconFor(h.code, h.isDay),
                        lines: [
                          Text(_temp(h.temperature)),
                          if (h.precipitationProbability != null)
                            Text(
                              '${h.precipitationProbability}%',
                              style: theme.bodySmall,
                            ),
                        ],
                      ),
                  ],
                ),
        ),
        section(
          l.weatherDaily,
          data.daily.isEmpty
              ? Text(l.weatherNoData)
              : Row(
                  children: [
                    for (final d in data.daily)
                      _ForecastColumn(
                        label: _shortDate(d.date),
                        icon: weatherIconFor(d.code, true),
                        lines: [
                          Text('${_temp(d.min)} … ${_temp(d.max)}'),
                          if (d.precipitationProbability != null)
                            Text(
                              '${d.precipitationProbability}%',
                              style: theme.bodySmall,
                            ),
                        ],
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
