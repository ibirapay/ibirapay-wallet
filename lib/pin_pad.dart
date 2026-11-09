// The PIN screens. The digits come from an on-screen keypad, not the system keyboard: no autocorrect, no keyboard history, and the
// length is free (4 to 8) so there is an OK key instead of submitting at a fixed length.
import 'dart:async';
import 'dart:math' show min;

import 'package:flutter/material.dart';

import 'i18n.dart';
import 'pin.dart';
import 'theme.dart';

String fmtWait(Duration d) {
  final s = d.inSeconds + (d.inMilliseconds % 1000 > 0 ? 1 : 0);
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s % 60)}' : '${two(m)}:${two(s % 60)}';
}

class PinPad extends StatefulWidget {
  const PinPad({super.key, required this.title, required this.onSubmit, this.subtitle, this.message, this.waitUntil, this.now, this.blocked});
  final String title;
  final String? subtitle;

  /// A line under the dots (what went wrong).
  final String? message;

  /// While this is in the future the keys are off and the time left is shown.
  final DateTime? waitUntil;

  /// Not null: the keys are off for good and this is shown (the PIN is dead; see [pinMaxFails]).
  final String? blocked;
  final DateTime Function()? now;

  /// The digits typed, when OK is pressed. The pad clears itself first, so a wrong try starts blank.
  final Future<void> Function(String pin) onSubmit;
  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> {
  String _pin = '';
  bool _busy = false;
  Timer? _tick;

  DateTime _now() => (widget.now ?? DateTime.now)();
  Duration? get _left {
    final u = widget.waitUntil;
    return u != null && u.isAfter(_now()) ? u.difference(_now()) : null;
  }

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.waitUntil != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  bool get _can => !_busy && _left == null && widget.blocked == null;

  void _digit(String d) {
    if (_can && _pin.length < pinMaxLength) setState(() => _pin += d);
  }

  void _del() {
    if (_can && _pin.isNotEmpty) setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _ok() async {
    if (!_can || _pin.length < pinMinLength) return;
    final p = _pin;
    setState(() {
      _busy = true;
      _pin = '';
    });
    try {
      await widget.onSubmit(p);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// One round key of [size] dp: the keypad cell hands every key the biggest circle that fits.
  Widget _key(String id, Widget child, VoidCallback onTap, double size, {Color? color}) => Material(
    color: color ?? C.elevated,
    shape: const CircleBorder(),
    child: InkWell(
      key: Key('pin-$id'),
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: SizedBox(width: size, height: size, child: Center(child: child)),
    ),
  );

  Widget _digitKey(String d, double size) =>
      _key(d, Text(d, style: TextStyle(fontFamily: monoFamily, fontSize: size * .38, fontWeight: FontWeight.w600)), () => _digit(d), size);

  /// 4 rows by 3 columns. Each key is as big as the room under the dots allows, up to [_maxKey] dp (between the old 68 and a
  /// screen-filling pad: that was too big), with [_keyGap] dp between keys; the block sits in the middle of the free room.
  Widget _keypad() => LayoutBuilder(
    builder: (context, box) {
      final size = (min(box.maxWidth / 3, box.maxHeight / 4) - _keyGap).clamp(44.0, _maxKey);
      Widget cell(Widget key) => Padding(padding: const EdgeInsets.all(_keyGap / 2), child: key);
      Widget row(List<Widget> keys) => Row(mainAxisSize: MainAxisSize.min, children: [for (final k in keys) cell(k)]);
      return Center(
        child: Opacity(
          opacity: _can ? 1 : .4,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final r in const [
                ['1', '2', '3'],
                ['4', '5', '6'],
                ['7', '8', '9'],
              ])
                row([for (final d in r) _digitKey(d, size)]),
              row([
                _key('del', Icon(Icons.backspace_outlined, color: C.textSec, size: size * .36), _del, size, color: Colors.transparent),
                _digitKey('0', size),
                _key('ok', Icon(Icons.check, size: size * .4, color: _pin.length >= pinMinLength ? Colors.black : C.muted), _ok, size, color: _pin.length >= pinMinLength ? C.primaryLight : C.elevated),
              ]),
            ],
          ),
        ),
      );
    },
  );

  static const _keyGap = 12.0;
  static const _maxKey = 88.0;

  @override
  Widget build(BuildContext context) {
    final left = _left;
    // a small frame (12 dp) on the sides and the top; the keypad takes everything else
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Column(
        children: [
          Text(widget.title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          if (widget.subtitle != null) ...[
            const SizedBox(height: 8),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text(widget.subtitle!, textAlign: TextAlign.center, style: const TextStyle(color: C.textSec, fontSize: 13))),
          ],
          const SizedBox(height: 20),
          Row(
            key: const Key('pin-dots'),
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < (_pin.length < pinMinLength ? pinMinLength : _pin.length); i++)
                Container(
                  width: 14,
                  height: 14,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(shape: BoxShape.circle, color: i < _pin.length ? C.primaryLight : Colors.transparent, border: Border.all(color: C.primaryLight, width: 1.5)),
                ),
            ],
          ),
          SizedBox(
            height: widget.blocked != null ? 96 : 52,
            child: Center(
              child: Text(
                widget.blocked ?? (left != null ? tr('pin.wait', {'time': fmtWait(left)}) : (widget.message ?? '')),
                textAlign: TextAlign.center,
                style: const TextStyle(color: C.warn, fontSize: 13),
              ),
            ),
          ),
          Expanded(child: _keypad()),
        ],
      ),
    );
  }
}

