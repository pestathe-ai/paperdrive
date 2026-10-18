import 'package:material_ui/material_ui.dart';

import '../core/models.dart';
import '../state/app_state.dart';
import 'widgets.dart';

class TrashScreen extends StatelessWidget {
  const TrashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final docs = app.archive.trashedDocuments
      ..sort((a, b) => (b.trashedAt ?? 0).compareTo(a.trashedAt ?? 0));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cestino'),
        actions: [
          if (docs.isNotEmpty)
            TextButton(
              onPressed: () async {
                final ok = await confirm(context,
                    title: 'Svuotare il cestino?',
                    message: '${docs.length} documenti verranno eliminati per sempre, anche da Google Drive.',
                    ok: 'Svuota',
                    danger: true);
                if (ok) await app.deleteForever(docs);
              },
              child: const Text('Svuota'),
            ),
        ],
      ),
      body: docs.isEmpty
          ? const EmptyState(icon: Icons.delete_outline, text: 'Il cestino è vuoto')
          : ListView(
              children: [
                for (final d in docs)
                  ListTile(
                    leading: DocThumb(d, width: 40, height: 54),
                    title: Text(d.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(d.trashedAt == null
                        ? ''
                        : 'Eliminato il ${formatDate(DateTime.fromMillisecondsSinceEpoch(d.trashedAt!))}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Ripristina',
                          icon: const Icon(Icons.restore),
                          onPressed: () => app.restore([d]),
                        ),
                        IconButton(
                          tooltip: 'Elimina per sempre',
                          icon: const Icon(Icons.delete_forever_outlined),
                          onPressed: () async {
                            final ok = await confirm(context,
                                title: 'Eliminare per sempre?', ok: 'Elimina', danger: true);
                            if (ok) await app.deleteForever([d]);
                          },
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}
