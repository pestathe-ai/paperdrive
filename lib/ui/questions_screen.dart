import 'package:material_ui/material_ui.dart';

import '../core/assistant.dart';
import '../core/models.dart';
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
    return Scaffold(
      appBar: AppBar(title: const Text('Domande per te')),
      body: qs.isEmpty
          ? const EmptyState(icon: Icons.check_circle_outline, text: 'Nessun dubbio: è tutto in ordine')
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
              itemCount: qs.length,
              itemBuilder: (context, i) => ReviewCard(doc: qs[i].doc, question: qs[i]),
            ),
    );
  }
}

/// Un documento da sistemare: anteprima, eventuale domanda con le scelte,
/// oppure "Va bene così".
class ReviewCard extends StatelessWidget {
  const ReviewCard({super.key, required this.doc, this.question});

  final Document doc;
  final DocQuestion? question;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final theme = Theme.of(context);
    final d = doc;
    final q = question;
    final a = app.archive;
    final excerpt = d.content.replaceAll(RegExp(r'\s+'), ' ').trim();
    final info = [a.type(d.typeId)?.name, a.correspondent(d.correspondentId)?.name, firstDateIt(d)]
        .whereType<String>()
        .join(' · ');
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
                        Text(info, style: theme.textTheme.bodySmall),
                        if (excerpt.isNotEmpty)
                          Text(
                            excerpt.length > 140 ? '${excerpt.substring(0, 140)}…' : excerpt,
                            style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            if (q != null) ...[
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
                        QuestionKind.category => a.type(o)?.name ?? o,
                        QuestionKind.folder => o.isEmpty
                            ? 'No, cartella normale'
                            : 'Sì: ${(a.storagePath(o)?.template.split('/').first ?? '')} › ${a.storagePath(o)?.name ?? ''}',
                      }),
                      onPressed: app.readOnly ? null : () => app.answerQuestion(q, o),
                    ),
                ],
              ),
            ] else
              Row(
                children: [
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.check),
                    label: const Text('Va bene così'),
                    onPressed: app.readOnly ? null : () => app.markReviewed([d]),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => DocumentScreen(docId: d.id)),
                    ),
                    child: const Text('Correggi'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
