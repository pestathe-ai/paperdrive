import 'package:material_ui/material_ui.dart';

import '../core/models.dart';
import '../state/app_state.dart';
import 'widgets.dart';

/// Pannello filtri: tag, corrispondente, tipo, date, ordinamento.
Future<DocumentFilter?> showFilterSheet(BuildContext context, DocumentFilter initial) {
  final f = initial.copy();
  return showModalBottomSheet<DocumentFilter>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => StatefulBuilder(builder: (c, setState) {
      final app = AppScope.read(c);
      final a = app.archive;
      Future<void> pickDate(bool isFrom) async {
        final now = DateTime.now();
        final d = await showDatePicker(
          context: c,
          initialDate: (isFrom ? f.from : f.to) ?? now,
          firstDate: DateTime(1900),
          lastDate: DateTime(now.year + 1, 12, 31),
        );
        if (d == null) return;
        setState(() {
          if (isFrom) {
            f.from = d;
          } else {
            f.to = d;
          }
        });
      }

      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.85),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              Text('Filtri', style: Theme.of(c).textTheme.titleLarge),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Solo da esaminare'),
                value: f.inboxOnly,
                onChanged: (v) => setState(() => f.inboxOnly = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Solo senza tag'),
                value: f.untaggedOnly,
                onChanged: (v) => setState(() => f.untaggedOnly = v),
              ),
              if (app.settings.driveShared || app.archive.activeDocuments.any((d) => d.owner != null && d.owner != app.settings.driveAccount))
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Solo aggiunti da me'),
                  value: f.mineOnly,
                  onChanged: (v) => setState(() => f.mineOnly = v),
                ),
              const Divider(),
              Text('Tag (tutti quelli scelti)', style: Theme.of(c).textTheme.titleSmall),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final t in a.activeTags)
                    FilterChip(
                      label: Text(t.name),
                      selected: f.tagIds.contains(t.id),
                      avatar: CircleAvatar(backgroundColor: Color(t.color), radius: 6),
                      onSelected: (v) => setState(() {
                        v ? f.tagIds.add(t.id) : f.tagIds.remove(t.id);
                        f.excludedTagIds.remove(t.id);
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text('Escludi tag', style: Theme.of(c).textTheme.titleSmall),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final t in a.activeTags)
                    FilterChip(
                      label: Text(t.name),
                      selected: f.excludedTagIds.contains(t.id),
                      onSelected: (v) => setState(() {
                        v ? f.excludedTagIds.add(t.id) : f.excludedTagIds.remove(t.id);
                        f.tagIds.remove(t.id);
                      }),
                    ),
                ],
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_outline),
                title: const Text('Corrispondente'),
                subtitle: Text(a.correspondent(f.correspondentId)?.name ?? 'Tutti'),
                onTap: () async {
                  final r = await pickCorrespondent(c, f.correspondentId);
                  if (r != null) setState(() => f.correspondentId = r.id);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.category_outlined),
                title: const Text('Tipo di documento'),
                subtitle: Text(a.type(f.typeId)?.name ?? 'Tutti'),
                onTap: () async {
                  final r = await pickType(c, f.typeId);
                  if (r != null) setState(() => f.typeId = r.id);
                },
              ),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.event),
                      label: Text(f.from == null ? 'Dal…' : 'Dal ${formatDate(f.from!)}'),
                      onPressed: () => pickDate(true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.event),
                      label: Text(f.to == null ? 'Al…' : 'Al ${formatDate(f.to!)}'),
                      onPressed: () => pickDate(false),
                    ),
                  ),
                ],
              ),
              if (f.from != null || f.to != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => setState(() {
                      f.from = null;
                      f.to = null;
                    }),
                    child: const Text('Togli date'),
                  ),
                ),
              const Divider(),
              Text('Ordina per', style: Theme.of(c).textTheme.titleSmall),
              Wrap(
                spacing: 6,
                children: [
                  for (final s in SortField.values)
                    ChoiceChip(
                      label: Text(s.label),
                      selected: f.sort == s,
                      onSelected: (_) => setState(() => f.sort = s),
                    ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Dal più recente / Z→A'),
                value: f.descending,
                onChanged: (v) => setState(() => f.descending = v),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(c, DocumentFilter(query: f.query)),
                    child: const Text('Azzera'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () => Navigator.pop(c, f),
                    child: const Text('Applica'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }),
  );
}
