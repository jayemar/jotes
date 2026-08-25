import 'package:flutter/material.dart';
import '../models/repeat_rule.dart';

enum _EndMode { never, onDate, afterCount }

/// Full custom recurrence editor - interval count, specific weekdays (for a
/// weekly rule), and an end condition - reached from ReminderEditScreen's
/// Repeat picker sheet via its own "Custom..." option, modeled directly on
/// Google Calendar's own Custom recurrence dialog (on request), which the
/// picker sheet's 6 quick presets (the original 5 fixed presets plus
/// "Every weekday") don't cover.
class CustomRecurrenceScreen extends StatefulWidget {
  /// The rule to start editing from - a fresh default (weekly, on the
  /// reminder's own weekday, never-ending) when null or when it doesn't
  /// carry enough detail of its own (e.g. a quick preset has no specific
  /// weekdays set yet).
  final RepeatRule? initialRule;

  /// The reminder's own date - source of the default weekday (and the
  /// earliest selectable "ends on" date) when [initialRule] doesn't
  /// already specify one.
  final DateTime startDate;

  const CustomRecurrenceScreen({
    super.key,
    this.initialRule,
    required this.startDate,
  });

  @override
  State<CustomRecurrenceScreen> createState() =>
      _CustomRecurrenceScreenState();
}

class _CustomRecurrenceScreenState extends State<CustomRecurrenceScreen> {
  late final TextEditingController _intervalCtrl;
  late final TextEditingController _endCountCtrl;
  late RepeatFrequency _frequency;
  late int _interval;
  late Set<int> _weekdays;
  late _EndMode _endMode;
  late DateTime _endDate;
  late int _endCount;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialRule;
    _frequency = initial?.frequency ?? RepeatFrequency.weekly;
    _interval = initial?.interval ?? 1;
    _intervalCtrl = TextEditingController(text: '$_interval');
    _weekdays = (initial != null && initial.weekdays.isNotEmpty)
        ? {...initial.weekdays}
        : {widget.startDate.weekday};

    final defaultEndDate = widget.startDate.add(const Duration(days: 30));
    switch (initial?.end) {
      case RepeatEndOnDate(:final date):
        _endMode = _EndMode.onDate;
        _endDate = date;
        _endCount = 1;
      case RepeatEndAfterCount(:final count):
        _endMode = _EndMode.afterCount;
        _endCount = count;
        _endDate = defaultEndDate;
      case _:
        _endMode = _EndMode.never;
        _endCount = 1;
        _endDate = defaultEndDate;
    }
    _endCountCtrl = TextEditingController(text: '$_endCount');
  }

  @override
  void dispose() {
    _intervalCtrl.dispose();
    _endCountCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickEndDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _endDate.isAfter(widget.startDate)
          ? _endDate
          : widget.startDate,
      firstDate: widget.startDate,
      lastDate: widget.startDate.add(const Duration(days: 365 * 10)),
    );
    if (date == null || !mounted) return;
    setState(() => _endDate = date);
  }

  void _done() {
    final end = switch (_endMode) {
      _EndMode.never => const RepeatEndNever(),
      _EndMode.onDate => RepeatEndOnDate(_endDate),
      _EndMode.afterCount => RepeatEndAfterCount(_endCount),
    };
    Navigator.pop(
      context,
      RepeatRule(
        frequency: _frequency,
        interval: _interval,
        weekdays: _frequency == RepeatFrequency.weekly ? _weekdays : const {},
        end: end,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Cancel',
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Custom recurrence'),
        actions: [
          IconButton(
            key: const Key('custom_recurrence_done'),
            icon: const Icon(Icons.check),
            tooltip: 'Done',
            onPressed: _done,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              const Text('Repeat every'),
              const SizedBox(width: 12),
              SizedBox(
                width: 56,
                child: TextField(
                  key: const Key('custom_recurrence_interval'),
                  controller: _intervalCtrl,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  onChanged: (value) {
                    final parsed = int.tryParse(value);
                    if (parsed != null && parsed >= 1) {
                      setState(() => _interval = parsed);
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButton<RepeatFrequency>(
                  key: const Key('custom_recurrence_frequency'),
                  value: _frequency,
                  isExpanded: true,
                  items: [
                    for (final frequency in RepeatFrequency.values)
                      DropdownMenuItem(
                        value: frequency,
                        child: Text(
                          _interval == 1
                              ? frequency.unitLabel
                              : '${frequency.unitLabel}s',
                        ),
                      ),
                  ],
                  onChanged: (frequency) {
                    if (frequency == null) return;
                    setState(() => _frequency = frequency);
                  },
                ),
              ),
            ],
          ),
          if (_frequency == RepeatFrequency.weekly) ...[
            const SizedBox(height: 24),
            const Text('Repeat on'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final entry in weekdayShortLabels.entries)
                  FilterChip(
                    key: Key('custom_recurrence_weekday_${entry.key}'),
                    label: Text(entry.value),
                    selected: _weekdays.contains(entry.key),
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _weekdays.add(entry.key);
                        } else if (_weekdays.length > 1) {
                          // At least one weekday must stay selected - a
                          // weekly rule with none picked would never fire.
                          _weekdays.remove(entry.key);
                        }
                      });
                    },
                  ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          const Text('Ends', style: TextStyle(fontWeight: FontWeight.bold)),
          RadioGroup<_EndMode>(
            groupValue: _endMode,
            onChanged: (mode) {
              if (mode == null) return;
              setState(() => _endMode = mode);
            },
            child: Column(
              children: [
                const RadioListTile<_EndMode>(
                  key: Key('custom_recurrence_end_never'),
                  value: _EndMode.never,
                  contentPadding: EdgeInsets.zero,
                  title: Text('Never'),
                ),
                RadioListTile<_EndMode>(
                  key: const Key('custom_recurrence_end_on_date'),
                  value: _EndMode.onDate,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('On'),
                  subtitle: _endMode == _EndMode.onDate
                      ? OutlinedButton(
                          key: const Key('custom_recurrence_end_date_button'),
                          onPressed: _pickEndDate,
                          child: Text(
                            '${_endDate.year}-'
                            '${_endDate.month.toString().padLeft(2, '0')}-'
                            '${_endDate.day.toString().padLeft(2, '0')}',
                          ),
                        )
                      : null,
                ),
                RadioListTile<_EndMode>(
                  key: const Key('custom_recurrence_end_after_count'),
                  value: _EndMode.afterCount,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('After'),
                  subtitle: _endMode == _EndMode.afterCount
                      ? Row(
                          children: [
                            SizedBox(
                              width: 56,
                              child: TextField(
                                key: const Key('custom_recurrence_end_count'),
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                controller: _endCountCtrl,
                                onChanged: (value) {
                                  final parsed = int.tryParse(value);
                                  if (parsed != null && parsed >= 1) {
                                    setState(() => _endCount = parsed);
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(_endCount == 1 ? 'occurrence' : 'occurrences'),
                          ],
                        )
                      : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
