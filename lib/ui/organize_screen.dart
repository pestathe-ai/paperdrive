import 'package:material_ui/material_ui.dart';

import '../core/models.dart';
import '../core/organize.dart';
import '../core/people.dart' show Person;
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

  Future<void> _editPerson(Person? person) async {
    final name = TextEditingController(text: person?.name ?? '');
    final aka = TextEditingController(text: person?.aliases.join(', ') ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(person == null ? 'Nuova persona' : 'Modifica persona'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nome della cartella', hintText: 'Maria'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: aka,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Come compare nei documenti',
                hintText: 'Maria Rossi, RSSMRA80A41F205X',
                helperText: 'Nome e cognome, codice fiscale… separati da virgole',
                helperMaxLines: 2,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Salva')),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    final aliases = aka.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final c = app.archive.config;
    if (person == null) {
      c.people.add(Person(name: name.text.trim(), aliases: aliases));
    } else {
      person
        ..name = name.text.trim()
        ..aliases = aliases;
    }
    app.saveConfig();
    if (mounted) setState(() {});
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
              'D. Paper Lab viene letto, classificato, rinominato e archiviato da solo.',
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
            Text('Persone', style: theme.textTheme.titleMedium),
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: Text(
                'I documenti di ogni persona vanno nella sua cartella (es. Lavoro/Maria/2026). '
                'La sanità è divisa anche per specialità, referti e prescrizioni, anno e mese: '
                'Sanità/Maria/Cardiologia/Referti/2026/03 Marzo.',
                style: theme.textTheme.bodySmall,
              ),
            ),
            for (final (i, person) in c.people.indexed)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_outline),
                title: Text(person.name),
                subtitle: person.aliases.isEmpty ? null : Text(person.aliases.join(', ')),
                trailing: IconButton(
                  tooltip: 'Togli',
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    c.people.removeAt(i);
                    app.saveConfig();
                    setState(() {});
                  },
                ),
                onTap: () => _editPerson(person),
              ),
            Row(
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.person_add_alt),
                  label: const Text('Aggiungi persona'),
                  onPressed: () => _editPerson(null),
                ),
                const Spacer(),
                if (c.people.isNotEmpty)
                  TextButton(
                    onPressed: app.readOnly
                        ? null
                        : () {
                            final n = app.reapplyPeople();
                            showMessage(context, n == 0 ? 'Nessun documento da aggiornare' : 'Aggiornati $n documenti');
                          },
                    child: const Text('Applica ai documenti'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Categorie comuni a tutta la casa (senza cartella per persona)', style: theme.textTheme.bodySmall),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final t in app.archive.activeTypes)
                  FilterChip(
                    label: Text(t.name),
                    selected: c.sharedTypeIds.contains(t.id),
                    onSelected: (v) {
                      if (v) {
                        c.sharedTypeIds.add(t.id);
                      } else {
                        c.sharedTypeIds.remove(t.id);
                      }
                      app.saveConfig();
                      setState(() {});
                    },
                  ),
              ],
            ),
            const Divider(height: 32),
            Text('Apprendimento automatico', style: theme.textTheme.titleMedium),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: app.training
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.psychology_outlined),
              title: Text(app.training
                  ? 'Addestramento in corso…'
                  : app.classifier == null
                      ? 'Non ancora addestrato'
                      : 'Addestrato su ${app.classifier!.trainedOn} documenti'),
              subtitle: const Text(
                'Come in Paperless: impara dai documenti già esaminati (senza il tag "Da esaminare") '
                'e assegna tag, corrispondenti, tipi e percorsi con algoritmo "Automatica".',
              ),
              trailing: IconButton(
                tooltip: 'Riaddestra ora',
                icon: const Icon(Icons.refresh),
                onPressed: app.training ? null : () => app.retrain(force: true),
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
