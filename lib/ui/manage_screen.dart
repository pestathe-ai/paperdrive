import 'package:material_ui/material_ui.dart';

import '../core/matching.dart';
import '../core/models.dart';
import '../state/app_state.dart';
import 'widgets.dart';

/// Gestione di tag, corrispondenti, tipi, viste salvate e campi.
class ManageScreen extends StatelessWidget {
  const ManageScreen({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final a = app.archive;
    return DefaultTabController(
      length: 5,
      initialIndex: initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Gestione'),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Tag'),
              Tab(text: 'Corrispondenti'),
              Tab(text: 'Tipi'),
              Tab(text: 'Viste'),
              Tab(text: 'Campi'),
            ],
          ),
        ),
        floatingActionButton: Builder(
          builder: (c) => FloatingActionButton(
            onPressed: () => _create(c, DefaultTabController.of(c).index),
            child: const Icon(Icons.add),
          ),
        ),
        body: TabBarView(
          children: [
            _list(
              context,
              empty: 'Nessun tag',
              children: [
                for (final t in a.activeTags)
                  ListTile(
                    leading: CircleAvatar(backgroundColor: Color(t.color), radius: 12),
                    title: Text(t.name),
                    subtitle: Text(_ruleText(t, a.countWithTag(t.id), inbox: t.isInbox)),
                    onTap: () => _open(context, EntityEditor.tag(tag: t)),
                  ),
              ],
            ),
            _list(
              context,
              empty: 'Nessun corrispondente',
              children: [
                for (final e in a.activeCorrespondents)
                  ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: Text(e.name),
                    subtitle: Text(_ruleText(e, a.countWithCorrespondent(e.id))),
                    onTap: () => _open(context, EntityEditor.correspondent(entity: e)),
                  ),
              ],
            ),
            _list(
              context,
              empty: 'Nessun tipo di documento',
              children: [
                for (final e in a.activeTypes)
                  ListTile(
                    leading: const Icon(Icons.category_outlined),
                    title: Text(e.name),
                    subtitle: Text(_ruleText(e, a.countWithType(e.id))),
                    onTap: () => _open(context, EntityEditor.type(entity: e)),
                  ),
              ],
            ),
            _list(
              context,
              empty: 'Nessuna vista salvata.\nDalla lista documenti: filtra, poi menu ⋮ → "Salva come vista".',
              children: [
                for (final v in a.activeViews)
                  ListTile(
                    leading: const Icon(Icons.view_list_outlined),
                    title: Text(v.name),
                    subtitle: Text('${app.query(v.filter).length} documenti'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          value: v.showOnHome,
                          onChanged: (x) {
                            v.showOnHome = x;
                            app.saveView(v);
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            if (await confirm(context, title: 'Eliminare la vista "${v.name}"?', danger: true, ok: 'Elimina')) {
                              app.deleteView(v);
                            }
                          },
                        ),
                      ],
                    ),
                    onTap: () async {
                      final n = await askText(context, title: 'Rinomina vista', initial: v.name);
                      if (n == null || n.isEmpty) return;
                      v.name = n;
                      app.saveView(v);
                    },
                  ),
              ],
            ),
            _list(
              context,
              empty: 'Nessun campo personalizzato.\nEs. "Importo", "Scadenza", "Numero contratto".',
              children: [
                for (final f in a.activeFields)
                  ListTile(
                    leading: const Icon(Icons.dashboard_customize_outlined),
                    title: Text(f.name),
                    subtitle: Text(f.type.label),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        if (await confirm(context,
                            title: 'Eliminare il campo "${f.name}"?',
                            message: 'I valori inseriti nei documenti verranno tolti.',
                            danger: true,
                            ok: 'Elimina')) {
                          app.deleteField(f);
                        }
                      },
                    ),
                    onTap: () async {
                      final n = await askText(context, title: 'Rinomina campo', initial: f.name);
                      if (n == null || n.isEmpty) return;
                      f.name = n;
                      app.saveField(f);
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _ruleText(Matchable m, int count, {bool inbox = false}) {
    final parts = <String>[
      count == 1 ? '1 documento' : '$count documenti',
      if (inbox) 'tag "da esaminare"',
      if (m.algorithm != MatchAlgorithm.none)
        m.algorithm.needsPattern
            ? '${m.algorithm.label}: ${m.pattern}'
            : m.algorithm.label,
    ];
    return parts.join(' · ');
  }

  Widget _list(BuildContext context, {required String empty, required List<Widget> children}) {
    if (children.isEmpty) {
      return EmptyState(icon: Icons.folder_open_outlined, text: empty);
    }
    return ListView(padding: const EdgeInsets.only(bottom: 96), children: children);
  }

  void _open(BuildContext context, Widget page) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  Future<void> _create(BuildContext context, int tab) async {
    final app = AppScope.read(context);
    switch (tab) {
      case 0:
        _open(context, EntityEditor.tag());
      case 1:
        _open(context, EntityEditor.correspondent());
      case 2:
        _open(context, EntityEditor.type());
      case 3:
        showMessage(context, 'Filtra i documenti nella lista, poi menu ⋮ → "Salva come vista".');
      case 4:
        final name = await askText(context, title: 'Nuovo campo');
        if (name == null || name.isEmpty || !context.mounted) return;
        final type = await showDialog<CustomFieldType>(
          context: context,
          builder: (c) => SimpleDialog(
            title: const Text('Tipo di campo'),
            children: [
              for (final t in CustomFieldType.values)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(c, t),
                  child: Text(t.label),
                ),
            ],
          ),
        );
        if (type == null) return;
        app.saveField(CustomField(name: name, type: type));
    }
  }
}

