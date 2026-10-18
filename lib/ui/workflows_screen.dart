import 'package:material_ui/material_ui.dart';

import '../core/matching.dart' show regexError;
import '../core/models.dart';
import '../core/workflows.dart';
import '../state/app_state.dart';
import 'widgets.dart';

/// Elenco dei flussi di lavoro.
class WorkflowsScreen extends StatelessWidget {
  const WorkflowsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final flows = app.archive.activeWorkflows;
    return Scaffold(
      appBar: AppBar(title: const Text('Flussi di lavoro')),
      floatingActionButton: app.readOnly
          ? null
          : FloatingActionButton.extended(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => WorkflowEditor(
                    workflow: Workflow(
                      name: '',
                      order: flows.isEmpty ? 1 : flows.last.order + 1,
                    ),
                    isNew: true,
                  ),
                ),
              ),
              icon: const Icon(Icons.add),
              label: const Text('Nuovo flusso'),
            ),
      body: flows.isEmpty
          ? const EmptyState(
              icon: Icons.account_tree_outlined,
              text: 'Nessun flusso di lavoro.\n\n'
                  'Un flusso fa qualcosa da solo quando un documento viene aggiunto o '
                  'modificato. Esempio: se arriva per email e contiene "Enel", '
                  'imposta il titolo "Enel {created_year}-{created_month}", aggiungi il tag '
                  '"Bollette" e assegna l\'ASN.',
            )
          : ReorderableListView(
              padding: const EdgeInsets.only(bottom: 96),
              buildDefaultDragHandles: !app.readOnly,
              onReorder: (from, to) {
                final list = [...flows];
                if (to > from) to -= 1;
                final w = list.removeAt(from);
                list.insert(to, w);
                for (var i = 0; i < list.length; i++) {
                  if (list[i].order != i + 1) {
                    list[i].order = i + 1;
                    app.saveWorkflow(list[i]);
                  }
                }
              },
              children: [
                for (final w in flows)
                  ListTile(
                    key: ValueKey(w.id),
                    leading: Switch(
                      value: w.enabled,
                      onChanged: app.readOnly
                          ? null
                          : (v) {
                              w.enabled = v;
                              app.saveWorkflow(w);
                            },
                    ),
                    title: Text(w.name),
                    subtitle: Text(_summary(app, w), maxLines: 2, overflow: TextOverflow.ellipsis),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => WorkflowEditor(workflow: Workflow.fromJson(w.toJson())),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  static String _summary(AppState app, Workflow w) {
    final when = w.triggers.map((t) => t.label.toLowerCase()).join(' o ');
    final actions = <String>[
      if (w.titleTemplate.isNotEmpty) 'titolo',
      if (w.addTags.isNotEmpty) '+${w.addTags.length} tag',
      if (w.removeTags.isNotEmpty || w.removeAllTags) 'toglie tag',
      if (w.setCorrespondent != null) 'corrispondente',
      if (w.setType != null) 'tipo',
      if (w.setStoragePath != null) 'percorso',
      if (w.setFields.isNotEmpty) 'campi',
      if (w.assignAsn) 'ASN',
      if (w.markReviewed) 'esaminato',
      if (w.addNote.isNotEmpty) 'nota',
    ];
    return 'Quando: $when · Azioni: ${actions.isEmpty ? 'nessuna' : actions.join(', ')}';
  }
}

/// Modifica di un flusso: quando, condizioni, azioni.
class WorkflowEditor extends StatefulWidget {
  const WorkflowEditor({super.key, required this.workflow, this.isNew = false});

  /// Copia da modificare: viene salvata solo con "Salva".
  final Workflow workflow;
  final bool isNew;

  @override
  State<WorkflowEditor> createState() => _WorkflowEditorState();
}

class _WorkflowEditorState extends State<WorkflowEditor> {
  Workflow get w => widget.workflow;
  late final TextEditingController name = TextEditingController(text: w.name);
  late final TextEditingController file = TextEditingController(text: w.filenamePattern);
  late final TextEditingController pattern = TextEditingController(text: w.pattern);
  late final TextEditingController title = TextEditingController(text: w.titleTemplate);
  late final TextEditingController note = TextEditingController(text: w.addNote);

  @override
  void dispose() {
    for (final c in [name, file, pattern, title, note]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _apply() {
    if (name.text.trim().isEmpty) return 'Dai un nome al flusso';
    if (w.triggers.isEmpty) return 'Scegli almeno un momento (aggiunto o modificato)';
    if (w.algorithm == MatchAlgorithm.regex) {
      final err = regexError(pattern.text);
      if (err != null) return 'Espressione regolare non valida: $err';
    }
    w
      ..name = name.text.trim()
      ..filenamePattern = file.text.trim()
      ..pattern = pattern.text.trim()
      ..titleTemplate = title.text.trim()
      ..addNote = note.text.trim();
    return null;
  }

  Widget _section(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 24, 0, 8),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );

  Widget _tagsTile(String label, Set<String> ids) {
    final app = AppScope.read(context);
    final tags = ids.map(app.archive.tag).whereType<Tag>().toList();
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: tags.isEmpty
          ? const Text('Nessuno')
          : Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(spacing: 4, runSpacing: 4, children: [
                for (final t in tags) TagChip(t, small: true),
              ]),
            ),
      trailing: const Icon(Icons.edit_outlined),
      onTap: () async {
        final r = await pickTags(context, ids);
        if (r == null) return;
        setState(() {
          ids
            ..clear()
            ..addAll(r);
        });
      },
    );
  }

  Widget _entityTile(String label, String? value, String? name, Future<void> Function() onTap) =>
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        subtitle: Text(value == null ? 'Qualsiasi / nessuna modifica' : (name ?? '?')),
        trailing: const Icon(Icons.edit_outlined),
        onTap: onTap,
      );

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final a = app.archive;
    final ro = app.readOnly;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isNew ? 'Nuovo flusso' : 'Modifica flusso'),
        actions: [
          if (!widget.isNew && !ro)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (await confirm(context, title: 'Eliminare il flusso?', ok: 'Elimina', danger: true)) {
                  app.deleteWorkflow(a.workflows[w.id]!);
                  if (context.mounted) Navigator.pop(context);
                }
              },
            ),
          if (!ro)
            TextButton(
              onPressed: () {
                final err = _apply();
                if (err != null) {
                  showMessage(context, err);
                  return;
                }
                app.saveWorkflow(w);
                Navigator.pop(context);
              },
              child: const Text('Salva'),
            ),
        ],
      ),
      body: IgnorePointer(
        ignoring: ro,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
          children: [
            TextField(
              controller: name,
              autofocus: widget.isNew,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Nome', border: OutlineInputBorder()),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Attivo'),
              value: w.enabled,
              onChanged: (v) => setState(() => w.enabled = v),
            ),
            _section('Quando'),
            for (final t in WorkflowTrigger.values)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t.label),
                value: w.triggers.contains(t),
                onChanged: (v) => setState(() => v == true ? w.triggers.add(t) : w.triggers.remove(t)),
              ),
            if (w.triggers.contains(WorkflowTrigger.added)) ...[
              const Text('Provenienza (nessuna scelta = tutte)'),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                children: [
                  for (final s in DocSource.values)
                    FilterChip(
                      label: Text(s.label),
                      selected: w.sources.contains(s),
                      onSelected: (v) => setState(() => v ? w.sources.add(s) : w.sources.remove(s)),
                    ),
                ],
              ),
            ],
            _section('Condizioni (tutte devono valere)'),
            TextField(
              controller: file,
              decoration: const InputDecoration(
                labelText: 'Nome del file',
                hintText: 'es. *fattura*.pdf  (vuoto = qualsiasi)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<MatchAlgorithm>(
              initialValue: w.algorithm == MatchAlgorithm.auto ? MatchAlgorithm.none : w.algorithm,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Il testo del documento contiene',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final m in MatchAlgorithm.values.where((m) => m != MatchAlgorithm.auto))
                  DropdownMenuItem(
                    value: m,
                    child: Text(m == MatchAlgorithm.none ? 'Nessuna condizione sul testo' : m.label),
                  ),
              ],
              onChanged: (v) => setState(() => w.algorithm = v ?? MatchAlgorithm.none),
            ),
            if (w.algorithm.needsPattern) ...[
              const SizedBox(height: 8),
              TextField(
                controller: pattern,
                decoration: InputDecoration(
                  labelText: w.algorithm == MatchAlgorithm.regex ? 'Espressione regolare' : 'Parole o testo',
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
            _tagsTile('Ha tutti questi tag', w.hasTags),
            _tagsTile('Non ha nessuno di questi tag', w.hasNotTags),
            _entityTile('Corrispondente è', w.ifCorrespondent, a.correspondent(w.ifCorrespondent)?.name,
                () async {
              final r = await pickCorrespondent(context, w.ifCorrespondent);
              if (r != null) setState(() => w.ifCorrespondent = r.id);
            }),
            _entityTile('Tipo è', w.ifType, a.type(w.ifType)?.name, () async {
              final r = await pickType(context, w.ifType);
              if (r != null) setState(() => w.ifType = r.id);
            }),
            _section('Azioni'),
            TextField(
              controller: title,
              decoration: const InputDecoration(
                labelText: 'Nuovo titolo (vuoto = non cambiare)',
                hintText: '{correspondent} {document_type} {created_year}-{created_month}',
                border: OutlineInputBorder(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final e in titlePlaceholders.entries)
                    ActionChip(
                      label: Text(e.key, style: const TextStyle(fontSize: 11)),
                      tooltip: e.value,
                      onPressed: () {
                        final t = title.text;
                        title.text = t.isEmpty || t.endsWith(' ') ? '$t${e.key}' : '$t ${e.key}';
                      },
                    ),
                  const ActionChip(
                    label: Text('{campo:Nome}', style: TextStyle(fontSize: 11)),
                    tooltip: 'valore di un campo personalizzato',
                  ),
                ],
              ),
            ),
            _tagsTile('Aggiungi tag', w.addTags),
            _tagsTile('Togli tag', w.removeTags),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Togli prima tutti i tag'),
              value: w.removeAllTags,
              onChanged: (v) => setState(() => w.removeAllTags = v),
            ),
            _entityTile('Imposta corrispondente', w.setCorrespondent,
                a.correspondent(w.setCorrespondent)?.name, () async {
              final r = await pickCorrespondent(context, w.setCorrespondent);
              if (r != null) setState(() => w.setCorrespondent = r.id);
            }),
            _entityTile('Imposta tipo', w.setType, a.type(w.setType)?.name, () async {
              final r = await pickType(context, w.setType);
              if (r != null) setState(() => w.setType = r.id);
            }),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Imposta percorso di archiviazione'),
              subtitle: Text(a.storagePath(w.setStoragePath)?.name ?? 'Non cambiare'),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () async {
                final chosen = await showDialog<String>(
                  context: context,
                  builder: (c) => SimpleDialog(
                    title: const Text('Percorso'),
                    children: [
                      SimpleDialogOption(
                        onPressed: () => Navigator.pop(c, ''),
                        child: const Text('Non cambiare'),
                      ),
                      for (final p in a.activeStoragePaths)
                        SimpleDialogOption(onPressed: () => Navigator.pop(c, p.id), child: Text(p.name)),
                    ],
                  ),
                );
                if (chosen != null) setState(() => w.setStoragePath = chosen.isEmpty ? null : chosen);
              },
            ),
            for (final f in a.activeFields)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Campo "${f.name}"'),
                subtitle: Text(w.setFields.containsKey(f.id)
                    ? 'Imposta: ${w.setFields[f.id]!.isEmpty ? '(vuoto)' : w.setFields[f.id]}'
                    : 'Non cambiare'),
                trailing: w.setFields.containsKey(f.id)
                    ? IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => w.setFields.remove(f.id)),
                      )
                    : const Icon(Icons.add),
                onTap: () async {
                  final v = await askText(context,
                      title: f.name, label: f.type.label, initial: w.setFields[f.id] ?? '');
                  if (v != null) setState(() => w.setFields[f.id] = v);
                },
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Assegna il prossimo ASN'),
              value: w.assignAsn,
              onChanged: (v) => setState(() => w.assignAsn = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Segna come esaminato'),
              subtitle: const Text('Toglie il tag "da esaminare"'),
              value: w.markReviewed,
              onChanged: (v) => setState(() => w.markReviewed = v),
            ),
            TextField(
              controller: note,
              decoration: const InputDecoration(
                labelText: 'Aggiungi una nota (vuoto = nessuna)',
                border: OutlineInputBorder(),
              ),
            ),
            if (!widget.isNew) ...[
              const SizedBox(height: 24),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.play_arrow),
                label: const Text('Salva ed esegui sui documenti esistenti'),
                onPressed: () async {
                  final err = _apply();
                  if (err != null) {
                    showMessage(context, err);
                    return;
                  }
                  final ok = await confirm(context,
                      title: 'Eseguire "${w.name}" su tutti i documenti?',
                      message: 'Le azioni verranno applicate ai documenti che soddisfano le condizioni '
                          '(la provenienza non conta).',
                      ok: 'Esegui');
                  if (!ok) return;
                  app.saveWorkflow(w);
                  final n = app.runWorkflowOn(w, app.archive.activeDocuments);
                  if (!context.mounted) return;
                  showMessage(context, 'Aggiornati $n documenti');
                  Navigator.pop(context);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
