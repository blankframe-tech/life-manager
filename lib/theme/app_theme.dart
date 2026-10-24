import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Font families bundled in `assets/fonts/` (SIL OFL — see the licences there).
const kSans = 'DMSans';
const kSerif = 'Newsreader';

/// A module's colour pair — a strong ink for icons/marks and a pastel tile
/// behind it — defined separately for light and dark. Dark is its own palette
/// (deep, desaturated tiles with lighter inks), not an inversion of light.
class ModuleAccent {
  const ModuleAccent({
    required this.ink,
    required this.soft,
    required this.chart,
    required this.inkDark,
    required this.softDark,
  });

  /// Icon / mark colour on [soft] (light mode). ≥ 4.5:1 on [soft].
  final Color ink;

  /// Pastel tile / card tint (light mode).
  final Color soft;

  /// Mid-tone used for chart segments and progress fills (both modes).
  final Color chart;

  final Color inkDark;
  final Color softDark;

  bool _dark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  Color inkOf(BuildContext context) => _dark(context) ? inkDark : ink;
  Color softOf(BuildContext context) => _dark(context) ? softDark : soft;
}

/// The V2 palette: warm cream, deep forest green, and pastel module accents.
class Accents {
  static const forest = ModuleAccent(
    ink: Color(0xFF1F4D3A),
    soft: Color(0xFFE3ECE4),
    chart: Color(0xFF2F6B50),
    inkDark: Color(0xFF9FD3B4),
    softDark: Color(0xFF21302A),
  );
  static const sage = ModuleAccent(
    ink: Color(0xFF345E3E),
    soft: Color(0xFFE6EEE3),
    chart: Color(0xFF94B592),
    inkDark: Color(0xFFB4D3AF),
    softDark: Color(0xFF23302A),
  );
  static const butter = ModuleAccent(
    ink: Color(0xFF805A00),
    soft: Color(0xFFFBF0D3),
    chart: Color(0xFFF2C14E),
    inkDark: Color(0xFFF2CF79),
    softDark: Color(0xFF33301F),
  );
  static const rose = ModuleAccent(
    ink: Color(0xFF9E3D36),
    soft: Color(0xFFF8E4E1),
    chart: Color(0xFFDB7C74),
    inkDark: Color(0xFFF1AAA3),
    softDark: Color(0xFF382625),
  );
  static const lavender = ModuleAccent(
    ink: Color(0xFF574B8F),
    soft: Color(0xFFECE9F5),
    chart: Color(0xFF9C90D0),
    inkDark: Color(0xFFC3B9F0),
    softDark: Color(0xFF2A2838),
  );
  static const sky = ModuleAccent(
    ink: Color(0xFF285E86),
    soft: Color(0xFFE2EDF5),
    chart: Color(0xFF7DB3D9),
    inkDark: Color(0xFFA5CDEA),
    softDark: Color(0xFF1F2D38),
  );
  static const peach = ModuleAccent(
    ink: Color(0xFF8E4A22),
    soft: Color(0xFFFBE8DA),
    chart: Color(0xFFEDA272),
    inkDark: Color(0xFFF2BC98),
    softDark: Color(0xFF382C24),
  );

  /// Stable order for derived colours (transaction categories etc.).
  static const all = [sage, butter, rose, lavender, sky, peach, forest];
}

/// Theme-aware surface/text tokens. Access via `context.colors` — never put
/// raw hex in a widget.
class AppSurface extends ThemeExtension<AppSurface> {
  const AppSurface({
    required this.bg,
    required this.card,
    required this.ink,
    required this.inkSub,
    required this.hair,
    required this.primary,
    required this.onPrimary,
    required this.positive,
    required this.negative,
  });

  final Color bg;
  final Color card;
  final Color ink;
  final Color inkSub;
  final Color hair;

  /// Forest green: buttons, active states, the FAB.
  final Color primary;
  final Color onPrimary;

  /// Money in / credit / done (text-safe on bg and card).
  final Color positive;

  /// Money out over budget / debt / destructive (text-safe on bg and card).
  final Color negative;

