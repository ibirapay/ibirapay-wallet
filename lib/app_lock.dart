// When the wallet is locked. It locks at start, and again when the app comes back after more than [awayFor]; while the app is not in the
// foreground the screen is marked secure so the recents thumbnail is blank. Sensitive actions ask the PIN again through [confirm].
import 'dart:async';

import 'package:flutter/material.dart';

import 'pin.dart';
import 'pin_pad.dart';
import 'seed_backup.dart' show secureScreen;
import 'theme.dart';

/// Who needs the screen blocked from screenshots, recordings and the recents thumbnail. The flag is on while ANY reason is held and goes
/// off only when the last one is released, so two features can never switch each other's protection off.
class SecureHolds {
  SecureHolds(this._apply);
  final Future<void> Function(bool) _apply;
  final _reasons = <String>{};
  bool _applied = false;
  Future<bool>? _switchingOn;

  bool get on => _reasons.isNotEmpty;

  /// Holds the screen protection for [reason] and says whether it is really ON now. A caller that is about to show something secret
  /// waits for this and shows nothing when it is false (a platform call that failed is not protection).
  Future<bool> hold(String reason) {
    _reasons.add(reason);
    if (_applied) return Future.value(true);
    return _switchingOn ??= _switchOn(); // one platform call at a time: later holds wait for the one in flight
  }

  Future<bool> _switchOn() async {
    try {
      await _apply(true);
      _applied = true;
      if (!on) _off(); // everything was released while it was switching on
      return true;
    } catch (_) {
      return false;
    } finally {
      _switchingOn = null;
    }
  }

  void _off() {
    _applied = false;
    _apply(false).catchError((_) {});
  }

  void release(String reason) {
    if (_reasons.remove(reason) && !on && _applied) _off();
  }
}

class AppLock extends ChangeNotifier with WidgetsBindingObserver {
  AppLock({required this.pins, DateTime Function()? now, Future<void> Function(bool)? secure, this.awayFor = const Duration(seconds: 30)})
    : _now = now ?? DateTime.now,
      secure = SecureHolds(secure ?? secureScreen);
  final PinStore pins;
  final Duration awayFor;
  final DateTime Function() _now;

  /// The screen protection: this class holds 'away' while the app is out of the foreground or locked; the words screen holds 'words'.
  final SecureHolds secure;

  bool _locked = false;
  bool _hasPin = false;

  /// How many times the wallet was wiped in this run; the Gate watches it to go back to the welcome screen.
  int wipes = 0;
  DateTime? _pausedAt;
  Completer<void>? _waiter;

  bool get locked => _locked;
  bool get hasPin => _hasPin;

  void attach() => WidgetsBinding.instance.addObserver(this);
  void detach() => WidgetsBinding.instance.removeObserver(this);

  /// Re-reads whether a PIN exists (after setting or clearing it) and, at start, locks when there is one.
  Future<void> refresh({bool lockIfSet = false}) async {
    _hasPin = await pins.has();
    if (lockIfSet && _hasPin) lockNow();
  }

  void lockNow() {
    if (_locked) return;
    _locked = true;
    _waiter ??= Completer<void>();
    notifyListeners();
  }

  void unlock() {
    if (!_locked) return;
    _locked = false;
    _waiter?.complete();
    _waiter = null;
    secure.release('away');
    notifyListeners();
  }

  /// The wallet was just deleted from this device: no PIN, no lock, and whoever watches [wipes] starts over.
  void walletWiped() {
    _hasPin = false;
    wipes++;
    if (_locked) {
      _locked = false;
      _waiter?.complete();
      _waiter = null;
    }
    secure.release('away');
    notifyListeners();
  }

