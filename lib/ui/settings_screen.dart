import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:material_ui/material_ui.dart';

import '../core/models.dart';
import '../services/ai_assistant.dart';
import '../state/app_state.dart';
import 'widgets.dart';

/// Dati da inserire su Google Cloud per collegare Drive.
const String androidPackage = 'dev.paperdrive.paperdrive';
const String signingSha1 = '28:64:55:35:6C:77:EA:5D:30:D8:50:F4:CD:62:3D:38:89:CC:81:FD';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool connecting = false;

  Future<void> connect(AppState app) async {
    setState(() => connecting = true);
    try {
      await app.connectDrive();
      if (mounted) showMessage(context, 'Google Drive collegato');
    } catch (e) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Collegamento non riuscito'),
          content: SingleChildScrollView(
            child: Text(
              '$e\n\n'
              'Se l\'errore parla di configurazione o la finestra si chiude subito, '
              'controlla su Google Cloud: API di Google Drive attivata, ID client Android '
              'con nome pacchetto e SHA-1 qui sotto, e il tuo account tra gli utenti di test.',
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
        ),
      );
    } finally {
      if (mounted) setState(() => connecting = false);
    }
  }

  void copy(String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    showMessage(context, '$label copiato');
  }

  Future<void> _download(AppState app, AiModelOption m) async {
    final ok = await confirm(
      context,
      title: 'Scaricare ${m.label}?',
      message: '${m.description}.\n\nUsa il Wi-Fi e tieni l\'app aperta finché il download non è finito. '
          'Il modello resta solo sul telefono: i documenti non vengono inviati a nessuno.',
      ok: 'Scarica',
    );
    if (!ok) return;
    final previous = aiModelById(app.settings.aiModel);
    try {
      await app.ai.install(m);
      if (previous != null && previous.id != m.id) await app.ai.uninstall(previous);
      app.settings
        ..aiModel = m.id
        ..aiEnabled = true;
      await app.saveSettings();
      if (mounted) showMessage(context, 'AI pronta: da ora legge i documenti che aggiungi');
    } catch (e) {
      if (mounted) showMessage(context, 'Download non riuscito: ${app.ai.error ?? e}');
    }
  }

  Future<void> _remove(AppState app, AiModelOption m) async {
    final ok = await confirm(context, title: 'Cancellare ${m.label} dal telefono?', ok: 'Cancella', danger: true);
    if (!ok) return;
    await app.ai.uninstall(m);
    app.settings
      ..aiModel = null
      ..aiEnabled = false;
    await app.saveSettings();
  }

  Widget _aiSection(AppState app, ThemeData theme) {
    final s = app.settings;
    final ai = app.ai;
    final installed = aiModelById(s.aiModel);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text('AI sul telefono', style: theme.textTheme.titleMedium),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            'Un modello linguistico gratuito, scaricato una volta, legge ogni documento come una persona: '
            'capisce che cos\'è, chi lo manda, la data e gli dà un nome chiaro. Funziona senza internet '
            'e nessun documento lascia il telefono. Le tue correzioni restano più importanti dell\'AI.',
            style: theme.textTheme.bodySmall,
          ),
        ),
        for (final m in aiModels)
          ListTile(
            leading: Icon(installed?.id == m.id ? Icons.check_circle : Icons.smart_toy_outlined,
                color: installed?.id == m.id ? theme.colorScheme.primary : null),
            title: Text(m.label),
            subtitle: Text(installed?.id == m.id ? '${m.description} · scaricato' : m.description),
            trailing: installed?.id == m.id
                ? IconButton(
                    tooltip: 'Cancella dal telefono',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: ai.downloading || ai.working ? null : () => _remove(app, m),
                  )
                : TextButton(
                    onPressed: ai.downloading || ai.working ? null : () => _download(app, m),
                    child: const Text('Scarica'),
                  ),
          ),
        if (ai.downloading)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
            child: Row(
              children: [
                Expanded(child: LinearProgressIndicator(value: (ai.progress ?? 0) / 100)),
                const SizedBox(width: 12),
                Text('${ai.progress ?? 0}%'),
                TextButton(onPressed: ai.cancelDownload, child: const Text('Annulla')),
              ],
            ),
          ),
        SwitchListTile(
          secondary: const Icon(Icons.auto_awesome),
          title: const Text('Usa l\'AI quando aggiungi documenti'),
          subtitle: Text(installed == null
              ? 'Prima scarica un modello'
              : 'Qualche secondo in più per documento · dal menu di un documento: "Rileggi con l\'AI"'),
          value: installed != null && s.aiEnabled,
          onChanged: installed == null
              ? null
              : (v) {
                  s.aiEnabled = v;
                  app.saveSettings();
                },
        ),
        if (ai.error != null && !ai.downloading)
          ListTile(
            leading: const Icon(Icons.error_outline),
            title: const Text('Ultimo errore dell\'AI'),
            subtitle: Text(ai.error!, maxLines: 4, overflow: TextOverflow.ellipsis),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.settings;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Impostazioni')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('Google Drive', style: theme.textTheme.titleMedium),
          ),
          if (!s.driveEnabled) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'I documenti e l\'indice vengono salvati in una cartella "Paperdrive" '
                'del tuo Drive, che puoi condividere con altre persone. Google mostrerà '
                'l\'avviso "app non verificata": è normale per un\'app personale, tocca '
                '"Avanzate" e poi "Vai a Paperdrive".',
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                onPressed: connecting ? null : () => connect(app),
                icon: connecting
                    ? const SizedBox(
                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.add_to_drive),
                label: const Text('Collega Google Drive'),
              ),
            ),
          ] else ...[
            ListTile(
              leading: const Icon(Icons.account_circle_outlined),
              title: Text(s.driveAccount ?? 'Account collegato'),
              subtitle: Text(s.lastSync == null
                  ? 'Mai sincronizzato'
                  : 'Ultima sincronizzazione: ${formatDate(DateTime.fromMillisecondsSinceEpoch(s.lastSync!))} '
                      '${TimeOfDay.fromDateTime(DateTime.fromMillisecondsSinceEpoch(s.lastSync!)).format(context)}'),
            ),
            if (s.driveShared)
              ListTile(
                leading: const Icon(Icons.folder_shared_outlined),
                title: Text('Archivio di ${s.driveFolderOwner ?? 'un\'altra persona'}'),
                subtitle: Text(s.driveCanEdit ? 'Puoi modificare' : 'Sola lettura'),
              ),
            if (s.lastSyncError != null)
              ListTile(
                leading: Icon(Icons.error_outline, color: theme.colorScheme.error),
                title: const Text('Ultimo errore'),
                subtitle: Text(s.lastSyncError!),
              ),
            if (app.syncStatus != null)
              ListTile(
                leading: const SizedBox(
                    width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                title: Text(app.syncStatus!),
              ),
            SwitchListTile(
              secondary: const Icon(Icons.sync),
              title: const Text('Sincronizza in automatico'),
              subtitle: const Text('All\'apertura e pochi secondi dopo ogni modifica'),
              value: s.autoSync,
              onChanged: (v) {
                s.autoSync = v;
                app.saveSettings();
              },
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: app.syncing
                        ? null
                        : () async {
                            try {
                              final r = await app.syncNow();
                              if (context.mounted) showMessage(context, r);
                            } catch (e) {
                              if (context.mounted) showMessage(context, 'Errore: $e');
                            }
                          },
                    icon: const Icon(Icons.sync),
                    label: const Text('Sincronizza ora'),
                  ),
                  OutlinedButton(
                    onPressed: connecting ? null : () => connect(app),
                    child: const Text('Ricollega'),
                  ),
                  TextButton(
                    onPressed: () async {
                      final ok = await confirm(context,
                          title: 'Scollegare Google Drive?',
                          message: 'I documenti restano sul telefono e su Drive.',
                          ok: 'Scollega');
                      if (ok) await app.disconnectDrive();
                    },
                    child: const Text('Scollega'),
                  ),
                ],
              ),
            ),
          ],
          ExpansionTile(
            leading: const Icon(Icons.key_outlined),
            title: const Text('Dati per Google Cloud'),
            subtitle: const Text('Servono una volta per creare l\'accesso a Drive'),
            children: [
              ListTile(
                title: const Text('Nome pacchetto'),
                subtitle: const Text(androidPackage),
                trailing: const Icon(Icons.copy),
                onTap: () => copy('Nome pacchetto', androidPackage),
              ),
              ListTile(
                title: const Text('Impronta SHA-1'),
                subtitle: const Text(signingSha1),
                trailing: const Icon(Icons.copy),
                onTap: () => copy('SHA-1', signingSha1),
              ),
            ],
          ),
          const Divider(height: 32),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text('Archivio', style: theme.textTheme.titleMedium),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.text_snippet_outlined),
            title: const Text('Leggi il testo (OCR)'),
            subtitle: const Text('Sul telefono, senza inviare nulla a server esterni'),
            value: s.ocrEnabled,
            onChanged: (v) {
              s.ocrEnabled = v;
              app.saveSettings();
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.picture_as_pdf_outlined),
            title: const Text('Crea versione PDF/A ricercabile'),
            subtitle: const Text('Per scansioni e foto: PDF/A con il testo selezionabile, come Paperless'),
            value: s.makeArchive,
            onChanged: (v) {
              s.makeArchive = v;
              app.saveSettings();
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.numbers),
            title: const Text('Numero d\'archivio (ASN) automatico'),
            subtitle: Text('Prossimo: ${app.archive.nextAsn()}'),
            value: s.autoAsn,
            onChanged: (v) {
              s.autoAsn = v;
              app.saveSettings();
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.copy_all_outlined),
            title: const Text('Salta i duplicati'),
            subtitle: const Text('Non importa di nuovo un file identico'),
            value: s.skipDuplicates,
            onChanged: (v) {
              s.skipDuplicates = v;
              app.saveSettings();
            },
          ),
          const Divider(height: 32),
          ListenableBuilder(listenable: app.ai, builder: (context, _) => _aiSection(app, theme)),
          const Divider(height: 32),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Paperdrive'),
            subtitle: Text(
              '${app.archive.activeDocuments.length} documenti · '
              '${app.archive.activeTags.length} tag · '
              '${app.archive.activeCorrespondents.length} corrispondenti',
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