/// Asks for the current PIN. [onVerified] runs once it is right.
class PinVerifyView extends StatefulWidget {
  const PinVerifyView({super.key, required this.store, required this.onVerified, this.title, this.subtitle, this.now, this.onExhausted});
  final PinStore store;
  final VoidCallback onVerified;
  final String? title;
  final String? subtitle;
  final DateTime Function()? now;

  /// Runs when the PIN is found dead (too many wrong tries): the caller leads the user to "Esqueci o PIN".
  final VoidCallback? onExhausted;
  @override
  State<PinVerifyView> createState() => _PinVerifyViewState();
}

class _PinVerifyViewState extends State<PinVerifyView> {
  String? _message;
  DateTime? _until;
  bool _dead = false;

  String get _deadText => tr('pin.dead', {'n': pinMaxFails});

  void _die() {
    setState(() => _dead = true);
    widget.onExhausted?.call();
  }

  @override
  void initState() {
    super.initState();
    // a wait that started before the app was closed is still running, and a PIN that died stays dead
    widget.store.exhausted().then((dead) {
      if (mounted && dead) _die();
    }, onError: (_) {});
    widget.store.waitingUntil().then((u) {
      if (mounted && u != null) setState(() => _until = u);
    }, onError: (_) {});
  }

  Future<void> _submit(String pin) async {
    try {
      final r = await widget.store.verify(pin);
      if (!mounted) return;
      switch (r) {
        case PinOk():
          widget.onVerified();
        case PinWrong(:final triesLeft):
          setState(() => _message = triesLeft == 1 ? tr('pin.wrong1') : tr('pin.wrongN', {'n': triesLeft}));
        case PinWait(:final until):
          setState(() {
            _until = until;
            _message = null;
          });
        case PinExhausted():
          _die();
      }
    } catch (_) {
      if (mounted) setState(() => _message = tr('pin.unreadable'));
    }
  }

  @override
  Widget build(BuildContext context) =>
      PinPad(title: widget.title ?? tr('pin.enter'), subtitle: widget.subtitle, message: _message, waitUntil: _until, now: widget.now, blocked: _dead ? _deadText : null, onSubmit: _submit);
}

/// Sets a new PIN: typed twice. [onDone] runs once it is stored.
class PinCreateView extends StatefulWidget {
  const PinCreateView({super.key, required this.store, required this.onDone, this.title});
  final PinStore store;
  final VoidCallback onDone;
  final String? title;
  @override
  State<PinCreateView> createState() => _PinCreateViewState();
}

class _PinCreateViewState extends State<PinCreateView> {
  String? _first;
  String? _message;

  Future<void> _submit(String pin) async {
    final first = _first;
    if (first == null) {
      final problem = pinProblem(pin);
      setState(() => _message = problem);
      if (problem == null) setState(() => _first = pin);
      return;
    }
    if (pin != first) {
      setState(() {
        _first = null;
        _message = tr('pin.mismatch');
      });
      return;
    }
    try {
      await widget.store.set(pin);
      if (mounted) widget.onDone();
    } catch (e) {
      if (mounted) {
        setState(() {
          _first = null;
          _message = tr('pin.cannotSave', {'e': e});
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PinPad(
    key: ValueKey(_first == null),
    title: _first == null ? (widget.title ?? tr('pin.create')) : tr('pin.repeat'),
    subtitle: _first == null ? tr('pin.createHint', {'min': pinMinLength, 'max': pinMaxLength}) : tr('pin.repeatHint'),
    message: _message,
    onSubmit: _submit,
  );
}
