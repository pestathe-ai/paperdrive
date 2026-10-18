import 'package:material_ui/material_ui.dart';

import '../core/models.dart';
import '../core/search.dart' show snippet;
import '../state/app_state.dart';
import 'document_screen.dart';
import 'filter_sheet.dart';
import 'mail_screen.dart';
import 'manage_screen.dart';
import 'settings_screen.dart';
import 'sharing_screen.dart';
import 'trash_screen.dart';
import 'workflows_screen.dart';
import 'widgets.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  DocumentFilter filter = DocumentFilter();
  String? activeViewId;
  final searchCtrl = TextEditingController();
  final Set<String> selected = {};

  @override
  void dispose() {
    searchCtrl.dispose();
    super.dispose();
  }

  void setFilter(DocumentFilter f, {String? viewId}) {
    setState(() {
      filter = f;
      activeViewId = viewId;
      searchCtrl.text = f.query;
      selected.clear();
    });
  }

  Future<void> add(bool scan) async {
    final app = AppScope.read(context);
    try {
      final msgs = scan ? await app.scanDocument() : await app.importFiles();
      if (!mounted || msgs.isEmpty) return;
      showMessage(context, msgs.length == 1 ? msgs.first : msgs.join('\n'));
    } catch (e) {
      if (mounted) showMessage(context, 'Errore: $e');
    }
  }

  void showAddSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.document_scanner_outlined),
              title: const Text('Scansiona documento'),
              subtitle: const Text('Fotocamera con ritaglio automatico e OCR'),
              onTap: () {
                Navigator.pop(c);
                add(true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.upload_file),
              title: const Text('Importa PDF o immagini'),
              subtitle: const Text('Dal telefono, da Drive o da altre app'),
              onTap: () {
                Navigator.pop(c);
                add(false);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> sync() async {
    final app = AppScope.read(context);
    if (!app.settings.driveEnabled) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
      return;
    }
    try {
      final r = await app.syncNow();
      if (mounted) showMessage(context, r);
    } catch (e) {
      if (mounted) showMessage(context, 'Sincronizzazione non riuscita: $e');
    }
  }

  Future<void> saveView() async {
    final app = AppScope.read(context);
    final name = await askText(context, title: 'Salva vista', label: 'Nome della vista');
    if (name == null || name.isEmpty) return;
    final v = SavedView(name: name, filter: filter.copy());
    app.saveView(v);
    setState(() => activeViewId = v.id);
  }

  // ---------------------------------------------------------------- selezione

  List<Document> selectedDocs(AppState app) =>
      selected.map((id) => app.archive.documents[id]).whereType<Document>().toList();

  Future<void> bulk(String action) async {
    final app = AppScope.read(context);
    final docs = selectedDocs(app);
    if (docs.isEmpty) return;
    switch (action) {
      case 'tag':
        final tags = await pickTags(context, {});
        if (tags == null) return;
        for (final t in tags) {
          app.bulkAddTag(docs, t);
        }
      case 'untag':
        final tags = await pickTags(context, {});
        if (tags == null) return;
        for (final t in tags) {
          app.bulkRemoveTag(docs, t);
        }
      case 'corr':
        if (!mounted) return;
        final r = await pickCorrespondent(context, null);
        if (r != null) app.bulkSetCorrespondent(docs, r.id);
      case 'type':
        final r = await pickType(context, null);
        if (r != null) app.bulkSetType(docs, r.id);
      case 'reviewed':
        app.markReviewed(docs);
      case 'rules':
        final n = app.reapplyRules(docs);
        if (mounted) showMessage(context, 'Regole applicate: $n documenti aggiornati');
      case 'all':
        setState(() => selected.addAll(app.query(filter).map((d) => d.id)));
        return;
      case 'trash':
        final ok = await confirm(context,
            title: 'Spostare ${docs.length} documenti nel cestino?', ok: 'Sposta', danger: true);
        if (!ok) return;
        app.moveToTrash(docs);
    }
    setState(selected.clear);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (!app.ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final docs = app.query(filter);
    final selecting = selected.isNotEmpty;
    final views = app.archive.activeViews.where((v) => v.showOnHome).toList();
    final filterActive = filter.tagIds.isNotEmpty ||
        filter.excludedTagIds.isNotEmpty ||
        filter.correspondentId != null ||
        filter.typeId != null ||
        filter.from != null ||
        filter.to != null ||
        filter.inboxOnly ||
        filter.untaggedOnly ||
        filter.mineOnly;

    return PopScope(
      canPop: !selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(selected.clear);
      },
      child: Scaffold(
        drawer: selecting ? null : _drawer(app),
        appBar: selecting
            ? AppBar(
                leading: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(selected.clear),
                ),
                title: Text('${selected.length} selezionati'),
                actions: [
                  IconButton(
                    tooltip: 'Aggiungi tag',
                    icon: const Icon(Icons.label_outline),
                    onPressed: () => bulk('tag'),
                  ),
                  IconButton(
                    tooltip: 'Esaminati',
                    icon: const Icon(Icons.done_all),
                    onPressed: () => bulk('reviewed'),
                  ),
                  IconButton(
                    tooltip: 'Cestino',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => bulk('trash'),
                  ),
                  PopupMenuButton<String>(
                    onSelected: bulk,
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'all', child: Text('Seleziona tutti')),
                      PopupMenuItem(value: 'untag', child: Text('Togli tag')),
                      PopupMenuItem(value: 'corr', child: Text('Imposta corrispondente')),
                      PopupMenuItem(value: 'type', child: Text('Imposta tipo')),
                      PopupMenuItem(value: 'rules', child: Text('Applica regole automatiche')),
                    ],
                  ),
                ],
              )
            : AppBar(
                title: const Text('Paperdrive'),
                actions: [
                  IconButton(
                    tooltip: 'Sincronizza',
                    onPressed: app.syncing ? null : sync,
                    icon: app.syncing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(app.settings.driveEnabled
                            ? (app.settings.lastSyncError == null
                                ? Icons.cloud_done_outlined
                                : Icons.cloud_off_outlined)
                            : Icons.cloud_outlined),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'save') saveView();
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'save', child: Text('Salva come vista')),
                    ],
                  ),
                ],
              ),
        floatingActionButton: selecting || app.readOnly
            ? null
            : FloatingActionButton.extended(
                onPressed: app.busy == null ? showAddSheet : null,
                icon: const Icon(Icons.add),
                label: const Text('Aggiungi'),
              ),
        body: Column(
          children: [
            if (app.readOnly)
              Material(
                color: Theme.of(context).colorScheme.tertiaryContainer,
                child: const ListTile(
                  dense: true,
                  leading: Icon(Icons.visibility_outlined),
                  title: Text('Archivio condiviso in sola lettura'),
                ),
              ),
            if (app.busy != null || app.syncStatus != null)
              Material(
                color: Theme.of(context).colorScheme.secondaryContainer,
                child: Column(
                  children: [
                    const LinearProgressIndicator(minHeight: 2),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              app.busy ?? app.syncStatus ?? '',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: SearchBar(
                controller: searchCtrl,
                hintText: 'Cerca nel testo, tag:casa, da:enel…',
                leading: const Icon(Icons.search),
                elevation: const WidgetStatePropertyAll(0),
                onChanged: (v) => setState(() {
                  filter.query = v;
                  activeViewId = null;
                }),
                trailing: [
                  if (searchCtrl.text.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() {
                        searchCtrl.clear();
                        filter.query = '';
                      }),
                    ),
                  IconButton(
                    tooltip: 'Filtri',
                    icon: Badge(
                      isLabelVisible: filterActive,
                      smallSize: 8,
                      child: const Icon(Icons.tune),
                    ),
                    onPressed: () async {
                      final f = await showFilterSheet(context, filter);
                      if (f != null) setFilter(f..query = searchCtrl.text);
                    },
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                children: [
                  _viewChip('Tutti', activeViewId == null && filter.isEmpty,
                      () => setFilter(DocumentFilter())),
                  _viewChip('Da esaminare', activeViewId == null && filter.inboxOnly && filter.query.isEmpty,
                      () => setFilter(DocumentFilter(inboxOnly: true))),
                  for (final v in views)
                    _viewChip(v.name, activeViewId == v.id,
                        () => setFilter(v.filter.copy(), viewId: v.id)),
                ],
              ),
            ),
            Expanded(
              child: docs.isEmpty
                  ? EmptyState(
                      icon: app.archive.activeDocuments.isEmpty
                          ? Icons.inventory_2_outlined
                          : Icons.search_off,
                      text: app.archive.activeDocuments.isEmpty
                          ? 'L\'archivio è vuoto.\nScansiona o importa il primo documento.'
                          : 'Nessun documento corrisponde.',
                      action: app.archive.activeDocuments.isEmpty
                          ? FilledButton.icon(
                              onPressed: showAddSheet,
                              icon: const Icon(Icons.add),
                              label: const Text('Aggiungi'),
                            )
                          : null,
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 96),
                      itemCount: docs.length + 1,
                      separatorBuilder: (_, _) => const Divider(height: 1, indent: 84),
                      itemBuilder: (c, i) {
                        if (i == 0) {
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                            child: Text(
                              docs.length == 1 ? '1 documento' : '${docs.length} documenti',
                              style: Theme.of(c).textTheme.labelMedium,
                            ),
                          );
                        }
                        return _docTile(app, docs[i - 1]);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _viewChip(String label, bool active, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Text(label),
          selected: active,
          onSelected: (_) => onTap(),
        ),
      );

  Widget _docTile(AppState app, Document d) {
    final a = app.archive;
    final corr = a.correspondent(d.correspondentId);
    final type = a.type(d.typeId);
    final tags = d.tagIds.map(a.tag).whereType<Tag>().toList();
    final isSel = selected.contains(d.id);
    final sub = [
      formatDate(d.created),
      if (corr != null) corr.name,
      if (type != null) type.name,
      if (d.asn != null) 'ASN ${d.asn}',
    ].join(' · ');
    final excerpt = filter.query.trim().isEmpty ? '' : snippet(d, filter.query);
    return ListTile(
      selected: isSel,
      selectedTileColor: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      leading: Stack(
        children: [
          DocThumb(d),
          if (isSel)
            const Positioned(
              right: 2,
              bottom: 2,
              child: Icon(Icons.check_circle, size: 20),
            ),
        ],
      ),
      title: Text(d.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis),
          if (excerpt.isNotEmpty)
            Text(excerpt,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontStyle: FontStyle.italic)),
          if (tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [for (final t in tags) TagChip(t, small: true)],
              ),
            ),
        ],
      ),
      onLongPress: app.readOnly
          ? null
          : () => setState(() => isSel ? selected.remove(d.id) : selected.add(d.id)),
      onTap: () {
        if (selected.isNotEmpty) {
          setState(() => isSel ? selected.remove(d.id) : selected.add(d.id));
          return;
        }
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => DocumentScreen(docId: d.id)),
        );
      },
    );
  }

  Drawer _drawer(AppState app) {
    void go(Widget page) {
      Navigator.pop(context);
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    }

    final total = app.archive.activeDocuments.length;
    final s = app.settings;
    return Drawer(
      child: SafeArea(
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Paperdrive', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 4),
                  Text('$total documenti'
                      '${s.driveEnabled ? ' · Drive: ${s.driveAccount ?? 'collegato'}' : ' · solo sul telefono'}'),
                ],
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.inbox_outlined),
              title: const Text('Da esaminare'),
              onTap: () {
                Navigator.pop(context);
                setFilter(DocumentFilter(inboxOnly: true));
              },
            ),
            ListTile(
              leading: const Icon(Icons.label_outline),
              title: const Text('Tag, corrispondenti e tipi'),
              onTap: () => go(const ManageScreen()),
            ),
            ListTile(
              leading: const Icon(Icons.view_list_outlined),
              title: const Text('Viste salvate e campi'),
              onTap: () => go(const ManageScreen(initialTab: 3)),
            ),
            ListTile(
              leading: const Icon(Icons.account_tree_outlined),
              title: const Text('Flussi di lavoro'),
              trailing: app.archive.activeWorkflows.isEmpty
                  ? null
                  : Text('${app.archive.activeWorkflows.length}'),
              onTap: () => go(const WorkflowsScreen()),
            ),
            ListTile(
              leading: const Icon(Icons.mail_outline),
              title: const Text('Importazione da email'),
              onTap: () => go(const MailScreen()),
            ),
            ListTile(
              leading: const Icon(Icons.group_outlined),
              title: const Text('Utenti e condivisione'),
              subtitle: s.driveShared
                  ? Text('Archivio di ${s.driveFolderOwner ?? 'un\'altra persona'}')
                  : null,
              onTap: () => go(const SharingScreen()),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Cestino'),
              trailing: app.archive.trashedDocuments.isEmpty
                  ? null
                  : Text('${app.archive.trashedDocuments.length}'),
              onTap: () => go(const TrashScreen()),
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Impostazioni e Google Drive'),
              onTap: () => go(const SettingsScreen()),
            ),
          ],
        ),
      ),
    );
  }
}
