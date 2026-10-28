import 'dart:async';

import 'package:flutter/material.dart';

import 'core.dart';
import 'notify.dart';

class BodyTab extends StatefulWidget {
  final Repo repo;
  const BodyTab({super.key, required this.repo});

  @override
  State<BodyTab> createState() => _BodyTabState();
}

class _BodyTabState extends State<BodyTab> {
  final TextEditingController _ml = TextEditingController();
  final TextEditingController _sleep = TextEditingController();
  final TextEditingController _weight = TextEditingController();
  final TextEditingController _height = TextEditingController();
  final TextEditingController _med = TextEditingController();
  final TextEditingController _sugar = TextEditingController();
  final TextEditingController _sys = TextEditingController();
  final TextEditingController _dia = TextEditingController();

  Timer? _breakTimer;
  int _breakSeconds = 0;

  Repo get repo => widget.repo;

  @override
  void dispose() {
    _breakTimer?.cancel();
    super.dispose();
  }

  double get _waterToday {
    final now = DateTime.now().millisecondsSinceEpoch;
    var total = 0.0;
    for (final w in repo.list('water')) {
      if (sameDay((w['ts'] as num).toInt(), now)) {
        total += (w['ml'] as num).toDouble();
      }
    }
    return total;
  }

  void _addWater(double ml) {
    repo.add('water', <String, dynamic>{'ml': ml});
    setState(() {});
  }

