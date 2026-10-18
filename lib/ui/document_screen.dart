import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart' show PdfViewer;
import 'package:share_plus/share_plus.dart';

import '../core/dates.dart' show findDates;
import '../core/models.dart';
import '../state/app_state.dart';
import 'widgets.dart';

class DocumentScreen extends StatefulWidget {
  const DocumentScreen({super.key, required this.docId});

  final String docId;

  @override
  State<DocumentScreen> createState() => _DocumentScreenState();
}

class _DocumentScreenState extends State<DocumentScreen> {
  late final TextEditingController titleCtrl;
  late final TextEditingController contentCtrl;
  bool contentEditing = false;

  @override
  void initState() {
    super.initState();
    final d = AppScope.read(context).archive.documents[widget.docId];
    titleCtrl = TextEditingController(text: d?.title ?? '');
    contentCtrl = TextEditingController(text: d?.content ?? '');
  }

  @override
  void dispose() {
    titleCtrl.dispose();
    contentCtrl.dispose();
    super.dispose();
  }

  Future<void> share(AppState app, Document d) async {
    try {
      final f = await app.ensureFile(d);
      if (f == null) {
        if (mounted) showMessage(context, 'File non disponibile su questo telefono');
        return;
      }
      // Nome leggibile per chi riceve il file.
      final safe = d.title.replaceAll(RegExp(r'[^\w\s.-]', unicode: true), '_').trim();
      final named = File(app.storage.tmpPath('${safe.isEmpty ? d.id : safe}.pdf'));
      await f.copy(named.path);
      await SharePlus.instance.share(ShareParams(files: [XFile(named.path)]));
    } catch (e) {
      if (mounted) showMessage(context, 'Condivisione non riuscita: $e');
    }
  }

