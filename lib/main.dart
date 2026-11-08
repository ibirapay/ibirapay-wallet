// IBIRAPAY Carteira (test build): onboarding (create / restore), connect to Spark, then the home screen.
import 'dart:io';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart' as breez;
import 'package:flutter/material.dart';

import 'app_lock.dart';
import 'delete_wallet_view.dart';
import 'home_page.dart';
import 'pending_sends.dart';
import 'pin.dart';
import 'pin_pad.dart';
import 'secret_store.dart';
import 'spark.dart';
import 'theme.dart';
import 'wallet.dart';
import 'wallet_seed.dart';
import 'wipe.dart';

const _channel = String.fromEnvironment('APP_CHANNEL', defaultValue: 'dev');
const _version = String.fromEnvironment('APP_VERSION', defaultValue: '0.0.0');
const _commit = String.fromEnvironment('APP_COMMIT', defaultValue: 'local');
const _versionLine = 'v$_version-$_channel.$_commit';

/// A wallet connected and ready for the home screen. [sdk] is the Spark handle, left opaque here so a test can fake the connection.
class OpenedWallet {
  const OpenedWallet({required this.wallet, required this.words, required this.sdk});
  final DerivedWallet wallet;
  final List<String> words;
  final Object sdk;
}

typedef WalletOpener = Future<OpenedWallet> Function(List<String> words);
typedef HomeBuilder = Widget Function(BuildContext context, OpenedWallet w, WalletOps ops, AppLock lock);

Future<OpenedWallet> openWithSpark(List<String> words) async {
  final w = await deriveWallet(words);
  final spark = await SparkWallet.open(credential: w.sparkCredential);
  return OpenedWallet(wallet: w, words: words, sdk: spark.sdk);
}

Widget homeWithSpark(BuildContext context, OpenedWallet w, WalletOps ops, AppLock lock) =>
    HomePage(sdk: w.sdk as breez.BreezSdk, wallet: w.wallet, words: w.words, version: _versionLine, lock: lock, ops: ops);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = SecretStore();
  final lock = AppLock(pins: PinStore(store))..attach();
  await lock.refresh(lockIfSet: true); // with a PIN, the lock is up before the first frame
  runApp(
    WalletApp(
      store: store,
      lock: lock,
      ops: WalletOps(
        store: store,
        pins: lock.pins,
        pending: SecretPendingStore(store),
        closeSpark: SparkWallet.close,
        deleteSparkData: () async {
          final d = Directory(await sparkDataDir());
          if (await d.exists()) await d.delete(recursive: true);
        },
      ),
    ),
  );
}

class WalletApp extends StatelessWidget {
  const WalletApp({super.key, required this.store, required this.lock, required this.ops, this.open = openWithSpark, this.home = homeWithSpark});
  final SecretStore store;
  final AppLock lock;
  final WalletOps ops;
  final WalletOpener open;
  final HomeBuilder home;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'IBIRAPAY Carteira',
    theme: appTheme(),
    // the lock screen sits above the whole navigator, so it also covers a sheet or page that was open when the app was left
    builder: (context, child) => LockLayer(
      lock: lock,
      forgotBuilder: (context, back) => DeleteWalletView(ops: ops, onWiped: lock.walletWiped, onBack: back),
      child: child!,
    ),
    home: Gate(store: store, lock: lock, ops: ops, open: open, home: home),
  );
}

class Gate extends StatefulWidget {
  const Gate({super.key, required this.store, required this.lock, required this.ops, required this.open, required this.home});
  final SecretStore store;
  final AppLock lock;
  final WalletOps ops;
  final WalletOpener open;
  final HomeBuilder home;
  @override
  State<Gate> createState() => _GateState();
}

class _GateState extends State<Gate> {
  final _restore = TextEditingController();
  bool _loading = true;
  bool _restoring = false;
  bool _needPin = false;
  String? _error;
  List<String>? _words;
  OpenedWallet? _opened;
  int _seenWipes = 0;

  @override
  void initState() {
    super.initState();
    _seenWipes = widget.lock.wipes;
    widget.lock.addListener(_onLock);
    _load();
  }

  @override
  void dispose() {
    widget.lock.removeListener(_onLock);
    _restore.dispose();
    super.dispose();
  }

  /// The wallet was deleted: back to the welcome screen, with nothing of the old one left in memory.
  void _onLock() {
    if (widget.lock.wipes == _seenWipes) return;
    _seenWipes = widget.lock.wipes;
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    setState(() {
      _opened = null;
      _words = null;
      _error = null;
      _restoring = false;
      _needPin = false;
      _loading = false;
      _restore.clear();
    });
  }

