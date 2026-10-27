// PRANAYA - local-first encrypted ledger.
//
// Security model, in one paragraph: the vault is a Hive box encrypted with a
// key held in the platform keystore (flutter_secure_storage). That key is only
// used after the user authenticates, and the box is closed again on lock or
// when the app goes to the background. The MPIN is never stored or compared in
// plaintext - only a salted, iterated HMAC-SHA256 digest is kept, compared in
// constant time, with a persisted failure counter and cooldown.

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:local_auth/local_auth.dart';

const String kVaultBoxName = 'pranaya_local_vault';
const String _kPinHashKey = 'pranaya_pin_hash';
const String _kPinSaltKey = 'pranaya_pin_salt';
const String _kVaultKeyKey = 'pranaya_vault_key';
const String _kFailedAttemptsKey = 'pranaya_failed_attempts';
const String _kLockUntilKey = 'pranaya_lock_until_ms';

const int kMaxFailedAttempts = 5;
const Duration kLockoutDuration = Duration(seconds: 30);
const int _kKdfIterations = 20000;

const FlutterSecureStorage _secure = FlutterSecureStorage();

/// Iterated HMAC-SHA256 over the salt, keyed by the PIN. Deliberately slow.
/// In a hardened build, replace with a native KDF (argon2 / PBKDF2 via
/// pointycastle) - pure-Dart iteration is a cost compromise, not best practice.
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
  // Intentionally NOT opening the vault here: the encryption key must not be
  // usable until the user has authenticated.
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

/// Decides between first-run MPIN setup and normal unlock.
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
      MaterialPageRoute(
        builder: (_) => MainDashboard(onThemeToggle: widget.onThemeToggle),
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

/// First run only: user chooses their own MPIN.
class PinSetupScreen extends StatefulWidget {
  final VoidCallback onConfigured;
  const PinSetupScreen({super.key, required this.onConfigured});

  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen> {
  final _pin = TextEditingController();
  final _confirm = TextEditingController();
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
            children: [
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
                'This protects your vault on this device. There is no server-side reset.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 32),
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
              if (_error.isNotEmpty) ...[
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

/// Normal unlock: MPIN or biometric, with attempt limiting.
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
      setState(
        () =>
            _error = 'Too many attempts. Wait ${kLockoutDuration.inSeconds}s.',
      );
      return;
    }
    setState(
      () => _error =
          'Incorrect MPIN. ${kMaxFailedAttempts - attempts} attempt(s) left.',
    );
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
        setState(
          () => _error = 'No biometric hardware enrolled on this device.',
        );
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
            children: [
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
              const SizedBox(height: 8),
              const Text(
                'Universal Life Interface Engine',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 40),
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
              if (_error.isNotEmpty) ...[
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

class MainDashboard extends StatefulWidget {
  final VoidCallback onThemeToggle;
  const MainDashboard({super.key, required this.onThemeToggle});

  @override
  State<MainDashboard> createState() => _MainDashboardState();
}

class _MainDashboardState extends State<MainDashboard>
    with WidgetsBindingObserver {
  late Box _vault;
  final TextEditingController _input = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _vault = Hive.box(kVaultBoxName);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _input.dispose();
    super.dispose();
  }

  /// Re-lock whenever the app leaves the foreground: closes the encrypted box
  /// so the key is not sitting in memory behind a stale screen.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _lockAndExit();
    }
  }

  Future<void> _lockAndExit() async {
    await Vault.close();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => AuthGate(onThemeToggle: widget.onThemeToggle),
      ),
      (_) => false,
    );
  }

  void _commit() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    final ts = DateTime.now().millisecondsSinceEpoch;
    final entry = {
      'id': 'entry_$ts',
      'raw_string': text,
      'timestamp': ts,
      'inferred_category': 'Manual Input',
    };
    _vault.put(entry['id'], jsonEncode(entry));
    _input.clear();
    setState(() {});
  }

  void _delete(String key) {
    _vault.delete(key);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = _vault.values.toList().reversed.toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'PRANAYA CORE',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2),
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            onPressed: widget.onThemeToggle,
            icon: const Icon(Icons.palette_outlined),
          ),
          IconButton(
            tooltip: 'Lock vault',
            onPressed: _lockAndExit,
            icon: const Icon(Icons.lock_outline),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    decoration: InputDecoration(
                      hintText: 'Log an expense or note...',
                      filled: true,
                      fillColor: theme.colorScheme.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (_) => _commit(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _commit,
                  icon: const Icon(Icons.arrow_upward),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: items.isEmpty
                  ? const Center(child: Text('No entries yet.'))
                  : ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = jsonDecode(
                          items[index] as String,
                        ) as Map<String, dynamic>;
                        return Card(
                          color: theme.colorScheme.surface,
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListTile(
                            title: Text(
                              item['raw_string'] as String? ?? '',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              '${item['inferred_category']} - ${item['id']}',
                              style: const TextStyle(fontSize: 11),
                            ),
                            trailing: IconButton(
                              icon: const Icon(
                                Icons.delete_outline,
                                color: Colors.redAccent,
                              ),
                              onPressed: () => _delete(item['id'] as String),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
