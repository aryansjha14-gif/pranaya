import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core.dart';

class DoctorTab extends StatefulWidget {
  final Repo repo;
  const DoctorTab({super.key, required this.repo});

  @override
  State<DoctorTab> createState() => _DoctorTabState();
}

class _DoctorTabState extends State<DoctorTab> {
  final TextEditingController _symptom = TextEditingController();
  final TextEditingController _days = TextEditingController();
  final TextEditingController _notes = TextEditingController();
  String _verdict = '';
  String _advice = '';
  Color _colour = Colors.grey;

  Repo get repo => widget.repo;

  static const List<List<String>> _redFlags = <List<String>>[
    <String>['chest pain', 'pressure in chest'],
    <String>['cannot breathe', 'breathless', 'shortness of breath'],
    <String>['unconscious', 'fainted', 'not responding'],
    <String>['bleeding heavily', 'heavy bleeding'],
    <String>['stroke', 'face drooping', 'slurred speech'],
    <String>['seizure', 'fits'],
    <String>['suicidal', 'want to die', 'end my life'],
  ];

  void _triage() {
    final text = _symptom.text.toLowerCase();
    final days = int.tryParse(_days.text.trim()) ?? 0;
    if (text.trim().isEmpty) {
      setState(() {
        _verdict = 'Describe the problem first.';
        _advice = '';
        _colour = Colors.grey;
      });
      return;
    }

    for (final group in _redFlags) {
      for (final phrase in group) {
        if (text.contains(phrase)) {
          setState(() {
            _verdict = 'Call 108 or go to an emergency room now.';
            _advice =
                'This can be an emergency. Do not wait, do not drive yourself. '
                'If it is about self-harm, call 14416 and stay with someone.';
            _colour = Colors.redAccent;
          });
          return;
        }
      }
    }

    if (days >= 3) {
      setState(() {
        _verdict = 'See a doctor within a day or two.';
        _advice = 'A complaint lasting three days or more should be looked at '
            'in person. Note the start date, what makes it worse, and any '
            'medicine already taken.';
        _colour = Colors.orangeAccent;
      });
      return;
    }

    setState(() {
      _verdict = 'Watch it at home for now.';
      _advice = 'Rest, fluids, and write down how it changes over the next '
          'two days. If it gets worse, or a red flag appears, see a doctor '
          'straight away.';
      _colour = Colors.greenAccent;
    });
  }

