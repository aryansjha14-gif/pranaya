import 'dart:async';

import 'package:flutter/material.dart';

import 'core.dart';

// ---------------------------------------------------------------- BODY

class BodyTab extends StatefulWidget {
  final Repo repo;
  const BodyTab({super.key, required this.repo});

  @override
  State<BodyTab> createState() => _BodyTabState();
}

class _BodyTabState extends State<BodyTab> {
  final TextEditingController _ml = TextEditingController();
  final TextEditingController _sleep = TextEditingController();
  final TextEditingController _med = TextEditingController();

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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('20 minutes up - look 20 feet away for 20 seconds.'),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final goal = repo.number('water_goal');
    final progress = goal <= 0 ? 0.0 : (_waterToday / goal).clamp(0.0, 1.0);
    final sleeps = repo.list('sleep');
    final meds = repo.list('med');
    final minutes = _breakSeconds ~/ 60;
    final seconds = _breakSeconds % 60;

    return ListView(
      padding: const EdgeInsets.all(14),
      children: <Widget>[
        SectionCard(
          title: 'WATER',
          subtitle:
              'Goal: ${goal <= 0 ? 'not set' : '${goal.toStringAsFixed(0)} ml'}',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '${_waterToday.toStringAsFixed(0)} ml today',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: Colors.white12,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: <Widget>[
                  OutlinedButton(
                    onPressed: () => _addWater(250),
                    child: const Text('+250 ml'),
                  ),
                  OutlinedButton(
                    onPressed: () => _addWater(500),
                    child: const Text('+500 ml'),
                  ),
                ],
              ),
              TextField(
                controller: _ml,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  hintText: 'Daily goal in ml, e.g. 2500',
                  isDense: true,
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    final v = double.tryParse(_ml.text.trim());
                    if (v == null) return;
                    repo.setNumber('water_goal', v);
                    _ml.clear();
                    setState(() {});
                  },
                  child: const Text('SET GOAL'),
                ),
              ),
            ],
          ),
        ),
        SectionCard(
          title: 'SLEEP LOG',
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _sleep,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        hintText: 'Hours slept',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () {
                      final v = double.tryParse(_sleep.text.trim());
                      if (v == null || v <= 0) return;
                      repo.add('sleep', <String, dynamic>{'hours': v});
                      _sleep.clear();
                      setState(() {});
                    },
                    child: const Text('LOG'),
                  ),
                ],
              ),
              ...sleeps.take(5).map(
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
        const BreathingPacerCard(),
        SectionCard(
          title: 'EYE BREAK TIMER (20-20-20)',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                _breakSeconds == 0
                    ? 'Idle'
                    : '$minutes:${two(seconds)} until your next break',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _startBreakTimer,
                child: const Text('START 20 MINUTE CYCLE'),
              ),
            ],
          ),
        ),
        SectionCard(
          title: 'MEDICINE REMINDERS',
          subtitle: 'Kept on this phone; nothing is sent anywhere.',
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _med,
                      decoration: const InputDecoration(
                        hintText: 'Medicine and time, e.g. B12 at 9am',
                        isDense: true,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: () {
                      if (_med.text.trim().isEmpty) return;
                      repo.add('med', <String, dynamic>{
                        'text': _med.text.trim(),
                      });
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
                  title: Text(
                    m['text'] as String,
                    style: const TextStyle(fontSize: 13),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.check, size: 18),
                    onPressed: () {
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

class BreathingPacerCard extends StatefulWidget {
  const BreathingPacerCard({super.key});

  @override
  State<BreathingPacerCard> createState() => _BreathingPacerCardState();
}

class _BreathingPacerCardState extends State<BreathingPacerCard> {
  Timer? _timer;
  bool _running = false;
  bool _inhale = true;
  int _phaseSeconds = 0;

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
        _phaseSeconds = 0;
      });
      return;
    }
    setState(() {
      _running = true;
      _inhale = true;
      _phaseSeconds = 4;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _phaseSeconds--;
        if (_phaseSeconds <= 0) {
          _inhale = !_inhale;
          _phaseSeconds = _inhale ? 4 : 6;
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = _inhale ? 130.0 : 90.0;
    return SectionCard(
      title: 'BREATHING PACER (4 IN, 6 OUT)',
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
                  color:
                      Theme.of(context).colorScheme.primary.withOpacity(0.25),
                ),
                child: Center(
                  child: Text(
                    _running ? (_inhale ? 'IN' : 'OUT') : 'READY',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ),
          ),
          OutlinedButton(
            onPressed: _toggle,
            child: Text(_running ? 'STOP' : 'START'),
          ),
        ],
      ),
    );
  }
}

class FirstAidCard extends StatelessWidget {
  const FirstAidCard({super.key});

