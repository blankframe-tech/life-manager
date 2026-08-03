import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const kDefaultMonthlySalary = 40000.0;

const _kThemeModeKey = 'theme_mode';
const _kSalaryKey = 'monthly_salary';

/// Persisted appearance choice — defaults to following the system setting.
class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier(this._prefs) : super(_load(_prefs));

  final SharedPreferences _prefs;

  static ThemeMode _load(SharedPreferences prefs) {
    switch (prefs.getString(_kThemeModeKey)) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  void set(ThemeMode mode) {
    state = mode;
    _prefs.setString(_kThemeModeKey, mode.name);
  }
}

/// Persisted monthly salary used for the 65/20/15 budget split — user-editable
/// in Settings instead of a compile-time constant.
class SalaryNotifier extends StateNotifier<double> {
  SalaryNotifier(this._prefs)
      : super(_prefs.getDouble(_kSalaryKey) ?? kDefaultMonthlySalary);

  final SharedPreferences _prefs;

  void set(double salary) {
    state = salary;
    _prefs.setDouble(_kSalaryKey, salary);
  }
}