  void _copyVisitNote() {
    final buffer = StringBuffer()
      ..writeln('Pranaya visit note')
      ..writeln('Date: ${fmtDate(DateTime.now().millisecondsSinceEpoch)}')
      ..writeln('Complaint: ${_symptom.text.trim()}')
      ..writeln(
          'Since: ${_days.text.trim().isEmpty ? 'not stated' : '${_days.text.trim()} day(s)'}')
      ..writeln('Notes: ${_notes.text.trim()}');
    final weights = repo.list('weight');
    final bps = repo.list('bp');
    final sugars = repo.list('sugar');
    if (weights.isNotEmpty) {
      buffer.writeln(
          'Latest weight: ${(weights.first['kg'] as num).toStringAsFixed(1)} kg');
    }
    if (bps.isNotEmpty) {
      buffer.writeln('Latest BP: ${bps.first['sys']}/${bps.first['dia']} mmHg');
    }
    if (sugars.isNotEmpty) {
      buffer.writeln(
          'Latest sugar: ${(sugars.first['value'] as num).toStringAsFixed(0)} mg/dL');
    }
    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Visit note copied. Show it to the doctor.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: <Widget>[
        SectionCard(
          title: 'SHOULD I SEE A DOCTOR',
          icon: Icons.healing,
          subtitle:
              'Offline triage. It does not diagnose; it tells you how urgent it looks.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              TextField(
                controller: _symptom,
                maxLines: 2,
                decoration: const InputDecoration(
                  hintText: 'What is wrong? e.g. fever and body ache',
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  SizedBox(
                    width: 110,
                    child: TextField(
                      controller: _days,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(hintText: 'Days'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _notes,
                      decoration: const InputDecoration(
                        hintText: 'Anything else (optional)',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: _triage,
                icon: const Icon(Icons.search),
                label: const Text('Check'),
              ),
              if (_verdict.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _colour.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _colour.withOpacity(0.5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        _verdict,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: _colour,
                        ),
                      ),
                      if (_advice.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 6),
                        Text(
                          _advice,
                          style: const TextStyle(fontSize: 12.5, height: 1.5),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _copyVisitNote,
                  icon: const Icon(Icons.copy_all),
                  label: const Text('Copy note for the doctor'),
                ),
              ],
            ],
          ),
        ),
        SectionCard(
          title: 'CALL A DOCTOR',
          icon: Icons.call,
          subtitle: 'Tap Call and the phone dialer opens with the number ready.',
          child: Column(
            children: const <Widget>[
              CallRow(
                name: 'Ambulance',
                number: '108',
                detail: 'Free emergency transport, 24 hours',
              ),
              CallRow(
                name: 'Health helpline',
                number: '104',
                detail: 'Government medical advice line',
              ),
              CallRow(
                name: 'Mental health helpline',
                number: '14416',
                detail: 'Tele-MANAS, free counselling',
              ),
              CallRow(
                name: 'Child helpline',
                number: '1098',
                detail: 'For children in danger',
              ),
              CallRow(
                name: 'Women helpline',
                number: '181',
                detail: 'Domestic abuse and distress',
              ),
              CallRow(
                name: 'Poison control',
                number: '1066',
                detail: 'Suspected poisoning',
              ),
            ],
          ),
        ),
        SectionCard(
          title: 'HOSPITAL LINES',
          icon: Icons.local_hospital_outlined,
          subtitle: 'This build has no internet, so save your own doctors below.',
          child: Column(
            children: const <Widget>[
              CallRow(
                name: 'Apollo appointment line',
                number: '1066',
                detail: 'National booking line',
              ),
              CallRow(
                name: 'AIIMS Delhi',
                number: '01126588500',
                detail: 'Main hospital line',
              ),
            ],
          ),
        ),
        const SavedDoctorsCard(),
        SectionCard(
          title: 'WHEN TO GO STRAIGHT TO HOSPITAL',
          icon: Icons.warning_amber_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const <String>[
              'Chest pain or pressure, especially spreading to the arm or jaw',
              'Sudden weakness on one side, face drooping, slurred speech',
              'Breathing difficulty at rest',
              'Heavy bleeding that will not stop with pressure',
              'Fainting, confusion, or a fit',
              'Fever with a stiff neck or a rash that does not fade',
              'Thoughts of harming yourself',
            ]
                .map(
                  (line) => Padding(
                    padding: EdgeInsets.only(bottom: 6),
                    child: Text('- $line',
                        style: TextStyle(fontSize: 12.5, height: 1.5)),
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }
}

class SavedDoctorsCard extends StatefulWidget {
  const SavedDoctorsCard({super.key});

  @override
  State<SavedDoctorsCard> createState() => _SavedDoctorsCardState();
}

class _SavedDoctorsCardState extends State<SavedDoctorsCard> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _number = TextEditingController();
  final List<Map<String, String>> _saved = <Map<String, String>>[];

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'MY DOCTORS',
      icon: Icons.contact_phone_outlined,
      subtitle: 'Add your own doctor once, then call with one tap.',
      child: Column(
        children: <Widget>[
          ..._saved.map(
            (d) => CallRow(
              name: d['name'] ?? '',
              number: d['number'] ?? '',
            ),
          ),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _name,
                  decoration: const InputDecoration(hintText: 'Dr Sharma'),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 130,
                child: TextField(
                  controller: _number,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(hintText: 'Number'),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle),
                onPressed: () {
                  if (_name.text.trim().isEmpty ||
                      _number.text.trim().isEmpty) {
                    return;
                  }
                  setState(() {
                    _saved.add(<String, String>{
                      'name': _name.text.trim(),
                      'number': _number.text.trim(),
                    });
                    _name.clear();
                    _number.clear();
                  });
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