  static const Map<String, String> _steps = <String, String>{
    'Bleeding': 'Press firmly on the wound with cloth. Keep pressure 10 minutes. '
        'Raise the limb. Do not peek early.',
    'Burns': 'Cool under running water 20 minutes. Do not apply ice, butter or '
        'toothpaste. Cover loosely.',
    'Choking': 'Five back blows between the shoulder blades, then five '
        'abdominal thrusts. Repeat until clear.',
    'Fainting': 'Lay flat, raise the legs 30 cm, loosen tight clothing, check '
        'breathing. Call for help if not awake in one minute.',
    'Snake bite': 'Keep the person still and the limb below heart level. '
        'Remove rings. No cutting, no sucking. Get to hospital.',
    'Fever': 'Fluids, light clothing, paracetamol as per weight. See a doctor '
        'if fever lasts more than three days.',
  };

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'FIRST AID (OFFLINE)',
      subtitle: 'General guidance only. Call 108 for an emergency.',
      child: Column(
        children: _steps.keys.map((key) {
          return ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 8),
            title: Text(key, style: const TextStyle(fontSize: 13)),
            children: <Widget>[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _steps[key]!,
                  style: const TextStyle(fontSize: 12, height: 1.4),
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}

// ---------------------------------------------------------------- MIND

class MindTab extends StatefulWidget {
  final Repo repo;
  const MindTab({super.key, required this.repo});

  @override
  State<MindTab> createState() => _MindTabState();
}

class _MindTabState extends State<MindTab> {
  final TextEditingController _gratitude = TextEditingController();
  final TextEditingController _note = TextEditingController();
  int _mood = 3;

  Repo get repo => widget.repo;

  static const List<String> _prompts = <String>[
    'What is one thing that went better than expected today?',
    'What did you avoid today, and what did avoiding it cost you?',
    'Who helped you this week, and have you told them?',
    'What would tomorrow look like if it went well?',
    'What is one small thing you can finish in ten minutes?',
  ];

  @override
  Widget build(BuildContext context) {
    final moods = repo.list('mood');
    final gratitude = repo.list('gratitude');
    final dayIndex = DateTime.now().day % _prompts.length;

    var average = 0.0;
    if (moods.isNotEmpty) {
      var sum = 0.0;
      final sample = moods.length > 7 ? 7 : moods.length;
      for (var i = 0; i < sample; i++) {
        sum += (moods[i]['score'] as num).toDouble();
      }
      average = sum / sample;
    }

    return ListView(
      padding: const EdgeInsets.all(14),
      children: <Widget>[
        SectionCard(
          title: 'HOW IS TODAY',
          subtitle: average > 0
              ? 'Recent average: ${average.toStringAsFixed(1)} / 5'
              : 'Rate your day from 1 to 5.',
          child: Column(
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List<Widget>.generate(5, (i) {
                  final value = i + 1;
                  final selected = _mood == value;
                  return GestureDetector(
                    onTap: () => setState(() => _mood = value),
                    child: Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: selected
                            ? Theme.of(context).colorScheme.primary
                            : Colors.white10,
                      ),
                      child: Center(
                        child: Text(
                          '$value',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: selected ? Colors.black : null,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    repo.add('mood', <String, dynamic>{'score': _mood});
                    setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Check-in saved.')),
                    );
                  },
                  child: const Text('SAVE CHECK-IN'),
                ),
              ),
            ],
          ),
        ),
        SectionCard(
          title: 'GRATITUDE VAULT',
          child: Column(
            children: <Widget>[
              TextField(
                controller: _gratitude,
                maxLines: 2,
                decoration: const InputDecoration(
                  hintText: 'One thing you are grateful for',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () {
                    if (_gratitude.text.trim().isEmpty) return;
                    repo.add('gratitude', <String, dynamic>{
                      'text': _gratitude.text.trim(),
                    });
                    _gratitude.clear();
                    setState(() {});
                  },
                  child: const Text('STORE'),
                ),
              ),
              ...gratitude.take(5).map(
                    (g) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        g['text'] as String,
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: Text(
                        fmtDate((g['ts'] as num).toInt()),
                        style: const TextStyle(fontSize: 10),
                      ),
                    ),
                  ),
            ],
          ),
        ),
        SectionCard(
          title: 'REFLECTION PROMPT',
          child: Text(
            _prompts[dayIndex],
            style: const TextStyle(fontSize: 13, height: 1.5),
          ),
        ),
        SectionCard(
          title: 'JOURNAL',
          child: Column(
            children: <Widget>[
              TextField(
                controller: _note,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Write freely. It stays on this phone.',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () {
                    if (_note.text.trim().isEmpty) return;
                    repo.add('journal', <String, dynamic>{
                      'text': _note.text.trim(),
                    });
                    _note.clear();
                    setState(() {});
                  },
                  child: const Text('SAVE ENTRY'),
                ),
              ),
              ...repo.list('journal').take(3).map(
                    (j) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        j['text'] as String,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                      subtitle: Text(
                        fmtDate((j['ts'] as num).toInt()),
                        style: const TextStyle(fontSize: 10),
                      ),
                    ),
                  ),
            ],
          ),
        ),
        const FocusTimerCard(),
      ],
    );
  }
}

