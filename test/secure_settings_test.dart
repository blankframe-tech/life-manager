import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_manager/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const storage = FlutterSecureStorage();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('native: salary and name never land in SharedPreferences', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final secure = await SecureSettings.load(prefs, storage);

    SalaryNotifier(prefs, secure).set(55000);
    UserNameNotifier(prefs, secure).set('  Sam ');
    await pumpEventQueue();

    expect(prefs.getKeys(), isNot(contains('monthly_salary')));
    expect(prefs.getKeys(), isNot(contains('user_name')));
    expect(await storage.read(key: 'monthly_salary'), '55000.0');
    expect(await storage.read(key: 'user_name'), 'Sam');

    // Next launch reads them back.
    final again = await SecureSettings.load(prefs, storage);
    expect(SalaryNotifier(prefs, again).state, 55000);
    expect(UserNameNotifier(prefs, again).state, 'Sam');
  });

  test('native: values from older builds move out of prefs once', () async {
    SharedPreferences.setMockInitialValues({
      'monthly_salary': 62000.0,
      'user_name': 'Rafi',
      'theme_mode': 'dark',
    });
    final prefs = await SharedPreferences.getInstance();
    final secure = await SecureSettings.load(prefs, storage);

    expect(SalaryNotifier(prefs, secure).state, 62000);
    expect(UserNameNotifier(prefs, secure).state, 'Rafi');
    expect(prefs.getKeys(), {'theme_mode'});
    expect(await storage.read(key: 'monthly_salary'), '62000.0');
  });

  test('native: a Keychain value wins over a stale prefs copy', () async {
    FlutterSecureStorage.setMockInitialValues({'user_name': 'New'});
    SharedPreferences.setMockInitialValues({'user_name': 'Old'});
    final prefs = await SharedPreferences.getInstance();
    final secure = await SecureSettings.load(prefs, storage);

    expect(UserNameNotifier(prefs, secure).state, 'New');
    expect(prefs.getKeys(), isEmpty);
  });

  test('clear removes them from the Keychain', () async {
    SharedPreferences.setMockInitialValues({'monthly_salary': 1.0});
    final prefs = await SharedPreferences.getInstance();
    final secure = await SecureSettings.load(prefs, storage);
    await secure.clear();

    expect(await storage.readAll(), isEmpty);
    expect(SalaryNotifier(prefs, secure).state, kDefaultMonthlySalary);
  });

  test('web (no secure store): prefs as before', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    SalaryNotifier(prefs).set(30000);
    UserNameNotifier(prefs).set('Web');

    expect(prefs.getDouble('monthly_salary'), 30000);
    expect(prefs.getString('user_name'), 'Web');
  });
}
