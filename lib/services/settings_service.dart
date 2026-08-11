import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/item.dart';

const kDefaultMonthlySalary = 40000.0;

const _kThemeModeKey = 'theme_mode';
const _kSalaryKey = 'monthly_salary';
const _kSplitNeedsKey = 'budget_split_needs';
const _kSplitWantsKey = 'budget_split_wants';
const _kSplitSavingsKey = 'budget_split_savings';

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

/// Target Needs/Wants/Savings split, as fractions of monthly salary
/// (e.g. 0.65 == 65%). Defaults to the classic 65/15/20 rule but is fully
/// user-editable in Settings — nothing enforces the three summing to 1.0.
class BudgetSplit {
  const BudgetSplit(
      {required this.needs, required this.wants, required this.savings});

  final double needs;
  final double wants;
  final double savings;

  /// Keyed by [BudgetCategory] so the budget screen can look values up
  /// alongside items, which are also stored by that same string key.
  Map<String, double> get byCategory => {
        BudgetCategory.needs: needs,
        BudgetCategory.wants: wants,
        BudgetCategory.savings: savings,
      };
}

const kDefaultBudgetSplit =
    BudgetSplit(needs: 0.65, wants: 0.15, savings: 0.20);

/// Persisted Needs/Wants/Savings target split — user-editable in Settings
/// instead of the old hardcoded 65/15/20 constants.
class BudgetSplitNotifier extends StateNotifier<BudgetSplit> {
  BudgetSplitNotifier(this._prefs) : super(_load(_prefs));

  final SharedPreferences _prefs;

  static BudgetSplit _load(SharedPreferences prefs) => BudgetSplit(
        needs: prefs.getDouble(_kSplitNeedsKey) ?? kDefaultBudgetSplit.needs,
        wants: prefs.getDouble(_kSplitWantsKey) ?? kDefaultBudgetSplit.wants,
        savings:
            prefs.getDouble(_kSplitSavingsKey) ?? kDefaultBudgetSplit.savings,
      );

  void set(BudgetSplit split) {
    state = split;
    _prefs.setDouble(_kSplitNeedsKey, split.needs);
    _prefs.setDouble(_kSplitWantsKey, split.wants);
    _prefs.setDouble(_kSplitSavingsKey, split.savings);
  }
}
