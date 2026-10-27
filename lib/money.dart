import 'package:flutter/material.dart';

import 'core.dart';

class MoneyTab extends StatefulWidget {
  final Repo repo;
  const MoneyTab({super.key, required this.repo});

  @override
  State<MoneyTab> createState() => _MoneyTabState();
}

class _MoneyTabState extends State<MoneyTab> {
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _note = TextEditingController();
  final TextEditingController _sms = TextEditingController();
  final TextEditingController _budget = TextEditingController();
  String _category = 'Food';
  String _smsMessage = '';

  Repo get repo => widget.repo;

  List<Map<String, dynamic>> get _expenses => repo.list('expense');

  double get _todaySpend {
    final now = DateTime.now().millisecondsSinceEpoch;
    var total = 0.0;
    for (final e in _expenses) {
      if (sameDay((e['ts'] as num).toInt(), now)) {
        total += (e['amount'] as num).toDouble();
      }
    }
    return total;
  }

  double get _monthSpend {
    final now = DateTime.now().millisecondsSinceEpoch;
    var total = 0.0;
    for (final e in _expenses) {
      if (sameMonth((e['ts'] as num).toInt(), now)) {
        total += (e['amount'] as num).toDouble();
      }
    }
    return total;
  }

  Map<String, double> get _byCategory {
    final now = DateTime.now().millisecondsSinceEpoch;
    final map = <String, double>{};
    for (final e in _expenses) {
      if (!sameMonth((e['ts'] as num).toInt(), now)) continue;
      final cat = (e['category'] as String?) ?? 'Other';
      map[cat] = (map[cat] ?? 0) + (e['amount'] as num).toDouble();
    }
    return map;
  }

  void _addExpense(double value, String category, String note) {
    if (value <= 0) return;
    repo.add('expense', <String, dynamic>{
      'amount': value,
      'category': category,
      'note': note,
    });
    setState(() {});
  }

  void _submitManual() {
    final value = double.tryParse(_amount.text.trim());
    if (value == null || value <= 0) {
      _toast('Enter a valid amount.');
      return;
    }
    _addExpense(value, _category, _note.text.trim());
    _amount.clear();
    _note.clear();
    _toast('Saved.');
  }

  void _submitSms() {
    final text = _sms.text.trim();
    if (text.isEmpty) return;
    final parsed = parseBankSms(text);
    if (parsed.amount == null) {
      setState(() => _smsMessage = 'No amount found in that message.');
      return;
    }
    if (!parsed.isDebit) {
      setState(() => _smsMessage = 'That looks like a credit, not a spend.');
      return;
    }
    _addExpense(
      parsed.amount!,
      _guessCategory(parsed.merchant ?? text),
      parsed.merchant ?? 'From SMS',
    );
    _sms.clear();
    setState(() {
      _smsMessage = 'Added ${money(parsed.amount!)} from SMS.';
    });
  }

  String _guessCategory(String text) {
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
        lower.contains('irctc')) {
      return 'Travel';
    }
    if (lower.contains('jio') ||
        lower.contains('airtel') ||
        lower.contains('electric') ||
        lower.contains('bill')) {
      return 'Bills';
    }
    if (lower.contains('pharmacy') ||
        lower.contains('hospital') ||
        lower.contains('medical')) {
      return 'Health';
    }
    if (lower.contains('amazon') ||
        lower.contains('flipkart') ||
        lower.contains('myntra')) {
      return 'Shopping';
    }
    return 'Other';
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final budget = repo.number('daily_budget');
    final progress = budget <= 0 ? 0.0 : (_todaySpend / budget).clamp(0.0, 1.0);
    final recent = _expenses.take(8).toList();

