import 'package:flutter/material.dart';

/// حقل نص بيقترح اختيارات وإنت بتكتب، ويقبل أي حاجة مكتوبة برا القائمة.
class SuggestField extends StatefulWidget {
  const SuggestField({
    super.key,
    required this.controller,
    required this.label,
    required this.options,
    this.icon,
    this.validator,
    this.onSelected,
    this.textDirection,
  });

  final TextEditingController controller;
  final String label;
  final Iterable<String> Function() options;
  final IconData? icon;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onSelected;
  final TextDirection? textDirection;

  @override
  State<SuggestField> createState() => _SuggestFieldState();
}

class _SuggestFieldState extends State<SuggestField> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<String>(
      textEditingController: widget.controller,
      focusNode: _focus,
      optionsBuilder: (value) {
        final q = value.text.trim().toLowerCase();
        final all = widget.options();
        if (q.isEmpty) return all.take(12);
        final starts = all.where((o) => o.toLowerCase().startsWith(q));
        final contains = all.where((o) => !o.toLowerCase().startsWith(q) && o.toLowerCase().contains(q));
        return [...starts, ...contains].take(12);
      },
      onSelected: widget.onSelected,
      fieldViewBuilder: (context, controller, focus, onSubmit) => TextFormField(
        controller: controller,
        focusNode: focus,
        textDirection: widget.textDirection,
        decoration: InputDecoration(labelText: widget.label, prefixIcon: widget.icon == null ? null : Icon(widget.icon)),
        validator: widget.validator,
        onFieldSubmitted: (_) => onSubmit(),
      ),
      optionsViewBuilder: (context, onSelect, options) => Align(
        alignment: AlignmentDirectional.topStart,
        child: Material(
          elevation: 6,
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280, maxWidth: 360),
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 6),
              shrinkWrap: true,
              children: [
                for (final o in options)
                  ListTile(dense: true, title: Text(o, textDirection: widget.textDirection), onTap: () => onSelect(o)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
