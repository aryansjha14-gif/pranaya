import 'package:flutter/material.dart';

import 'core.dart';

class ToolsTab extends StatefulWidget {
  final Repo repo;
  const ToolsTab({super.key, required this.repo});

  @override
  State<ToolsTab> createState() => _ToolsTabState();
}

class _ToolsTabState extends State<ToolsTab> {
  final TextEditingController _note = TextEditingController();
  final TextEditingController _value = TextEditingController();
  String _from = 'km';
  String _to = 'miles';
  String _converted = '';

  Repo get repo => widget.repo;

  static const Map<String, double> _units = <String, double>{
    'km': 1000,
    'm': 1,
    'miles': 1609.34,
    'feet': 0.3048,
    'kg': 1,
    'g': 0.001,
    'lb': 0.453592,
  };

  void _convert() {
    final input = double.tryParse(_value.text.trim());
    final a = _units[_from];
    final b = _units[_to];
    if (input == null || a == null || b == null) {
      setState(() => _converted = 'Enter a number.');
      return;
    }
    final result = input * a / b;
    setState(() {
      _converted = '${result.toStringAsFixed(3)} $_to';
    });
  }

  @override
  Widget build(BuildContext context) {
    final notes = repo.list('note');

    return ListView(
      padding: const EdgeInsets.all(14),
      children: <Widget>[
        SectionCard(
          title: 'QUICK NOTES',
          child: Column(
            children: <Widget>[
              TextField(
                controller: _note,
                maxLines: 2,
                decoration: const InputDecoration(
                  hintText: 'Anything you want to keep',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () {
                    if (_note.text.trim().isEmpty) return;
                    repo.add('note', <String, dynamic>{
                      'text': _note.text.trim(),
                    });
                    _note.clear();
                    setState(() {});
                  },
                  child: const Text('SAVE'),
                ),
              ),
              ...notes.map(
                (n) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    n['text'] as String,
                    style: const TextStyle(fontSize: 13),
                  ),
                  subtitle: Text(
                    fmtDate((n['ts'] as num).toInt()),
                    style: const TextStyle(fontSize: 10),
                  ),
                  trailing: IconButton(
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 18,
                      color: Colors.redAccent,
                    ),
                    onPressed: () {
                      repo.remove(n['id'] as String);
                      setState(() {});
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        SectionCard(
          title: 'UNIT CONVERTER',
          child: Column(
            children: <Widget>[
              TextField(
                controller: _value,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  hintText: 'Value',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _from,
                      decoration: const InputDecoration(isDense: true),
                      items: _units.keys
                          .map(
                            (u) => DropdownMenuItem<String>(
                              value: u,
                              child:
                                  Text(u, style: const TextStyle(fontSize: 13)),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => _from = v ?? 'km'),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Text('to'),
                  ),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _to,
                      decoration: const InputDecoration(isDense: true),
                      items: _units.keys
                          .map(
                            (u) => DropdownMenuItem<String>(
                              value: u,
                              child:
                                  Text(u, style: const TextStyle(fontSize: 13)),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => _to = v ?? 'miles'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _convert,
                  child: const Text('CONVERT'),
                ),
              ),
              if (_converted.isNotEmpty) ...<Widget>[
                const SizedBox(height: 6),
                Text(_converted, style: const TextStyle(fontSize: 14)),
              ],
            ],
          ),
        ),
        const PhrasebookCard(),
        SectionCard(
          title: 'EMERGENCY NUMBERS (INDIA)',
          child: Column(
            children: const <Widget>[
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('108 - Ambulance', style: TextStyle(fontSize: 13)),
              ),
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('100 - Police', style: TextStyle(fontSize: 13)),
              ),
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('101 - Fire', style: TextStyle(fontSize: 13)),
              ),
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('112 - All emergencies',
                    style: TextStyle(fontSize: 13)),
              ),
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('14416 - Mental health helpline',
                    style: TextStyle(fontSize: 13)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class PhrasebookCard extends StatefulWidget {
  const PhrasebookCard({super.key});

  @override
  State<PhrasebookCard> createState() => _PhrasebookCardState();
}

class _PhrasebookCardState extends State<PhrasebookCard> {
  String _language = 'Hindi';

  static const Map<String, List<List<String>>> _book =
      <String, List<List<String>>>{
    'Hindi': <List<String>>[
      <String>['Where is the hospital?', 'Aspataal kahan hai?'],
      <String>['How much does this cost?', 'Yeh kitne ka hai?'],
      <String>['I need help', 'Mujhe madad chahiye'],
      <String>['Please speak slowly', 'Kripya dheere boliye'],
      <String>['I am not well', 'Meri tabiyat theek nahi hai'],
    ],
    'Tamil': <List<String>>[
      <String>['Where is the hospital?', 'Maruthuvamanai engae irukku?'],
      <String>['How much does this cost?', 'Idhu evvalavu?'],
      <String>['I need help', 'Enakku udhavi venum'],
      <String>['Please speak slowly', 'Konjam medhuva pesunga'],
      <String>['I am not well', 'Enakku udambu seri illai'],
    ],
    'Bengali': <List<String>>[
      <String>['Where is the hospital?', 'Hospital kothay?'],
      <String>['How much does this cost?', 'Eta koto taka?'],
      <String>['I need help', 'Amar shahajjo dorkar'],
      <String>['Please speak slowly', 'Ektu aste bolun'],
      <String>['I am not well', 'Amar shorir bhalo nei'],
    ],
  };

  @override
  Widget build(BuildContext context) {
    final phrases = _book[_language] ?? <List<String>>[];
    return SectionCard(
      title: 'OFFLINE PHRASEBOOK',
      subtitle: 'Works with no internet.',
      child: Column(
        children: <Widget>[
          DropdownButtonFormField<String>(
            value: _language,
            decoration: const InputDecoration(isDense: true),
            items: _book.keys
                .map(
                  (l) => DropdownMenuItem<String>(
                    value: l,
                    child: Text(l, style: const TextStyle(fontSize: 13)),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => _language = v ?? 'Hindi'),
          ),
          const SizedBox(height: 8),
          ...phrases.map(
            (p) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(p[0], style: const TextStyle(fontSize: 13)),
              subtitle: Text(p[1], style: const TextStyle(fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }
}
