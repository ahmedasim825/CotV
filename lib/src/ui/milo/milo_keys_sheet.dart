import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/milo_providers.dart';
import '../components/components.dart';
import '../theme/app_theme.dart';
import '../widgets/ph_light_icons.dart';

/// Opens the sheet that holds Milo's keys and the PC agent's address.
Future<void> showMiloKeysSheet(BuildContext context) {
  return showStandardBottomSheet<void>(
    context,
    builder: (context) => const MiloKeysSheet(),
  );
}

/// Where the two API keys and the PC agent's credentials are entered.
///
/// The fields start empty even when keys are stored: a saved secret is
/// never read back into a text field, so shoulder-surfing the sheet cannot
/// recover it. The row under each field says whether one is already set.
class MiloKeysSheet extends ConsumerStatefulWidget {
  const MiloKeysSheet({super.key});

  @override
  ConsumerState<MiloKeysSheet> createState() => _MiloKeysSheetState();
}

class _MiloKeysSheetState extends ConsumerState<MiloKeysSheet> {
  final _groq = TextEditingController();
  final _gemini = TextEditingController();
  final _host = TextEditingController();
  final _token = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // The host is an address, not a secret, so it is the one field worth
    // showing back to the user for editing.
    final secrets = ref.read(miloSecretsProvider).value;
    if (secrets?.pcHost != null) _host.text = secrets!.pcHost!;
  }

  @override
  void dispose() {
    _groq.dispose();
    _gemini.dispose();
    _host.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await ref.read(miloCredentialsProvider).save(
          // Null leaves a stored value alone; only a field the user
          // actually typed in is written.
          groqApiKey: _groq.text.isEmpty ? null : _groq.text,
          geminiApiKey: _gemini.text.isEmpty ? null : _gemini.text,
          pcHost: _host.text,
          pcToken: _token.text.isEmpty ? null : _token.text,
        );
    ref.invalidate(miloSecretsProvider);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final secrets = ref.watch(miloSecretsProvider).value;

    return StandardBottomSheet(
      title: 'Milo settings',
      subtitle: 'Keys are held in the iOS Keychain and never leave the '
          'device except as request headers to the service they belong to.',
      actions: Row(
        children: [
          Expanded(
            child: PrimaryButton(
              label: 'Cancel',
              variant: ButtonVariant.outline,
              expand: true,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: PrimaryButton(
              label: 'Save',
              icon: PhLight.floppyDisk,
              expand: true,
              loading: _saving,
              onPressed: _saving ? null : _save,
            ),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SecretField(
            controller: _groq,
            icon: PhLight.lightning,
            label: 'Groq API key',
            hint: 'gsk_...',
            isSet: secrets?.hasGroq ?? false,
            help: 'Answers instant requests and PC commands.',
          ),
          const SizedBox(height: 22),
          _SecretField(
            controller: _gemini,
            icon: PhLight.brain,
            label: 'Gemini API key',
            hint: 'AIza...',
            isSet: secrets?.hasGemini ?? false,
            help: 'Answers planning, summaries and anything long.',
          ),
          const SizedBox(height: 30),
          SectionHeader(
            eyebrow: 'PC BRIDGE',
            title: 'Windows agent',
            titleSize: 20,
            subtitle: 'Run tools/milo_pc_agent/milo_pc_agent.py on the '
                'laptop, then point Milo at it. Both devices have to be on '
                'the same Wi-Fi.',
            accent: context.palette.priorityLow,
          ),
          const SizedBox(height: 18),
          FieldLabel(
            icon: PhLight.plugsConnected,
            label: 'Agent address',
            accent: context.palette.priorityLow,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _host,
            keyboardType: TextInputType.url,
            autocorrect: false,
            style: context.typography.mono(size: 13.5),
            decoration: appInputDecoration(context, hint: '192.168.1.20:8765'),
          ),
          const SizedBox(height: 22),
          _SecretField(
            controller: _token,
            icon: PhLight.key,
            label: 'Agent token',
            hint: 'The token from milo_agent.toml',
            isSet: secrets?.pcToken != null,
            help: 'Must match the agent config exactly.',
            accent: context.palette.priorityLow,
          ),
        ],
      ),
    );
  }
}

/// A masked field for one secret, with a reveal toggle and a line saying
/// whether a value is already stored.
class _SecretField extends StatefulWidget {
  const _SecretField({
    required this.controller,
    required this.icon,
    required this.label,
    required this.hint,
    required this.isSet,
    required this.help,
    this.accent,
  });

  final TextEditingController controller;
  final IconData icon;
  final String label;
  final String hint;
  final bool isSet;
  final String help;
  final Color? accent;

  @override
  State<_SecretField> createState() => _SecretFieldState();
}

class _SecretFieldState extends State<_SecretField> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final accent = widget.accent ?? palette.accent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel(icon: widget.icon, label: widget.label, accent: accent),
        const SizedBox(height: 8),
        TextField(
          controller: widget.controller,
          obscureText: !_revealed,
          autocorrect: false,
          enableSuggestions: false,
          style: context.typography.mono(size: 13.5),
          decoration: appInputDecoration(
            context,
            hint: widget.isSet ? 'Stored — type to replace' : widget.hint,
            suffixIcon: IconButton(
              // The reveal toggle is for checking a pasted key, so it says
              // what it will do rather than what state it is in.
              tooltip: _revealed ? 'Hide key' : 'Show key',
              icon: Icon(
                _revealed ? PhLight.eyeSlash : PhLight.eye,
                size: 17,
                color: palette.textMuted,
              ),
              onPressed: () => setState(() => _revealed = !_revealed),
            ),
          ),
        ),
        const SizedBox(height: 7),
        Row(
          children: [
            Icon(
              widget.isSet ? PhLight.checkCircle : PhLight.warningCircle,
              size: 13,
              color: widget.isSet ? palette.success : palette.textMuted,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                widget.isSet ? 'Set. ${widget.help}' : widget.help,
                style: context.typography.ui(
                  size: 11.5,
                  color: palette.textMuted,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