    return ListView(
      padding: const EdgeInsets.all(14),
      children: <Widget>[
        SectionCard(
          title: 'DAILY BUDGET GUARD',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  StatTile(
                    label: 'spent today',
                    value: money(_todaySpend),
                    colour: progress > 0.99 ? Colors.redAccent : null,
                  ),
                  StatTile(label: 'this month', value: money(_monthSpend)),
                  StatTile(
                    label: 'daily limit',
                    value: budget <= 0 ? 'not set' : money(budget),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: Colors.white12,
                color: progress > 0.99 ? Colors.redAccent : null,
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _budget,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        hintText: 'Set daily limit, e.g. 500',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () {
                      final v = double.tryParse(_budget.text.trim());
                      if (v == null || v <= 0) return;
                      repo.setNumber('daily_budget', v);
                      _budget.clear();
                      setState(() {});
                    },
                    child: const Text('SAVE'),
                  ),
                ],
              ),
            ],
          ),
        ),
        SectionCard(
          title: 'QUICK ADD',
          child: Column(
            children: <Widget>[
              TextField(
                controller: _amount,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  hintText: 'Amount',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _category,
                      decoration: const InputDecoration(isDense: true),
                      items: kCategories
                          .map(
                            (c) => DropdownMenuItem<String>(
                              value: c,
                              child:
                                  Text(c, style: const TextStyle(fontSize: 13)),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => _category = v ?? 'Food'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _note,
                      decoration: const InputDecoration(
                        hintText: 'Note',
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submitManual,
                  child: const Text('ADD EXPENSE'),
                ),
              ),
            ],
          ),
        ),
        SectionCard(
          title: 'BANK SMS PARSER',
          subtitle:
              'Reading SMS in the background is blocked by Play Store, so paste the message here instead.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              TextField(
                controller: _sms,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Rs.450.00 debited from A/c ... at SWIGGY on 12-05',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _submitSms,
                  child: const Text('READ MESSAGE'),
                ),
              ),
              if (_smsMessage.isNotEmpty) ...<Widget>[
                const SizedBox(height: 6),
                Text(
                  _smsMessage,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ],
          ),
        ),
        SectionCard(
          title: 'THIS MONTH BY CATEGORY',
          child: BarList(data: _byCategory),
        ),
        SectionCard(
          title: 'RECENT ENTRIES',
          child: recent.isEmpty
              ? const Text('Nothing yet.', style: TextStyle(fontSize: 12))
              : Column(
                  children: recent.map((e) {
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        (e['note'] as String?)?.isNotEmpty == true
                            ? e['note'] as String
                            : e['category'] as String,
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: Text(
                        '${e['category']} - ${fmtDate((e['ts'] as num).toInt())}',
                        style: const TextStyle(fontSize: 10),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            money((e['amount'] as num).toDouble()),
                            style: const TextStyle(fontSize: 13),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.delete_outline,
                              size: 18,
                              color: Colors.redAccent,
                            ),
                            onPressed: () {
                              repo.remove(e['id'] as String);
                              setState(() {});
                            },
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
        ),
        SubscriptionCard(repo: repo, onChanged: () => setState(() {})),
        ImpulseHoldCard(repo: repo, onChanged: () => setState(() {})),
        SavingsGoalCard(repo: repo),
        InflationCard(repo: repo),
        DebtCard(repo: repo),
        SplitBillCard(repo: repo),
      ],
    );
  }
}

class SubscriptionCard extends StatefulWidget {
  final Repo repo;
  final VoidCallback onChanged;
  const SubscriptionCard({
    super.key,
    required this.repo,
    required this.onChanged,
  });

  @override
  State<SubscriptionCard> createState() => _SubscriptionCardState();
}

