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
  final TextEditingController _bill = TextEditingController();
  final TextEditingController _percent = TextEditingController();
  final TextEditingController _birth = TextEditingController();
  String _from = 'km';
  String _to = 'miles';
  String _converted = '';
  String _discountResult = '';
  String _ageResult = '';

  Repo get repo => widget.repo;

  static const Map<String, double> _units = <String, double>{
    'km': 1000,
    'm': 1,
    'miles': 1609.34,
    'feet': 0.3048,
    'kg': 1,
    'g': 0.001,
    'lb': 0.453592,
    'litre': 1,
    'ml': 0.001,
  };

  void _convert() {
    final input = double.tryParse(_value.text.trim());
    final a = _units[_from];
    final b = _units[_to];
    if (input == null || a == null || b == null) {
      setState(() => _converted = 'Enter a number.');
      return;
    }
    setState(() {
      _converted = '${(input * a / b).toStringAsFixed(3)} $_to';
    });
  }

  void _discount() {
    final bill = double.tryParse(_bill.text.trim());
    final percent = double.tryParse(_percent.text.trim());
    if (bill == null || percent == null) {
      setState(() => _discountResult = 'Enter both numbers.');
      return;
    }
    final off = bill * percent / 100;
    setState(() {
      _discountResult =
          'You save ${money(off)}. Final price ${money(bill - off)}.';
    });
  }

  void _age() {
    final date = DateTime.tryParse(_birth.text.trim());
    if (date == null) {
      setState(() => _ageResult = 'Use the format 2001-08-15.');
      return;
    }
    final now = DateTime.now();
    var years = now.year - date.year;
    if (now.month < date.month ||
        (now.month == date.month && now.day < date.day)) {
      years--;
    }
    final days = now.difference(date).inDays;
    setState(() {
      _ageResult = '$years years old, $days days so far.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final notes = repo.list('note');

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: <Widget>[
        SectionCard(
          title: 'QUICK NOTES',
          icon: Icons.sticky_note_2_outlined,
          child: Column(
            children: <Widget>[
              TextField(
                controller: _note,
                maxLines: 2,
                decoration:
                    const InputDecoration(hintText: 'Anything to keep'),
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
                  child: const Text('Save'),
                ),
              ),
              ...notes.map(
                (n) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(n['text'] as String,
                      style: const TextStyle(fontSize: 13)),
                  subtitle: Text(
                    fmtDate((n['ts'] as num).toInt()),
                    style: const TextStyle(fontSize: 10),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.close,
                        size: 16, color: Colors.redAccent),
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
          icon: Icons.swap_horiz,
          child: Column(
            children: <Widget>[
              TextField(
                controller: _value,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(hintText: 'Value'),
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _from,
                      decoration: const InputDecoration(),
                      items: _units.keys
                          .map(
                            (u) => DropdownMenuItem<String>(
                              value: u,
                              child: Text(u,
                                  style: const TextStyle(fontSize: 13)),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => _from = v ?? 'km'),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('to'),
                  ),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _to,
                      decoration: const InputDecoration(),
                      items: _units.keys
                          .map(
                            (u) => DropdownMenuItem<String>(
                              value: u,
                              child: Text(u,
                                  style: const TextStyle(fontSize: 13)),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => _to = v ?? 'miles'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _convert,
                  child: const Text('Convert'),
                ),
              ),
              if (_converted.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                Text(_converted,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
              ],
            ],
          ),
        ),
        SectionCard(
          title: 'DISCOUNT',
          icon: Icons.percent,
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _bill,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(hintText: 'Bill'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _percent,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(hintText: 'Percent off'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _discount,
                  child: const Text('Work it out'),
                ),
              ),
              if (_discountResult.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                Text(_discountResult, style: const TextStyle(fontSize: 12.5)),
              ],
            ],
          ),
        ),
        SectionCard(
          title: 'AGE',
          icon: Icons.cake_outlined,
          child: Column(
            children: <Widget>[
              TextField(
                controller: _birth,
                decoration: const InputDecoration(
                  hintText: 'Birth date 2001-08-15',
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _age,
                  child: const Text('Calculate'),
                ),
              ),
              if (_ageResult.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                Text(_ageResult, style: const TextStyle(fontSize: 12.5)),
              ],
            ],
          ),
        ),
        const PhrasebookCard(),
        SectionCard(
          title: 'EMERGENCY NUMBERS',
          icon: Icons.emergency_outlined,
          subtitle: 'Tap Call to open the dialer.',
          child: Column(
            children: const <Widget>[
              CallRow(name: 'All emergencies', number: '112'),
              CallRow(name: 'Ambulance', number: '108'),
              CallRow(name: 'Police', number: '100'),
              CallRow(name: 'Fire', number: '101'),
              CallRow(name: 'Mental health', number: '14416'),
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
      icon: Icons.translate,
      subtitle: 'Works with no internet.',
      child: Column(
        children: <Widget>[
          DropdownButtonFormField<String>(
            value: _language,
            decoration: const InputDecoration(),
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
