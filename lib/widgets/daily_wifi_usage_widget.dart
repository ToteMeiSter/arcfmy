import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/providers/network_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_bar_focus_ring.dart';
import 'focus_aware_app_bar.dart';

class DailyWifiUsageWidget extends StatelessWidget {
  const DailyWifiUsageWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<NetworkService, SettingsService>(
      builder: (context, networkService, settingsService, _) {
        final localizations = AppLocalizations.of(context)!;

        if (!networkService.hasUsageStatsPermission) {
          return AppBarFocusRing(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            onPressed: () => networkService.requestPermission(),
            semanticLabel: localizations.dailyWifiUsageGrantAccessSemantics,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.data_usage,
                  size: HeaderStyle.iconSize,
                  color: Colors.white,
                  shadows: HeaderStyle.shadows,
                ),
                const SizedBox(width: HeaderStyle.iconGap),
                Text(
                  localizations.dailyWifiUsageGrantAccess,
                  style: HeaderStyle.text,
                ),
              ],
            ),
          );
        }

        final period = settingsService.wifiUsagePeriod;
        String label;
        switch (period) {
          case 'weekly':
            label = localizations.dailyWifiUsageLabelWeekly;
            break;
          case 'monthly':
            label = localizations.dailyWifiUsageLabelMonthly;
            break;
          case 'daily':
          default:
            label = localizations.dailyWifiUsageLabelDaily;
            break;
        }

        return FutureBuilder<int>(
          future: networkService.getWifiUsageForPeriod(period),
          builder: (context, snapshot) {
            final usage = snapshot.data ?? networkService.dailyWifiUsage;
            final usageString = _formatBytes(usage);

            return Text('$label$usageString', style: HeaderStyle.text);
          },
        );
      },
    );
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = 0;
    double d = bytes.toDouble();
    while (d >= 1024 && i < suffixes.length - 1) {
      d /= 1024;
      i++;
    }
    return "${d.toStringAsFixed(2)} ${suffixes[i]}";
  }
}