  static const light = AppSurface(
    bg: Color(0xFFF7F3EA),
    card: Color(0xFFFFFDF8),
    ink: Color(0xFF1E2A23),
    inkSub: Color(0xFF5B665F),
    hair: Color(0xFFE8E1D3),
    primary: Color(0xFF1F4D3A),
    onPrimary: Color(0xFFFBF8F1),
    positive: Color(0xFF22654A),
    negative: Color(0xFFA63D35),
  );

  static const dark = AppSurface(
    bg: Color(0xFF121814),
    card: Color(0xFF1B231E),
    ink: Color(0xFFEFEBE2),
    inkSub: Color(0xFFA6B0A9),
    hair: Color(0xFF2C3630),
    primary: Color(0xFF9FD3B4),
    onPrimary: Color(0xFF0F2219),
    positive: Color(0xFF9FD3B4),
    negative: Color(0xFFF1A39B),
  );

  @override
  AppSurface copyWith({
    Color? bg,
    Color? card,
    Color? ink,
    Color? inkSub,
    Color? hair,
    Color? primary,
    Color? onPrimary,
    Color? positive,
    Color? negative,
  }) => AppSurface(
    bg: bg ?? this.bg,
    card: card ?? this.card,
    ink: ink ?? this.ink,
    inkSub: inkSub ?? this.inkSub,
    hair: hair ?? this.hair,
    primary: primary ?? this.primary,
    onPrimary: onPrimary ?? this.onPrimary,
    positive: positive ?? this.positive,
    negative: negative ?? this.negative,
  );

  @override
  AppSurface lerp(ThemeExtension<AppSurface>? other, double t) {
    if (other is! AppSurface) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppSurface(
      bg: l(bg, other.bg),
      card: l(card, other.card),
      ink: l(ink, other.ink),
      inkSub: l(inkSub, other.inkSub),
      hair: l(hair, other.hair),
      primary: l(primary, other.primary),
      onPrimary: l(onPrimary, other.onPrimary),
      positive: l(positive, other.positive),
      negative: l(negative, other.negative),
    );
  }
}

extension AppSurfaceX on BuildContext {
  AppSurface get colors {
    final theme = Theme.of(this);
    // Falls back for widgets pumped without buildTheme() (tests, dialogs).
    return theme.extension<AppSurface>() ??
        (theme.brightness == Brightness.dark
            ? AppSurface.dark
            : AppSurface.light);
  }

  TextTheme get text => Theme.of(this).textTheme;
}

/// A stable accent for a user-created transaction category.
///
/// Categories are free text with no stored colour, so the colour is derived
/// from the name — the same name always gets the same swatch, on every device
/// and every launch. `String.hashCode` isn't usable for that (it's salted per
/// run), hence the explicit sum.
ModuleAccent categoryAccent(String name) {
  var sum = 0;
  for (final unit in name.toLowerCase().codeUnits) {
    sum = (sum * 31 + unit) % 100003;
  }
  return Accents.all[sum % Accents.all.length];
}

TextTheme _textTheme(AppSurface s) {
  TextStyle serif(double size, {FontWeight w = FontWeight.w600}) => TextStyle(
    fontFamily: kSerif,
    fontSize: size,
    fontWeight: w,
    height: 1.15,
    color: s.ink,
    letterSpacing: -0.3,
  );
  TextStyle sans(double size, FontWeight w, Color color, {double h = 1.35}) =>
      TextStyle(
        fontFamily: kSans,
        fontSize: size,
        fontWeight: w,
        height: h,
        color: color,
      );
  return TextTheme(
    displaySmall: serif(36),
    headlineMedium: serif(29),
    headlineSmall: serif(25),
    titleLarge: serif(22),
    titleMedium: sans(16, FontWeight.w600, s.ink),
    titleSmall: sans(14.5, FontWeight.w600, s.ink),
    bodyLarge: sans(16, FontWeight.w400, s.ink, h: 1.45),
    bodyMedium: sans(14.5, FontWeight.w400, s.ink),
    bodySmall: sans(12.5, FontWeight.w400, s.inkSub),
    labelLarge: sans(15, FontWeight.w600, s.ink),
    labelMedium: sans(12.5, FontWeight.w500, s.inkSub),
    labelSmall: sans(11.5, FontWeight.w500, s.inkSub),
  );
}

