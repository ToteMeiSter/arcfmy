import 'package:flauncher/widgets/settings/settings_panel.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/launcher_state.dart';
import '../providers/network_service.dart';
import '../providers/settings_service.dart';
import 'app_bar_focus_ring.dart';
import 'daily_wifi_usage_widget.dart';
import 'date_time_widget.dart';
import 'header_metrics.dart';
import 'network_widget.dart';

/// The one style of the status bar: every text, icon, shadow and gap in the
/// header comes from here. Height and letter spacing are explicit so the text
/// does not inherit different values from the AppBar title and actions.
abstract final class HeaderStyle {
  static const shadows = [
    Shadow(color: Colors.black54, offset: Offset(0, 2), blurRadius: 4),
  ];
  static const text = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w500,
    height: 1.2,
    letterSpacing: 0,
    leadingDistribution: TextLeadingDistribution.even,
    color: Colors.white,
    shadows: shadows,
  );
  static const double iconSize = 22;
  static const double iconGap = 6;
  static const double gap = 16;
}

class FocusAwareAppBar extends StatefulWidget implements PreferredSizeWidget {
  const FocusAwareAppBar({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() {
    return FocusAwareAppBarState();
  }

  @override
  Size get preferredSize => Size.fromHeight(kToolbarHeight);
}

class FocusAwareAppBarState extends State<FocusAwareAppBar> {
  bool focused = false;
  late FocusNode _settingsFocusNode;

  @override
  void initState() {
    super.initState();
    _settingsFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _settingsFocusNode.dispose();
    super.dispose();
  }

  void focusSettings() {
    _settingsFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Selector2<
      SettingsService,
      LauncherState,
      ({bool autoHide, bool hideInGrid, bool appGridFocused})
    >(
      selector: (_, settings, launcherState) => (
        autoHide: settings.autoHideAppBarEnabled,
        hideInGrid: settings.hideStatusBarInGrid,
        appGridFocused: launcherState.appGridFocused,
      ),
      builder: (context, data, widget) {
        final isVisible =
            focused ||
            (!data.autoHide && !(data.hideInGrid && data.appGridFocused));

        return Focus(
          canRequestFocus: false,
          onFocusChange: (hasFocus) {
            if (hasFocus) {
              context.read<LauncherState>().setAppGridFocused(false);
            }
            setState(() {
              focused = hasFocus;
            });
          },
          child: IgnorePointer(
            ignoring: !isVisible,
            child: AnimatedOpacity(
              curve: Curves.easeInOut,
              duration: const Duration(milliseconds: 200),
              opacity: isVisible ? 1.0 : 0.0,
              child: ClipRect(
                child: AnimatedContainer(
                  curve: Curves.decelerate,
                  duration: const Duration(milliseconds: 200),
                  height: isVisible ? kToolbarHeight : 0,
                  child: OverflowBox(
                    minHeight: 0,
                    maxHeight: kToolbarHeight,
                    alignment: Alignment.topCenter,
                    child: widget!,
                  ),
                ),
              ),
            ),
          ),
        );
      },
      child: RepaintBoundary(
        child: AppBar(
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: Colors.transparent,
          // Left side: Settings, Network indicator, WiFi usage
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Settings button
              AppBarFocusRing(
                focusNode: _settingsFocusNode,
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => const SettingsPanel(),
                ),
                semanticLabel: 'Settings',
                child: const Icon(
                  Icons.settings_outlined,
                  size: HeaderStyle.iconSize,
                  color: Colors.white,
                  shadows: HeaderStyle.shadows,
                ),
              ),
              // Focus rings add 6 px on each side: visible gap stays 16 px.
              const SizedBox(width: HeaderStyle.gap - 12),
              // Network indicator (conditionally shown)
              Selector<SettingsService, bool>(
                selector: (_, settings) =>
                    settings.showNetworkIndicatorInStatusBar,
                builder: (context, showNetwork, _) => showNetwork
                    ? Padding(
                        padding: const EdgeInsets.only(
                          right: HeaderStyle.gap - 12,
                        ),
                        child: AppBarFocusRing(
                          onPressed: () =>
                              context.read<NetworkService>().openWifiSettings(),
                          semanticLabel: 'Network',
                          child: const NetworkWidget(),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              // WiFi usage widget
              Selector<SettingsService, bool>(
                selector: (_, settings) => settings.showWifiWidgetInStatusBar,
                builder: (context, showWifi, _) => showWifi
                    ? const DailyWifiUsageWidget()
                    : const SizedBox.shrink(),
              ),
            ],
          ),
          // Right side: Date/Time only
          actions: [
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 32),
              child:
                  Selector<
                    SettingsService,
                    ({
                      bool showDateInStatusBar,
                      bool showTimeInStatusBar,
                      String dateFormat,
                      String timeFormat,
                    })
                  >(
                    selector: (context, service) => (
                      showDateInStatusBar: service.showDateInStatusBar,
                      showTimeInStatusBar: service.showTimeInStatusBar,
                      dateFormat: service.dateFormat,
                      timeFormat: service.timeFormat,
                    ),
                    builder: (context, dateTimeSettings, _) {
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const HeaderMetrics(),
                          // Date
                          if (dateTimeSettings.showDateInStatusBar)
                            DateTimeWidget(
                              dateTimeSettings.dateFormat,
                              key: const Key("statusbar_date"),
                              updateInterval: const Duration(minutes: 1),
                              textStyle: HeaderStyle.text,
                            ),

                          if (dateTimeSettings.showDateInStatusBar &&
                              dateTimeSettings.showTimeInStatusBar)
                            const SizedBox(width: HeaderStyle.gap),

                          // Clock: same style as the rest of the header.
                          if (dateTimeSettings.showTimeInStatusBar)
                            DateTimeWidget(
                              dateTimeSettings.timeFormat,
                              key: const Key("statusbar_clock"),
                              updateInterval: const Duration(minutes: 1),
                              textStyle: HeaderStyle.text,
                            ),
                        ],
                      );
                    },
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
