import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/models/app.dart';
import 'package:flauncher/models/watch_next_item.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/watch_next_service.dart';
import 'package:flauncher/widgets/watch_next_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../mocks.dart' show fakeApp;
import '../mocks.mocks.dart';
import 'watch_next_hero_test.dart';

class _CaptionAppsService extends TestAppsService {
  final Map<String, String> names;
  _CaptionAppsService(this.names);

  @override
  App? getApplication(String? packageName) {
    final name = packageName != null ? names[packageName] : null;
    if (name == null) {
      return null;
    }
    return fakeApp(packageName: packageName, name: name);
  }
}

void main() {
  testWidgets('Watch Next card caption shows source app name with section-title fallback',
      (tester) async {
    final settings = MockSettingsService();
    when(settings.showWatchNextSection).thenReturn(true);
    when(settings.watchNextBigPictureMode).thenReturn(false);
    when(settings.showFocusBorders).thenReturn(true);
    when(settings.focusBorderThickness).thenReturn(1.5);
    when(settings.appKeyClickEnabled).thenReturn(false);

    final service = TestWatchNextService();
    service.testItems = [
      WatchNextItem(id: 1, title: 'Movie', packageName: 'com.netflix.ninja'),
      WatchNextItem(id: 2, title: 'Show'),
    ];

    final apps = _CaptionAppsService({'com.netflix.ninja': 'Netflix'});

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsService>.value(value: settings),
          ChangeNotifierProvider<WatchNextService>.value(value: service),
          ChangeNotifierProvider<_CaptionAppsService>.value(value: apps),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: WatchNextRow(isFirstSection: true)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Netflix'), findsOneWidget);
    final context = tester.element(find.text('Netflix'));
    final fallbackTitle = AppLocalizations.of(context)!.watchNextSectionTitle;
    expect(find.text(fallbackTitle), findsOneWidget);
  });
}
