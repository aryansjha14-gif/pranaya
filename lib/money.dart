import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core.dart';
import 'notify.dart';
import 'sms.dart';

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
  String _status = '';
  bool _importing = false;

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

  String get _topMerchant {
    final counts = <String, int>{};
    for (final e in _expenses.take(40)) {
      final note = (e['note'] as String?) ?? '';
      if (note.isEmpty) continue;
      counts[note] = (counts[note] ?? 0) + 1;
    }
    if (counts.isEmpty) return '-';
    var best = '';
    var bestCount = 0;
    counts.forEach((k, v) {
      if (v > bestCount) {
        best = k;
        bestCount = v;
      }
    });
    return best;
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
    final budget = repo.number('daily_budget');
    if (budget > 0 && _todaySpend > budget) {
      Notifier.instance.showNow(
        9001,
        'Daily budget crossed',
        'You have spent ${money(_todaySpend)} of ${money(budget)} today.',
      );
    }
  }

  void _submitPasted() {
    final text = _sms.text.trim();
    if (text.isEmpty) return;
    final parsed = parseBankSms(text);
    if (parsed.amount == null) {
      setState(() => _status = 'No amount found in that message.');
      return;
    }
    if (!parsed.isDebit) {
      setState(() => _status = 'That looks like a credit, not a spend.');
      return;
    }
    _addExpense(
      parsed.amount!,
      guessCategory(parsed.merchant ?? text),
      parsed.merchant ?? 'From SMS',
    );
    _sms.clear();
    setState(() {
      _status = 'Added ${money(parsed.amount!)} from SMS.';
    });
  }

  Future<void> _importFromInbox() async {
    setState(() {
      _importing = true;
      _status = 'Reading messages...';
    });
    final messages = await SmsReader.readInbox();
    if (!mounted) return;
    if (messages.isEmpty) {
      setState(() {
        _importing = false;
        _status =
            'No messages available. Allow SMS access, or paste a message below.';
      });
      return;
    }
    var added = 0;
    for (final m in messages) {
      final body = (m['body'] as String?) ?? '';
      final lower = body.toLowerCase();
      final looksBank = lower.contains('debited') ||
          lower.contains('spent') ||
          lower.contains('paid') ||
          lower.contains('withdrawn');
      if (!looksBank) continue;
      final dateMs = int.tryParse((m['date'] as String?) ?? '') ??
          DateTime.now().millisecondsSinceEpoch;
      final parsed = parseBankSms(body, dateMs: dateMs);
      if (parsed.amount == null) continue;
      final already = _expenses.any(
        (e) =>
            ((e['amount'] as num).toDouble() - parsed.amount!).abs() < 0.01 &&
            sameDay((e['ts'] as num).toInt(), dateMs),
      );
      if (already) continue;
      repo.add('expense', <String, dynamic>{
        'amount': parsed.amount,
        'category': guessCategory(parsed.merchant ?? body),
        'note': parsed.merchant ?? (m['address'] as String? ?? 'SMS'),
        'ts': dateMs,
      });
      added++;
    }
    setState(() {
      _importing = false;
      _status = added == 0
          ? 'No new bank messages found.'
          : 'Imported $added transactions from SMS.';
    });
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  void _exportSummary() {
    final buffer = StringBuffer()
      ..writeln(
          'Pranaya summary ${fmtDate(DateTime.now().millisecondsSinceEpoch)}')
      ..writeln('Spent today: ${money(_todaySpend)}')
      ..writeln('Spent this month: ${money(_monthSpend)}')
      ..writeln('Top payee: $_topMerchant')
      ..writeln('By category:');
    _byCategory.forEach((k, v) => buffer.writeln('  $k: ${money(v)}'));
    Clipboard.setData(ClipboardData(text: buffer.toString()));
    _toast('Summary copied to clipboard.');
  }

  @override
  Widget build(BuildContext context) {
    final budget = repo.number('daily_budget');
    final progress = budget <= 0 ? 0.0 : (_todaySpend / budget).clamp(0.0, 1.0);
    final recent = _expenses.take(8).toList();
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(20),
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                theme.colorScheme.primary.withOpacity(0.28),
                theme.colorScheme.primary.withOpacity(0.04),
              ],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Spent today',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurface.withOpacity(0.65),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                money(_todaySpend),
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 9,
                  backgroundColor: theme.colorScheme.onSurface.withOpacity(0.1),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  StatTile(label: 'this month', value: money(_monthSpend)),
                  StatTile(
                    label: 'limit',
                    value: budget <= 0 ? 'not set' : money(budget),
                  ),
                  StatTile(label: 'top payee', value: _topMerchant),
                ],
              ),
            ],
          ),
        ),
        SectionCard(
          title: 'DAILY LIMIT',
          icon: Icons.speed,
          child: Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _budget,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(hintText: 'e.g. 500'),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () {
                  final v = double.tryParse(_budget.text.trim());
                  if (v == null || v <= 0) return;
                  repo.setNumber('daily_budget', v);
                  _budget.clear();
                  setState(() {});
                  scheduleReminder(
                    key: 'budget',
                    title: 'Daily budget check',
                    body: 'How much is left for today?',
                    time: const TimeOfDay(hour: 20, minute: 30),
                  );
                  _toast('Limit saved and a nightly check scheduled.');
                },
                child: const Text('Save'),
              ),
            ],
          ),
        ),
        SectionCard(
          title: 'ADD EXPENSE',
          icon: Icons.add_card,
          child: Column(
            children: <Widget>[
              TextField(
                controller: _amount,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(hintText: 'Amount'),
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _category,
                      decoration: const InputDecoration(),
                      items: kCategories
                          .map(
                            (c) => DropdownMenuItem<String>(
                              value: c,
                              child: Text(c,
                                  style: const TextStyle(fontSize: 13)),
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
                      decoration: const InputDecoration(hintText: 'Note'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _submitManual,
                  icon: const Icon(Icons.check),
                  label: const Text('Add'),
                ),
              ),
            ],
          ),
        ),
        SectionCard(
          title: 'SMS IMPORTER',
          icon: Icons.sms_outlined,
          subtitle:
              'Reads bank messages on this phone and adds the spends. Nothing is uploaded.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              FilledButton.tonalIcon(
                onPressed: _importing ? null : _importFromInbox,
                icon: const Icon(Icons.download),
                label: Text(_importing ? 'Reading...' : 'Import from SMS inbox'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _sms,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Or paste one message: Rs.450 debited at SWIGGY',
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _submitPasted,
                child: const Text('Read pasted message'),
              ),
              if (_status.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  _status,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: theme.colorScheme.onSurface.withOpacity(0.65),
                  ),
                ),
              ],
            ],
          ),
        ),
        SectionCard(
          title: 'THIS MONTH',
          icon: Icons.pie_chart_outline,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              BarList(data: _byCategory),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: _exportSummary,
                icon: const Icon(Icons.copy_all),
                label: const Text('Copy summary'),
              ),
            ],
          ),
        ),
        SectionCard(
          title: 'RECENT',
          icon: Icons.receipt_long,
          child: recent.isEmpty
              ? const Text('Nothing yet.', style: TextStyle(fontSize: 12))
              : Column(
                  children: recent.map((e) {
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        radius: 16,
                        backgroundColor:
                            theme.colorScheme.primary.withOpacity(0.15),
                        child: Text(
                          ((e['category'] as String?) ?? 'O').substring(0, 1),
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
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
                              Icons.close,
                              size: 16,
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
        RecurringBillsCard(repo: repo, onChanged: () => setState(() {})),
        SavingsGoalCard(repo: repo),
        InflationCard(repo: repo),
        DebtCard(repo: repo),
        SplitBillCard(repo: repo),
        UnitPriceCard(repo: repo),
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
      monthly += (s['amount'] as num).toDouble();
    }
    return SectionCard(
      title: 'SUBSCRIPTIONS',
      icon: Icons.autorenew,
      subtitle: 'Monthly total: ${money(monthly)}',
      child: Column(
        children: <Widget>[
          ...subs.map(
            (s) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(s['name'] as String,
                  style: const TextStyle(fontSize: 13)),
              subtitle: Text(
                '${money((s['amount'] as num).toDouble())} per month',
                style: const TextStyle(fontSize: 10),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.close,
                    size: 16, color: Colors.redAccent),
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
                  decoration: const InputDecoration(hintText: 'Netflix'),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 92,
                child: TextField(
                  controller: _cost,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(hintText: '649'),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle),
                onPressed: () {
                  final cost = double.tryParse(_cost.text.trim());
                  if (_name.text.trim().isEmpty || cost == null) return;
                  widget.repo.add('sub', <String, dynamic>{
                    'name': _name.text.trim(),
                    'amount': cost,
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
      title: 'IMPULSE HOLD',
      icon: Icons.hourglass_bottom,
      subtitle: 'Park a purchase for 24 hours before deciding.',
      child: Column(
        children: <Widget>[
          ...holds.map((h) {
            final created = (h['ts'] as num).toInt();
            final leftMs = created + 24 * 3600 * 1000 - now;
            final hoursLeft =
                (leftMs / 3600000).clamp(0, 24).toStringAsFixed(1);
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(h['item'] as String,
                  style: const TextStyle(fontSize: 13)),
              subtitle: Text(
                leftMs > 0
                    ? '${hoursLeft}h left - ${money((h['amount'] as num).toDouble())}'
                    : 'Ready to decide',
                style: const TextStyle(fontSize: 10),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.close, size: 16),
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
                  decoration: const InputDecoration(hintText: 'What to buy?'),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 84,
                child: TextField(
                  controller: _cost,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(hintText: 'Rs'),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle),
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

class RecurringBillsCard extends StatefulWidget {
  final Repo repo;
  final VoidCallback onChanged;
  const RecurringBillsCard({
    super.key,
    required this.repo,
    required this.onChanged,
  });

  @override
  State<RecurringBillsCard> createState() => _RecurringBillsCardState();
}

class _RecurringBillsCardState extends State<RecurringBillsCard> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _day = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final bills = widget.repo.list('bill');
    final today = DateTime.now().day;
    return SectionCard(
      title: 'MONTHLY BILLS',
      icon: Icons.event_repeat,
      subtitle: 'Tap the bell to get a reminder on that date.',
      child: Column(
        children: <Widget>[
          ...bills.map((b) {
            final due = (b['day'] as num).toInt();
            final soon = due >= today && due - today <= 3;
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(b['name'] as String,
                  style: const TextStyle(fontSize: 13)),
              subtitle: Text(
                soon ? 'Due on day $due - coming up' : 'Due on day $due',
                style: TextStyle(
                  fontSize: 10,
                  color: soon ? Colors.orangeAccent : null,
                ),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.notifications_active, size: 18),
                onPressed: () {
                  scheduleReminder(
                    key: 'bill_${b['name']}',
                    title: 'Bill due: ${b['name']}',
                    body: 'Today is the usual date for this bill.',
                    time: const TimeOfDay(hour: 9, minute: 0),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Daily 9 am reminder set for this bill.'),
                    ),
                  );
                },
              ),
            );
          }),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _name,
                  decoration: const InputDecoration(hintText: 'Electricity'),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 70,
                child: TextField(
                  controller: _day,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(hintText: 'Day'),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle),
                onPressed: () {
                  final day = int.tryParse(_day.text.trim());
                  if (_name.text.trim().isEmpty || day == null) return;
                  widget.repo.add('bill', <String, dynamic>{
                    'name': _name.text.trim(),
                    'day': day.clamp(1, 28),
                  });
                  _name.clear();
                  _day.clear();
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
    return _CalcCard(
      title: 'GOAL CALCULATOR',
      icon: Icons.flag_outlined,
      fields: <Widget>[
        TextField(
          controller: _target,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: 'Target amount'),
        ),
        const SizedBox(width: 8),
        TextField(
          controller: _monthly,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: 'Per month'),
        ),
      ],
      result: _result,
      onCalculate: _calculate,
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
    for (var i = 0; i < exponent; i++) {
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
    final future = amount * _pow(1.06, years);
    final worth = amount / _pow(1.06, years);
    setState(() {
      _result = 'At 6 percent inflation, ${money(amount)} today needs '
          '${money(future)} in $years years. ${money(amount)} then is worth '
          '${money(worth)} today.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return _CalcCard(
      title: 'INFLATION IMPACT',
      icon: Icons.trending_up,
      fields: <Widget>[
        TextField(
          controller: _amount,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: 'Amount today'),
        ),
        const SizedBox(width: 8),
        TextField(
          controller: _years,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: 'Years'),
        ),
      ],
      result: _result,
      onCalculate: _calculate,
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
    return _CalcCard(
      title: 'DEBT PAYOFF',
      icon: Icons.account_balance,
      fields: <Widget>[
        TextField(
          controller: _balance,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: 'Balance'),
        ),
        const SizedBox(width: 6),
        TextField(
          controller: _rate,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: 'Rate %'),
        ),
        const SizedBox(width: 6),
        TextField(
          controller: _payment,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: 'EMI'),
        ),
      ],
      result: _result,
      onCalculate: _calculate,
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
    return _CalcCard(
      title: 'SPLIT BILL',
      icon: Icons.groups_outlined,
      fields: <Widget>[
        TextField(
          controller: _total,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: 'Bill total'),
        ),
        const SizedBox(width: 8),
        TextField(
          controller: _people,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: 'People'),
        ),
      ],
      result: _result,
      onCalculate: _split,
    );
  }
}

class UnitPriceCard extends StatefulWidget {
  final Repo repo;
  const UnitPriceCard({super.key, required this.repo});

  @override
  State<UnitPriceCard> createState() => _UnitPriceCardState();
}

class _UnitPriceCardState extends State<UnitPriceCard> {
  final TextEditingController _priceA = TextEditingController();
  final TextEditingController _sizeA = TextEditingController();
  final TextEditingController _priceB = TextEditingController();
  final TextEditingController _sizeB = TextEditingController();
  String _result = '';

  void _compare() {
    final pa = double.tryParse(_priceA.text.trim());
    final sa = double.tryParse(_sizeA.text.trim());
    final pb = double.tryParse(_priceB.text.trim());
    final sb = double.tryParse(_sizeB.text.trim());
    if (pa == null ||
        sa == null ||
        pb == null ||
        sb == null ||
        sa <= 0 ||
        sb <= 0) {
      setState(() => _result = 'Fill all four fields.');
      return;
    }
    final perA = pa / sa;
    final perB = pb / sb;
    final cheaper = perA < perB ? 'A' : 'B';
    setState(() {
      _result = 'A: ${perA.toStringAsFixed(2)} per unit, '
          'B: ${perB.toStringAsFixed(2)} per unit. Pack $cheaper is cheaper.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'PACK PRICE COMPARISON',
      icon: Icons.compare_arrows,
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _priceA,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(hintText: 'A price'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _sizeA,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(hintText: 'A grams'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _priceB,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(hintText: 'B price'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _sizeB,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(hintText: 'B grams'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _compare,
              child: const Text('Compare'),
            ),
          ),
          if (_result.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(_result, style: const TextStyle(fontSize: 12)),
          ],
        ],
      ),
    );
  }
}

class _CalcCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> fields;
  final String result;
  final VoidCallback onCalculate;
  const _CalcCard({
    required this.title,
    required this.icon,
    required this.fields,
    required this.result,
    required this.onCalculate,
  });

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: title,
      icon: icon,
      child: Column(
        children: <Widget>[
          Row(children: fields),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onCalculate,
              child: const Text('Calculate'),
            ),
          ),
          if (result.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(result, style: const TextStyle(fontSize: 12)),
            ),
          ],
        ],
      ),
    );
  }
}
