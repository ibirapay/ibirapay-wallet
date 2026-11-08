// The PIN screens. The digits come from an on-screen keypad, not the system keyboard: no autocorrect, no keyboard history, and the
// length is free (4 to 8) so there is an OK key instead of submitting at a fixed length.
import 'dart:async';

import 'package:flutter/material.dart';

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

  Widget _key(String id, Widget child, VoidCallback onTap, {Color? color}) => Padding(
    padding: const EdgeInsets.all(6),
    child: Material(
      color: color ?? C.elevated,
      shape: const CircleBorder(),
      child: InkWell(
        key: Key('pin-$id'),
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(width: 68, height: 68, child: Center(child: child)),
      ),
    ),
  );

  Widget _digitKey(String d) => _key(d, Text(d, style: const TextStyle(fontFamily: monoFamily, fontSize: 26, fontWeight: FontWeight.w600)), () => _digit(d));

  @override
  Widget build(BuildContext context) {
    final left = _left;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(widget.title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        if (widget.subtitle != null) ...[
          const SizedBox(height: 8),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: Text(widget.subtitle!, textAlign: TextAlign.center, style: const TextStyle(color: C.textSec, fontSize: 13))),
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
              widget.blocked ?? (left != null ? 'Muitas tentativas. Tente de novo em ${fmtWait(left)}' : (widget.message ?? '')),
              textAlign: TextAlign.center,
              style: const TextStyle(color: C.warn, fontSize: 13),
            ),
          ),
        ),
        Opacity(
          opacity: _can ? 1 : .4,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final row in const [
                ['1', '2', '3'],
                ['4', '5', '6'],
                ['7', '8', '9'],
              ])
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [for (final d in row) _digitKey(d)]),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _key('del', const Icon(Icons.backspace_outlined, color: C.textSec), _del, color: Colors.transparent),
                  _digitKey('0'),
                  _key('ok', Icon(Icons.check, color: _pin.length >= pinMinLength ? Colors.black : C.muted), _ok, color: _pin.length >= pinMinLength ? C.primaryLight : C.elevated),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Asks for the current PIN. [onVerified] runs once it is right.
class PinVerifyView extends StatefulWidget {
  const PinVerifyView({super.key, required this.store, required this.onVerified, this.title = 'Digite o PIN', this.subtitle, this.now, this.onExhausted});
  final PinStore store;
  final VoidCallback onVerified;
  final String title;
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

  static const _deadText = 'PIN bloqueado: foram $pinMaxFails tentativas erradas. Use "Esqueci o PIN" para apagar a carteira deste aparelho e restaurar com as 12 palavras.';

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
          setState(() => _message = triesLeft == 1 ? 'PIN errado. Mais 1 tentativa antes de esperar.' : 'PIN errado. Mais $triesLeft tentativas antes de esperar.');
        case PinWait(:final until):
          setState(() {
            _until = until;
            _message = null;
          });
        case PinExhausted():
          _die();
      }
    } catch (_) {
      if (mounted) setState(() => _message = 'Não consegui ler o PIN guardado neste aparelho.');
    }
  }

  @override
  Widget build(BuildContext context) =>
      PinPad(title: widget.title, subtitle: widget.subtitle, message: _message, waitUntil: _until, now: widget.now, blocked: _dead ? _deadText : null, onSubmit: _submit);
}

/// Sets a new PIN: typed twice. [onDone] runs once it is stored.
class PinCreateView extends StatefulWidget {
  const PinCreateView({super.key, required this.store, required this.onDone, this.title = 'Crie um PIN'});
  final PinStore store;
  final VoidCallback onDone;
  final String title;
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
        _message = 'Os dois PINs são diferentes. Comece de novo.';
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
          _message = 'Não consegui guardar o PIN: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PinPad(
    key: ValueKey(_first == null),
    title: _first == null ? widget.title : 'Repita o PIN',
    subtitle: _first == null ? 'De $pinMinLength a $pinMaxLength números. Você vai usá-lo para abrir o app, enviar e ver as 12 palavras.' : 'Digite o mesmo PIN de novo para confirmar.',
    message: _message,
    onSubmit: _submit,
  );
}
