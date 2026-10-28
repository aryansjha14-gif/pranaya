import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:local_auth/local_auth.dart';

import 'body.dart';
import 'core.dart';
import 'doctor.dart';
import 'mind.dart';
import 'money.dart';
import 'notify.dart';
import 'time.dart';
import 'tools.dart';

const String _kPinHashKey = 'pranaya_pin_hash';
const String _kPinSaltKey = 'pranaya_pin_salt';
const String _kVaultKeyKey = 'pranaya_vault_key';
const String _kFailedAttemptsKey = 'pranaya_failed_attempts';
const String _kLockUntilKey = 'pranaya_lock_until_ms';

const int kMaxFailedAttempts = 5;
const int _kKdfIterations = 20000;

const FlutterSecureStorage _secure = FlutterSecureStorage();

const List<Color> kAccents = <Color>[
  Color(0xFF00E676),
  Color(0xFF7C4DFF),
  Color(0xFF00B0FF),
  Color(0xFFFF6D00),
  Color(0xFFFF4081),
];

const List<IconData> kLogos = <IconData>[
  Icons.all_inclusive,
  Icons.bolt,
  Icons.spa,
  Icons.hexagon_outlined,
  Icons.auto_awesome,
];

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
  await Notifier.instance.init();
  runApp(const PranayaApp());
}

class PranayaApp extends StatefulWidget {
  const PranayaApp({super.key});

  @override
  State<PranayaApp> createState() => _PranayaAppState();
}

class _PranayaAppState extends State<PranayaApp> {
  bool _dark = true;
  int _accent = 0;
  int _logo = 0;

  ThemeData _theme(Brightness brightness) {
    final accent = kAccents[_accent];
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme.copyWith(
        primary: brightness == Brightness.dark ? accent : scheme.primary,
        surface: brightness == Brightness.dark
            ? const Color(0xFF15171C)
            : Colors.white,
      ),
      scaffoldBackgroundColor: brightness == Brightness.dark
          ? const Color(0xFF0B0D12)
          : const Color(0xFFF4F5F9),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: brightness == Brightness.dark
            ? Colors.white.withOpacity(0.05)
            : Colors.black.withOpacity(0.04),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        isDense: true,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pranaya',
      debugShowCheckedModeBanner: false,
      themeMode: _dark ? ThemeMode.dark : ThemeMode.light,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: AuthGate(
        onSettingsChanged: (dark, accent, logo) {
          setState(() {
            _dark = dark;
            _accent = accent;
            _logo = logo;
          });
        },
        logo: _logo,
        dark: _dark,
        accent: _accent,
      ),
    );
  }
}

class AuthGate extends StatefulWidget {
  final void Function(bool dark, int accent, int logo) onSettingsChanged;
  final int logo;
  final bool dark;
  final int accent;
  const AuthGate({
    super.key,
    required this.onSettingsChanged,
    required this.logo,
    required this.dark,
    required this.accent,
  });

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
        builder: (_) => HomeShell(
          onSettingsChanged: widget.onSettingsChanged,
          logo: widget.logo,
          dark: widget.dark,
          accent: widget.accent,
        ),
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
            ? PinUnlockScreen(onUnlocked: _onReady, logo: widget.logo)
            : PinSetupScreen(onConfigured: _onReady, logo: widget.logo);
      },
    );
  }
}

class BrandMark extends StatelessWidget {
  final int logo;
  final double size;
  const BrandMark({super.key, required this.logo, this.size = 84});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = kLogos[logo % kLogos.length];
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.32),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            theme.colorScheme.primary,
            theme.colorScheme.primary.withOpacity(0.45),
          ],
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: theme.colorScheme.primary.withOpacity(0.35),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Icon(icon, size: size * 0.5, color: Colors.black87),
    );
  }
}

