/*
 * FLauncher
 * Copyright (C) 2024 Oscar Rojas
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import 'package:flauncher/widgets/rounded_switch_list_tile.dart';
import 'package:flauncher/widgets/settings/settings_theme.dart';
import 'package:flauncher/widgets/settings/focusable_settings_tile.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flauncher/l10n/app_localizations.dart';

import '../../providers/settings_service.dart';

class StatusBarPanelPage extends StatelessWidget {
  static const String routeName = "status_bar_panel";

  @override
  Widget build(BuildContext context) {
    AppLocalizations localizations = AppLocalizations.of(context)!;
    SettingsService settingsService = Provider.of(context);

    return Column(
      children: [
        SettingsPageHeader(title: localizations.statusBar),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              RoundedSwitchListTile(
                autofocus: true,
                value: settingsService.autoHideAppBarEnabled,
                onChanged: (value) =>
                    settingsService.setAutoHideAppBarEnabled(value),
                title: Text(
                  localizations.autoHideAppBar,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                secondary: const Icon(Icons.visibility_off_outlined),
              ),
              RoundedSwitchListTile(
                value: settingsService.hideStatusBarInGrid,
                onChanged: (value) =>
                    settingsService.setHideStatusBarInGrid(value),
                title: Text(
                  localizations.hideStatusBarInGrid,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                secondary: const Icon(Icons.grid_view_outlined),
              ),
              const SettingsSectionDivider(),
              RoundedSwitchListTile(
                value: settingsService.showDateInStatusBar,
                onChanged: (value) =>
                    settingsService.setShowDateInStatusBar(value),
                title: Text(localizations.date),
                secondary: Icon(Icons.calendar_today_outlined),
              ),
              RoundedSwitchListTile(
                value: settingsService.showTimeInStatusBar,
                onChanged: (value) =>
                    settingsService.setShowTimeInStatusBar(value),
                title: Text(localizations.time),
                secondary: Icon(Icons.watch_later_outlined),
              ),
              FocusableSettingsTile(
                leading: const Icon(Icons.cloud_outlined),
                title: const Text('Город погоды'),
                trailing: Text(settingsService.weatherCity),
                onPressed: () => _editWeather(context, settingsService),
              ),
              RoundedSwitchListTile(
                value: settingsService.showWifiWidgetInStatusBar,
                onChanged: (value) =>
                    settingsService.setShowWifiWidgetInStatusBar(value),
                title: Text(localizations.wifiUsage),
                secondary: Icon(Icons.wifi),
              ),
              RoundedSwitchListTile(
                value: settingsService.showNetworkIndicatorInStatusBar,
                onChanged: (value) =>
                    settingsService.setShowNetworkIndicatorInStatusBar(value),
                title: Text(localizations.networkIndicator),
                secondary: Icon(Icons.signal_wifi_4_bar),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _editWeather(
    BuildContext context,
    SettingsService settings,
  ) async {
    final city = TextEditingController(text: settings.weatherCity);
    final latitude = TextEditingController(
      text: settings.weatherLatitude.toString(),
    );
    final longitude = TextEditingController(
      text: settings.weatherLongitude.toString(),
    );
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Погода: город и координаты'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: city,
              decoration: const InputDecoration(labelText: 'Город'),
            ),
            TextField(
              controller: latitude,
              decoration: const InputDecoration(labelText: 'Широта'),
            ),
            TextField(
              controller: longitude,
              decoration: const InputDecoration(labelText: 'Долгота'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    final lat = double.tryParse(latitude.text.replaceAll(',', '.'));
    final lon = double.tryParse(longitude.text.replaceAll(',', '.'));
    if (result == true &&
        city.text.trim().isNotEmpty &&
        lat != null &&
        lon != null &&
        lat >= -90 &&
        lat <= 90 &&
        lon >= -180 &&
        lon <= 180) {
      await settings.setWeatherLocation(city.text, lat, lon);
    }
    city.dispose();
    latitude.dispose();
    longitude.dispose();
  }
}
