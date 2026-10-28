import 'dart:async';

import 'package:flutter/material.dart';

import 'core.dart';
import 'notify.dart';

class MindTab extends StatefulWidget {
  final Repo repo;
  const MindTab({super.key, required this.repo});

  @override
  State<MindTab> createState() => _MindTabState();
}

class _MindTabState extends State<MindTab> {
  final TextEditingController _gratitude = TextEditingController();
  final TextEditingController _note = TextEditingController();
  final TextEditingController _thought = TextEditingController();
  final TextEditingController _reframe = TextEditingController();
  int _mood = 3;

  Repo get repo => widget.repo;

  static const List<String> _prompts = <String>[
    'What went better than expected today?',
    'What did you avoid today, and what did avoiding it cost?',
    'Who helped you this week, and have you told them?',
    'What would tomorrow look like if it went well?',
    'What is one small thing you can finish in ten minutes?',
    'What is one thing you can stop doing this week?',
  ];

  static const List<String> _sleepTips = <String>[
    'Keep the phone out of the bed for the last twenty minutes.',
    'Same wake-up time every day beats a perfect bedtime.',
    'No caffeine after 4 pm if you wake up during the night.',
    'Dim the room an hour before sleeping.',
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
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: <Widget>[
        SectionCard(
          title: 'MOOD CHECK-IN',
          icon: Icons.mood,
          subtitle: average > 0
              ? 'Recent average ${average.toStringAsFixed(1)} out of 5'
              : 'Rate the day from 1 to 5.',
          child: Column(
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List<Widget>.generate(5, (i) {
                  final value = i + 1;
                  final selected = _mood == value;
                  return GestureDetector(
                    onTap: () => setState(() => _mood = value),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: selected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withOpacity(0.06),
                      ),
                      child: Center(
                        child: Text(
                          '$value',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: selected ? Colors.black : null,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    repo.add('mood', <String, dynamic>{'score': _mood});
                    setState(() {});
                  },
                  child: const Text('Save check-in'),
                ),
              ),
            ],
          ),
        ),
        SectionCard(
          title: 'THOUGHT RECORD',
          icon: Icons.psychology_alt_outlined,
          subtitle: 'Write the thought, then a fairer version of it.',
          child: Column(
            children: <Widget>[
              TextField(
                controller: _thought,
                maxLines: 2,
                decoration: const InputDecoration(hintText: 'The thought'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _reframe,
                maxLines: 2,
                decoration: const InputDecoration(hintText: 'A fairer version'),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () {
                    if (_thought.text.trim().isEmpty) return;
                    repo.add('thought', <String, dynamic>{
                      'thought': _thought.text.trim(),
                      'reframe': _reframe.text.trim(),
                    });
                    _thought.clear();
                    _reframe.clear();
                    setState(() {});
                  },
                  child: const Text('Save pair'),
                ),
              ),
              ...repo.list('thought').take(3).map(
                    (t) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(t['thought'] as String,
                          style: const TextStyle(fontSize: 12.5)),
                      subtitle: Text(
                        (t['reframe'] as String).isEmpty
                            ? 'No reframe yet'
                            : t['reframe'] as String,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  ),
            ],
          ),
        ),
        SectionCard(
          title: 'GRATITUDE',
          icon: Icons.favorite_outline,
          child: Column(
            children: <Widget>[
              TextField(
                controller: _gratitude,
                maxLines: 2,
                decoration:
                    const InputDecoration(hintText: 'One good thing today'),
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
                  child: const Text('Store'),
                ),
              ),
              ...gratitude.take(4).map(
                    (g) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(g['text'] as String,
                          style: const TextStyle(fontSize: 12.5)),
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
          title: 'JOURNAL',
          icon: Icons.edit_note,
          child: Column(
            children: <Widget>[
              TextField(
                controller: _note,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Write freely. It stays on this phone.',
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
                  child: const Text('Save entry'),
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
        SectionCard(
          title: 'TODAY PROMPT',
          icon: Icons.lightbulb_outline,
          child: Text(
            _prompts[dayIndex],
            style: const TextStyle(fontSize: 13.5, height: 1.6),
          ),
        ),
        SectionCard(
          title: 'SLEEP NOTES',
          icon: Icons.nightlight_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _sleepTips
                .map(
                  (tip) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('- $tip',
                        style: const TextStyle(fontSize: 12.5, height: 1.5)),
                  ),
                )
                .toList(),
          ),
        ),
        const FocusCard(),
      ],
    );
  }
}

class FocusCard extends StatefulWidget {
  const FocusCard({super.key});

  @override
  State<FocusCard> createState() => _FocusCardState();
}

class _FocusCardState extends State<FocusCard> {
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
      if (_secondsLeft == 25 * 60) {
        Notifier.instance.showNow(
          7200,
          'Focus session complete',
          'Twenty five minutes done. Take a short break.',
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'FOCUS SESSION',
      icon: Icons.timer_outlined,
      subtitle: 'Twenty five minutes without interruptions.',
      child: Column(
        children: <Widget>[
          Text(
            '${_secondsLeft ~/ 60}:${two(_secondsLeft % 60)}',
            style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w900),
          ),
          OutlinedButton(
            onPressed: _toggle,
            child: Text(_running ? 'Pause' : 'Start'),
          ),
        ],
      ),
    );
  }
}
