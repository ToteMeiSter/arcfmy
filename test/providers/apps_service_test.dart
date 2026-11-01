/*
 * FLauncher
 * Copyright (C) 2021  Étienne Fesser
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

import 'package:drift/drift.dart';
import 'package:flauncher/database.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../mocks.dart';
import '../mocks.mocks.dart';

void main() {
  group("AppsService initialised correctly", () {
    test("with empty database", () async {
      final channel = MockFLauncherChannel();
      final database = MockFLauncherDatabase();
      when(channel.getApplications()).thenAnswer((_) => Future.value([
            {
              'packageName': 'me.efesser.flauncher',
              'name': 'FLauncher',
              'version': null,
              'sideloaded': false
            },
            {
              'packageName': 'me.efesser.flauncher.2',
              'name': 'FLauncher 2',
              'version': '2.0.0',
              'sideloaded': true
            }
          ]));
      when(database.getApplications()).thenAnswer((_) => Future.value([
            fakeApp(
              packageName: "me.efesser.flauncher",
              name: "FLauncher",
              version: "1.0.0",
              sideloaded: false,
            ),
            fakeApp(
              packageName: "me.efesser.flauncher.2",
              name: "FLauncher 2",
              version: "2.0.0",
              sideloaded: true,
            ),
          ]));
      when(database.getCategories()).thenAnswer((_) => Future.value([]));
      when(database.getAppsCategories()).thenAnswer((_) => Future.value([]));
      when(database.getLauncherSpacers()).thenAnswer((_) => Future.value([]));
      when(database.insertCategory(any)).thenAnswer((_) => Future.value(1));
      when(database.nextAppCategoryOrder(any)).thenAnswer((_) => Future.value(0));
      when(database.transaction(any)).thenAnswer((realInvocation) => realInvocation.positionalArguments[0]());
      when(database.wasCreated).thenReturn(true);
      AppsService(channel, database);
      await untilCalled(channel.addAppsChangedListener(any));

      verify(database.getApplications());
      verify(database.persistApps([
        AppsCompanion.insert(
          packageName: "me.efesser.flauncher",
          name: "FLauncher",
          version: "",
        ),
        AppsCompanion.insert(
          packageName: "me.efesser.flauncher.2",
          name: "FLauncher 2",
          version: "2.0.0",
        ),
      ]));
      verify(database.deleteApps([]));
      final insertedCategories = verify(database.insertCategory(captureAny))
          .captured.cast<CategoriesCompanion>();
      expect(
        insertedCategories.map((category) => category.name.value),
        ['Избранное', 'Приложения', 'Проектор', 'Служебное'],
      );
    });

    test("with newly installed, uninstalled and existing apps", () async {
      final channel = MockFLauncherChannel();
      final database = MockFLauncherDatabase();
      when(channel.getApplications()).thenAnswer((_) => Future.value([
            {
              'packageName': 'me.efesser.flauncher',
              'name': 'FLauncher',
              'version': '2.0.0',
              'sideloaded': false,
            },
            {
              'packageName': 'me.efesser.flauncher.2',
              'name': 'FLauncher 2',
              'version': '1.0.0',
              'sideloaded': false,
            }
          ]));
      when(channel.applicationExists("uninstalled.app")).thenAnswer((_) => Future.value(false));
      when(channel.applicationExists("disabled.app")).thenAnswer((_) => Future.value(false));
      when(channel.applicationExists("not.uninstalled.app")).thenAnswer((_) => Future.value(true));
      when(database.getApplications()).thenAnswer((_) => Future.value([
            fakeApp(packageName: "me.efesser.flauncher", name: "FLauncher", version: "1.0.0"),
            fakeApp(packageName: "uninstalled.app", name: "Uninstalled Application", version: "1.0.0"),
            fakeApp(packageName: "disabled.app", name: "Disabled Application", version: "1.0.0"),
            fakeApp(packageName: "not.uninstalled.app", name: "Not Uninstalled Application", version: "1.0.0")
          ]));
      when(database.getCategories()).thenAnswer((_) => Future.value([]));
      when(database.getAppsCategories()).thenAnswer((_) => Future.value([]));
      when(database.getLauncherSpacers()).thenAnswer((_) => Future.value([]));
      when(database.transaction(any)).thenAnswer((realInvocation) => realInvocation.positionalArguments[0]());
      when(database.wasCreated).thenReturn(false);
      AppsService(channel, database);
      await untilCalled(channel.addAppsChangedListener(any));

      verify(database.getApplications());
      verify(database.persistApps([
        AppsCompanion.insert(
          packageName: "me.efesser.flauncher",
          name: "FLauncher",
          version: "2.0.0",
        ),
        AppsCompanion.insert(
          packageName: "me.efesser.flauncher.2",
          name: "FLauncher 2",
          version: "1.0.0",
        )
      ]));
      verify(database.deleteApps(["uninstalled.app", "disabled.app"]));
    });
    test("keeps a TV input tile and does not ask the system whether it is installed", () async {
      final channel = MockFLauncherChannel();
      final database = MockFLauncherDatabase();
      const inputId = 'tvinput:com.tv/.hdmi.HDMIInputService/HW5';
      when(channel.getApplications()).thenAnswer((_) => Future.value([
            {
              'packageName': inputId,
              'name': 'HDMI 1',
              'version': '',
              'sideloaded': false,
              'action': 'content://android.media.tv/passthrough/x',
            }
          ]));
      when(database.getApplications()).thenAnswer((_) => Future.value([
            fakeApp(packageName: inputId, name: "HDMI 1", version: "", hidden: true),
          ]));
      when(database.getCategories()).thenAnswer((_) => Future.value([]));
      when(database.getAppsCategories()).thenAnswer((_) => Future.value([]));
      when(database.getLauncherSpacers()).thenAnswer((_) => Future.value([]));
      when(database.transaction(any)).thenAnswer((realInvocation) => realInvocation.positionalArguments[0]());
      when(database.wasCreated).thenReturn(false);
      final appsService = AppsService(channel, database);
      await untilCalled(channel.addAppsChangedListener(any));

      verifyNever(channel.applicationExists(any));
      verify(database.deleteApps([]));
      final app = appsService.applications.firstWhere((a) => a.packageName == inputId);
      expect(app.hidden, isTrue);
      expect(app.action, 'content://android.media.tv/passthrough/x');

      await appsService.launchApp(app);
      verify(channel.launchActivityFromAction('content://android.media.tv/passthrough/x'));
      verifyNever(channel.launchApp(any));
    });
  });

  group("tile placement on an existing database", () {
    const inputId = 'tvinput:com.tv/.hdmi.HDMIInputService/HW5';
    late Category row;

    Future<MockFLauncherDatabase> start({
      required List<Map<String, Object?>> system,
      required List<App> stored,
    }) async {
      final channel = MockFLauncherChannel();
      final database = MockFLauncherDatabase();
      when(channel.getApplications()).thenAnswer((_) => Future.value(system));
      when(channel.applicationExists(any)).thenAnswer((_) => Future.value(true));
      when(database.getApplications()).thenAnswer((_) => Future.value(stored));
      when(database.getCategories()).thenAnswer((_) => Future.value([row]));
      when(database.getAppsCategories()).thenAnswer((_) => Future.value([]));
      when(database.getLauncherSpacers()).thenAnswer((_) => Future.value([]));
      when(database.nextAppCategoryOrder(any)).thenAnswer((_) => Future.value(0));
      when(database.insertAppsCategories(any)).thenAnswer((_) => Future.value());
      when(database.transaction(any)).thenAnswer((i) => i.positionalArguments[0]());
      when(database.wasCreated).thenReturn(false);
      AppsService(channel, database);
      await untilCalled(channel.addAppsChangedListener(any));
      return database;
    }

    Map<String, Object?> sys(String id) =>
        {'packageName': id, 'name': id, 'version': '', 'sideloaded': false};

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      row = fakeCategory(name: 'Приложения', id: 7, type: CategoryType.row, applications: []);
    });

    test("new app on an existing database is added to the row", () async {
      final channel = MockFLauncherChannel();
      final database = MockFLauncherDatabase();
      var persisted = false;
      when(channel.getApplications()).thenAnswer((_) => Future.value([sys('old.app'), sys('new.app')]));
      when(channel.applicationExists(any)).thenAnswer((_) => Future.value(true));
      when(database.getApplications()).thenAnswer((_) => Future.value(persisted
          ? [fakeApp(packageName: 'old.app'), fakeApp(packageName: 'new.app')]
          : [fakeApp(packageName: 'old.app')]));
      when(database.persistApps(any)).thenAnswer((_) async {
        persisted = true;
      });
      when(database.getCategories()).thenAnswer((_) => Future.value([row]));
      when(database.getAppsCategories()).thenAnswer((_) => Future.value([]));
      when(database.getLauncherSpacers()).thenAnswer((_) => Future.value([]));
      when(database.nextAppCategoryOrder(any)).thenAnswer((_) => Future.value(0));
      when(database.insertAppsCategories(any)).thenAnswer((_) => Future.value());
      when(database.transaction(any)).thenAnswer((i) => i.positionalArguments[0]());
      when(database.wasCreated).thenReturn(false);
      AppsService(channel, database);
      await untilCalled(channel.addAppsChangedListener(any));

      final inserted = verify(database.insertAppsCategories(captureAny)).captured.single
          as List<AppsCategoriesCompanion>;
      expect(inserted.map((c) => c.appPackageName.value), ['new.app']);
      expect(inserted.single.categoryId.value, row.id);
    });

    test("a new hidden app stays out of the row", () async {
      final channel = MockFLauncherChannel();
      final database = MockFLauncherDatabase();
      var persisted = false;
      when(channel.getApplications()).thenAnswer((_) => Future.value([sys('new.app')]));
      when(channel.applicationExists(any)).thenAnswer((_) => Future.value(true));
      when(database.getApplications()).thenAnswer((_) => Future.value(
          persisted ? [fakeApp(packageName: 'new.app', hidden: true)] : []));
      when(database.persistApps(any)).thenAnswer((_) async {
        persisted = true;
      });
      when(database.getCategories()).thenAnswer((_) => Future.value([row]));
      when(database.getAppsCategories()).thenAnswer((_) => Future.value([]));
      when(database.getLauncherSpacers()).thenAnswer((_) => Future.value([]));
      when(database.transaction(any)).thenAnswer((i) => i.positionalArguments[0]());
      when(database.wasCreated).thenReturn(false);
      AppsService(channel, database);
      await untilCalled(channel.addAppsChangedListener(any));

      verifyNever(database.insertAppsCategories(any));
    });

    test("4141 input tiles without a category are placed once; a removed tile stays removed", () async {
      final system = [sys(inputId)];
      final first = await start(system: system, stored: [fakeApp(packageName: inputId)]);
      final inserted = verify(first.insertAppsCategories(captureAny)).captured.single
          as List<AppsCategoriesCompanion>;
      expect(inserted.single.appPackageName.value, inputId);
      expect(inserted.single.categoryId.value, row.id);
      expect((await SharedPreferences.getInstance()).getBool('tvinput_row_migrated'), isTrue);

      // The owner removed the tile from the row: the record is stored without a category again.
      final second = await start(system: system, stored: [fakeApp(packageName: inputId)]);
      verifyNever(second.insertAppsCategories(any));
    });

    test("a hidden 4141 input tile is not placed by the migration", () async {
      final database = await start(system: [sys(inputId)], stored: [fakeApp(packageName: inputId, hidden: true)]);
      verifyNever(database.insertAppsCategories(any));
    });
  });

  test("launchApp calls channel", () async {
    final channel = MockFLauncherChannel();
    final database = MockFLauncherDatabase();
    final appsService = await _buildInitialisedAppsService(channel, database, []);
    final app = fakeApp();

    await appsService.launchApp(app);
  });

  test("openAppInfo calls channel", () async {
    final channel = MockFLauncherChannel();
    final database = MockFLauncherDatabase();
    final appsService = await _buildInitialisedAppsService(channel, database, []);
    final app = fakeApp();

    await appsService.openAppInfo(app);

    verify(channel.openAppInfo(app.packageName));
  });

  test("uninstallApp calls channel", () async {
    final channel = MockFLauncherChannel();
    final database = MockFLauncherDatabase();
    final appsService = await _buildInitialisedAppsService(channel, database, []);
    final app = fakeApp();

    await appsService.uninstallApp(app);

    verify(channel.uninstallApp(app.packageName));
  });

  test("openSettings calls channel", () async {
    final channel = MockFLauncherChannel();
    final database = MockFLauncherDatabase();
    final appsService = await _buildInitialisedAppsService(channel, database, []);

    await appsService.openSettings();

    verify(channel.openSettings());
  });

  test("isDefaultLauncher calls channel", () async {
    final channel = MockFLauncherChannel();
    final database = MockFLauncherDatabase();
    when(channel.isDefaultLauncher()).thenAnswer((_) => Future.value(true));
    final appsService = await _buildInitialisedAppsService(channel, database, []);

    final isDefaultLauncher = await appsService.isDefaultLauncher();

    verify(channel.isDefaultLauncher());
    expect(isDefaultLauncher, isTrue);
  });

  test("startAmbientMode calls channel", () async {
    final channel = MockFLauncherChannel();
    final database = MockFLauncherDatabase();
    final appsService = await _buildInitialisedAppsService(channel, database, []);

    await appsService.startAmbientMode();

    verify(channel.startAmbientMode());
  });

  test("addToCategory adds app to category", () async {
    final channel = MockFLauncherChannel();
    final database = MockFLauncherDatabase();
    final appsService = await _buildInitialisedAppsService(channel, database, []);
    final category = fakeCategory(name: "Category");
    when(database.nextAppCategoryOrder(category.id)).thenAnswer((_) => Future.value(1));

    await appsService.addToCategory(fakeApp(packageName: "app.to.be.added"), category);

    verify(database.insertAppsCategories(
        [AppsCategoriesCompanion.insert(categoryId: category.id, appPackageName: "app.to.be.added", order: 1)]));
  });

  test("removeFromCategory removes app from category", () async {
    final channel = MockFLauncherChannel();
    final database = MockFLauncherDatabase();
    final appsService = await _buildInitialisedAppsService(channel, database, []);
    final app = fakeApp(packageName: "app.to.be.added");
    final category = fakeCategory(name: "Category");

    await appsService.removeFromCategory(app, category);

    verify(database.deleteAppCategory(category.id, app.packageName));
  });

  test("saveOrderInCategory persists apps order from memory to database", () async {
    final channel = MockFLauncherChannel();
    final database = MockFLauncherDatabase();
    final category = fakeCategory(name: "Category");
    final appsService = await _buildInitialisedAppsService(channel, database, [
      CategoryWithApps(category, [fakeApp(packageName: "app.1"), fakeApp(packageName: "app.2")])
    ]);

    await appsService.saveApplicationOrderInCategory(category);

    verify(database.replaceAppsCategories([
      AppsCategoriesCompanion.insert(categoryId: category.id, appPackageName: "app.1", order: 0),
      AppsCategoriesCompanion.insert(categoryId: category.id, appPackageName: "app.2", order: 1)
    ]));
  });

  test("reorderApplication changes application order in-memory", () async {
    final channel = MockFLauncherChannel();
    final database = MockFLauncherDatabase();
    final category = fakeCategory(name: "Category");
    final appsService = await _buildInitialisedAppsService(channel, database, [
      CategoryWithApps(category, [fakeApp(packageName: "app.1"), fakeApp(packageName: "app.2")])
    ]);

    appsService.reorderApplication(category, 1, 0);

    expect(appsService.categoriesWithApps[0].applications[0].packageName, "app.2");
    expect(appsService.categoriesWithApps[0].applications[1].packageName, "app.1");
  });

  test("addCategory adds category at index 0 and moves others", () async {
    final channel = MockFLauncherChannel();
    final database = MockFLauncherDatabase();
    final existingCategory = fakeCategory(name: "Existing Category", order: 0);
    final appsService = await _buildInitialisedAppsService(
      channel,
      database,
      [CategoryWithApps(existingCategory, [])],
    );

    await appsService.addCategory("New Category");

    verify(database.insertCategory(CategoriesCompanion.insert(name: "New Category", order: 0)));
    verify(database.updateCategories([CategoriesCompanion(id: Value(existingCategory.id), order: Value(1))]));
  });

  test("renameCategory renames category", () async {
    final channel = MockFLauncherChannel();
    final database = MockFLauncherDatabase();
    final category = fakeCategory(name: "Old name", order: 0);
    final appsService = await _buildInitialisedAppsService(
      channel,
      database,
      [CategoryWithApps(category, [])],
    );

    await appsService.renameCategory(category, "New name");

    verify(database.updateCategory(category.id, CategoriesCompanion(name: Value("New name"))));
  });

  test("deleteCategory deletes category", () async {
    final channel = MockFLauncherChannel();
    final database = MockFLauncherDatabase();
    final defaultCategory = fakeCategory(name: "Applications", order: 0);
    final categoryToDelete = fakeCategory(name: "Delete Me", order: 1);
    final appInDefaultCategory = fakeApp();
    final appInCategoryToDelete = fakeApp(packageName: "app.to.be.moved.1");
    final hiddenAppInCategoryToDelete = fakeApp(packageName: "app.to.be.moved.2", hidden: true);
    final appsService = await _buildInitialisedAppsService(
      channel,
      database,
      [
        CategoryWithApps(defaultCategory, [appInDefaultCategory]),
        CategoryWithApps(categoryToDelete, [appInCategoryToDelete, hiddenAppInCategoryToDelete])
      ],
    );

    await appsService.deleteCategory(categoryToDelete);

    verify(database.deleteCategory(categoryToDelete.id));
  });

  test("moveCategory changes categories order", () async {
    final channel = MockFLauncherChannel();
    final database = MockFLauncherDatabase();
    final applicationsCategory = fakeCategory(name: "Applications", order: 0);
    final favoritesCategory = fakeCategory(name: "Favorites", order: 1);
    final appsService = await _buildInitialisedAppsService(
      channel,
      database,
      [CategoryWithApps(applicationsCategory, []), CategoryWithApps(favoritesCategory, [])],
    );
    when(database.nextAppCategoryOrder(applicationsCategory.id)).thenAnswer((_) => Future.value(1));

    await appsService.moveCategory(1, 0);

    verify(database.updateCategories(
      [
        CategoriesCompanion(id: Value(favoritesCategory.id), order: Value(0)),
        CategoriesCompanion(id: Value(applicationsCategory.id), order: Value(1))
      ],
    ));
  });

  test("hideApplication hides application", () async {
    final database = MockFLauncherDatabase();
    final application = fakeApp();
    final appsService = await _buildInitialisedAppsService(MockFLauncherChannel(), database, [], [application]);

    await appsService.hideApplication(application);

    verify(database.updateApp(application.packageName, const AppsCompanion(hidden: Value(true))));
    expect(appsService.applications, [application]);
    expect(application.hidden, isTrue);
  });

  test("unHideApplication unhides application", () async {
    final database = MockFLauncherDatabase();
    final application = fakeApp(hidden: true);
    final appsService = await _buildInitialisedAppsService(MockFLauncherChannel(), database, [], [application]);

    await appsService.unHideApplication(application);

    verify(database.updateApp(application.packageName, const AppsCompanion(hidden: Value(false))));
    expect(application.hidden, isFalse);
  });

  test("setCategoryType persists change in database", () async {
    final database = MockFLauncherDatabase();
    final category = fakeCategory(type: CategoryType.row);
    final appsService = await _buildInitialisedAppsService(MockFLauncherChannel(), database, []);

    await appsService.setCategoryType(category, CategoryType.grid);

    verify(database.updateCategory(category.id, CategoriesCompanion(type: Value(CategoryType.grid))));
  });

  test("setCategorySort persists change in database", () async {
    final database = MockFLauncherDatabase();
    final category = fakeCategory(sort: CategorySort.manual);
    final appsService = await _buildInitialisedAppsService(MockFLauncherChannel(), database, []);

    await appsService.setCategorySort(category, CategorySort.alphabetical);

    verify(database.updateCategory(category.id, CategoriesCompanion(sort: Value(CategorySort.alphabetical))));
  });

  test("setCategoryColumnsCount persists change in database", () async {
    final database = MockFLauncherDatabase();
    final category = fakeCategory(columnsCount: 6);
    final appsService = await _buildInitialisedAppsService(MockFLauncherChannel(), database, []);

    await appsService.setCategoryColumnsCount(category, 8);

    verify(database.updateCategory(category.id, CategoriesCompanion(columnsCount: Value(8))));
  });

  test("setCategoryRowHeight persists change in database", () async {
    final database = MockFLauncherDatabase();
    final category = fakeCategory(rowHeight: 110);
    final appsService = await _buildInitialisedAppsService(MockFLauncherChannel(), database, []);

    await appsService.setCategoryRowHeight(category, 120);

    verify(database.updateCategory(category.id, CategoriesCompanion(rowHeight: Value(120))));
  });
}

Future<AppsService> _buildInitialisedAppsService(
  MockFLauncherChannel channel,
  MockFLauncherDatabase database,
  List<CategoryWithApps> categoriesWithApps, [
  List<App> initialApps = const [],
]) async {
  when(channel.getApplications()).thenAnswer((_) => Future.value(
      initialApps.map((a) => {'packageName': a.packageName, 'name': a.name}).toList()));
  when(database.getApplications()).thenAnswer((_) => Future.value(initialApps));
  when(database.getCategories()).thenAnswer((_) => Future.value(categoriesWithApps));
  when(database.getAppsCategories()).thenAnswer((_) => Future.value([]));
  when(database.getLauncherSpacers()).thenAnswer((_) => Future.value([]));
  when(database.transaction(any)).thenAnswer((realInvocation) => realInvocation.positionalArguments[0]());
  when(database.wasCreated).thenReturn(false);
  final appsService = AppsService(channel, database);
  await untilCalled(channel.addAppsChangedListener(any));
  clearInteractions(channel);
  clearInteractions(database);
  return appsService;
}