enum EntityKind { tag, correspondent, type }

/// Modifica di un tag, corrispondente o tipo, con la regola automatica.
class EntityEditor extends StatefulWidget {
  const EntityEditor._({required this.kind, this.tag, this.entity});

  factory EntityEditor.tag({Tag? tag}) => EntityEditor._(kind: EntityKind.tag, tag: tag);
  factory EntityEditor.correspondent({NamedEntity? entity}) =>
      EntityEditor._(kind: EntityKind.correspondent, entity: entity);
  factory EntityEditor.type({NamedEntity? entity}) =>
      EntityEditor._(kind: EntityKind.type, entity: entity);

  final EntityKind kind;
  final Tag? tag;
  final NamedEntity? entity;

  @override
  State<EntityEditor> createState() => _EntityEditorState();
}

class _EntityEditorState extends State<EntityEditor> {
  late final TextEditingController name;
  late final TextEditingController pattern;
  late MatchAlgorithm algorithm;
  late bool ci;
  late int color;
  late bool inbox;
  int? matchCount;

  bool get isNew => widget.tag == null && widget.entity == null;

  String get kindLabel => switch (widget.kind) {
        EntityKind.tag => 'tag',
        EntityKind.correspondent => 'corrispondente',
        EntityKind.type => 'tipo di documento',
      };

  @override
  void initState() {
    super.initState();
    final Matchable? m = widget.tag ?? widget.entity;
    name = TextEditingController(text: m?.name ?? '');
    pattern = TextEditingController(text: m?.pattern ?? '');
    algorithm = m?.algorithm ?? MatchAlgorithm.none;
    ci = m?.caseInsensitive ?? true;
    color = widget.tag?.color ?? tagPalette[DateTime.now().millisecond % tagPalette.length];
    inbox = widget.tag?.isInbox ?? false;
  }

  @override
  void dispose() {
    name.dispose();
    pattern.dispose();
    super.dispose();
  }

  /// Regola temporanea con i valori del modulo, per provarla.
  Matchable _draft() => NamedEntity(
        name: name.text,
        algorithm: algorithm,
        pattern: pattern.text,
        caseInsensitive: ci,
      );

  void _test(AppState app) {
    final rule = _draft();
    final n = app.archive.activeDocuments.where((d) => matchesRule(rule, matchText(d))).length;
    setState(() => matchCount = n);
  }