class PinSetupScreen extends StatefulWidget {
  final VoidCallback onConfigured;
  final int logo;
  const PinSetupScreen({
    super.key,
    required this.onConfigured,
    required this.logo,
  });

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
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: <Widget>[
            const SizedBox(height: 40),
            Center(child: BrandMark(logo: widget.logo)),
            const SizedBox(height: 22),
            const Text(
              'Pranaya',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              'Private ledger for money, body and mind',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 34),
            TextField(
              controller: _pin,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, letterSpacing: 8),
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
              style: const TextStyle(fontSize: 22, letterSpacing: 8),
              decoration: const InputDecoration(
                counterText: '',
                hintText: 'CONFIRM MPIN',
              ),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(_busy ? 'Creating vault...' : 'Create vault'),
            ),
            if (_error.isNotEmpty) ...<Widget>[
              const SizedBox(height: 14),
              Text(
                _error,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class PinUnlockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;
  final int logo;
  const PinUnlockScreen({
    super.key,
    required this.onUnlocked,
    required this.logo,
  });

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
      final until = DateTime.now()
          .add(const Duration(seconds: 30))
          .millisecondsSinceEpoch;
      await _secure.write(key: _kLockUntilKey, value: '$until');
      await _secure.write(key: _kFailedAttemptsKey, value: '0');
      if (!mounted) return;
      setState(() => _error = 'Too many attempts. Wait 30 seconds.');
      return;
    }
    if (!mounted) return;
    setState(() {
      _error = 'Wrong MPIN. ${kMaxFailedAttempts - attempts} left.';
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
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: <Widget>[
            const SizedBox(height: 50),
            Center(child: BrandMark(logo: widget.logo)),
            const SizedBox(height: 22),
            const Text(
              'Pranaya',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 34),
            TextField(
              controller: _mpin,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, letterSpacing: 8),
              decoration: const InputDecoration(
                counterText: '',
                hintText: 'ENTER MPIN',
              ),
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _busy ? null : _verifyPin,
              child: Text(_busy ? 'Checking...' : 'Unlock'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _busy ? null : _verifyBiometric,
              icon: const Icon(Icons.fingerprint),
              label: const Text('Use fingerprint'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            if (_error.isNotEmpty) ...<Widget>[
              const SizedBox(height: 18),
              Text(
                _error,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class HomeShell extends StatefulWidget {
  final void Function(bool dark, int accent, int logo) onSettingsChanged;
  final int logo;
  final bool dark;
  final int accent;
  const HomeShell({
    super.key,
    required this.onSettingsChanged,
    required this.logo,
    required this.dark,
    required this.accent,
  });

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
        builder: (_) => AuthGate(
          onSettingsChanged: widget.onSettingsChanged,
          logo: widget.logo,
          dark: widget.dark,
          accent: widget.accent,
        ),
      ),
      (_) => false,
    );
  }

  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheet) {
            final theme = Theme.of(context);
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'Appearance',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: <Widget>[
                      const Text('Dark mode'),
                      const Spacer(),
                      Switch(
                        value: widget.dark,
                        onChanged: (v) {
                          widget.onSettingsChanged(
                              v, widget.accent, widget.logo);
                          setSheet(() {});
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text('Accent colour'),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 12,
                    children: List<Widget>.generate(kAccents.length, (i) {
                      return GestureDetector(
                        onTap: () {
                          widget.onSettingsChanged(
                              widget.dark, i, widget.logo);
                          setSheet(() {});
                        },
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: kAccents[i],
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: i == widget.accent
                                  ? theme.colorScheme.onSurface
                                  : Colors.transparent,
                              width: 3,
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 18),
                  const Text('Logo style'),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 12,
                    children: List<Widget>.generate(kLogos.length, (i) {
                      return GestureDetector(
                        onTap: () {
                          widget.onSettingsChanged(
                              widget.dark, widget.accent, i);
                          setSheet(() {});
                        },
                        child: Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: i == widget.logo
                                ? theme.colorScheme.primary.withOpacity(0.2)
                                : theme.colorScheme.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: i == widget.logo
                                  ? theme.colorScheme.primary
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: Icon(kLogos[i]),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed: () {
                        Navigator.pop(context);
                        _lock();
                      },
                      icon: const Icon(Icons.lock_outline),
                      label: const Text('Lock the vault'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
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
      DoctorTab(repo: _repo),
      ToolsTab(repo: _repo),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: <Widget>[
            BrandMark(logo: widget.logo, size: 34),
            const SizedBox(width: 10),
            const Text(
              'Pranaya',
              style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.4),
            ),
          ],
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Appearance',
            onPressed: _openSettings,
            icon: const Icon(Icons.tune),
          ),
          IconButton(
            tooltip: 'Lock',
            onPressed: _lock,
            icon: const Icon(Icons.lock_outline),
          ),
        ],
      ),
      body: IndexedStack(index: _tab, children: tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        backgroundColor: theme.colorScheme.surface,
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet),
            label: 'Money',
          ),
          NavigationDestination(
            icon: Icon(Icons.favorite_border),
            selectedIcon: Icon(Icons.favorite),
            label: 'Body',
          ),
          NavigationDestination(
            icon: Icon(Icons.self_improvement_outlined),
            selectedIcon: Icon(Icons.self_improvement),
            label: 'Mind',
          ),
          NavigationDestination(
            icon: Icon(Icons.checklist_outlined),
            selectedIcon: Icon(Icons.checklist),
            label: 'Time',
          ),
          NavigationDestination(
            icon: Icon(Icons.medical_services_outlined),
            selectedIcon: Icon(Icons.medical_services),
            label: 'Doctor',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view),
            label: 'Tools',
          ),
        ],
      ),
    );
  }
}
