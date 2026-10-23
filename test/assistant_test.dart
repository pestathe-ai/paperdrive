import 'package:flutter_test/flutter_test.dart';
import 'package:paperdrive/core/archive.dart';
import 'package:paperdrive/core/assistant.dart';
import 'package:paperdrive/core/models.dart';
import 'package:paperdrive/core/people.dart';
import 'package:paperdrive/core/search.dart';

void main() {
  final now = DateTime(2026, 10, 23);

  Archive archive() {
    final a = Archive.starter();
    a.config.people.addAll([
      Person(name: 'Maria', aliases: ['Maria Rossi']),
      Person(name: 'Luca'),
    ]);
    ensurePeopleEntities(a);
    a.correspondents['enel'] = NamedEntity(id: 'enel', name: 'Enel Energia');
    Document doc(String title, String typeId, DateTime created, String content,
        {String? person, String? spec, String? kind, String? corr, bool inbox = false}) {
      final d = Document(title: title, typeId: typeId, created: created, content: content, correspondentId: corr);
      if (person != null) d.customFields[personFieldId] = person;
      if (spec != null) d.customFields[specialtyFieldId] = spec;
      if (kind != null) d.customFields[healthKindFieldId] = kind;
      a.documents[d.id] = d;
      return d;
    }

    doc('Bolletta luce marzo', 'st-bolletta', DateTime(2026, 3, 5), 'Bolletta luce Totale da pagare 84,20 euro', corr: 'enel');
    doc('Bolletta luce agosto', 'st-bolletta', DateTime(2026, 8, 5), 'Bolletta luce Totale da pagare 60,00 euro', corr: 'enel');
    doc('Bolletta gas agosto', 'st-bolletta', DateTime(2026, 8, 9), 'Bolletta gas metano Totale da pagare 20,00 euro');
    doc('Ecocardiogramma', healthTypeId, DateTime(2026, 3, 12), 'Referto ecocardiogramma',
        person: 'Maria', spec: 'Cardiologia', kind: 'Referti');
    doc('Fattura dentista', healthTypeId, DateTime(2025, 5, 2), 'Studio dentistico fattura Totale 120,00 euro',
        person: 'Luca', spec: 'Dentista', kind: 'Altro');
    doc('Igiene dentale', healthTypeId, DateTime(2025, 11, 2), 'Studio dentistico igiene Totale 80,00 euro',
        person: 'Maria', spec: 'Dentista', kind: 'Altro');
    return a;
  }

  test('ultima bolletta della luce', () {
    final a = archive();
    final q = parseQuestion(a, 'Trovami l\'ultima bolletta della luce', now: now);
    expect(q.intent, AskIntent.latest);
    expect(q.typeId, 'st-bolletta');
    expect(q.words, ['luce']);
    final hits = runAsk(a, q, SearchIndex());
    expect(hits.first.$1.title, 'Bolletta luce agosto');
    expect(hits.length, 2);
  });

  test('referto cardiologico di Maria', () {
    final a = archive();
    final q = parseQuestion(a, 'trovami il referto cardiologico di Maria', now: now);
    expect(q.person, 'Maria');
    expect(q.specialty, 'Cardiologia');
    expect(q.healthKind, 'Referti');
    expect(q.words, isEmpty);
    expect(runAsk(a, q, SearchIndex()).single.$1.title, 'Ecocardiogramma');
  });

  test('quanto ho speso dal dentista nel 2025', () {
    final a = archive();
    final q = parseQuestion(a, 'Quanto ho speso dal dentista nel 2025?', now: now);
    expect(q.intent, AskIntent.total);
    expect(q.year, 2025);
    expect(q.specialty, 'Dentista');
    final hits = runAsk(a, q, SearchIndex());
    expect(hits.length, 2);
    expect(answerText(a, q, hits), contains('200,00 €'));
  });

  test('mittente e mese', () {
    final a = archive();
    final q = parseQuestion(a, 'bollette Enel di agosto', now: now);
    expect(q.correspondentId, 'enel');
    expect(q.from, DateTime(2026, 8));
    expect(runAsk(a, q, SearchIndex()).single.$1.title, 'Bolletta luce agosto');
  });

  test('risposta dell\'AI completa la domanda', () {
    final a = archive();
    final base = parseQuestion(a, 'spese mediche di Luca', now: now);
    final q = mergeAskResponse(a, base, '{"intento": "totale", "categoria": "Sanità", "anno": 2025}');
    expect(q.intent, AskIntent.total);
    expect(q.typeId, healthTypeId);
    expect(q.person, 'Luca');
    expect(answerText(a, q, runAsk(a, q, SearchIndex())), contains('120,00 €'));
  });

  test('domande quando non è sicura', () {
    final a = archive();
    final inbox = a.inboxTags.first.id;
    final senza = Document(title: 'scan001', content: 'testo')..tagIds.add(inbox);
    final referto = Document(title: 'Referto', typeId: healthTypeId, content: 'referto')..tagIds.add(inbox);
    final luce = Document(title: 'Luce', typeId: 'st-bolletta', content: 'luce')..tagIds.add(inbox);
    for (final d in [senza, referto, luce]) {
      a.documents[d.id] = d;
    }
    final qs = openQuestions(a);
    expect(qs.map((q) => (q.doc.title, q.kind)).toSet(),
        {('scan001', QuestionKind.category), ('Referto', QuestionKind.person)});
  });

  test('importi', () {
    expect(euro(1234.5), '1.234,50 €');
  });
}
