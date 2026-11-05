import 'package:material_ui/material_ui.dart';

import '../core/drive_learning.dart' show folderOf;
import '../core/models.dart';
import '../core/organize.dart' show drivePath;
import '../core/text_utils.dart' show folderKey;
import '../state/app_state.dart';
import 'widgets.dart';

/// Sceglie la cartella su Drive di un documento sfogliando quelle che
/// esistono già (le cartelle dei tuoi documenti), come nell'archivio. Si
/// può anche creare una sottocartella nuova. Restituisce il percorso
/// ("Casa/Via Alessandrina/2026") o null.
Future<String?> pickFolder(BuildContext context, AppState app, {Document? doc}) => Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => FolderPicker(app: app, doc: doc)),
    );

/// Sposta il documento nella cartella scelta (l'app impara la scelta).
Future<void> moveToPickedFolder(BuildContext context, AppState app, Document d) async {
  final path = await pickFolder(context, app, doc: d);
  if (path == null) return;
  final changes = app.setFolder(d, path);
  if (context.mounted) {
    showMessage(context, changes.isEmpty ? 'Nessun cambiamento' : 'Fatto: i documenti simili andranno qui da soli');
  }
}

class FolderPicker extends StatefulWidget {
  const FolderPicker({super.key, required this.app, this.doc});

  final AppState app;
  final Document? doc;

  @override
  State<FolderPicker> createState() => _FolderPickerState();
}

class _FolderPickerState extends State<FolderPicker> {
  List<String> path = const [];
  final List<List<String>> _forward = [];

  /// Cartelle create qui ma ancora vuote (nessun documento dentro).
  final Set<String> _created = {};

  @override
  void initState() {
    super.initState();
    // Si parte dalla cartella in cui sta il documento.
    final d = widget.doc;
    if (d != null) {
      final now = folderOf(widget.app.archive, d);
      if (now.isNotEmpty) path = now.split('/');
    }
  }

  void _open(List<String> p) => setState(() {
        _forward.clear();
        path = p;
      });

  void _up() {
    if (path.isEmpty) return;
    setState(() {
      _forward.add(path);
      path = path.sublist(0, path.length - 1);
    });
  }

  Future<void> _newFolder() async {
    final name = await askText(context, title: 'Nuova cartella', label: 'Nome, es. Box');
    final n = name?.trim().replaceAll('/', '-');
    if (n == null || n.isEmpty) return;
    setState(() {
      _created.add([...path, n].join('/'));
      _forward.clear();
      path = [...path, n];
    });
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.app.archive;
    final theme = Theme.of(context);
    // Le sottocartelle che esistono qui: quelle dei documenti, più quelle
    // appena create.
    // Cartelle uguali a parte maiuscole/accenti sono la stessa (come su
    // Drive): si mostra il nome più usato.
    final sub = <String, int>{};
    final spellings = <String, Map<String, int>>{};
    void add(String name, int n) {
      final k = folderKey(name);
      sub.update(k, (x) => x + n, ifAbsent: () => n);
      spellings.putIfAbsent(k, () => {}).update(name, (x) => x + n + 1, ifAbsent: () => n + 1);
    }

    bool under(List<String> f) {
      for (var i = 0; i < path.length; i++) {
        if (folderKey(f[i]) != folderKey(path[i])) return false;
      }
      return true;
    }

    for (final d in a.activeDocuments) {
      final (f, _) = drivePath(a, d);
      if (f.length > path.length && under(f)) add(f[path.length], 1);
    }
    for (final c in _created) {
      final f = c.split('/');
      if (f.length == path.length + 1 && under(f)) add(f.last, 0);
    }
    String label(String k) => spellings[k]!.entries.reduce((x, y) => x.value >= y.value ? x : y).key;
    final names = sub.keys.toList();
    final dated = RegExp(r'^\d');
    names.sort((x, y) {
      if (dated.hasMatch(x) && dated.hasMatch(y)) return y.compareTo(x);
      return x.toLowerCase().compareTo(y.toLowerCase());
    });
    return PopScope(
      canPop: path.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _up();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Scegli la cartella'),
          leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
        ),
        body: GestureDetector(
          // Scorri verso destra: cartella superiore; verso sinistra: avanti.
          onHorizontalDragEnd: (e) {
            final v = e.primaryVelocity ?? 0;
            if (v > 300) {
              _up();
            } else if (v < -300 && _forward.isNotEmpty) {
              setState(() => path = _forward.removeLast());
            }
          },
          child: ListView(
            padding: const EdgeInsets.only(bottom: 120),
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Row(
                  children: [
                    ActionChip(
                      avatar: const Icon(Icons.home_outlined, size: 18),
                      label: const Text('Archivio'),
                      onPressed: path.isEmpty ? null : () => _open(const []),
                    ),
                    for (var i = 0; i < path.length; i++) ...[
                      const Icon(Icons.chevron_right, size: 18),
                      ActionChip(
                        label: Text(path[i]),
                        onPressed: i == path.length - 1 ? null : () => _open(path.sublist(0, i + 1)),
                      ),
                    ],
                  ],
                ),
              ),
              if (names.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    path.isEmpty ? 'Ancora nessuna cartella' : 'Nessuna sottocartella: puoi mettere il documento qui o crearne una',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              for (final n in names)
                ListTile(
                  leading: Icon(dated.hasMatch(n) ? Icons.folder_outlined : Icons.folder,
                      color: dated.hasMatch(n) ? null : brandBlue),
                  title: Text(label(n), style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: sub[n] == 0 ? const Text('nuova') : null,
                  trailing: sub[n] == 0 ? null : Text('${sub[n]}', style: theme.textTheme.labelLarge),
                  onTap: () => _open([...path, label(n)]),
                ),
              ListTile(
                leading: const Icon(Icons.create_new_folder_outlined),
                title: const Text('Nuova cartella qui'),
                onTap: _newFolder,
              ),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: FilledButton.icon(
              icon: const Icon(Icons.drive_file_move_outline),
              label: Text(path.isEmpty ? 'Scegli una cartella' : 'Metti in ${path.last}'),
              onPressed: path.isEmpty ? null : () => Navigator.pop(context, path.join('/')),
            ),
          ),
        ),
      ),
    );
  }
}