  void _startBreakTimer() {
    _breakTimer?.cancel();
    setState(() => _breakSeconds = 20 * 60);
    _breakTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _breakSeconds--;
        if (_breakSeconds <= 0) {
          t.cancel();
          _breakSeconds = 0;
        }
      });
      if (_breakSeconds == 0) {
        Notifier.instance.showNow(
          7100,
          'Look away for 20 seconds',
          'Twenty minutes of screen time is done.',
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final goal = repo.number('water_goal');
    final progress = goal <= 0 ? 0.0 : (_waterToday / goal).clamp(0.0, 1.0);
    final sleeps = repo.list('sleep');
    final weights = repo.list('weight');
    final meds = repo.list('med');
    final sugars = repo.list('sugar');
    final bps = repo.list('bp');
    final height = repo.number('height_cm');
    final latestWeight =
        weights.isEmpty ? 0.0 : (weights.first['kg'] as num).toDouble();
    final bmi = (height > 0 && latestWeight > 0)
        ? latestWeight / ((height / 100) * (height / 100))
        : 0.0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: <Widget>[
        SectionCard(
          title: 'WATER',
          icon: Icons.water_drop_outlined,
          subtitle: goal <= 0
              ? 'Set a daily goal below.'
              : '${_waterToday.toStringAsFixed(0)} of ${goal.toStringAsFixed(0)} ml',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 10,
                  backgroundColor:
                      Theme.of(context).colorScheme.onSurface.withOpacity(0.08),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  FilledButton.tonal(
                    onPressed: () => _addWater(250),
                    child: const Text('+250 ml'),
                  ),
                  FilledButton.tonal(
                    onPressed: () => _addWater(500),
                    child: const Text('+500 ml'),
                  ),
                  OutlinedButton(
                    onPressed: () {
                      scheduleReminder(
                        key: 'water',
                        title: 'Drink water',
                        body: 'Time for a glass of water.',
                        time: const TimeOfDay(hour: 11, minute: 0),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Daily 11 am reminder set.')),
                      );
                    },
                    child: const Text('Remind me'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _ml,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(hintText: 'Goal in ml'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      final v = double.tryParse(_ml.text.trim());
                      if (v == null) return;
                      repo.setNumber('water_goal', v);
                      _ml.clear();
                      setState(() {});
                    },
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
        SectionCard(
          title: 'WEIGHT AND BMI',
          icon: Icons.monitor_weight_outlined,
          subtitle: bmi > 0
              ? 'BMI ${bmi.toStringAsFixed(1)} (${bmi < 18.5 ? 'under' : bmi < 25 ? 'normal' : bmi < 30 ? 'over' : 'obese'})'
              : 'Add height and weight once.',
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _weight,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(hintText: 'Weight kg'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _height,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(hintText: 'Height cm'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      final kg = double.tryParse(_weight.text.trim());
                      final cm = double.tryParse(_height.text.trim());
                      if (kg != null && kg > 0) {
                        repo.add('weight', <String, dynamic>{'kg': kg});
                      }
                      if (cm != null && cm > 0) {
                        repo.setNumber('height_cm', cm);
                      }
                      _weight.clear();
                      _height.clear();
                      setState(() {});
                    },
                    child: const Text('Save'),
                  ),
                ],
              ),
              ...weights.take(4).map(
                    (w) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '${(w['kg'] as num).toStringAsFixed(1)} kg',
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: Text(
                        fmtDate((w['ts'] as num).toInt()),
                        style: const TextStyle(fontSize: 10),
                      ),
                    ),
                  ),
            ],
          ),
        ),
        SectionCard(
          title: 'BLOOD PRESSURE',
          icon: Icons.favorite_outline,
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _sys,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(hintText: 'Systolic'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _dia,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(hintText: 'Diastolic'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      final s = int.tryParse(_sys.text.trim());
                      final d = int.tryParse(_dia.text.trim());
                      if (s == null || d == null) return;
                      repo.add('bp', <String, dynamic>{'sys': s, 'dia': d});
                      _sys.clear();
                      _dia.clear();
                      setState(() {});
                      if (s >= 140 || d >= 90) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'That reading is high. Please speak to a doctor.',
                            ),
                          ),
                        );
                      }
                    },
                    child: const Text('Add'),
                  ),
                ],
              ),
              ...bps.take(4).map(
                    (b) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '${b['sys']}/${b['dia']} mmHg',
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: Text(
                        fmtDate((b['ts'] as num).toInt()),
                        style: const TextStyle(fontSize: 10),
                      ),
                    ),
                  ),
            ],
          ),
        ),
        SectionCard(
          title: 'SUGAR READINGS',
          icon: Icons.bloodtype_outlined,
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _sugar,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          hintText: 'mg/dL, fasting'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      final v = double.tryParse(_sugar.text.trim());
                      if (v == null) return;
                      repo.add('sugar', <String, dynamic>{'value': v});
                      _sugar.clear();
                      setState(() {});
                    },
                    child: const Text('Add'),
                  ),
                ],
              ),
              ...sugars.take(4).map(
                    (s) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '${(s['value'] as num).toStringAsFixed(0)} mg/dL',
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: Text(
                        fmtDate((s['ts'] as num).toInt()),
                        style: const TextStyle(fontSize: 10),
                      ),
                    ),
                  ),
            ],
          ),
        ),
        SectionCard(
          title: 'SLEEP',
          icon: Icons.bedtime_outlined,
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _sleep,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(hintText: 'Hours'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      final v = double.tryParse(_sleep.text.trim());
                      if (v == null || v <= 0) return;
                      repo.add('sleep', <String, dynamic>{'hours': v});
                      _sleep.clear();
                      setState(() {});
                    },
                    child: const Text('Log'),
                  ),
                ],
              ),
              ...sleeps.take(4).map(
                    (s) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '${(s['hours'] as num).toStringAsFixed(1)} hours',
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: Text(
                        fmtDate((s['ts'] as num).toInt()),
                        style: const TextStyle(fontSize: 10),
                      ),
                    ),
                  ),
            ],
          ),
        ),
        const BreathingCard(),
        SectionCard(
          title: 'EYE BREAK (20-20-20)',
          icon: Icons.visibility_outlined,
          subtitle: _breakSeconds == 0
              ? 'Start a cycle before long screen work.'
              : '${_breakSeconds ~/ 60}:${two(_breakSeconds % 60)} left',
          child: FilledButton.tonal(
            onPressed: _startBreakTimer,
            child: const Text('Start 20 minute cycle'),
          ),
        ),
        SectionCard(
          title: 'MEDICINES',
          icon: Icons.medication_outlined,
          subtitle: 'Add a medicine and a time; you get a daily reminder.',
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _med,
                      decoration: const InputDecoration(hintText: 'B12 at 9:00'),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle),
                    onPressed: () async {
                      final text = _med.text.trim();
                      if (text.isEmpty) return;
                      final parts = text.split(' at ');
                      final timeParts =
                          parts.length > 1 ? parts[1].split(':') : <String>[];
                      final hour =
                          timeParts.isNotEmpty ? int.tryParse(timeParts[0]) ?? 9 : 9;
                      final minute = timeParts.length > 1
                          ? int.tryParse(timeParts[1]) ?? 0
                          : 0;
                      repo.add('med', <String, dynamic>{
                        'text': text,
                        'hour': hour,
                        'minute': minute,
                      });
                      await scheduleReminder(
                        key: 'med_$text',
                        title: 'Medicine',
                        body: text,
                        time: TimeOfDay(hour: hour, minute: minute),
                      );
                      _med.clear();
                      setState(() {});
                    },
                  ),
                ],
              ),
              ...meds.map(
                (m) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(m['text'] as String,
                      style: const TextStyle(fontSize: 13)),
                  subtitle: Text(
                    'daily at ${two((m['hour'] as num).toInt())}:${two((m['minute'] as num).toInt())}',
                    style: const TextStyle(fontSize: 10),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () {
                      cancelReminder('med_${m['text']}');
                      repo.remove(m['id'] as String);
                      setState(() {});
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        const FirstAidCard(),
      ],
    );
  }
}

