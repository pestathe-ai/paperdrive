import 'package:material_ui/material_ui.dart';

import '../core/assistant.dart';
import '../core/models.dart';
import '../core/people.dart';
import '../state/app_state.dart';
import 'document_screen.dart';
import 'questions_screen.dart';
import 'widgets.dart';

/// "Chiedi": domande in italiano sull'archivio, con l'AI sul telefono.
class AskScreen extends StatefulWidget {
  const AskScreen({super.key});

  @override
  State<AskScreen> createState() => _AskScreenState();
}

class _AskScreenState extends State<AskScreen> {
  final ctrl = TextEditingController();
  late final AppState app = AppScope.read(context);
  bool thinking = false;
  String? asked;
  String? answer;
  String? understood;
  List<AskHit> hits = const [];

  @override
  void dispose() {
    ctrl.dispose();
    // Il modello occupa memoria: si libera uscendo.
    app.ai.release();
    super.dispose();
  }

  Future<void> _ask(String question) async {
    final q = question.trim();
    if (q.isEmpty || thinking) return;
    FocusScope.of(context).unfocus();
    setState(() {
      thinking = true;
      asked = q;
      answer = null;
    });
    final (query, found, text) = await app.ask(q);
    if (!mounted) return;
    setState(() {
      thinking = false;
      hits = found;
      answer = text;
      understood = query.describe(app.archive);
    });
  }

  List<String> _examples() {
    final people = app.archive.config.people;
    final who = people.isEmpty ? '' : ' di ${people.first.name}';
    return [
      'Ultima bolletta della luce',
      'Referti$who',
      'Quanto ho speso dal dentista nel ${DateTime.now().year - 1}?',
      'Ricette di quest\'anno',
      'Quante buste paga ci sono?',
    ];
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final theme = Theme.of(context);
    final hasAi = app.settings.aiModel != null;
    final questions = app.questions;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: brandBlue,
        foregroundColor: Colors.white,
        title: const Text('Chiedi', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                if (asked == null) ...[
                  Text('Chiedi qualcosa sul tuo archivio', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text(
                    hasAi
                        ? 'Scrivi come parleresti, oppure detta col microfono della tastiera. '
                            'L\'AI sul telefono capisce la domanda e cerca tra i tuoi documenti.'
                        : 'Scrivi come parleresti, oppure detta col microfono della tastiera. '
                            'Con l\'AI sul telefono (Impostazioni) capisce anche domande più libere.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final e in _examples())
                        ActionChip(
                          avatar: const Icon(Icons.search, size: 18),
                          label: Text(e),
                          onPressed: () {
                            ctrl.text = e;
                            _ask(e);
                          },
                        ),
                    ],
                  ),
                  if (questions.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.help_outline, color: brandOrange),
                        title: Text(questions.length == 1
                            ? 'Ho un dubbio su 1 documento'
                            : 'Ho un dubbio su ${questions.length} documenti'),
                        subtitle: const Text('Rispondi con un tocco: imparo per le prossime volte'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const QuestionsScreen()),
                        ),
                      ),
                    ),
                  ],
                ] else ...[
                  Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(asked!),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (thinking)
                    Row(
                      children: [
                        const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                        const SizedBox(width: 12),
                        Text(hasAi ? 'Ci penso…' : 'Cerco…'),
                      ],
                    )
                  else if (answer != null) ...[
                    Text(answer!, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                    if (understood != null && understood!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('Ho cercato: $understood', style: theme.textTheme.bodySmall),
                      ),
                    const SizedBox(height: 8),
                    for (final (d, _) in hits.take(50)) _result(d),
                    if (hits.length > 50) Text('… e altri ${hits.length - 50}'),
                  ],
                ],
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: ctrl,
                      textInputAction: TextInputAction.search,
                      textCapitalization: TextCapitalization.sentences,
                      onSubmitted: _ask,
                      decoration: InputDecoration(
                        hintText: 'Es. referto cardiologico di Maria',
                        filled: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Chiedi',
                    onPressed: thinking ? null : () => _ask(ctrl.text),
                    icon: const Icon(Icons.arrow_upward),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _result(Document d) {
    final a = app.archive;
    final parts = [
      a.type(d.typeId)?.name,
      d.customFields[personFieldId],
      d.customFields[specialtyFieldId],
      a.correspondent(d.correspondentId)?.name,
      dateIt(d.created),
    ].whereType<String>().where((e) => e.isNotEmpty);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: DocThumb(d),
        title: Text(d.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(parts.join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => DocumentScreen(docId: d.id)),
        ),
      ),
    );
  }
}