class _SubscriptionCardState extends State<SubscriptionCard> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _cost = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final subs = widget.repo.list('sub');
    var monthly = 0.0;
    for (final s in subs) {
      final amount = (s['amount'] as num).toDouble();
      monthly += s['cycle'] == 'yearly' ? amount / 12 : amount;
    }
    return SectionCard(
      title: 'SUBSCRIPTION DRAIN',
      subtitle: 'Monthly total: ${money(monthly)}',
      child: Column(
        children: <Widget>[
          ...subs.map(
            (s) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(
                s['name'] as String,
                style: const TextStyle(fontSize: 13),
              ),
              subtitle: Text(
                '${money((s['amount'] as num).toDouble())} / ${s['cycle']}',
                style: const TextStyle(fontSize: 10),
              ),
              trailing: IconButton(
                icon: const Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: Colors.redAccent,
                ),
                onPressed: () {
                  widget.repo.remove(s['id'] as String);
                  widget.onChanged();
                  setState(() {});
                },
              ),
            ),
          ),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _name,
                  decoration: const InputDecoration(
                    hintText: 'Netflix',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 90,
                child: TextField(
                  controller: _cost,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    hintText: '649',
                    isDense: true,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                onPressed: () {
                  final cost = double.tryParse(_cost.text.trim());
                  if (_name.text.trim().isEmpty || cost == null) return;
                  widget.repo.add('sub', <String, dynamic>{
                    'name': _name.text.trim(),
                    'amount': cost,
                    'cycle': 'monthly',
                  });
                  _name.clear();
                  _cost.clear();
                  widget.onChanged();
                  setState(() {});
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ImpulseHoldCard extends StatefulWidget {
  final Repo repo;
  final VoidCallback onChanged;
  const ImpulseHoldCard({
    super.key,
    required this.repo,
    required this.onChanged,
  });

  @override
  State<ImpulseHoldCard> createState() => _ImpulseHoldCardState();
}

class _ImpulseHoldCardState extends State<ImpulseHoldCard> {
  final TextEditingController _item = TextEditingController();
  final TextEditingController _cost = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final holds = widget.repo.list('hold');
    final now = DateTime.now().millisecondsSinceEpoch;
    return SectionCard(
      title: 'IMPULSE HOLD (24 HOURS)',
      subtitle: 'Park a purchase here instead of buying it now.',
      child: Column(
        children: <Widget>[
          ...holds.map((h) {
            final created = (h['ts'] as num).toInt();
            final leftMs = created + 24 * 3600 * 1000 - now;
            final hoursLeft = (leftMs / 3600000).clamp(0, 24).toStringAsFixed(1);
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(
                h['item'] as String,
                style: const TextStyle(fontSize: 13),
              ),
              subtitle: Text(
                leftMs > 0
                    ? '${hoursLeft}h left - ${money((h['amount'] as num).toDouble())}'
                    : 'Ready to decide',
                style: const TextStyle(fontSize: 10),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () {
                  widget.repo.remove(h['id'] as String);
                  widget.onChanged();
                  setState(() {});
                },
              ),
            );
          }),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _item,
                  decoration: const InputDecoration(
                    hintText: 'What do you want to buy?',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 80,
                child: TextField(
                  controller: _cost,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(hintText: 'Rs', isDense: true),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                onPressed: () {
                  final cost = double.tryParse(_cost.text.trim()) ?? 0;
                  if (_item.text.trim().isEmpty) return;
                  widget.repo.add('hold', <String, dynamic>{
                    'item': _item.text.trim(),
                    'amount': cost,
                  });
                  _item.clear();
                  _cost.clear();
                  widget.onChanged();
                  setState(() {});
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class SavingsGoalCard extends StatefulWidget {
  final Repo repo;
  const SavingsGoalCard({super.key, required this.repo});

  @override
  State<SavingsGoalCard> createState() => _SavingsGoalCardState();
}

class _SavingsGoalCardState extends State<SavingsGoalCard> {
  final TextEditingController _target = TextEditingController();
  final TextEditingController _monthly = TextEditingController();
  String _result = '';

  void _calculate() {
    final target = double.tryParse(_target.text.trim());
    final monthly = double.tryParse(_monthly.text.trim());
    if (target == null || monthly == null || monthly <= 0) {
      setState(() => _result = 'Enter both numbers.');
      return;
    }
    final months = (target / monthly).ceil();
    final years = months ~/ 12;
    final rest = months % 12;
    setState(() {
      _result = years > 0
          ? '$years year(s) $rest month(s) to reach ${money(target)}'
          : '$months month(s) to reach ${money(target)}';
    });
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'GOAL CALCULATOR',
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _target,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    hintText: 'Target amount',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _monthly,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    hintText: 'Save per month',
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _calculate,
              child: const Text('CALCULATE'),
            ),
          ),
          if (_result.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Text(_result, style: const TextStyle(fontSize: 12)),
          ],
        ],
      ),
    );
  }
}

class InflationCard extends StatefulWidget {
  final Repo repo;
  const InflationCard({super.key, required this.repo});

  @override
  State<InflationCard> createState() => _InflationCardState();
}

class _InflationCardState extends State<InflationCard> {
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _years = TextEditingController();
  String _result = '';

  double _pow(double base, int exponent) {
    var result = 1.0;
    var count = exponent;
    if (count < 1) count = 1;
    for (var i = 0; i < count; i++) {
      result *= base;
    }
    return result;
  }

  void _calculate() {
    final amount = double.tryParse(_amount.text.trim());
    final years = int.tryParse(_years.text.trim());
    if (amount == null || years == null || years <= 0) {
      setState(() => _result = 'Enter both numbers.');
      return;
    }
    const rate = 0.06;
    final future = amount * _pow(1 + rate, years);
    final worth = amount / _pow(1 + rate, years);
    setState(() {
      _result = 'At 6 percent inflation, ${money(amount)} today will need '
          '${money(future)} in $years years. ${money(amount)} then is worth '
          '${money(worth)} today.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'INFLATION IMPACT',
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _amount,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    hintText: 'Amount today',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _years,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    hintText: 'Years',
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _calculate,
              child: const Text('CALCULATE'),
            ),
          ),
          if (_result.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Text(_result, style: const TextStyle(fontSize: 12)),
          ],
        ],
      ),
    );
  }
}

class DebtCard extends StatefulWidget {
  final Repo repo;
  const DebtCard({super.key, required this.repo});

  @override
  State<DebtCard> createState() => _DebtCardState();
}

class _DebtCardState extends State<DebtCard> {
  final TextEditingController _balance = TextEditingController();
  final TextEditingController _rate = TextEditingController();
  final TextEditingController _payment = TextEditingController();
  String _result = '';

  void _calculate() {
    final balance = double.tryParse(_balance.text.trim());
    final rate = double.tryParse(_rate.text.trim());
    final payment = double.tryParse(_payment.text.trim());
    if (balance == null || rate == null || payment == null || payment <= 0) {
      setState(() => _result = 'Fill all three fields.');
      return;
    }
    final monthlyRate = rate / 12 / 100;
    var remaining = balance;
    var months = 0;
    var interest = 0.0;
    while (remaining > 0 && months < 1200) {
      final monthlyInterest = remaining * monthlyRate;
      interest += monthlyInterest;
      remaining = remaining + monthlyInterest - payment;
      months++;
      if (monthlyInterest >= payment && months > 12) break;
    }
    if (remaining > 0) {
      setState(() {
        _result = 'At this payment the debt never clears. Pay more.';
      });
      return;
    }
    setState(() {
      _result =
          'Cleared in $months month(s). Total interest ${money(interest)}.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'DEBT PAYOFF',
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _balance,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    hintText: 'Balance',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 70,
                child: TextField(
                  controller: _rate,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    hintText: 'percent',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 80,
                child: TextField(
                  controller: _payment,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    hintText: 'EMI',
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _calculate,
              child: const Text('CALCULATE'),
            ),
          ),
          if (_result.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Text(_result, style: const TextStyle(fontSize: 12)),
          ],
        ],
      ),
    );
  }
}

class SplitBillCard extends StatefulWidget {
  final Repo repo;
  const SplitBillCard({super.key, required this.repo});

  @override
  State<SplitBillCard> createState() => _SplitBillCardState();
}

class _SplitBillCardState extends State<SplitBillCard> {
  final TextEditingController _total = TextEditingController();
  final TextEditingController _people = TextEditingController();
  String _result = '';

  void _split() {
    final total = double.tryParse(_total.text.trim());
    final count = int.tryParse(_people.text.trim());
    if (total == null || count == null || count <= 0) {
      setState(() => _result = 'Enter a total and how many people.');
      return;
    }
    final each = total / count;
    widget.repo.add('split', <String, dynamic>{
      'total': total,
      'people': count,
      'each': each,
    });
    setState(() {
      _result = '${money(each)} each, for $count people.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'SPLIT BILL',
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _total,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    hintText: 'Bill total',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _people,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    hintText: 'People',
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _split,
              child: const Text('SPLIT'),
            ),
          ),
          if (_result.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Text(_result, style: const TextStyle(fontSize: 12)),
          ],
        ],
      ),
    );
  }
}
