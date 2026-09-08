import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/milo_providers.dart';
import '../../services/milo/milo_speech_service.dart';
import '../../services/milo/wake_word_listener.dart';
import '../../providers/user_settings_providers.dart';
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
            help: 'Answers instant requests and PC commands, and transcribes '
                'speech when the PC agent is not running.',
          ),
          const SizedBox(height: 22),
          _SecretField(
            controller: _gemini,
            icon: PhLight.brain,
            label: 'Gemini API key',
            hint: 'AIza...',
            isSet: secrets?.hasGemini ?? false,
            help: 'Answers medical questions, research, planning and '
                'anything long.',
          ),
          const SizedBox(height: 30),
          SectionHeader(
            eyebrow: 'VOICE',
            title: 'Hands-free',
            titleSize: 20,
            subtitle: 'Milo can wait for its name — or a clap — instead of '
                'waiting for a tap.',
            accent: context.palette.accentBright,
          ),
          const SizedBox(height: 16),
          const _VoicePicker(),
          const SizedBox(height: 20),
          _WakeWordToggle(
            value: ref.watch(miloListensProvider),
            // The setting says what was asked for; the status says whether
            // it actually started. They differ when the microphone is busy
            // or the model fails to load, and that gap is worth showing.
            status: ref.watch(wakeWordProvider),
            onChanged: (value) => ref
                .read(userSettingsControllerProvider.notifier)
                .setListensForWakeWord(value),
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

/// The always-on listening switch.
///
/// Given more room than a plain row because what it turns on is not
/// obvious from its name: the microphone stays open. Saying so here, where
/// the decision is made, is worth more than a line in a README.
class _WakeWordToggle extends StatelessWidget {
  const _WakeWordToggle({
    required this.value,
    required this.status,
    required this.onChanged,
  });

  final bool value;
  final WakeWordStatus status;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return CustomCard(
      radius: 20,
      elevated: false,
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      semanticLabel: value
          ? 'Listening for Hey Milo. Tap to turn off.'
          : 'Not listening. Tap to listen for Hey Milo.',
      onTap: () => onChanged(!value),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            value ? PhLight.microphone : PhLight.microphoneSlash,
            size: 18,
            color: value ? palette.accentBright : palette.textMuted,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Listen for "Hey Milo"',
                  style: context.typography.ui(
                    size: 14,
                    weight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'The wake word is matched on this device, and a clap is '
                  'recognised by its shape rather than by a model, so '
                  'nothing is sent anywhere until one of them fires. Only '
                  'what you say after it is transcribed.',
                  style: context.typography.ui(
                    size: 12,
                    color: palette.textSecondary,
                    height: 1.45,
                  ),
                ),
                if (status.error != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(PhLight.warningCircle,
                          size: 13, color: palette.danger),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          status.error!,
                          style: context.typography.ui(
                            size: 11.5,
                            color: palette.danger,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ] else if (value) ...[
                  const SizedBox(height: 10),
                  const _WakeWordDiagnostics(),
                  const SizedBox(height: 7),
                  Text(
                    status.armed
                        ? 'Listening. The microphone stays open while this '
                            'is on.'
                        : 'Paused while the mic button is in use.',
                    style: context.typography.ui(
                      size: 11.5,
                      color: palette.textMuted,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// Which voice Milo speaks with.
///
/// Every entry previews itself on tap. A voice cannot be chosen from its
/// name — "David" and "Zira" tell you nothing about how either sounds — so
/// the list is audition-first and the tick only records what you picked.
class _VoicePicker extends ConsumerStatefulWidget {
  const _VoicePicker();

  @override
  ConsumerState<_VoicePicker> createState() => _VoicePickerState();
}

class _VoicePickerState extends ConsumerState<_VoicePicker> {
  late Future<List<MiloVoice>> _voices;

  @override
  void initState() {
    super.initState();
    _voices = ref.read(miloSpeechProvider).voices();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final chosen = ref.watch(
      userSettingsControllerProvider.select((s) => s.value?.voiceName),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel(
          icon: PhLight.speakerHigh,
          label: 'Voice',
          accent: palette.accentBright,
        ),
        const SizedBox(height: 8),
        FutureBuilder<List<MiloVoice>>(
          future: _voices,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return Text(
                'Reading the voices installed on this device…',
                style: context.typography.ui(
                  size: 12,
                  color: palette.textMuted,
                ),
              );
            }
            final voices = snapshot.data ?? const <MiloVoice>[];
            if (voices.isEmpty) {
              return Text(
                'No speech voices are installed. On Windows they are added '
                'under Settings › Time & language › Speech.',
                style: context.typography.ui(
                  size: 12,
                  color: palette.textMuted,
                  height: 1.45,
                ),
              );
            }
            return Column(
              children: [
                for (final voice in voices) ...[
                  _VoiceRow(
                    voice: voice,
                    selected: voice.name == chosen,
                    onTap: () {
                      ref
                          .read(userSettingsControllerProvider.notifier)
                          .setVoiceName(voice.name);
                      unawaited(ref.read(miloSpeechProvider).preview(voice));
                    },
                  ),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 2),
                Text(
                  'Tap one to hear it. Windows can install more under '
                  'Settings › Time & language › Speech.',
                  style: context.typography.ui(
                    size: 11.5,
                    color: palette.textMuted,
                    height: 1.4,
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _VoiceRow extends StatelessWidget {
  const _VoiceRow({
    required this.voice,
    required this.selected,
    required this.onTap,
  });

  final MiloVoice voice;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return CustomCard(
      radius: 16,
      elevated: false,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      semanticLabel: 'Play a sample of ${voice.label}'
          '${selected ? ', currently selected' : ''}',
      onTap: onTap,
      child: Row(
        children: [
          Icon(
            selected ? PhLight.checkCircle : PhLight.speakerHigh,
            size: 16,
            color: selected ? palette.accentBright : palette.textMuted,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              voice.label,
              style: context.typography.ui(
                size: 13.5,
                weight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          Text(
            'Play',
            style: context.typography.eyebrow(color: palette.textMuted),
          ),
        ],
      ),
    );
  }
}

/// Live counters from the listener.
///
/// Present because the failure modes here are all indistinguishable from
/// the outside: no frames arriving, frames arriving unreadable, and frames
/// the spotter simply never fires on all look like "nothing happens".
/// Numbers separate them in seconds.
class _WakeWordDiagnostics extends ConsumerStatefulWidget {
  const _WakeWordDiagnostics();

  @override
  ConsumerState<_WakeWordDiagnostics> createState() =>
      _WakeWordDiagnosticsState();
}

class _WakeWordDiagnosticsState
    extends ConsumerState<_WakeWordDiagnostics> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Polled rather than pushed: the audio callback runs per frame and must
    // not be rebuilding widgets.
    _ticker = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final listener = ref.read(wakeWordListenerProvider);
    final seconds =
        listener.samplesSeen / WakeWordListener.sampleRate;
    final level = (listener.peakLevel * 100).clamp(0, 100).toStringAsFixed(0);

    final rows = <(String, String, bool)>[
      ('Audio heard', '${seconds.toStringAsFixed(1)}s', listener.framesSeen > 0),
      ('Loudest so far', '$level%', listener.peakLevel > 0.02),
      ('Wake word hits', '${listener.detections}', listener.detections > 0),
      ('Claps', '${listener.clapDetections}', listener.clapDetections > 0),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: palette.glassFill,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (label, value, ok) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Icon(
                    ok ? PhLight.checkCircle : PhLight.warningCircle,
                    size: 12,
                    color: ok ? palette.success : palette.textMuted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      style: context.typography.ui(
                        size: 11.5,
                        color: palette.textSecondary,
                      ),
                    ),
                  ),
                  Text(
                    value,
                    style: context.typography.mono(
                      size: 11.5,
                      color: palette.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          if (listener.lastError != null) ...[
            const SizedBox(height: 6),
            Text(
              listener.lastError!,
              style: context.typography.ui(
                size: 11,
                color: palette.danger,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
