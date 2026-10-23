import 'package:material_ui/material_ui.dart';

import '../core/assistant.dart';
import '../state/app_state.dart';
import 'document_screen.dart';
import 'widgets.dart';

/// I dubbi dell'app: invece di sbagliare cartella, chiede. Ogni risposta
/// vale come correzione e insegna all'app.
class QuestionsScreen extends StatelessWidget {
  const QuestionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final qs = app.questions;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Domande per te')),
      body: qs.isEmpty
          ? const EmptyState(icon: Icons.check_circle_outline, text: 'Nessun dubbio: è tutto in ordine')
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
              itemCount: qs.length,
              itemBuilder: (context, i) {
                final q = qs[i];
                final d = q.doc;
                final excerpt = d.content.replaceAll(RegExp(r'\s+'), ' ').trim();
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        InkWell(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => DocumentScreen(docId: d.id)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              DocThumb(d),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(d.title, style: theme.textTheme.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                                    Text(firstDateIt(d), style: theme.textTheme.bodySmall),
                                    if (excerpt.isNotEmpty)
                                      Text(
                                        excerpt.length > 160 ? '${excerpt.substring(0, 160)}…' : excerpt,
                                        style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(q.text, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final o in q.options)
                              ActionChip(
                                label: Text(switch (q.kind) {
                                  QuestionKind.person => o.isEmpty ? 'Di tutta la casa' : o,
                                  QuestionKind.category => app.archive.type(o)?.name ?? o,
                                }),
                                onPressed: app.readOnly ? null : () => app.answerQuestion(q, o),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