  Future<void> menu(AppState app, Document d, String action) async {
    switch (action) {
      case 'share':
        await share(app, d);
      case 'rules':
        final changed = app.reapplyRules([d]);
        if (mounted) showMessage(context, changed > 0 ? 'Regole applicate' : 'Nessuna regola corrisponde');
      case 'ocr':
        try {
          await app.reprocess(d);
          contentCtrl.text = d.content;
          if (mounted) showMessage(context, 'Testo riletto');
        } catch (e) {
          if (mounted) showMessage(context, 'Errore: $e');
        }
      case 'asn':
        d.asn = app.archive.nextAsn();
        app.saveDocument(d);
      case 'reviewed':
        app.markReviewed([d]);
      case 'trash':
        final ok = await confirm(context, title: 'Spostare nel cestino?', ok: 'Sposta', danger: true);
        if (!ok) return;
        app.moveToTrash([d]);
        if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final d = app.archive.documents[widget.docId];
    if (d == null || d.deleted) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('Documento non trovato')));
    }
    final isInbox = app.archive.inboxTags.any((t) => d.tagIds.contains(t.id));
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(d.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            if (isInbox)
              IconButton(
                tooltip: 'Segna come esaminato',
                icon: const Icon(Icons.done_all),
                onPressed: () => menu(app, d, 'reviewed'),
              ),
            IconButton(
              tooltip: 'Condividi',
              icon: const Icon(Icons.share_outlined),
              onPressed: () => share(app, d),
            ),
            PopupMenuButton<String>(
              onSelected: (v) => menu(app, d, v),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'rules', child: Text('Applica regole automatiche')),
                const PopupMenuItem(value: 'ocr', child: Text('Rileggi il testo (OCR)')),
                if (d.asn == null)
                  const PopupMenuItem(value: 'asn', child: Text('Assegna ASN')),
                const PopupMenuItem(value: 'trash', child: Text('Sposta nel cestino')),
              ],
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Dettagli'),
              Tab(text: 'Anteprima'),
              Tab(text: 'Testo'),
              Tab(text: 'Note'),
            ],
          ),
        ),
        body: Column(
          children: [
            if (app.busy != null)
              Column(children: [
                const LinearProgressIndicator(minHeight: 2),
                Padding(padding: const EdgeInsets.all(8), child: Text(app.busy!)),
              ]),
            Expanded(
              child: TabBarView(
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _details(app, d),
                  _Preview(doc: d),
                  _content(app, d),
                  _notes(app, d),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _details(AppState app, Document d) {
    final a = app.archive;
    final tags = d.tagIds.map(a.tag).whereType<Tag>().toList();
    final dates = findDates(d.content).take(6).toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: titleCtrl,
          decoration: const InputDecoration(labelText: 'Titolo', border: OutlineInputBorder()),
          textCapitalization: TextCapitalization.sentences,
          onChanged: (v) {
            d.title = v.trim();
            app.saveDocument(d);
          },
        ),
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event),
          title: const Text('Data del documento'),
          subtitle: Text(formatDate(d.created)),
          onTap: () async {
            final now = DateTime.now();
            final picked = await showDatePicker(
              context: context,
              initialDate: d.created,
              firstDate: DateTime(1900),
              lastDate: DateTime(now.year + 1, 12, 31),
            );
            if (picked == null) return;
            d.created = picked;
            app.saveDocument(d);
          },
        ),
        if (dates.length > 1)
          Padding(
            padding: const EdgeInsets.only(left: 56, bottom: 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final dt in dates)
                  ActionChip(
                    label: Text(formatDate(dt)),
                    onPressed: () {
                      d.created = dt;
                      app.saveDocument(d);
                    },
                  ),
              ],
            ),
          ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.person_outline),
          title: const Text('Corrispondente'),
          subtitle: Text(a.correspondent(d.correspondentId)?.name ?? 'Nessuno'),
          onTap: () async {
            final r = await pickCorrespondent(context, d.correspondentId);
            if (r == null) return;
            d.correspondentId = r.id;
            app.saveDocument(d);
          },
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.category_outlined),
          title: const Text('Tipo di documento'),
          subtitle: Text(a.type(d.typeId)?.name ?? 'Nessuno'),
          onTap: () async {
            final r = await pickType(context, d.typeId);
            if (r == null) return;
            d.typeId = r.id;
            app.saveDocument(d);
          },
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.numbers),
          title: const Text('Numero d\'archivio (ASN)'),
          subtitle: Text(d.asn?.toString() ?? 'Nessuno'),
          onTap: () async {
            final v = await askText(context,
                title: 'ASN', label: 'Numero (vuoto per toglierlo)', initial: d.asn?.toString() ?? '');
            if (v == null) return;
            d.asn = int.tryParse(v);
            app.saveDocument(d);
          },
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(Icons.label_outline),
            const SizedBox(width: 16),
            Text('Tag', style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            TextButton.icon(
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Modifica'),
              onPressed: () async {
                final r = await pickTags(context, d.tagIds);
                if (r == null) return;
                d.tagIds = r;
                app.saveDocument(d);
              },
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 40),
          child: tags.isEmpty
              ? const Text('Nessun tag')
              : Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final t in tags)
                      TagChip(t, onDeleted: () {
                        d.tagIds.remove(t.id);
                        app.saveDocument(d);
                      }),
                  ],
                ),
        ),
        const SizedBox(height: 16),
        ..._customFields(app, d),
        const Divider(height: 32),
        _info('Aggiunto', formatDate(DateTime.fromMillisecondsSinceEpoch(d.added))),
        _info('File originale', d.originalName),
        _info('Pagine', '${d.pageCount}'),
        _info('Dimensione', '${(d.fileSize / 1024).toStringAsFixed(0)} KB'),
        _info('Checksum MD5', d.checksum),
      ],
    );
  }

  Widget _info(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 120, child: Text(k, style: Theme.of(context).textTheme.labelMedium)),
            Expanded(child: Text(v, style: Theme.of(context).textTheme.bodySmall)),
          ],
        ),
      );

  List<Widget> _customFields(AppState app, Document d) {
    final fields = app.archive.activeFields;
    if (fields.isEmpty) return const [];
    final used = fields.where((f) => d.customFields.containsKey(f.id)).toList();
    final unused = fields.where((f) => !d.customFields.containsKey(f.id)).toList();
    return [
      Row(
        children: [
          const Icon(Icons.dashboard_customize_outlined),
          const SizedBox(width: 16),
          Text('Campi personalizzati', style: Theme.of(context).textTheme.titleMedium),
          const Spacer(),
          if (unused.isNotEmpty)
            PopupMenuButton<CustomField>(
              icon: const Icon(Icons.add),
              onSelected: (f) {
                d.customFields[f.id] = f.type == CustomFieldType.boolean ? 'false' : '';
                app.saveDocument(d);
              },
              itemBuilder: (_) => [
                for (final f in unused) PopupMenuItem(value: f, child: Text(f.name)),
              ],
            ),
        ],
      ),
      for (final f in used) _fieldEditor(app, d, f),
    ];
  }

  Widget _fieldEditor(AppState app, Document d, CustomField f) {
    final value = d.customFields[f.id] ?? '';
    final remove = IconButton(
      icon: const Icon(Icons.close),
      onPressed: () {
        d.customFields.remove(f.id);
        app.saveDocument(d);
      },
    );
    switch (f.type) {
      case CustomFieldType.boolean:
        return SwitchListTile(
          contentPadding: const EdgeInsets.only(left: 40),
          title: Text(f.name),
          value: value == 'true',
          onChanged: (v) {
            d.customFields[f.id] = '$v';
            app.saveDocument(d);
          },
          secondary: remove,
        );
      case CustomFieldType.date:
        final parsed = DateTime.tryParse(value);
        return ListTile(
          contentPadding: const EdgeInsets.only(left: 40),
          title: Text(f.name),
          subtitle: Text(parsed == null ? 'Tocca per scegliere' : formatDate(parsed)),
          trailing: remove,
          onTap: () async {
            final now = DateTime.now();
            final p = await showDatePicker(
              context: context,
              initialDate: parsed ?? now,
              firstDate: DateTime(1900),
              lastDate: DateTime(now.year + 20),
            );
            if (p == null) return;
            d.customFields[f.id] = p.toIso8601String().substring(0, 10);
            app.saveDocument(d);
          },
        );
      default:
        return ListTile(
          contentPadding: const EdgeInsets.only(left: 40),
          title: Text(f.name),
          subtitle: Text(value.isEmpty
              ? 'Tocca per inserire'
              : f.type == CustomFieldType.money
                  ? '€ $value'
                  : value),
          trailing: remove,
          onTap: () async {
            final v = await askText(context, title: f.name, label: f.type.label, initial: value);
            if (v == null) return;
            d.customFields[f.id] = v;
            app.saveDocument(d);
          },
        );
    }
  }

  Widget _content(AppState app, Document d) {
    if (!contentEditing && contentCtrl.text != d.content) contentCtrl.text = d.content;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  d.content.isEmpty
                      ? 'Nessun testo riconosciuto'
                      : '${d.content.length} caratteri',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
              TextButton.icon(
                icon: Icon(contentEditing ? Icons.check : Icons.edit_outlined),
                label: Text(contentEditing ? 'Fatto' : 'Correggi'),
                onPressed: () => setState(() {
                  if (contentEditing) {
                    d.content = contentCtrl.text;
                    app.saveDocument(d);
                  }
                  contentEditing = !contentEditing;
                }),
              ),
            ],
          ),
        ),
        Expanded(
          child: contentEditing
              ? Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    controller: contentCtrl,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(d.content.isEmpty ? '—' : d.content),
                ),
        ),
      ],
    );
  }

  Widget _notes(AppState app, Document d) {
    final notes = [...d.notes]..sort((x, y) => y.created.compareTo(x.created));
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        heroTag: 'note',
        onPressed: () async {
          final t = await askText(context, title: 'Nuova nota', label: 'Nota', multiline: true);
          if (t == null || t.isEmpty) return;
          d.notes.add(Note(text: t));
          app.saveDocument(d);
        },
        child: const Icon(Icons.add_comment_outlined),
      ),
      body: notes.isEmpty
          ? const EmptyState(icon: Icons.sticky_note_2_outlined, text: 'Nessuna nota')
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
              children: [
                for (final n in notes)
                  Card(
                    child: ListTile(
                      title: Text(n.text),
                      subtitle: Text(formatDate(DateTime.fromMillisecondsSinceEpoch(n.created))),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () {
                          d.notes.removeWhere((x) => x.id == n.id);
                          app.saveDocument(d);
                        },
                      ),
                      onTap: () async {
                        final t = await askText(context,
                            title: 'Modifica nota', label: 'Nota', initial: n.text, multiline: true);
                        if (t == null || t.isEmpty) return;
                        n.text = t;
                        app.saveDocument(d);
                      },
                    ),
                  ),
              ],
            ),
    );
  }
}

/// Anteprima del PDF (scaricato da Drive se manca sul telefono).
class _Preview extends StatefulWidget {
  const _Preview({required this.doc});

  final Document doc;

  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> with AutomaticKeepAliveClientMixin {
  Future<File?>? _file;

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _file ??= AppScope.read(context).ensureFile(widget.doc);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<File?>(
      future: _file,
      builder: (c, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError || snap.data == null) {
          return EmptyState(
            icon: Icons.cloud_off_outlined,
            text: 'Il PDF non è su questo telefono e non è stato possibile scaricarlo.'
                '${snap.hasError ? '\n${snap.error}' : ''}',
            action: OutlinedButton(
              onPressed: () => setState(() {
                _file = AppScope.read(context).ensureFile(widget.doc);
              }),
              child: const Text('Riprova'),
            ),
          );
        }
        return PdfViewer.file(snap.data!.path);
      },
    );
  }
}