  String? _save(AppState app) {
    final n = name.text.trim();
    if (n.isEmpty) return 'Inserisci un nome';
    if (algorithm == MatchAlgorithm.regex) {
      final err = regexError(pattern.text);
      if (err != null) return 'Espressione regolare non valida: $err';
    }
    switch (widget.kind) {
      case EntityKind.tag:
        final t = widget.tag ?? Tag(name: n);
        t
          ..name = n
          ..color = color
          ..isInbox = inbox
          ..algorithm = algorithm
          ..pattern = pattern.text.trim()
          ..caseInsensitive = ci;
        app.saveTag(t);
      case EntityKind.correspondent:
      case EntityKind.type:
        final e = widget.entity ?? NamedEntity(name: n);
        e
          ..name = n
          ..algorithm = algorithm
          ..pattern = pattern.text.trim()
          ..caseInsensitive = ci;
        if (widget.kind == EntityKind.type) {
          app.saveType(e);
        } else {
          app.saveCorrespondent(e);
        }
    }
    return null;
  }

  Future<void> _delete(AppState app) async {
    final ok = await confirm(context,
        title: 'Eliminare "${name.text}"?',
        message: 'Verrà tolto da tutti i documenti. I documenti restano.',
        ok: 'Elimina',
        danger: true);
    if (!ok) return;
    switch (widget.kind) {
      case EntityKind.tag:
        app.deleteTag(widget.tag!);
      case EntityKind.correspondent:
        app.deleteCorrespondent(widget.entity!);
      case EntityKind.type:
        app.deleteType(widget.entity!);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? 'Nuovo $kindLabel' : 'Modifica $kindLabel'),
        actions: [
          if (!isNew)
            IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _delete(app)),
          TextButton(
            onPressed: () {
              final err = _save(app);
              if (err != null) {
                showMessage(context, err);
              } else {
                Navigator.pop(context);
              }
            },
            child: const Text('Salva'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: name,
            autofocus: isNew,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Nome', border: OutlineInputBorder()),
          ),
          if (widget.kind == EntityKind.tag) ...[
            const SizedBox(height: 16),
            Text('Colore', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in tagPalette)
                  GestureDetector(
                    onTap: () => setState(() => color = c),
                    child: CircleAvatar(
                      radius: 18,
                      backgroundColor: Color(c),
                      child: c == color ? Icon(Icons.check, color: textOn(Color(c))) : null,
                    ),
                  ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Tag "da esaminare"'),
              subtitle: const Text('Aggiunto a ogni nuovo documento, finché non lo segni come esaminato'),
              value: inbox,
              onChanged: (v) => setState(() => inbox = v),
            ),
          ],
          const Divider(height: 32),
          Text('Assegnazione automatica', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          DropdownButtonFormField<MatchAlgorithm>(
            initialValue: algorithm,
            isExpanded: true,
            decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Algoritmo'),
            items: [
              for (final a in MatchAlgorithm.values)
                DropdownMenuItem(value: a, child: Text(a.label)),
            ],
            onChanged: (v) => setState(() {
              algorithm = v ?? MatchAlgorithm.none;
              matchCount = null;
            }),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(algorithm.help, style: Theme.of(context).textTheme.bodySmall),
          ),
          if (algorithm.needsPattern) ...[
            TextField(
              controller: pattern,
              decoration: InputDecoration(
                labelText: algorithm == MatchAlgorithm.regex ? 'Espressione regolare' : 'Parole o testo',
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() => matchCount = null),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Ignora maiuscole e accenti'),
              value: ci,
              onChanged: (v) => setState(() {
                ci = v;
                matchCount = null;
              }),
            ),
            Row(
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.science_outlined),
                  label: const Text('Prova sui documenti'),
                  onPressed: () => _test(app),
                ),
                const SizedBox(width: 12),
                if (matchCount != null)
                  Expanded(child: Text('Corrisponde a $matchCount documenti')),
              ],
            ),
          ],
          if (!isNew && algorithm != MatchAlgorithm.none) ...[
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.auto_fix_high),
              label: const Text('Salva e applica ai documenti esistenti'),
              onPressed: () {
                final err = _save(app);
                if (err != null) {
                  showMessage(context, err);
                  return;
                }
                final n = app.reapplyRules(app.archive.activeDocuments);
                showMessage(context, 'Aggiornati $n documenti');
                Navigator.pop(context);
              },
            ),
          ],
        ],
      ),
    );
  }
}
