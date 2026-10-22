import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../core/models.dart';
import '../state/app_state.dart';

/// Colori proposti per i tag.
const List<int> tagPalette = [
  0xFFC62828, 0xFFAD1457, 0xFF6A1B9A, 0xFF283593, 0xFF1565C0,
  0xFF00838F, 0xFF2E7D32, 0xFF558B2F, 0xFFF9A825, 0xFFEF6C00,
  0xFF4E342E, 0xFF546E7A,
];

Color textOn(Color bg) =>
    bg.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;

class TagChip extends StatelessWidget {
  const TagChip(this.tag, {super.key, this.small = false, this.onDeleted});

  final Tag tag;
  final bool small;
  final VoidCallback? onDeleted;

  @override
  Widget build(BuildContext context) {
    final bg = Color(tag.color);
    final fg = textOn(bg);
    if (small) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          tag.name,
          style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600),
          overflow: TextOverflow.ellipsis,
        ),
      );
    }
    return Chip(
      label: Text(tag.name, style: TextStyle(color: fg)),
      backgroundColor: bg,
      side: BorderSide.none,
      deleteIconColor: fg,
      onDeleted: onDeleted,
      visualDensity: VisualDensity.compact,
    );
  }
}

class DocThumb extends StatelessWidget {
  const DocThumb(this.doc, {super.key, this.width = 56, this.height = 76});

  final Document doc;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.read(context);
    final f = app.thumbOf(doc);
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: width,
        height: height,
        color: scheme.surfaceContainerHighest,
        child: f.existsSync()
            ? Image.file(
                f,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                key: ValueKey('${doc.id}-${doc.modified}'),
                errorBuilder: (_, _, _) => _placeholder(scheme),
              )
            : _placeholder(scheme),
      ),
    );
  }

  Widget _placeholder(ColorScheme s) =>
      Icon(Icons.description_outlined, color: s.onSurfaceVariant);
}

void showMessage(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  String? message,
  String ok = 'Conferma',
  bool danger = false,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annulla')),
        FilledButton(
          style: danger
              ? FilledButton.styleFrom(
                  backgroundColor: Theme.of(c).colorScheme.error,
                  foregroundColor: Theme.of(c).colorScheme.onError,
                )
              : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r ?? false;
}

Future<String?> askText(
  BuildContext context, {
  required String title,
  String initial = '',
  String label = 'Nome',
  bool multiline = false,
}) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        minLines: multiline ? 3 : 1,
        maxLines: multiline ? 8 : 1,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(labelText: label),
        onSubmitted: multiline ? null : (v) => Navigator.pop(c, v.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annulla')),
        FilledButton(
          onPressed: () => Navigator.pop(c, ctrl.text.trim()),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

/// Scelta multipla dei tag, con creazione rapida di un nuovo tag.
Future<Set<String>?> pickTags(BuildContext context, Set<String> selected) {
  final app = AppScope.read(context);
  final current = {...selected};
  return showModalBottomSheet<Set<String>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) {
        final tags = app.archive.activeTags;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.75),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('Tag', style: Theme.of(c).textTheme.titleLarge),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text('Nuovo'),
                        onPressed: () async {
                          final name = await askText(c, title: 'Nuovo tag');
                          if (name == null || name.isEmpty) return;
                          final t = Tag(
                            name: name,
                            algorithm: MatchAlgorithm.auto,
                            color: tagPalette[app.archive.tags.length % tagPalette.length],
                          );
                          app.saveTag(t);
                          setState(() => current.add(t.id));
                        },
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: tags.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('Nessun tag. Creane uno con "Nuovo".'),
                        )
                      : ListView(
                          shrinkWrap: true,
                          children: [
                            for (final t in tags)
                              CheckboxListTile(
                                value: current.contains(t.id),
                                onChanged: (v) => setState(() {
                                  v == true ? current.add(t.id) : current.remove(t.id);
                                }),
                                title: Text(t.name),
                                secondary: CircleAvatar(
                                  radius: 10,
                                  backgroundColor: Color(t.color),
                                ),
                              ),
                          ],
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(c, current),
                      child: const Text('Applica'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// Risultato della scelta di un'entità: [cleared] vero se si sceglie "nessuno".
class EntityChoice {
  EntityChoice(this.id);
  final String? id;
}

/// Scelta di un corrispondente o di un tipo, con creazione rapida.
Future<EntityChoice?> pickEntity(
  BuildContext context, {
  required String title,
  required List<NamedEntity> items,
  required String? selected,
  required NamedEntity Function(String name) create,
}) {
  return showModalBottomSheet<EntityChoice>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.75),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
              child: Row(
                children: [
                  Expanded(child: Text(title, style: Theme.of(c).textTheme.titleLarge)),
                  TextButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Nuovo'),
                    onPressed: () async {
                      final name = await askText(c, title: 'Nuovo: $title');
                      if (name == null || name.isEmpty || !c.mounted) return;
                      final e = create(name);
                      Navigator.pop(c, EntityChoice(e.id));
                    },
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  ListTile(
                    leading: Icon(selected == null
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked),
                    title: const Text('Nessuno'),
                    onTap: () => Navigator.pop(c, EntityChoice(null)),
                  ),
                  for (final e in items)
                    ListTile(
                      leading: Icon(selected == e.id
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked),
                      title: Text(e.name),
                      onTap: () => Navigator.pop(c, EntityChoice(e.id)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<EntityChoice?> pickCorrespondent(BuildContext context, String? selected) {
  final app = AppScope.read(context);
  return pickEntity(
    context,
    title: 'Corrispondente',
    items: app.archive.activeCorrespondents,
    selected: selected,
    create: (name) {
      final e = NamedEntity(name: name, algorithm: MatchAlgorithm.auto);
      app.saveCorrespondent(e);
      return e;
    },
  );
}

Future<EntityChoice?> pickType(BuildContext context, String? selected) {
  final app = AppScope.read(context);
  return pickEntity(
    context,
    title: 'Tipo di documento',
    items: app.archive.activeTypes,
    selected: selected,
    create: (name) {
      final e = NamedEntity(name: name, algorithm: MatchAlgorithm.auto);
      app.saveType(e);
      return e;
    },
  );
}

/// Spazio vuoto con icona e testo, per liste senza elementi.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: s.outline),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center, style: TextStyle(color: s.onSurfaceVariant)),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

/// Esiste il file? (usato per decidere se mostrare l'anteprima).
bool fileExists(File f) => f.existsSync();

/// Colori Dom Studio usati dal marchio.
const Color brandBlue = Color(0xFF1D3A8A);
const Color brandOrange = Color(0xFFF28C38);
const Color brandRed = Color(0xFFD7263D);

/// Il nome dell'app come marchio: la casa dell'icona, "D" con il punto
/// arancio come il tetto, "Paper Lab" in Sora 800.
class BrandTitle extends StatelessWidget {
  const BrandTitle({super.key, this.color = Colors.white, this.size = 22, this.logo = true});

  final Color color;
  final double size;
  final bool logo;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: 'Sora',
      fontWeight: FontWeight.w800,
      fontSize: size,
      letterSpacing: -0.5,
      color: color,
      height: 1.1,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (logo) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(size * 0.45),
            child: Image.asset('assets/logo.png', width: size * 2.1, height: size * 2.1),
          ),
          SizedBox(width: size * 0.3),
        ],
        Flexible(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: 'D', style: style),
              TextSpan(text: '.', style: style.copyWith(color: brandOrange)),
              TextSpan(text: ' Paper Lab', style: style),
            ]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