/// App-wide theme. Both brightnesses share shapes; only tokens differ.
ThemeData buildTheme({Brightness brightness = Brightness.light}) {
  final s = brightness == Brightness.dark ? AppSurface.dark : AppSurface.light;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: const Color(0xFF1F4D3A),
        brightness: brightness,
      ).copyWith(
        primary: s.primary,
        onPrimary: s.onPrimary,
        secondary: s.primary,
        onSecondary: s.onPrimary,
        surface: s.card,
        onSurface: s.ink,
        onSurfaceVariant: s.inkSub,
        surfaceContainerLowest: s.card,
        surfaceContainerLow: s.card,
        surfaceContainer: s.card,
        surfaceContainerHigh: s.card,
        surfaceContainerHighest: s.hair,
        outline: s.hair,
        outlineVariant: s.hair,
        error: s.negative,
      );
  final text = _textTheme(s);
  final pill = RoundedRectangleBorder(borderRadius: BorderRadius.circular(28));
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: s.bg,
    fontFamily: kSans,
    textTheme: text,
    extensions: [s],
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: s.bg,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      centerTitle: true,
      foregroundColor: s.ink,
      titleTextStyle: text.titleMedium!.copyWith(fontSize: 17),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: s.primary,
        foregroundColor: s.onPrimary,
        minimumSize: const Size(64, 52),
        padding: const EdgeInsets.symmetric(horizontal: 28),
        shape: pill,
        textStyle: text.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: s.primary,
        minimumSize: const Size(44, 44),
        textStyle: text.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: s.primary,
        minimumSize: const Size(64, 48),
        shape: pill,
        side: BorderSide(color: s.hair),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: s.primary,
      foregroundColor: s.onPrimary,
      elevation: 3,
      shape: const CircleBorder(),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: s.card,
      hintStyle: text.bodyLarge!.copyWith(color: s.inkSub),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: s.hair),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: s.hair),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: s.primary, width: 1.5),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: s.ink,
      contentTextStyle: text.bodyMedium!.copyWith(color: s.bg),
      actionTextColor: brightness == Brightness.dark
          ? AppSurface.light.primary
          : AppSurface.dark.primary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: s.bg,
      surfaceTintColor: Colors.transparent,
      showDragHandle: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: s.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titleTextStyle: text.headlineSmall,
    ),
    listTileTheme: ListTileThemeData(
      iconColor: s.inkSub,
      textColor: s.ink,
      minVerticalPadding: 12,
      titleTextStyle: text.titleSmall,
      subtitleTextStyle: text.bodySmall,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (st) => st.contains(WidgetState.selected) ? s.onPrimary : null,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (st) => st.contains(WidgetState.selected) ? s.primary : null,
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: s.card,
      side: BorderSide(color: s.hair),
      shape: const StadiumBorder(),
      labelStyle: text.labelLarge!.copyWith(fontSize: 13.5),
    ),
    dividerTheme: DividerThemeData(color: s.hair, thickness: 1, space: 1),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: s.primary,
      linearTrackColor: s.hair,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      },
    ),
  );
}

/// Rounded "card" decoration used throughout: soft corners, hairline border,
/// barely-there shadow — the mock's paper-on-cream look.
BoxDecoration cardDecoration(BuildContext context, {Color? color}) {
  final c = context.colors;
  return BoxDecoration(
    color: color ?? c.card,
    borderRadius: BorderRadius.circular(22),
    border: Border.all(color: c.hair),
    boxShadow: [
      BoxShadow(
        color: const Color(0xFF3B3222).withValues(alpha: 0.04),
        blurRadius: 18,
        offset: const Offset(0, 6),
      ),
    ],
  );
}
