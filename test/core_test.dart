import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:paperdrive/core/archive.dart';
import 'package:paperdrive/core/dates.dart';
import 'package:paperdrive/core/matching.dart';
import 'package:paperdrive/core/models.dart';
import 'package:paperdrive/core/search.dart';
import 'package:paperdrive/core/sync_merge.dart';
import 'package:paperdrive/core/text_utils.dart';

Document doc(String title, String content, {Set<String>? tags}) =>
    Document(title: title, content: content, tagIds: tags);

void main() {
  group('testo', () {
    test('normalizza accenti e maiuscole', () {
      expect(normalize('Società È PERCHÉ'), 'societa e perche');
      expect(tokenize('Fattura n. 123/A - Società'), ['fattura', 'n', '123', 'a', 'societa']);
    });

    test('termini con virgolette', () {
      expect(splitTerms('fattura "enel energia" luce'),
          ['fattura', 'enel energia', 'luce']);
    });

    test('somiglianza approssimata tollera errori OCR', () {
      expect(partialSimilarity('Agenzia Entrate', 'xx AGENZlA ENTRATE yy'),
          greaterThanOrEqualTo(fuzzyThreshold));
      expect(partialSimilarity('Agenzia Entrate', 'tutt altro testo qui'),
          lessThan(fuzzyThreshold));
    });
  });

  group('regole', () {
    final text = 'Bolletta ENEL Energia\nPeriodo marzo 2024\nTotale 45,30 €';

    Tag rule(MatchAlgorithm a, String p, {bool ci = true}) =>
        Tag(name: 'x', algorithm: a, pattern: p, caseInsensitive: ci);

    test('una qualsiasi parola', () {
      expect(matchesRule(rule(MatchAlgorithm.any, 'gas enel'), text), isTrue);
      expect(matchesRule(rule(MatchAlgorithm.any, 'gas acqua'), text), isFalse);
      // solo parole intere
      expect(matchesRule(rule(MatchAlgorithm.any, 'ene'), text), isFalse);
    });

    test('tutte le parole', () {
      expect(matchesRule(rule(MatchAlgorithm.all, 'enel bolletta'), text), isTrue);
      expect(matchesRule(rule(MatchAlgorithm.all, 'enel gas'), text), isFalse);
    });

    test('testo esatto e maiuscole', () {
      expect(matchesRule(rule(MatchAlgorithm.literal, 'enel energia'), text), isTrue);
      expect(
          matchesRule(rule(MatchAlgorithm.literal, 'enel energia', ci: false), text),
          isFalse);
    });

    test('regex', () {
      expect(matchesRule(rule(MatchAlgorithm.regex, r'totale\s+\d+'), text), isTrue);
      expect(matchesRule(rule(MatchAlgorithm.regex, r'([a'), text), isFalse);
      expect(regexError(r'([a'), isNotNull);
    });

    test('approssimata', () {
      expect(matchesRule(rule(MatchAlgorithm.fuzzy, 'Enel Enrgia'), text), isTrue);
    });

    test('applica tag, corrispondente e tipo', () {
      final a = Archive.starter();
      final casa = Tag(name: 'Casa', algorithm: MatchAlgorithm.any, pattern: 'bolletta');
      final enel = NamedEntity(name: 'Enel', algorithm: MatchAlgorithm.literal, pattern: 'enel');
      final fattura = NamedEntity(name: 'Fattura', algorithm: MatchAlgorithm.any, pattern: 'totale');
      a.tags[casa.id] = casa;
      a.correspondents[enel.id] = enel;
      a.types[fattura.id] = fattura;
      final d = doc('scan', text);
      a.documents[d.id] = d;
      expect(applyMatches(a, d), isTrue);
      expect(d.tagIds, contains(casa.id));
      expect(d.correspondentId, enel.id);
      expect(d.typeId, fattura.id);
    });

    test('automatica impara dagli esempi', () {
      final a = Archive();
      final medico = Tag(name: 'Medico', algorithm: MatchAlgorithm.auto);
      a.tags[medico.id] = medico;
      for (final c in [
        'Referto esame sangue emocromo ospedale',
        'Ricetta medica farmaco ospedale visita',
        'Visita cardiologica referto ospedale',
      ]) {
        final d = doc('d', c, tags: {medico.id});
        a.documents[d.id] = d;
      }
      final other = doc('o', 'Contratto affitto appartamento canone mensile');
      a.documents[other.id] = other;
      final nuovo = doc('n', 'Referto visita ospedale esame');
      expect(computeMatches(a, nuovo).tagIds, contains(medico.id));
      final affitto = doc('n2', 'Canone affitto appartamento');
      expect(computeMatches(a, affitto).tagIds, isNot(contains(medico.id)));
    });
  });

  group('date', () {
    final now = DateTime(2026, 10, 18);
    test('formati numerici e testuali', () {
      expect(detectDate('Data: 05/03/2024 ore 10', now: now), DateTime(2024, 3, 5));
      expect(detectDate('emessa il 2023-12-31', now: now), DateTime(2023, 12, 31));
      expect(detectDate('Roma, 12 marzo 2024', now: now), DateTime(2024, 3, 12));
      expect(detectDate('1° gen. 2025', now: now), DateTime(2025, 1, 1));
      expect(detectDate('March 3, 2022', now: now), DateTime(2022, 3, 3));
      expect(detectDate('scad. 7.8.25', now: now), DateTime(2025, 8, 7));
    });
    test('scarta date impossibili', () {
      expect(detectDate('31/02/2024 e 99/99/9999', now: now), isNull);
      expect(detectDate('nessuna data qui', now: now), isNull);
    });
    test('prima data nell\'ordine del testo', () {
      expect(detectDate('il 3 maggio 2021 e poi 01/01/2020', now: now),
          DateTime(2021, 5, 3));
    });
    test('titolo suggerito', () {
      expect(suggestTitle('\n  12\nFATTURA ACCOMPAGNATORIA\nriga'),
          'FATTURA ACCOMPAGNATORIA');
    });
  });

  group('ricerca', () {
    late Archive a;
    late Document bolletta, referto, contratto;
    late Tag casa;
    setUp(() {
      a = Archive();
      casa = Tag(name: 'Casa');
      a.tags[casa.id] = casa;
      final enel = NamedEntity(name: 'Enel Energia');
      a.correspondents[enel.id] = enel;
      bolletta = doc('Bolletta luce', 'Enel energia periodo marzo', tags: {casa.id})
        ..correspondentId = enel.id
        ..created = DateTime(2024, 3, 1)
        ..asn = 3;
      referto = doc('Referto', 'Ospedale: esame del sangue, è tutto nella norma')
        ..created = DateTime(2023, 5, 1);
      contratto = doc('Contratto affitto', 'Canone mensile bozza', tags: {casa.id})
        ..created = DateTime(2022, 1, 1);
      for (final d in [bolletta, referto, contratto]) {
        a.documents[d.id] = d;
      }
    });

    List<Document> s(String q) => runFilter(a, DocumentFilter(query: q), SearchIndex());

    test('parole, prefissi e accenti', () {
      expect(s('ospedale'), [referto]);
      expect(s('bollet'), [bolletta]);
      expect(s('E TUTTO'), [referto]);
    });
    test('frasi, esclusioni e campi', () {
      expect(s('"esame del sangue"'), [referto]);
      expect(s('"sangue esame"'), isEmpty);
      expect(s('tag:casa -bozza'), [bolletta]);
      expect(s('da:enel'), [bolletta]);
      expect(s('asn:3'), [bolletta]);
      expect(s('anno:2022'), [contratto]);
    });
    test('filtri e ordinamento', () {
      final f = DocumentFilter(tagIds: {casa.id}, sort: SortField.created);
      expect(runFilter(a, f, SearchIndex()), [bolletta, contratto]);
      f.descending = false;
      expect(runFilter(a, f, SearchIndex()), [contratto, bolletta]);
      referto.inTrash = true;
      expect(runFilter(a, DocumentFilter(), SearchIndex()), isNot(contains(referto)));
    });
    test('estratto', () {
      expect(snippet(referto, 'sangue'), contains('sangue'));
    });
  });

  group('archivio e sincronizzazione', () {
    test('JSON andata e ritorno', () {
      final a = Archive.starter();
      final f = CustomField(name: 'Importo', type: CustomFieldType.money);
      a.fields[f.id] = f;
      final d = doc('Titolo', 'contenuto')
        ..notes.add(Note(text: 'nota'))
        ..customFields[f.id] = '12,50'
        ..asn = 7;
      a.documents[d.id] = d;
      final v = SavedView(name: 'Casa', filter: DocumentFilter(query: 'x', inboxOnly: true));
      a.views[v.id] = v;
      final back = Archive.fromJson(
          jsonDecode(jsonEncode(a.toJson())) as Map<String, dynamic>);
      final d2 = back.documents[d.id]!;
      expect(d2.title, 'Titolo');
      expect(d2.notes.single.text, 'nota');
      expect(d2.customFields[f.id], '12,50');
      expect(d2.asn, 7);
      expect(DateTime(d2.created.year, d2.created.month, d2.created.day),
          DateTime(d.created.year, d.created.month, d.created.day));
      expect(back.views[v.id]!.filter.inboxOnly, isTrue);
      expect(back.inboxTags.length, 1);
      expect(back.nextAsn(), 8);
    });

    test('vince la modifica più recente, le cancellazioni si propagano', () {
      final local = Archive();
      final remote = Archive();
      final d1 = doc('vecchio', '')..modified = 100;
      final d1r = Document.fromJson(d1.toJson())
        ..title = 'nuovo'
        ..modified = 200;
      local.documents[d1.id] = d1;
      remote.documents[d1.id] = d1r;
      final onlyLocal = doc('solo telefono', '');
      local.documents[onlyLocal.id] = onlyLocal;
      final gone = doc('eliminato', '')..modified = 100;
      local.documents[gone.id] = gone;
      final goneR = Document.fromJson(gone.toJson());
      remote.purge(goneR);
      remote.documents[goneR.id] = goneR;

      final (m, report) = mergeArchives(local, remote);
      expect(m.documents[d1.id]!.title, 'nuovo');
      expect(m.documents[onlyLocal.id], isNotNull);
      expect(m.documents[gone.id]!.deleted, isTrue);
      expect(report.remoteChanged, isTrue);
      expect(report.localChanged, isTrue);

      final plan = planFiles(m,
          localFiles: {onlyLocal.fileName, gone.fileName},
          remoteFiles: {d1.fileName, gone.fileName});
      expect(plan.upload.map((d) => d.id), [onlyLocal.id]);
      expect(plan.download.map((d) => d.id), [d1.id]);
      expect(plan.deleteRemote, [gone.fileName]);
      expect(plan.deleteLocal, [gone.fileName]);
    });
  });
}