  Future<void> _load() async {
    await widget.lock.refresh();
    if (widget.lock.hasPin) {
      widget.lock.lockNow();
      await widget.lock.whenUnlocked(); // the words are not even read before the PIN
    }
    final saved = await widget.store.read(walletWordsKey);
    if (saved == null) {
      await widget.ops.clearLeftovers();
      await widget.lock.refresh();
      if (mounted) setState(() => _loading = false);
      return;
    }
    final words = saved.split(' ');
    if (!widget.lock.hasPin) {
      // a wallet from before the PIN existed (or one whose PIN step was cut short): it gets its PIN before it opens
      if (mounted) {
        setState(() {
          _words = words;
          _needPin = true;
          _loading = false;
        });
      }
      return;
    }
    await _open(words);
  }

  Future<void> _open(List<String> words) async {
    setState(() {
      _loading = true;
      _error = null;
      _needPin = false;
    });
    try {
      final opened = await widget.open(words);
      if (!mounted) return;
      setState(() {
        _opened = opened;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Não foi possível conectar: $e';
          _loading = false;
          _words = words;
        });
      }
    }
  }

  Future<void> _pinSet() async {
    await widget.lock.refresh();
    await _open(_words!);
  }

  Future<void> _create() async {
    final words = newMnemonic();
    await widget.store.write(walletWordsKey, words.join(' '));
    setState(() {
      _words = words;
      _needPin = true;
    });
  }

  Future<void> _restoreFromWords() async {
    final words = _restore.text.trim().toLowerCase().split(RegExp(r'\s+'));
    if (!validMnemonic(words)) {
      setState(() => _error = 'As palavras não formam uma carteira válida (12 palavras em inglês).');
      return;
    }
    await widget.store.write(walletWordsKey, words.join(' '));
    setState(() {
      _words = words;
      _needPin = true;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final opened = _opened;
    if (opened != null) return widget.home(context, opened, widget.ops, widget.lock);
    return Scaffold(
      body: Backdrop(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: _loading
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ClipRRect(borderRadius: BorderRadius.circular(24), child: Image.asset('assets/logo.png', width: 96, height: 96)),
                        const SizedBox(height: 24),
                        const CircularProgressIndicator(color: C.primaryLight),
                      ],
                    ),
                  )
                : _needPin
                ? PinCreateView(store: widget.lock.pins, title: 'Crie um PIN para proteger a carteira', onDone: _pinSet)
                : _words != null && _error != null
                ? _retry()
                : _restoring
                ? _restoreForm()
                : _welcome(),
          ),
        ),
      ),
    );
  }

  Widget _welcome() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Spacer(),
      Center(child: ClipRRect(borderRadius: BorderRadius.circular(28), child: Image.asset('assets/logo.png', width: 128, height: 128))),
      const SizedBox(height: 24),
      const Text('IBIRAPAY', textAlign: TextAlign.center, style: TextStyle(fontSize: 40, fontWeight: FontWeight.w800, letterSpacing: -1)),
      const Text('Carteira', textAlign: TextAlign.center, style: TextStyle(fontSize: 22, color: C.primaryLight, letterSpacing: 6)),
      const SizedBox(height: 16),
      const Text('Bitcoin pela Lightning, USDT e USDC.\nVocê guarda as chaves.', textAlign: TextAlign.center, style: TextStyle(color: C.textSec, fontSize: 14)),
      const Spacer(),
      if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_error!, style: const TextStyle(color: C.warn, fontSize: 13))),
      GradientButton(label: 'Criar carteira', onPressed: _create),
      const SizedBox(height: 12),
      OutlineButton(label: 'Restaurar com 12 palavras', onPressed: () => setState(() => _restoring = true)),
      const SizedBox(height: 16),
      Text(_versionLine, textAlign: TextAlign.center, style: const TextStyle(color: C.muted, fontSize: 11, fontFamily: monoFamily)),
    ],
  );

  Widget _restoreForm() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(children: [IconButton(onPressed: () => setState(() => _restoring = false), icon: const Icon(Icons.arrow_back))]),
      const SizedBox(height: 8),
      const Text('Restaurar carteira', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
      const SizedBox(height: 16),
      TextField(
        controller: _restore,
        minLines: 4,
        maxLines: 4,
        autocorrect: false,
        enableSuggestions: false,
        style: const TextStyle(fontFamily: monoFamily, fontSize: 15),
        decoration: const InputDecoration(hintText: 'as 12 palavras, separadas por espaço'),
      ),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: C.warn, fontSize: 13))),
      const SizedBox(height: 16),
      GradientButton(label: 'Restaurar', onPressed: _restoreFromWords),
    ],
  );

  Widget _retry() => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Icon(Icons.cloud_off, size: 48, color: C.warn),
      const SizedBox(height: 16),
      Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: C.textSec, fontSize: 13)),
      const SizedBox(height: 20),
      GradientButton(label: 'Tentar de novo', onPressed: () => _open(_words!)),
    ],
  );
}
