import 'package:material_ui/material_ui.dart';

import '../core/models.dart';
import '../core/organize.dart';
import '../core/workflows.dart' show titlePlaceholders;
import '../state/app_state.dart';
import 'widgets.dart';

/// Archiviazione automatica: titolo, cartelle su Drive, categorie,
/// codici a barre.
class OrganizeScreen extends StatefulWidget {
  const OrganizeScreen({super.key});

  @override
  State<OrganizeScreen> createState() => _OrganizeScreenState();
}

class _OrganizeScreenState extends State<OrganizeScreen> {
  late final AppState app = AppScope.read(context);
  late final title = TextEditingController(text: app.archive.config.titleTemplate);
  late final path = TextEditingController(text: app.archive.config.pathTemplate);
  late final sep = TextEditingController(text: app.archive.config.separatorBarcode);
  late final asn = TextEditingController(text: app.archive.config.asnPrefix);

  @override
  void dispose() {
    for (final c in [title, path, sep, asn]) {
      c.dispose();
    }
    super.dispose();
  }

  Document _sample() {
    final docs = app.archive.activeDocuments.where((d) => d.typeId != null).toList();
    if (docs.isNotEmpty) return Document.fromJson(docs.first.toJson());
    return Document(
      title: 'scansione',
      created: DateTime(2024, 3, 5),
      typeId: app.archive.type('st-bolletta') == null ? null : 'st-bolletta',
    );
  }

  void _save() {
    final c = app.archive.config;
    final before = c.toJson().toString();
    c
      ..titleTemplate = title.text.trim().isEmpty ? ArchiveConfig.defaultTitleTemplate : title.text.trim()
      ..pathTemplate = path.text.trim().isEmpty ? ArchiveConfig.defaultPathTemplate : path.text.trim()
      ..separatorBarcode = sep.text.trim()
      ..asnPrefix = asn.text.trim();
    if (c.toJson().toString() != before) app.saveConfig();
  }

  Widget _chips(TextEditingController ctrl, {bool slash = false}) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final e in titlePlaceholders.entries)
              ActionChip(
                label: Text(e.key, style: const TextStyle(fontSize: 11)),
                tooltip: e.value,
                onPressed: () => setState(() => ctrl.text = '${ctrl.text}${e.key}'),
              ),
            if (slash)
              ActionChip(
                label: const Text('/', style: TextStyle(fontSize: 11)),
                tooltip: 'nuova cartella',
                onPressed: () => setState(() => ctrl.text = '${ctrl.text}/'),
              ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = app.archive.config;
    final theme = Theme.of(context);
    final sample = _sample();
    // Anteprima con i valori del modulo, senza salvarli.
    final saved = (c.titleTemplate, c.pathTemplate);
    c
      ..titleTemplate = title.text
      ..pathTemplate = path.text;
    final t = autoTitle(app.archive, sample);
    if (t != null) sample.title = t;
    final (folders, file) = drivePath(app.archive, sample);
    c
      ..titleTemplate = saved.$1
      ..pathTemplate = saved.$2;

    return PopScope(
      onPopInvokedWithResult: (didPop, _) => _save(),
      child: Scaffold(
        appBar: AppBar(title: const Text('Archiviazione automatica')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
          children: [
            Text(
              'Ogni documento che scansioni, importi, ricevi per email o condividi verso '
              'Paperdrive viene letto, classificato, rinominato e archiviato da solo.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.auto_awesome),
                title: Text(sample.title),
                subtitle: Text('Drive: ${[...folders, '$file.pdf'].join(' / ')}'),
              ),
            ),
            const SizedBox(height: 16),
            Text('Categorie', style: theme.textTheme.titleMedium),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${app.archive.activeTypes.length} tipi di documento'),
              subtitle: const Text('Bolletta, Fattura, Sanità, Tasse… riconosciuti dalle parole chiave'),
              trailing: TextButton(
                onPressed: () {
                  final n = app.addStarterCategories();
                  showMessage(context, n == 0 ? 'Le categorie predefinite ci sono già' : 'Aggiunte $n categorie');
                },
                child: const Text('Aggiungi predefinite'),
              ),
            ),
            const Divider(height: 32),
            Text('Nome', style: theme.textTheme.titleMedium),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Rinomina in automatico'),
              subtitle: const Text('Legge che documento è, chi lo emette, importo e dettagli'),
              value: c.autoTitle,
              onChanged: (v) {
                c.autoTitle = v;
                app.saveConfig();
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Tieni il nome del file se è già descrittivo'),
              subtitle: const Text('Es. "Visura catastale casa via Roma" resta così; "IMG_1234" o "scan001" vengono rinominati'),
              value: c.keepFileName,
              onChanged: (v) {
                c.keepFileName = v;
                app.saveConfig();
              },
            ),
            TextField(
              controller: title,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Modello del titolo', border: OutlineInputBorder()),
            ),
            _chips(title),
            const Divider(height: 32),
            Text('Cartelle su Google Drive', style: theme.textTheme.titleMedium),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Archivia in cartelle'),
              subtitle: const Text('Altrimenti tutti i file nella cartella principale'),
              value: c.organizeDrive,
              onChanged: (v) {
                c.organizeDrive = v;
                app.saveConfig();
              },
            ),
            TextField(
              controller: path,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Cartelle e nome del file',
                helperText: 'Es. {document_type}/{created_year}/{created} {title}',
                border: OutlineInputBorder(),
              ),
            ),
            _chips(path, slash: true),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Per casi particolari crea dei "Percorsi" in Gestione (es. tutte le fatture '
                'di un fornitore in una cartella a parte).',
                style: theme.textTheme.bodySmall,
              ),
            ),
            const Divider(height: 32),
            Text('Codici a barre', style: theme.textTheme.titleMedium),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Dividi le scansioni con un foglio separatore'),
              subtitle: const Text('Scansiona più documenti insieme, con un foglio con codice a barre tra uno e l\'altro'),
              value: c.barcodeSplit,
              onChanged: (v) {
                c.barcodeSplit = v;
                app.saveConfig();
              },
            ),
            TextField(
              controller: sep,
              decoration: const InputDecoration(
                labelText: 'Testo del codice separatore',
                helperText: 'PATCHT è lo standard (fogli "PATCH T")',
                border: OutlineInputBorder(),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Leggi l\'ASN dalle etichette'),
              subtitle: const Text('Etichette con codice a barre tipo ASN00123'),
              value: c.asnBarcode,
              onChanged: (v) {
                c.asnBarcode = v;
                app.saveConfig();
              },
            ),
            TextField(
              controller: asn,
              decoration: const InputDecoration(labelText: 'Prefisso ASN', border: OutlineInputBorder()),
            ),
            const Divider(height: 32),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.auto_fix_high),
              label: const Text('Riclassifica e rinomina tutti i documenti'),
              onPressed: app.readOnly
                  ? null
                  : () async {
                      _save();
                      final ok = await confirm(context,
                          title: 'Riclassificare tutto l\'archivio?',
                          message: 'Categoria, corrispondente, percorso e titolo verranno ricalcolati '
                              'con le regole attuali. Su Drive i file verranno spostati alla prossima sincronizzazione.',
                          ok: 'Riclassifica');
                      if (!ok) return;
                      final n = app.reapplyRules(app.archive.activeDocuments, overwrite: true, retitle: true);
                      if (context.mounted) showMessage(context, 'Aggiornati $n documenti');
                    },
            ),
          ],
        ),
      ),
    );
  }
}
