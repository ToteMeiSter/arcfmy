import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/widgets/rounded_switch_list_tile.dart';
import 'package:flauncher/widgets/settings/focusable_settings_tile.dart';
import 'package:flauncher/widgets/settings/settings_theme.dart';
import 'package:flauncher/widgets/settings/weather_city_dialog.dart';
import 'package:flauncher/widgets/weather_geocoding.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Weather settings under System: city, units, what the header shows and how
/// often it refreshes. The on/off switch stays on the status bar page.
class WeatherSettingsPage extends StatefulWidget {
  static const String routeName = "weather_settings_panel";

  const WeatherSettingsPage({super.key});

  @override
  State<WeatherSettingsPage> createState() => _WeatherSettingsPageState();
}

class _WeatherSettingsPageState extends State<WeatherSettingsPage> {
  bool _showKeepOne = false;

  /// The header must show something: the last enabled field cannot be turned
  /// off, a message says why.
  void _toggleField(SettingsService settings, bool current, bool next,
      Future<void> Function(bool) set) {
    final enabled = [
      settings.weatherShowIcon,
      settings.weatherShowCity,
      settings.weatherShowTemperature,
      settings.weatherShowFeelsLike,
    ].where((value) => value).length;
    if (current && !next && enabled <= 1) {
      setState(() => _showKeepOne = true);
      return;
    }
    setState(() => _showKeepOne = false);
    set(next);
  }

  Future<void> _editCity(SettingsService settings) async {
    final city = await showDialog<WeatherCity>(
      context: context,
      builder: (_) => const WeatherCityDialog(),
    );
    if (city != null) {
      await settings.setWeatherLocation(city.name, city.latitude, city.longitude);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final settings = Provider.of<SettingsService>(context);
    final style = Theme.of(context).textTheme.bodyMedium;

    Widget field(String label, IconData icon, bool value,
        Future<void> Function(bool) set) {
      return RoundedSwitchListTile(
        value: value,
        onChanged: (next) => _toggleField(settings, value, next, set),
        title: Text(label, style: style),
        secondary: Icon(icon),
      );
    }

    final interval = settings.weatherRefreshMinutes;
    final nextInterval = WEATHER_REFRESH_OPTIONS[
        (WEATHER_REFRESH_OPTIONS.indexOf(interval) + 1) %
            WEATHER_REFRESH_OPTIONS.length];

    return Column(
      children: [
        SettingsPageHeader(title: l.weatherSettings),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              FocusableSettingsTile(
                autofocus: true,
                leading: const Icon(Icons.location_city_outlined),
                title: Text(l.weatherLocation, style: style),
                trailing: Text(settings.weatherCity),
                onPressed: () => _editCity(settings),
              ),
              FocusableSettingsTile(
                leading: const Icon(Icons.thermostat_outlined),
                title: Text(l.weatherTemperatureUnit, style: style),
                trailing: Text(settings.weatherFahrenheit ? '°F' : '°C'),
                onPressed: () =>
                    settings.setWeatherFahrenheit(!settings.weatherFahrenheit),
              ),
              FocusableSettingsTile(
                leading: const Icon(Icons.air),
                title: Text(l.weatherWindUnit, style: style),
                trailing: Text(
                  settings.weatherWindKmh ? l.weatherWindKmh : l.weatherWindMs,
                ),
                onPressed: () =>
                    settings.setWeatherWindKmh(!settings.weatherWindKmh),
              ),
              FocusableSettingsTile(
                leading: const Icon(Icons.update),
                title: Text(l.weatherRefreshInterval, style: style),
                trailing: Text(l.weatherMinutes(interval)),
                onPressed: () => settings.setWeatherRefreshMinutes(nextInterval),
              ),
              const SettingsSectionDivider(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(l.weatherHeaderFields, style: style),
              ),
              field(l.weatherFieldIcon, Icons.wb_sunny_outlined,
                  settings.weatherShowIcon, settings.setWeatherShowIcon),
              field(l.weatherFieldCity, Icons.location_on_outlined,
                  settings.weatherShowCity, settings.setWeatherShowCity),
              field(l.weatherFieldTemperature, Icons.thermostat_outlined,
                  settings.weatherShowTemperature,
                  settings.setWeatherShowTemperature),
              field(l.weatherFieldFeelsLike, Icons.accessibility_new,
                  settings.weatherShowFeelsLike,
                  settings.setWeatherShowFeelsLike),
              if (_showKeepOne)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    l.weatherKeepOneField,
                    style: style?.copyWith(color: Colors.amberAccent),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
