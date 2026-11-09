// Visual language after Breez's Glow wallet (MIT, github.com/breez/glow-web): dark void background, glass surfaces,
// gradient action buttons, mono amounts. Accent is IBIRAPAY teal instead of Glow's gold; no red anywhere.
import 'package:flutter/material.dart';

class C {
  static const voidBg = Color(0xFF0A0A0F);
  static const dark = Color(0xFF0F0F18);
  static const surface = Color(0xFF151520);
  static const elevated = Color(0xFF1A1A28);
  static const border = Color(0xFF252535);
  static const borderLight = Color(0xFF35354A);
  static const primary = Color(0xFF3E9C93);
  static const primaryLight = Color(0xFF57BEB2);
  static const electric = Color(0xFF00D4FF);
  static const success = Color(0xFF10B981);
  static const warn = Color(0xFFD4A574);
  static const textSec = Color(0xB3FFFFFF);
  static const muted = Color(0x66FFFFFF);
}

const monoFamily = 'monospace';

ThemeData appTheme() {
  OutlineInputBorder b(Color c) =>
      OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c));
  return ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    scaffoldBackgroundColor: C.voidBg,
    canvasColor: C.surface,
    colorScheme: const ColorScheme.dark(primary: C.primary, surface: C.surface, error: C.warn),
    dividerColor: C.border,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: C.dark,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: b(C.border),
      enabledBorder: b(C.border),
      focusedBorder: b(C.primary),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: C.elevated,
      contentTextStyle: const TextStyle(color: Colors.white),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}

String fmtSats(num n) {
  final s = n.abs().toInt().toString();
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(' ');
    out.write(s[i]);
  }
  return out.toString();
}

/// Gradient action button (Glow's `.button`): black label, 12 px radius, press feedback from InkWell.
class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.colors = const [C.primary, C.primaryLight],
    this.expand = true,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final List<Color> colors;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final on = onPressed != null;
    return Opacity(
      opacity: on ? 1 : .5,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: colors.first.withValues(alpha: .35), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onPressed,
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[Icon(icon, size: 20, color: Colors.black), const SizedBox(width: 8)],
                  Text(label, style: const TextStyle(color: Colors.black, fontSize: 15, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class OutlineButton extends StatelessWidget {
  const OutlineButton({super.key, required this.label, required this.onPressed, this.icon});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onPressed,
    icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 18),
    label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    style: OutlinedButton.styleFrom(
      foregroundColor: Colors.white,
      side: const BorderSide(color: C.borderLight, width: 1.5),
      minimumSize: const Size(0, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}

/// Inner card (Glow's PaymentInfoCard): faint dark fill, 1 px border, 16 px radius.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(16)});
  final Widget child;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(
      color: C.dark.withValues(alpha: .5),
      border: Border.all(color: C.border),
      borderRadius: BorderRadius.circular(16),
    ),
    child: child,
  );
}

class RowKV extends StatelessWidget {
  const RowKV(this.k, this.v, {super.key, this.strong = false});
  final String k;
  final String v;
  final bool strong;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(k, style: const TextStyle(color: C.textSec, fontSize: 14)),
        Text(
          v,
          style: TextStyle(
            fontFamily: monoFamily,
            fontSize: 14,
            fontWeight: strong ? FontWeight.w700 : FontWeight.w400,
            color: strong ? C.primaryLight : Colors.white,
          ),
        ),
      ],
    ),
  );
}

/// Bottom sheet: 24 px top corners, handle, keyboard-aware.
/// [dismissible] false: neither a swipe nor a tap outside closes it, for a flow that must not be walked away from mid-way.
Future<T?> showAppSheet<T>(BuildContext context, WidgetBuilder builder, {bool dismissible = true}) => showModalBottomSheet<T>(
  context: context,
  isDismissible: dismissible,
  enableDrag: dismissible,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: C.surface,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    side: BorderSide(color: C.border),
  ),
  builder: (ctx) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 48, height: 4, decoration: BoxDecoration(color: C.borderLight, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          builder(ctx),
        ],
      ),
    ),
  ),
);

class SheetTitle extends StatelessWidget {
  const SheetTitle(this.text, this.icon, {super.key});
  final String text;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Icon(icon, size: 20, color: C.primaryLight),
      const SizedBox(width: 8),
      Flexible(child: Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -.3))),
    ],
  );
}

/// Radial glows behind the app (Glow's void + violet/orange/cyan wash), here teal and cyan.
class Backdrop extends StatelessWidget {
  const Backdrop({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -1.1),
              radius: 1.1,
              colors: [C.primary.withValues(alpha: .18), Colors.transparent],
            ),
          ),
        ),
      ),
      Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-1.2, 1.2),
              radius: 1.0,
              colors: [C.electric.withValues(alpha: .06), Colors.transparent],
            ),
          ),
        ),
      ),
      child,
    ],
  );
}
