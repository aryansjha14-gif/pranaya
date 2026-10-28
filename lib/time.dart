import 'package:flutter/material.dart';

import 'core.dart';
import 'notify.dart';

class TimeTab extends StatefulWidget {
  final Repo repo;
  const TimeTab({super.key, required this.repo});

  @override
  State<TimeTab> createState() => _TimeTabState();
}

class _TimeTabState extends State<TimeTab> {
  final TextEditingController _task = TextEditingController();
  final TextEditingController _habit = TextEditingController();
  final TextEditingController _event = TextEditingController();

  Repo get repo => widget.repo;

  @override
  Widget build(BuildContext context) {
    final tasks = repo.list('task');
    final open = tasks.where((t) => t['done'] != true).toList();
    final habits = repo.list('habit');
    final events = repo.list('event');
    final today = DateTime.now().millisecondsSinceEpoch;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: <Widget>[
        SectionCard(
          title: 'TASKS',
          icon: Icons.checklist_rtl,
          subtitle: '${open.length} open',
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _task,
                      decoration:
                          const InputDecoration(hintText: 'What needs doing?'),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle),
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
                    icon: const Icon(Icons.close,
                        size: 16, color: Colors.redAccent),
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
          icon: Icons.local_fire_department_outlined,
          subtitle: 'Tap the circle each day to grow the streak.',
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _habit,
                      decoration: const InputDecoration(hintText: 'New habit'),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle),
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
                final doneToday =
                    days.any((d) => sameDay(int.tryParse(d) ?? 0, today));
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(h['name'] as String,
                      style: const TextStyle(fontSize: 13)),
                  subtitle: Text(
                    '${days.length} day streak',
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
          title: 'COUNTDOWNS',
          icon: Icons.event_outlined,
          subtitle: 'Add a date like 2026-12-25.',
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _event,
                      decoration: const InputDecoration(
                        hintText: 'Name 2026-12-25',
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle),
                    onPressed: () {
                      final text = _event.text.trim();
                      if (text.isEmpty) return;
                      final parts = text.split(' ');
                      final datePart = parts.last;
                      final date = DateTime.tryParse(datePart);
                      if (date == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Use the format: Name 2026-12-25'),
                          ),
                        );
                        return;
                      }
                      repo.add('event', <String, dynamic>{
                        'name': parts.take(parts.length - 1).join(' '),
                        'date': date.millisecondsSinceEpoch,
                      });
                      _event.clear();
                      setState(() {});
                    },
                  ),
                ],
              ),
              ...events.map((e) {
                final when = (e['date'] as num).toInt();
                final days = ((when - today) / 86400000).ceil();
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(e['name'] as String,
                      style: const TextStyle(fontSize: 13)),
                  subtitle: Text(
                    days >= 0 ? '$days day(s) to go' : '${-days} day(s) ago',
                    style: const TextStyle(fontSize: 10),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () {
                      repo.remove(e['id'] as String);
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
          icon: Icons.today_outlined,
          subtitle: fmtDate(today),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                open.isEmpty
                    ? 'Nothing pending. Add a task above.'
                    : open.map((t) => '- ${t['title']}').join('\n'),
                style: const TextStyle(fontSize: 13, height: 1.7),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () {
                  scheduleReminder(
                    key: 'plan',
                    title: 'Plan the day',
                    body: 'Open Pranaya and pick three things to finish.',
                    time: const TimeOfDay(hour: 8, minute: 30),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Daily 8:30 am planning reminder set.'),
                    ),
                  );
                },
                icon: const Icon(Icons.alarm),
                label: const Text('Remind me every morning'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