class FocusTimerCard extends StatefulWidget {
  const FocusTimerCard({super.key});

  @override
  State<FocusTimerCard> createState() => _FocusTimerCardState();
}

class _FocusTimerCardState extends State<FocusTimerCard> {
  Timer? _timer;
  int _secondsLeft = 25 * 60;
  bool _running = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _toggle() {
    if (_running) {
      _timer?.cancel();
      setState(() => _running = false);
      return;
    }
    setState(() => _running = true);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _secondsLeft--;
        if (_secondsLeft <= 0) {
          t.cancel();
          _running = false;
          _secondsLeft = 25 * 60;
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final minutes = _secondsLeft ~/ 60;
    final seconds = _secondsLeft % 60;
    return SectionCard(
      title: 'FOCUS SESSION',
      subtitle: '25 minutes, no interruptions.',
      child: Column(
        children: <Widget>[
          Text(
            '$minutes:${two(seconds)}',
            style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900),
          ),
          OutlinedButton(
            onPressed: _toggle,
            child: Text(_running ? 'PAUSE' : 'START'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- TIME

class TimeTab extends StatefulWidget {
  final Repo repo;
  const TimeTab({super.key, required this.repo});

  @override
  State<TimeTab> createState() => _TimeTabState();
}

class _TimeTabState extends State<TimeTab> {
  final TextEditingController _task = TextEditingController();
  final TextEditingController _habit = TextEditingController();

  Repo get repo => widget.repo;

  @override
  Widget build(BuildContext context) {
    final tasks = repo.list('task');
    final open = tasks.where((t) => t['done'] != true).toList();
    final habits = repo.list('habit');
    final today = DateTime.now().millisecondsSinceEpoch;

    return ListView(
      padding: const EdgeInsets.all(14),
      children: <Widget>[
        SectionCard(
          title: 'TASKS',
          subtitle: '${open.length} open',
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _task,
                      decoration: const InputDecoration(
                        hintText: 'What needs doing?',
                        isDense: true,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: () {
                      if (_task.text.trim().isEmpty) return;
                      repo.add('task', <String, dynamic>{
                        'title': _task.text.trim(),
                        'done': false,
                      });
                      _task.clear();
                      setState(() {});
                    },
                  ),
                ],
              ),
              ...tasks.map((t) {
                final done = t['done'] == true;
                return CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: done,
                  title: Text(
                    t['title'] as String,
                    style: TextStyle(
                      fontSize: 13,
                      decoration: done ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  secondary: IconButton(
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 18,
                      color: Colors.redAccent,
                    ),
                    onPressed: () {
                      repo.remove(t['id'] as String);
                      setState(() {});
                    },
                  ),
                  onChanged: (v) {
                    final record = Map<String, dynamic>.from(t);
                    record['done'] = v == true;
                    repo.save(record);
                    setState(() {});
                  },
                );
              }),
            ],
          ),
        ),
        SectionCard(
          title: 'HABITS',
          subtitle: 'Tap a habit each day to keep the streak.',
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _habit,
                      decoration: const InputDecoration(
                        hintText: 'New habit, e.g. walk 20 min',
                        isDense: true,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: () {
                      if (_habit.text.trim().isEmpty) return;
                      repo.add('habit', <String, dynamic>{
                        'name': _habit.text.trim(),
                        'days': <String>[],
                      });
                      _habit.clear();
                      setState(() {});
                    },
                  ),
                ],
              ),
              ...habits.map((h) {
                final days = ((h['days'] as List<dynamic>?) ?? <dynamic>[])
                    .map((d) => d.toString())
                    .toList();
                final doneToday = days.any(
                  (d) => sameDay(int.tryParse(d) ?? 0, today),
                );
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    h['name'] as String,
                    style: const TextStyle(fontSize: 13),
                  ),
                  subtitle: Text(
                    'streak: ${days.length} day(s)',
                    style: const TextStyle(fontSize: 10),
                  ),
                  trailing: IconButton(
                    icon: Icon(
                      doneToday ? Icons.check_circle : Icons.circle_outlined,
                      color: doneToday ? Colors.greenAccent : null,
                    ),
                    onPressed: () {
                      if (doneToday) return;
                      final record = Map<String, dynamic>.from(h);
                      record['days'] = <String>[...days, '$today'];
                      repo.save(record);
                      setState(() {});
                    },
                  ),
                );
              }),
            ],
          ),
        ),
        SectionCard(
          title: 'DAILY PLAN',
          subtitle: fmtDate(today),
          child: Text(
            open.isEmpty
                ? 'Nothing pending. Add a task above.'
                : open.map((t) => '- ${t['title']}').join('\n'),
            style: const TextStyle(fontSize: 13, height: 1.6),
          ),
        ),
      ],
    );
  }
}