class BreathingCard extends StatefulWidget {
  const BreathingCard({super.key});

  @override
  State<BreathingCard> createState() => _BreathingCardState();
}

class _BreathingCardState extends State<BreathingCard> {
  Timer? _timer;
  bool _running = false;
  bool _inhale = true;
  int _phase = 0;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _toggle() {
    if (_running) {
      _timer?.cancel();
      setState(() {
        _running = false;
        _phase = 0;
      });
      return;
    }
    setState(() {
      _running = true;
      _inhale = true;
      _phase = 4;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _phase--;
        if (_phase <= 0) {
          _inhale = !_inhale;
          _phase = _inhale ? 4 : 6;
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = _inhale ? 128.0 : 88.0;
    final theme = Theme.of(context);
    return SectionCard(
      title: 'BREATHING PACER',
      icon: Icons.air,
      subtitle: 'Four seconds in, six seconds out.',
      child: Column(
        children: <Widget>[
          SizedBox(
            height: 140,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 900),
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: <Color>[
                      theme.colorScheme.primary.withOpacity(0.5),
                      theme.colorScheme.primary.withOpacity(0.1),
                    ],
                  ),
                ),
                child: Center(
                  child: Text(
                    _running ? (_inhale ? 'IN' : 'OUT') : 'READY',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ),
          ),
          OutlinedButton(
            onPressed: _toggle,
            child: Text(_running ? 'Stop' : 'Start'),
          ),
        ],
      ),
    );
  }
}

class FirstAidCard extends StatelessWidget {
  const FirstAidCard({super.key});

  static const Map<String, String> _steps = <String, String>{
    'Bleeding': 'Press firmly on the wound with cloth for ten minutes. Raise '
        'the limb. Do not peek early.',
    'Burns': 'Cool under running water for twenty minutes. No ice, butter or '
        'toothpaste. Cover loosely.',
    'Choking': 'Five back blows between the shoulder blades, then five '
        'abdominal thrusts. Repeat until clear.',
    'Fainting': 'Lay flat, raise the legs 30 cm, loosen tight clothing, check '
        'breathing. Call 108 if not awake in a minute.',
    'Snake bite': 'Keep the person still, limb below heart level, remove rings. '
        'No cutting, no sucking. Get to hospital.',
    'Fever': 'Fluids, light clothing, paracetamol by weight. See a doctor if it '
        'lasts more than three days.',
  };

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'FIRST AID',
      icon: Icons.health_and_safety_outlined,
      subtitle: 'General guidance only. In an emergency call 108.',
      child: Column(
        children: _steps.keys.map((key) {
          return ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 8),
            title: Text(key, style: const TextStyle(fontSize: 13.5)),
            children: <Widget>[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _steps[key]!,
                  style: const TextStyle(fontSize: 12, height: 1.5),
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}
