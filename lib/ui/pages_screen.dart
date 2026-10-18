import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart' show PdfDocument;

import '../core/models.dart';
import '../state/app_state.dart';
import 'widgets.dart';

class _PageItem {
  _PageItem(this.index, this.image);
  final int index;
  final String? image;
  int quarterTurns = 0;

  /// Solo per la divisione: da questa pagina inizia una nuova parte.
  bool startsPart = false;
}

/// Modifica delle pagine: ruota, elimina, riordina. Oppure dividi il
/// documento in più parti.
class PagesScreen extends StatefulWidget {
  const PagesScreen({super.key, required this.doc, this.split = false});

  final Document doc;
  final bool split;

  @override
  State<PagesScreen> createState() => _PagesScreenState();
}

class _PagesScreenState extends State<PagesScreen> {
  List<_PageItem>? pages;
  String? error;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final app = AppScope.read(context);
    try {
      final f = await app.ensureFile(widget.doc);
      if (f == null) throw Exception('File non disponibile');
      final d = await PdfDocument.openFile(f.path);
      final list = <_PageItem>[];
      try {
        for (var i = 0; i < d.pages.length; i++) {
          String? img;
          try {
            img = await app.ingestor.renderPage(d.pages[i], width: 360);
          } catch (_) {}
          list.add(_PageItem(i, img));
          if (mounted) setState(() => pages = [...list]);
        }
      } finally {
        await d.dispose();
      }
      if (widget.split && list.length > 1) list[1].startsPart = true;
      if (mounted) setState(() => pages = list);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> _save(AppState app) async {
    final list = pages!;
    setState(() => saving = true);
    try {
      if (widget.split) {
        final groups = <List<int>>[];
        for (final p in list) {
          if (groups.isEmpty || p.startsPart) groups.add([]);
          groups.last.add(p.index);
        }
        if (groups.length < 2) {
          showMessage(context, 'Segna almeno un punto in cui dividere');
          setState(() => saving = false);
          return;
        }
        final trash = await confirm(context,
            title: 'Creare ${groups.length} documenti?',
            message: 'Vuoi spostare l\'originale nel cestino?',
            ok: 'Sì, sposta nel cestino');
        final n = await app.splitDocument(widget.doc, groups, trashOriginal: trash);
        if (!mounted) return;
        showMessage(context, 'Creati $n documenti');
        Navigator.pop(context);
        if (trash) Navigator.pop(context);
      } else {
        await app.editPages(widget.doc, [for (final p in list) (p.index, p.quarterTurns)]);
        if (!mounted) return;
        showMessage(context, 'Pagine salvate');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) showMessage(context, 'Errore: $e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Widget _thumb(_PageItem p) {
    final s = Theme.of(context).colorScheme;
    return RotatedBox(
      quarterTurns: p.quarterTurns,
      child: Container(
        width: 72,
        height: 96,
        color: s.surfaceContainerHighest,
        child: p.image == null
            ? const Icon(Icons.description_outlined)
            : Image.file(File(p.image!), fit: BoxFit.contain),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final list = pages;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.split ? 'Dividi documento' : 'Modifica pagine'),
        actions: [
          TextButton(
            onPressed: list == null || saving || list.isEmpty ? null : () => _save(app),
            child: Text(widget.split ? 'Dividi' : 'Salva'),
          ),
        ],
      ),
      body: Column(
        children: [
          if (saving || app.busy != null) const LinearProgressIndicator(minHeight: 2),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              widget.split
                  ? 'Tocca le forbici sulla pagina da cui deve iniziare un nuovo documento.'
                  : 'Trascina per riordinare, ruota o elimina le pagine.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(
            child: error != null
                ? EmptyState(icon: Icons.error_outline, text: error!)
                : list == null
                    ? const Center(child: CircularProgressIndicator())
                    : widget.split
                        ? ListView(
                            children: [
                              for (var i = 0; i < list.length; i++) ...[
                                if (i > 0)
                                  Center(
                                    child: IconButton(
                                      tooltip: 'Dividi qui',
                                      isSelected: list[i].startsPart,
                                      icon: const Icon(Icons.content_cut),
                                      selectedIcon: const Icon(Icons.content_cut, color: Colors.red),
                                      onPressed: () =>
                                          setState(() => list[i].startsPart = !list[i].startsPart),
                                    ),
                                  ),
                                ListTile(
                                  leading: _thumb(list[i]),
                                  title: Text('Pagina ${list[i].index + 1}'),
                                ),
                              ],
                            ],
                          )
                        : ReorderableListView(
                            onReorder: (from, to) => setState(() {
                              if (to > from) to -= 1;
                              list.insert(to, list.removeAt(from));
                            }),
                            children: [
                              for (final p in list)
                                ListTile(
                                  key: ValueKey(p.index),
                                  leading: _thumb(p),
                                  title: Text('Pagina ${p.index + 1}'),
                                  subtitle: p.quarterTurns % 4 == 0
                                      ? null
                                      : Text('Ruotata di ${(p.quarterTurns % 4) * 90}°'),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: 'Ruota',
                                        icon: const Icon(Icons.rotate_right),
                                        onPressed: () => setState(() => p.quarterTurns = (p.quarterTurns + 1) % 4),
                                      ),
                                      IconButton(
                                        tooltip: 'Elimina pagina',
                                        icon: const Icon(Icons.delete_outline),
                                        onPressed: list.length <= 1
                                            ? null
                                            : () => setState(() => list.remove(p)),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
          ),
        ],
      ),
    );
  }
}
