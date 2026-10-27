import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:local_auth/local_auth.dart';

import 'core.dart';
import 'life.dart';
import 'money.dart';
import 'tools.dart';

const String _kPinHashKey = 'pranaya_pin_hash';
const String _kPinSaltKey = 'pranaya_pin_salt';
const String _kVaultKeyKey = 'pranaya_vault_key';
const String _kFailedAttemptsKey = 'pranaya_failed_attempts';
const String _kLockUntilKey = 'pranaya_lock_until_ms';

const int kMaxFailedAttempts = 5;
const Duration kLockoutDuration = Duration(seconds: 30);
const int _kKdfIterations = 20000;

const FlutterSecureStorage _secure = FlutterSecureStorage();

/// Iterated HMAC-SHA256 over the salt, keyed by the PIN.
Uint8List derivePinHash(String pin, Uint8List salt) {
  final hmac = Hmac(sha256, utf8.encode(pin));
  var block = Uint8List.fromList(salt);
  for (var i = 0; i < _kKdfIterations; i++) {
    block = Uint8List.fromList(hmac.convert(block).bytes);
  }
  return block;
}

bool _constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

class Vault {
  static Future<Box> open() async {
    if (Hive.isBoxOpen(kVaultBoxName)) return Hive.box(kVaultBoxName);
    var keyB64 = await _secure.read(key: _kVaultKeyKey);
    if (keyB64 == null) {
      final key = Hive.generateSecureKey();
      keyB64 = base64UrlEncode(key);
      await _secure.write(key: _kVaultKeyKey, value: keyB64);
    }
    return Hive.openBox(
      kVaultBoxName,
      encryptionCipher: HiveAesCipher(base64Url.decode(keyB64)),
    );
  }

  static Future<void> close() async {
    if (Hive.isBoxOpen(kVaultBoxName)) {
      await Hive.box(kVaultBoxName).close();
    }
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  runApp(const PranayaApp());
}

class PranayaApp extends StatefulWidget {
  const PranayaApp({super.key});

  @override
  State<PranayaApp> createState() => _PranayaAppState();
}

class _PranayaAppState extends State<PranayaApp> {
  bool _isDark = true;

  void _toggleTheme() => setState(() => _isDark = !_isDark);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pranaya',
      debugShowCheckedModeBanner: false,
      themeMode: _isDark ? ThemeMode.dark : ThemeMode.light,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0D0D0D),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00FF66),
          secondary: Color(0xFF00E5FF),
          surface: Color(0xFF1A1A1A),
        ),
      ),
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF5F5F5),
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF00AA44),
          secondary: Color(0xFF0091EA),
          surface: Color(0xFFFFFFFF),
        ),
      ),
      home: AuthGate(onThemeToggle: _toggleTheme),
    );
  }
}

class AuthGate extends StatefulWidget {
  final VoidCallback onThemeToggle;
  const AuthGate({super.key, required this.onThemeToggle});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late Future<bool> _hasPin;

  @override
  void initState() {
    super.initState();
    _hasPin = _readHasPin();
  }

  Future<bool> _readHasPin() async =>
      (await _secure.read(key: _kPinHashKey)) != null;

  void _onReady() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => HomeShell(onThemeToggle: widget.onThemeToggle),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _hasPin,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return snapshot.data!
            ? PinUnlockScreen(onUnlocked: _onReady)
            : PinSetupScreen(onConfigured: _onReady);
      },
    );
  }
}