  /// Completes once the wallet is unlocked (at once when it is not locked).
  Future<void> whenUnlocked() => _locked ? (_waiter ??= Completer<void>()).future : Future.value();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_hasPin) return;
    switch (state) {
      case AppLifecycleState.inactive:
        secure.hold('away').ignore(); // before the system takes the recents snapshot
      case AppLifecycleState.hidden || AppLifecycleState.paused:
        _pausedAt ??= _now();
        secure.hold('away').ignore();
      case AppLifecycleState.resumed:
        final since = _pausedAt;
        _pausedAt = null;
        if (since != null && _now().difference(since) > awayFor) {
          lockNow(); // 'away' stays held until the PIN unlocks it
        } else if (!_locked) {
          secure.release('away');
        }
      case AppLifecycleState.detached:
        break;
    }
  }

  /// Asks the PIN on top of everything and says whether it was right. Without a PIN it says no: a lock that is missing opens nothing.
  Future<bool> confirm(BuildContext context, {String? reason}) async {
    if (!await pins.has()) return false;
    if (!context.mounted) return false;
    final ok = await Navigator.of(context, rootNavigator: true).push<bool>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => _ConfirmPage(pins: pins, reason: reason, now: _now, onDead: lockNow)),
    );
    return ok ?? false;
  }
}

class _ConfirmPage extends StatelessWidget {
  const _ConfirmPage({required this.pins, required this.reason, required this.now, required this.onDead});
  final PinStore pins;
  final String? reason;
  final DateTime Function() now;

  /// The PIN is dead: close this page and put the lock screen up, where "Esqueci o PIN" is.
  final VoidCallback onDead;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(backgroundColor: C.surface, leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context, false))),
    body: Backdrop(
      child: SafeArea(
        child: PinVerifyView(
          store: pins,
          subtitle: reason,
          now: now,
          onVerified: () => Navigator.pop(context, true),
          onExhausted: () {
            Navigator.pop(context, false);
            onDead();
          },
        ),
      ),
    ),
  );
}

/// Puts the lock screen ABOVE the whole navigator, so it also covers an open sheet or page; what runs underneath keeps running.
class LockLayer extends StatefulWidget {
  const LockLayer({super.key, required this.lock, required this.child, required this.forgotBuilder});
  final AppLock lock;
  final Widget child;

  /// The "Esqueci o PIN" screen (the wipe flow); [back] returns to the PIN pad.
  final Widget Function(BuildContext context, VoidCallback back) forgotBuilder;
  @override
  State<LockLayer> createState() => _LockLayerState();
}

class _LockLayerState extends State<LockLayer> {
  bool _forgot = false;

  /// The lock screen lives in its own [Overlay]: this layer sits ABOVE the navigator, so it has no overlay of its own to borrow, and
  /// a text field (the APAGAR box of the forgot-PIN screen) cannot exist without one.
  OverlayEntry? _entry;

  void _setForgot(bool v) {
    setState(() => _forgot = v);
    _entry?.markNeedsBuild();
  }

  Widget _content(BuildContext context) => Material(
    color: C.voidBg,
    child: Backdrop(
      child: SafeArea(
        child: _forgot
            ? widget.forgotBuilder(context, () => _setForgot(false))
            : Column(
                children: [
                  Expanded(child: PinVerifyView(store: widget.lock.pins, title: 'Digite o PIN', now: widget.lock._now, onVerified: widget.lock.unlock)),
                  TextButton(onPressed: () => _setForgot(true), child: const Text('Esqueci o PIN', style: TextStyle(color: C.muted))),
                  const SizedBox(height: 8),
                ],
              ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.lock,
    builder: (context, _) {
      if (!widget.lock.locked) {
        _entry = null; // a new session gets a new entry (the old overlay is gone with the screen)
        _forgot = false;
      }
      final entry = widget.lock.locked ? (_entry ??= OverlayEntry(builder: _content)) : null;
      return Stack(
        children: [
          widget.child,
          if (entry != null) Positioned.fill(child: Overlay(key: ObjectKey(entry), initialEntries: [entry])),
        ],
      );
    },
  );
}
