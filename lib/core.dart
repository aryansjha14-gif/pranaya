import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

const String kVaultBoxName = 'pranaya_local_vault';

String two(int n) => n.toString().padLeft(2, '0');

String fmtDate(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${two(d.day)}/${two(d.month)}/${d.year}';
}

String fmtTime(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${two(d.hour)}:${two(d.minute)}';
}

/// Rupees with Indian digit grouping: 1,23,456.
String money(num value) {
  final negative = value < 0;
  final s = value.abs().toStringAsFixed(0);
  String out;
  if (s.length <= 3) {
    out = s;
  } else {
    final last3 = s.substring(s.length - 3);
    var rest = s.substring(0, s.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    parts.insert(0, rest);
    out = '${parts.join(',')},$last3';
  }
  return negative ? '-Rs $out' : 'Rs $out';
}

bool sameDay(int a, int b) {
  final x = DateTime.fromMillisecondsSinceEpoch(a);
  final y = DateTime.fromMillisecondsSinceEpoch(b);
  return x.year == y.year && x.month == y.month && x.day == y.day;
}

bool sameMonth(int a, int b) {
  final x = DateTime.fromMillisecondsSinceEpoch(a);
  final y = DateTime.fromMillisecondsSinceEpoch(b);
  return x.year == y.year && x.month == y.month;
}

/// One encrypted box holds every record. Each record is a JSON string with a
/// `type` tag, so new features can be added without a schema migration.
class Repo {
  final Box box;
  Repo(this.box);

  List<Map<String, dynamic>> list(String type) {
    final out = <Map<String, dynamic>>[];
    for (final value in box.values) {
      if (value is String) {
        try {
          final m = jsonDecode(value) as Map<String, dynamic>;
          if (m['type'] == type) out.add(m);
        } catch (_) {}
      }
    }
    out.sort((a, b) {
      final x = (a['ts'] as num?)?.toInt() ?? 0;
      final y = (b['ts'] as num?)?.toInt() ?? 0;
      return y.compareTo(x);
    });
    return out;
  }

  Map<String, dynamic> add(String type, Map<String, dynamic> data) {
    final ts = (data['ts'] as num?)?.toInt() ??
        DateTime.now().millisecondsSinceEpoch;
    final id = '${type}_${ts}_${box.length}';
    final record = <String, dynamic>{'id': id, 'type': type, 'ts': ts};
    record.addAll(data);
    box.put(id, jsonEncode(record));
    return record;
  }

  void save(Map<String, dynamic> record) {
    box.put(record['id'] as String, jsonEncode(record));
  }

  void remove(String id) {
    box.delete(id);
  }

  double number(String key) {
    final raw = box.get('setting_$key');
    if (raw is String) {
      try {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        return (m['value'] as num?)?.toDouble() ?? 0;
      } catch (_) {}
    }
    return 0;
  }

  void setNumber(String key, double value) {
    box.put('setting_$key', jsonEncode({'type': 'setting', 'value': value}));
  }
}

/// Result of reading a bank SMS the user pastes in.
class ParsedSms {
  final double? amount;
  final String? merchant;
  final bool isDebit;
  final String raw;
  const ParsedSms({
    required this.amount,
    required this.merchant,
    required this.isDebit,
    required this.raw,
  });
}

/// Fully offline parser. The blueprint wanted to read SMS in the background,
/// which Play Store does not allow for this kind of app - so the user pastes
/// the message instead and this extracts the numbers locally.
ParsedSms parseBankSms(String text) {
  final amountMatch = RegExp(
    r'(?:rs\.?|inr|\u20b9)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)',
    caseSensitive: false,
  ).firstMatch(text);

  double? amount;
  if (amountMatch != null) {
    final cleaned = amountMatch.group(1)!.replaceAll(',', '');
    amount = double.tryParse(cleaned);
  }

  String? merchant;
  final merchantMatch = RegExp(
    r'\b(?:to|at|towards|from|by)\s+([A-Za-z0-9&._\- ]{3,28})',
    caseSensitive: false,
  ).firstMatch(text);
  if (merchantMatch != null) {
    merchant = merchantMatch.group(1)!.trim();
  }

  final lower = text.toLowerCase();
  final creditWords = ['credited', 'received', 'deposited', 'refund', 'cashback'];
  final debitWords = ['debited', 'spent', 'paid', 'withdrawn', 'purchase'];
  var isDebit = true;
  for (final w in creditWords) {
    if (lower.contains(w)) isDebit = false;
  }
  for (final w in debitWords) {
    if (lower.contains(w)) isDebit = true;
  }

  return ParsedSms(
    amount: amount,
    merchant: merchant,
    isDebit: isDebit,
    raw: text,
  );
}

const List<String> kCategories = <String>[
  'Food',
  'Travel',
  'Bills',
  'Shopping',
  'Health',
  'Family',
  'Other',
];

class SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  final String? subtitle;
  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.surface,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.primary,
              ),
            ),
            if (subtitle != null) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class BarList extends StatelessWidget {
  final Map<String, double> data;
  const BarList({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const Text('Nothing recorded yet.', style: TextStyle(fontSize: 12));
    }
    var maxValue = 0.0;
    data.forEach((_, v) {
      if (v > maxValue) maxValue = v;
    });
    if (maxValue <= 0) maxValue = 1;
    final keys = data.keys.toList();
    return Column(
      children: keys.map((key) {
        final value = data[key] ?? 0;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 78,
                child: Text(key, style: const TextStyle(fontSize: 11)),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (value / maxValue).clamp(0.0, 1.0),
                    minHeight: 10,
                    backgroundColor: Colors.white12,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 74,
                child: Text(
                  money(value),
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final Color? colour;
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.colour,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: colour,
          ),
        ),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ],
    );
  }
}
