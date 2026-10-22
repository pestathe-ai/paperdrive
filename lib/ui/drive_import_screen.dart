import 'package:material_ui/material_ui.dart';

import '../core/formats.dart' show supportedFormatsLabel;
import '../core/import_hint.dart';
import '../services/drive_sync.dart' show InboxFile;
import '../state/app_state.dart';
import 'widgets.dart';

/// Cartella di importazione su Drive, come la "consume folder" di Paperless.
class DriveImportScreen extends StatefulWidget {
  const DriveImportScreen({super.key});

  @override
  State<DriveImportScreen> createState() => _DriveImportScreenState();
}

class _DriveImportScreenState extends State<DriveImportScreen> {
  List<InboxFile>? files;
  bool loading = false;
  String? error;
  String? result;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    final app = AppScope.read(context);
    if (!app.settings.driveEnabled) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final f = await app.driveInbox();
      if (mounted) setState(() => files = f);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _import(AppState app) async {
    setState(() => result = null);
    final msg = await app.importDriveInbox();
    if (!mounted) return;
    setState(() => result = msg);
    await _check();
  }

  /// Anteprima: dove finisce un file secondo le sue cartelle.
  String _preview(InboxFile f) {
    final names = meaningfulFolders(f.folders);
    final year = folderYear(f.folders);
    final parts = [
      if (names.isNotEmpty) 'Categoria: ${names.first}',
      if (names.length > 1) 'Tag: ${names.skip(1).join(', ')}',
      if (year != null) 'Anno: $year',
    ];
    return parts.isEmpty ? 'Categoria decisa dall\'app' : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final theme = Theme.of(context);
    final s = app.settings;
    final list = files ?? const <InboxFile>[];
    final importable = list.where((f) => importableFile(f.name, mimeType: f.mimeType)).length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Importa da Drive'),
        actions: [
          IconButton(
            tooltip: 'Controlla di nuovo',
            icon: const Icon(Icons.refresh),
            onPressed: loading || app.importing ? null : _check,
          ),
        ],
      ),
      body: !s.driveEnabled
          ? const EmptyState(icon: Icons.cloud_off, text: 'Collega prima Google Drive dalle Impostazioni')
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
              children: [
                Text(
                  'Copia i tuoi documenti (anche intere cartelle, per esempio da Dropbox) nella '
                  'cartella "Paperdrive/$inboxFolderName" su Google Drive. D. Paper Lab li legge, '
                  'li archivia e poi li toglie da lì (finiscono nel cestino di Drive).',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Il tuo ordine viene rispettato: la prima cartella diventa la categoria, le '
                  'sottocartelle diventano tag, una cartella con l\'anno (es. 2023) dà l\'anno, '
                  'e un nome di file già chiaro resta il titolo. L\'app impara da questi documenti '
                  'come classifichi e rinomini.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                if (app.importing) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  Text(app.busy ?? 'Importazione…'),
                  const SizedBox(height: 8),
                  Text(
                    'Tieni l\'app aperta (lo schermo resta acceso da solo). Con l\'AI attiva ogni '
                    'documento richiede qualche secondo in più.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.stop),
                    label: const Text('Interrompi dopo questo file'),
                    onPressed: app.stopImport,
                  ),
                ] else if (loading)
                  const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
                else if (error != null)
                  ListTile(
                    leading: const Icon(Icons.error_outline),
                    title: const Text('Non riesco a leggere la cartella'),
                    subtitle: Text(error!),
                  )
                else ...[
                  if (result != null)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.check_circle_outline),
                        title: const Text('Importazione finita'),
                        subtitle: Text(result!),
                      ),
                    ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(list.isEmpty
                        ? 'La cartella è vuota'
                        : '$importable documenti da importare'
                            '${list.length > importable ? ' (${list.length - importable} file non supportati)' : ''}'),
                    subtitle: const Text(supportedFormatsLabel),
                  ),
                  FilledButton.icon(
                    icon: const Icon(Icons.download),
                    label: Text(importable == 0 ? 'Niente da importare' : 'Importa $importable documenti'),
                    onPressed: importable == 0 || app.readOnly || app.busy != null ? null : () => _import(app),
                  ),
                ],
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Importa in automatico all\'apertura'),
                  subtitle: const Text('Come Paperless: basta mettere i file nella cartella'),
                  value: s.autoImport,
                  onChanged: (v) {
                    s.autoImport = v;
                    app.saveSettings();
                  },
                ),
                if (list.isNotEmpty && !app.importing) ...[
                  const Divider(height: 24),
                  Text('Anteprima', style: theme.textTheme.titleMedium),
                  for (final f in list.take(100))
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(importableFile(f.name, mimeType: f.mimeType) ? Icons.description_outlined : Icons.block),
                      title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        importableFile(f.name, mimeType: f.mimeType)
                            ? '${f.folders.isEmpty ? '' : '${f.folders.join(' / ')}\n'}${_preview(f)}'
                            : 'Formato non supportato: resta nella cartella',
                      ),
                    ),
                  if (list.length > 100) Text('… e altri ${list.length - 100}'),
                ],
              ],
            ),
    );
  }
}
