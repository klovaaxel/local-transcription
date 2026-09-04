import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../models/model_catalog.dart';
import '../../ui/soft_buttons.dart';
import '../../ui/soft_icons.dart';
import '../../ui/soft_surface.dart';
import '../../ui/soft_theme.dart';
import '../../ui/soft_widgets.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _apiKey;
  late final TextEditingController _baseUrl;
  late final TextEditingController _chatModel;
  late final TextEditingController _transcribeModel;
  LectureAppState? _state;

  @override
  void initState() {
    super.initState();
    final settings = context.read<LectureAppState>().settings;
    _apiKey = TextEditingController(text: settings.cloudApiKey);
    _baseUrl = TextEditingController(text: settings.cloudBaseUrl);
    _chatModel = TextEditingController(text: settings.cloudChatModel);
    _transcribeModel = TextEditingController(text: settings.cloudTranscribeModel);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _state = context.read<LectureAppState>();
  }

  @override
  void dispose() {
    // Typed provider details are persisted on leave, like the lecture title.
    unawaited(_state?.saveSettings() ?? Future.value());
    _apiKey.dispose();
    _baseUrl.dispose();
    _chatModel.dispose();
    _transcribeModel.dispose();
    super.dispose();
  }

  /// A preset rewrites URL and model names, so the fields follow it. Never
  /// called from `build` — only from the radio callback.
  void _applyProvider(LectureAppState state, CloudProvider provider) {
    state.settings.applyProvider(provider);
    _baseUrl.text = state.settings.cloudBaseUrl;
    _chatModel.text = state.settings.cloudChatModel;
    _transcribeModel.text = state.settings.cloudTranscribeModel;
    state.saveSettings();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<LectureAppState>();
    final settings = state.settings;
    final needsCloud = settings.usesCloud;

    return SoftPage(
      title: 'Inställningar',
      subtitle: Text(
        needsCloud
            ? 'Moln är påslaget. Det du valt skickas till leverantören.'
            : 'Modellerna stannar på enheten.',
      ),
      leading: const SoftBackButton(),
      child: ListView(
        padding: softBodyPadding,
        children: [
          SoftSection(
            label: 'Transkribering',
            subtitle:
                'Lokalt ger live-text under lektionen. Moln skickar ljudet '
                'efter lektionen och behöver ingen nedladdad modell.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                RadioGroup<TranscriberKind>(
                  groupValue: settings.transcriber,
                  onChanged: state.busy
                      ? (_) {}
                      : (value) {
                          if (value == null) {
                            return;
                          }
                          settings.transcriber = value;
                          state.saveSettings();
                        },
                  child: const Column(
                    children: [
                      _Choice(
                        label: 'På enheten (standard)',
                        value: TranscriberKind.local,
                      ),
                      _Choice(
                        label: 'Moln (ljudet lämnar enheten)',
                        value: TranscriberKind.cloud,
                      ),
                    ],
                  ),
                ),
                if (settings.transcriber == TranscriberKind.local) ...[
                  const SizedBox(height: SoftSpace.lg),
                  RadioGroup<AsrModelSize>(
                    groupValue: settings.asrSize,
                    onChanged: state.busy
                        ? (_) {}
                        : (value) {
                            if (value == null) {
                              return;
                            }
                            settings.asrSize = value;
                            state.saveSettings();
                          },
                    child: Column(
                      children: [
                        _Choice(
                          label: ModelCatalog.small.label,
                          value: AsrModelSize.small,
                        ),
                        _Choice(
                          label: ModelCatalog.medium.label,
                          value: AsrModelSize.medium,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: SoftSpace.lg),
                  _ModelStatus(
                    ready: state.asrReady,
                    readyLabel: 'Talmodell finns på enheten',
                    missingLabel: 'Talmodell saknas',
                    onDownload: state.busy
                        ? null
                        : () async {
                            try {
                              await state.downloadAsr();
                            } catch (_) {}
                          },
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: SoftSpace.xxl),
          SoftSection(
            label: 'Sammanfattning',
            subtitle:
                '1,5B räcker på telefon. 7B ger ett bättre underlag på dator.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                RadioGroup<SummarizerKind>(
                  groupValue: settings.summarizer,
                  onChanged: state.busy
                      ? (_) {}
                      : (value) {
                          if (value == null) {
                            return;
                          }
                          settings.summarizer = value;
                          state.saveSettings();
                        },
                  child: const Column(
                    children: [
                      _Choice(
                        label: 'Lokal modell (standard)',
                        value: SummarizerKind.local,
                      ),
                      _Choice(
                        label: 'Moln (transkriptet lämnar enheten)',
                        value: SummarizerKind.cloud,
                      ),
                    ],
                  ),
                ),
                if (settings.summarizer == SummarizerKind.local) ...[
                  const SizedBox(height: SoftSpace.lg),
                  RadioGroup<LlmModelSize>(
                    groupValue: settings.llmSize,
                    onChanged: state.busy
                        ? (_) {}
                        : (value) {
                            if (value == null) {
                              return;
                            }
                            settings.llmSize = value;
                            state.saveSettings();
                          },
                    child: Column(
                      children: [
                        _Choice(
                          label: ModelCatalog.llmSmall.label,
                          value: LlmModelSize.small,
                        ),
                        _Choice(
                          label: ModelCatalog.llmLarge.label,
                          value: LlmModelSize.large,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: SoftSpace.lg),
                  _ModelStatus(
                    ready: state.llmReady,
                    readyLabel: 'Språkmodell finns på enheten',
                    missingLabel: 'Språkmodell saknas',
                    detail: ModelCatalog.llm(settings.llmSize).downloadedName,
                    onDownload: state.busy
                        ? null
                        : () async {
                            try {
                              await state.downloadLlm();
                            } catch (_) {}
                          },
                  ),
                ],
              ],
            ),
          ),
          if (needsCloud) ...[
            const SizedBox(height: SoftSpace.xxl),
            SoftSection(
              label: 'Leverantör',
              subtitle: _cloudSubtitle(settings.transcriber, settings.summarizer),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  RadioGroup<String>(
                    groupValue: settings.cloudProviderId,
                    onChanged: state.busy
                        ? (_) {}
                        : (value) {
                            if (value == null) {
                              return;
                            }
                            _applyProvider(state, CloudCatalog.byId(value));
                          },
                    child: Column(
                      children: [
                        for (final provider in CloudCatalog.all)
                          _Choice(label: provider.label, value: provider.id),
                      ],
                    ),
                  ),
                  const SizedBox(height: SoftSpace.lg),
                  _CloudField(
                    label: 'API-adress',
                    controller: _baseUrl,
                    hint: CloudCatalog.berget.baseUrl,
                    onChanged: (value) => settings.cloudBaseUrl = value,
                    onDone: state.saveSettings,
                  ),
                  const SizedBox(height: SoftSpace.md),
                  _CloudField(
                    label: 'API-nyckel',
                    controller: _apiKey,
                    hint: 'Klistra in nyckeln från leverantören',
                    obscure: true,
                    onChanged: (value) => settings.cloudApiKey = value,
                    onDone: state.saveSettings,
                  ),
                  if (settings.summarizer == SummarizerKind.cloud) ...[
                    const SizedBox(height: SoftSpace.md),
                    _CloudField(
                      label: 'Språkmodell',
                      controller: _chatModel,
                      hint: CloudCatalog.berget.chatModel,
                      onChanged: (value) => settings.cloudChatModel = value,
                      onDone: state.saveSettings,
                    ),
                  ],
                  if (settings.transcriber == TranscriberKind.cloud) ...[
                    const SizedBox(height: SoftSpace.md),
                    _CloudField(
                      label: 'Talmodell',
                      controller: _transcribeModel,
                      hint: CloudCatalog.berget.transcribeModel,
                      onChanged: (value) =>
                          settings.cloudTranscribeModel = value,
                      onDone: state.saveSettings,
                    ),
                  ],
                  const SizedBox(height: SoftSpace.lg),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          CloudCatalog.byId(settings.cloudProviderId).note,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      const SizedBox(width: SoftSpace.md),
                      SoftButton.quiet(
                        label: 'Testa anslutning',
                        icon: SoftIcons.cloud,
                        onPressed: state.busy
                            ? null
                            : () async {
                                await state.saveSettings();
                                try {
                                  await state.testCloudConnection();
                                } catch (_) {}
                              },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: SoftSpace.xxl),
          SoftSection(
            label: 'Lagring',
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Radera ljud efter transkribering'),
              subtitle: const Text('Behåller bara texten på enheten'),
              value: settings.deleteAudioAfterTranscribe,
              onChanged: state.busy
                  ? null
                  : (value) {
                      settings.deleteAudioAfterTranscribe = value;
                      state.saveSettings();
                    },
            ),
          ),
        ],
      ),
    );
  }

  /// Names exactly what leaves the device, so the teacher is never guessing.
  static String _cloudSubtitle(TranscriberKind asr, SummarizerKind brief) {
    if (asr == TranscriberKind.cloud && brief == SummarizerKind.cloud) {
      return 'Ljud och transkript skickas till leverantören.';
    }
    if (asr == TranscriberKind.cloud) {
      return 'Ljudet skickas till leverantören. Transkriptet stannar kvar.';
    }
    return 'Transkriptet skickas till leverantören. Ljudet stannar kvar.';
  }
}

/// One labelled text field in the provider card.
class _CloudField extends StatelessWidget {
  const _CloudField({
    required this.label,
    required this.controller,
    required this.hint,
    required this.onChanged,
    required this.onDone,
    this.obscure = false,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final VoidCallback onDone;
  final bool obscure;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: SoftSpace.xs),
        SoftField(
          padding: EdgeInsets.zero,
          child: TextField(
            controller: controller,
            obscureText: obscure,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(hintText: hint),
            onChanged: onChanged,
            onSubmitted: (_) => onDone(),
          ),
        ),
      ],
    );
  }
}

/// One radio row. Every choice in settings looks exactly like this.
class _Choice<T> extends StatelessWidget {
  const _Choice({required this.label, required this.value});

  final String label;
  final T value;

  @override
  Widget build(BuildContext context) {
    return RadioListTile<T>(
      title: Text(label),
      value: value,
      contentPadding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    );
  }
}

/// Presence of a downloaded model, plus the one action that changes it.
class _ModelStatus extends StatelessWidget {
  const _ModelStatus({
    required this.ready,
    required this.readyLabel,
    required this.missingLabel,
    required this.onDownload,
    this.detail,
  });

  final bool ready;
  final String readyLabel;
  final String missingLabel;
  final String? detail;
  final VoidCallback? onDownload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ready ? readyLabel : missingLabel,
                style: theme.textTheme.bodyMedium,
              ),
              if (detail != null) ...[
                const SizedBox(height: SoftSpace.xs),
                Text(detail!, style: theme.textTheme.bodySmall),
              ],
            ],
          ),
        ),
        const SizedBox(width: SoftSpace.md),
        SoftButton.quiet(
          label: 'Ladda ner',
          icon: SoftIcons.download,
          onPressed: onDownload,
        ),
      ],
    );
  }
}