class PinSetupScreen extends StatefulWidget {
  final VoidCallback onConfigured;
  const PinSetupScreen({super.key, required this.onConfigured});

  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen> {
  final TextEditingController _pin = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  String _error = '';
  bool _busy = false;

  Future<void> _save() async {
    final pin = _pin.text.trim();
    if (pin.length < 4 || pin.length > 6) {
      setState(() => _error = 'MPIN must be 4 to 6 digits.');
      return;
    }
    if (pin != _confirm.text.trim()) {
      setState(() => _error = 'The two entries do not match.');
      return;
    }
    setState(() {
      _busy = true;
      _error = '';
    });
    final salt = Hive.generateSecureKey();
    final digest = derivePinHash(pin, Uint8List.fromList(salt));
    await _secure.write(key: _kPinSaltKey, value: base64Encode(salt));
    await _secure.write(key: _kPinHashKey, value: base64Encode(digest));
    await _secure.write(key: _kFailedAttemptsKey, value: '0');
    await Vault.open();
    if (!mounted) return;
    widget.onConfigured();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'SET YOUR MPIN',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 3,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'This protects everything on this device. There is no server-side reset.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 28),
              TextField(
                controller: _pin,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                decoration: const InputDecoration(
                  counterText: '',
                  hintText: 'NEW MPIN',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _confirm,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                decoration: const InputDecoration(
                  counterText: '',
                  hintText: 'CONFIRM MPIN',
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _busy ? null : _save,
                child: Text(_busy ? 'DERIVING KEY...' : 'CREATE VAULT KEY'),
              ),
              if (_error.isNotEmpty) ...<Widget>[
                const SizedBox(height: 16),
                Text(
                  _error,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class PinUnlockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;
  const PinUnlockScreen({super.key, required this.onUnlocked});

  @override
  State<PinUnlockScreen> createState() => _PinUnlockScreenState();
}

class _PinUnlockScreenState extends State<PinUnlockScreen> {
  final LocalAuthentication _auth = LocalAuthentication();
  final TextEditingController _mpin = TextEditingController();
  String _error = '';
  bool _busy = false;

  Future<int> _failedAttempts() async =>
      int.tryParse(await _secure.read(key: _kFailedAttemptsKey) ?? '0') ?? 0;

  Future<int> _lockUntil() async =>
      int.tryParse(await _secure.read(key: _kLockUntilKey) ?? '0') ?? 0;

  Future<void> _registerFailure() async {
    final attempts = (await _failedAttempts()) + 1;
    await _secure.write(key: _kFailedAttemptsKey, value: '$attempts');
    if (attempts >= kMaxFailedAttempts) {
      final until = DateTime.now().add(kLockoutDuration).millisecondsSinceEpoch;
      await _secure.write(key: _kLockUntilKey, value: '$until');
      await _secure.write(key: _kFailedAttemptsKey, value: '0');
      if (!mounted) return;
      setState(() => _error = 'Too many attempts. Wait 30 seconds.');
      return;
    }
    if (!mounted) return;
    setState(() {
      _error = 'Incorrect MPIN. ${kMaxFailedAttempts - attempts} left.';
    });
  }

  Future<void> _verifyPin() async {
    if (_busy) return;
    final waitMs = await _lockUntil();
    if (DateTime.now().millisecondsSinceEpoch < waitMs) {
      setState(() => _error = 'Locked out. Try again shortly.');
      return;
    }
    final pin = _mpin.text.trim();
    if (pin.isEmpty) return;
    final saltB64 = await _secure.read(key: _kPinSaltKey);
    final storedB64 = await _secure.read(key: _kPinHashKey);
    if (saltB64 == null || storedB64 == null) {
      setState(() => _error = 'Vault metadata missing on this device.');
      return;
    }
    setState(() {
      _busy = true;
      _error = '';
    });
    final candidate = derivePinHash(
      pin,
      Uint8List.fromList(base64Decode(saltB64)),
    );
    final ok = _constantTimeEquals(candidate, base64Decode(storedB64));
    _mpin.clear();
    if (ok) {
      await _secure.write(key: _kFailedAttemptsKey, value: '0');
      await _secure.delete(key: _kLockUntilKey);
      await Vault.open();
      if (!mounted) return;
      widget.onUnlocked();
    } else {
      setState(() => _busy = false);
      await _registerFailure();
    }
  }

  Future<void> _verifyBiometric() async {
    try {
      if (!await _auth.canCheckBiometrics) {
        setState(() => _error = 'No biometrics enrolled on this device.');
        return;
      }
      final ok = await _auth.authenticate(
        localizedReason: 'Unlock the Pranaya vault',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );
      if (!ok) return;
      await Vault.open();
      if (!mounted) return;
      widget.onUnlocked();
    } catch (_) {
      setState(() => _error = 'Biometric error.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'PRANAYA',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 4,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Local-first life ledger',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 36),
              TextField(
                controller: _mpin,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  letterSpacing: 8,
                  fontWeight: FontWeight.bold,
                ),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: 'ENTER MPIN',
                  hintStyle: const TextStyle(fontSize: 14, letterSpacing: 2),
                  filled: true,
                  fillColor: theme.colorScheme.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _busy ? null : _verifyPin,
                child: Text(_busy ? 'VERIFYING...' : 'UNLOCK VAULT'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _busy ? null : _verifyBiometric,
                icon: const Icon(Icons.fingerprint),
                label: const Text('USE BIOMETRICS'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: BorderSide(color: theme.colorScheme.secondary),
                ),
              ),
              if (_error.isNotEmpty) ...<Widget>[
                const SizedBox(height: 20),
                Text(
                  _error,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class HomeShell extends StatefulWidget {
  final VoidCallback onThemeToggle;
  const HomeShell({super.key, required this.onThemeToggle});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _tab = 0;
  late Repo _repo;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _repo = Repo(Hive.box(kVaultBoxName));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _lock();
    }
  }

  Future<void> _lock() async {
    await Vault.close();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => AuthGate(onThemeToggle: widget.onThemeToggle),
      ),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tabs = <Widget>[
      MoneyTab(repo: _repo),
      BodyTab(repo: _repo),
      MindTab(repo: _repo),
      TimeTab(repo: _repo),
      ToolsTab(repo: _repo),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'PRANAYA',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2),
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: <Widget>[
          IconButton(
            onPressed: widget.onThemeToggle,
            icon: const Icon(Icons.palette_outlined),
          ),
          IconButton(
            tooltip: 'Lock',
            onPressed: _lock,
            icon: const Icon(Icons.lock_outline),
          ),
        ],
      ),
      body: IndexedStack(index: _tab, children: tabs),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tab,
        type: BottomNavigationBarType.fixed,
        backgroundColor: theme.colorScheme.surface,
        selectedItemColor: theme.colorScheme.primary,
        unselectedItemColor: Colors.grey,
        onTap: (i) => setState(() => _tab = i),
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.account_balance_wallet),
            label: 'Money',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.favorite_border),
            label: 'Body',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.self_improvement),
            label: 'Mind',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.checklist),
            label: 'Time',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.handyman_outlined),
            label: 'Tools',
          ),
        ],
      ),
    );
  }
}
