import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:splg_lib/splg_lib.dart';

/// Campo de texto con su rótulo arriba; es dueño de su controller.
class LabeledField extends StatefulWidget {
  const LabeledField({
    super.key,
    required this.label,
    required this.onChanged,
    this.hint,
    this.number = false,
    this.enabled = true,
    this.maxLength,
    this.initial = '',
  });

  final String label;
  final String? hint;
  final ValueChanged<String> onChanged;
  final bool number;
  final bool enabled;
  final int? maxLength;

  /// Texto con el que arranca (para no perder lo tipeado si la pantalla se rearma).
  final String initial;

  @override
  State<LabeledField> createState() => _LabeledFieldState();
}

class _LabeledFieldState extends State<LabeledField> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final type = SplgType.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.label, style: type.bodyStrong),
          const SizedBox(height: 6),
          SplgTextField(
            controller: _controller,
            hint: widget.hint,
            enabled: widget.enabled,
            onChanged: widget.onChanged,
            inputFormatters: widget.maxLength == null
                ? null
                : [LengthLimitingTextInputFormatter(widget.maxLength)],
            keyboardType: widget.number
                ? const TextInputType.numberWithOptions(decimal: true)
                : TextInputType.text,
          ),
        ],
      ),
    );
  }
}

/// Mensaje de error de una acción, en rojo Brasa.
class ActionError extends StatelessWidget {
  const ActionError(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(message,
            key: const Key('action-error'),
            style: SplgType.of(context)
                .body
                .copyWith(color: context.brasa.danger)),
      );
}

/// Renglón rótulo / valor.
class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key, this.strong = false});

  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final type = SplgType.of(context);
    final labelStyle = strong ? type.subtitle : type.body;
    final valueStyle = strong
        ? type.subtitle
        : type.body.copyWith(fontWeight: FontWeight.w700);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: labelStyle)),
          const SizedBox(width: 12),
          Text(value, style: valueStyle),
        ],
      ),
    );
  }
}
