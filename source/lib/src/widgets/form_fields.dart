import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/format.dart';
import '../core/theme.dart';

/// كارت بعنوان وأيقونة بيجمع مجموعة حقول في الفورم.
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, required this.icon, required this.children, this.trailing});

  final String title;
  final IconData icon;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium?.bold)),
                ?trailing,
              ],
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// حقل فلوس بالجنيه: بيقبل أرقام عربي وإنجليزي وفواصل.
class MoneyField extends StatelessWidget {
  const MoneyField({
    super.key,
    required this.controller,
    required this.label,
    this.validator,
    this.onChanged,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String label;
  final String? Function(int? cents)? validator;
  final ValueChanged<String>? onChanged;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩.,٫]'))],
      decoration: InputDecoration(labelText: label, suffixText: 'ج.م', prefixIcon: const Icon(Icons.payments_outlined)),
      onChanged: onChanged,
      validator: (v) {
        final cents = parseMoney(v ?? '');
        if (cents == null) return 'اكتب رقم صحيح';
        return validator?.call(cents);
      },
    );
  }
}

/// اختيار الموعد المتوقع: أزرار سريعة (النهارده، بكرة، ...) أو اختيار يوم وساعة.
class DuePicker extends StatelessWidget {
  const DuePicker({super.key, required this.value, required this.onChanged});

  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;

  DateTime _at(int daysFromNow, int hour) {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day + daysFromNow, hour);
  }

  Future<void> _pickCustom(BuildContext context) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: value ?? now.add(const Duration(days: 1)),
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(value ?? DateTime(now.year, now.month, now.day, 18)),
    );
    if (time == null) return;
    onChanged(DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  @override
  Widget build(BuildContext context) {
    final options = <String, DateTime>{
      'النهارده': _at(0, 20),
      'بكرة': _at(1, 18),
      'بعد يومين': _at(2, 18),
      'بعد 3 أيام': _at(3, 18),
      'بعد أسبوع': _at(7, 18),
    };
    bool same(DateTime a, DateTime b) => a.difference(b).inMinutes.abs() < 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final e in options.entries)
              ChoiceChip(
                label: Text(e.key),
                selected: value != null && same(value!, e.value),
                onSelected: (_) => onChanged(e.value),
              ),
            ActionChip(
              avatar: const Icon(Icons.event_rounded, size: 18),
              label: const Text('اختار يوم وساعة'),
              onPressed: () => _pickCustom(context),
            ),
          ],
        ),
        if (value != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.schedule_rounded, size: 18, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 6),
              Text('الموعد المتوقع: ${formatDateTime(value!)}', style: const TextStyle().semiBold),
              IconButton(
                tooltip: 'من غير موعد',
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () => onChanged(null),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// مجموعة اختيارات متعددة (Chips).
class MultiChips extends StatelessWidget {
  const MultiChips({super.key, required this.options, required this.selected, required this.onChanged});

  final List<String> options;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final o in options)
          FilterChip(
            label: Text(o),
            selected: selected.contains(o),
            onSelected: (v) => onChanged(v ? ({...selected, o}) : ({...selected}..remove(o))),
          ),
      ],
    );
  }
}
