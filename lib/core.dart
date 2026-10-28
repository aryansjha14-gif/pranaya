import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

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

Future<void> dialNumber(BuildContext context, String number) async {
  final uri = Uri(scheme: 'tel', path: number);
  try {
    final ok = await launchUrl(uri);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open the dialer for $number')),
      );
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Dial $number manually')),
      );
    }
  }
}

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
    final ts =
        (data['ts'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;
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

  String text(String key) {
    final raw = box.get('setting_$key');
    if (raw is String) {
      try {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        return (m['value'] as String?) ?? '';
      } catch (_) {}
    }
    return '';
  }

  void setText(String key, String value) {
    box.put('setting_$key', jsonEncode({'type': 'setting', 'value': value}));
  }
}

class ParsedSms {
  final double? amount;
  final String? merchant;
  final bool isDebit;
  final String raw;
  final int? dateMs;
  const ParsedSms({
    required this.amount,
    required this.merchant,
    required this.isDebit,
    required this.raw,
    this.dateMs,
  });
}

ParsedSms parseBankSms(String text, {int? dateMs}) {
  final amountMatch = RegExp(
    r'(?:rs\.?|inr|\u20b9)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)',
    caseSensitive: false,
  ).firstMatch(text);

  double? amount;
  if (amountMatch != null) {
    amount = double.tryParse(amountMatch.group(1)!.replaceAll(',', ''));
  }

  String? merchant;
  final merchantMatch = RegExp(
    r'\b(?:to|at|towards|from|by|via)\s+([A-Za-z0-9&._\- ]{3,28})',
    caseSensitive: false,
  ).firstMatch(text);
  if (merchantMatch != null) merchant = merchantMatch.group(1)!.trim();

  final lower = text.toLowerCase();
  var isDebit = true;
  for (final w in <String>[
    'credited',
    'received',
    'deposited',
    'refund',
    'cashback',
  ]) {
    if (lower.contains(w)) isDebit = false;
  }
  for (final w in <String>[
    'debited',
    'spent',
    'paid',
    'withdrawn',
    'purchase',
  ]) {
    if (lower.contains(w)) isDebit = true;
  }

  return ParsedSms(
    amount: amount,
    merchant: merchant,
    isDebit: isDebit,
    raw: text,
    dateMs: dateMs,
  );
}

String guessCategory(String text) {
  final lower = text.toLowerCase();
  if (lower.contains('swiggy') ||
      lower.contains('zomato') ||
      lower.contains('restaurant') ||
      lower.contains('cafe') ||
      lower.contains('food')) {
    return 'Food';
  }
  if (lower.contains('uber') ||
      lower.contains('ola') ||
      lower.contains('petrol') ||
      lower.contains('fuel') ||
      lower.contains('irctc') ||
      lower.contains('metro')) {
    return 'Travel';
  }
  if (lower.contains('jio') ||
      lower.contains('airtel') ||
      lower.contains('electric') ||
      lower.contains('bill') ||
      lower.contains('recharge')) {
    return 'Bills';
  }
  if (lower.contains('pharmacy') ||
      lower.contains('hospital') ||
      lower.contains('medical') ||
      lower.contains('clinic')) {
    return 'Health';
  }
  if (lower.contains('amazon') ||
      lower.contains('flipkart') ||
      lower.contains('myntra') ||
      lower.contains('store')) {
    return 'Shopping';
  }
  return 'Other';
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
  final IconData? icon;
  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: theme.dividerColor.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          if (subtitle != null) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.4,
                color: theme.colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ],
          const SizedBox(height: 12),
          child,
        ],
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
      return const Text('Nothing recorded yet.',
          style: TextStyle(fontSize: 12));
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
          padding: const EdgeInsets.only(bottom: 9),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 74,
                child: Text(key, style: const TextStyle(fontSize: 11.5)),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: (value / maxValue).clamp(0.0, 1.0),
                    minHeight: 10,
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.08),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 76,
                child: Text(
                  money(value),
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 11.5),
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
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.55),
          ),
        ),
      ],
    );
  }
}

class CallRow extends StatelessWidget {
  final String name;
  final String number;
  final String? detail;
  const CallRow({
    super.key,
    required this.name,
    required this.number,
    this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: theme.colorScheme.primary.withOpacity(0.15),
        child: Icon(Icons.call, size: 16, color: theme.colorScheme.primary),
      ),
      title: Text(name, style: const TextStyle(fontSize: 13.5)),
      subtitle: Text(
        detail ?? number,
        style: TextStyle(
          fontSize: 11,
          color: theme.colorScheme.onSurface.withOpacity(0.6),
        ),
      ),
      trailing: FilledButton.tonal(
        onPressed: () => dialNumber(context, number),
        child: const Text('Call'),
      ),
    );
  }
}
