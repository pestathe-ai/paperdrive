import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:paperdrive/core/archive.dart';
import 'package:paperdrive/core/dates.dart';
import 'package:paperdrive/core/extract.dart';
import 'package:paperdrive/core/mail_rules.dart';
import 'package:paperdrive/core/matching.dart';
import 'package:paperdrive/core/models.dart';
import 'package:paperdrive/core/organize.dart';
import 'package:paperdrive/core/starter.dart';
import 'package:paperdrive/core/search.dart';
import 'package:paperdrive/core/sync_merge.dart';
import 'package:paperdrive/core/text_utils.dart';
import 'package:paperdrive/core/workflows.dart';

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
      final a = Archive();
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
      expect(plan.upload, [onlyLocal.fileName]);
      expect(plan.download, [d1.fileName]);
      expect(plan.deleteRemote, [gone.fileName]);
      expect(plan.deleteLocal, [gone.fileName]);
    });

    test('versione archiviata: nuova si carica, vecchia si elimina', () {
      final a = Archive();
      final d = doc('x', '')..archiveRev = 2;
      a.documents[d.id] = d;
      expect(d.fileNames, ['${d.id}.pdf', '${d.id}.archive2.pdf']);
      final plan = planFiles(a,
          localFiles: {'${d.id}.pdf', '${d.id}.archive2.pdf'},
          remoteFiles: {'${d.id}.pdf', '${d.id}.archive1.pdf', 'sconosciuto.pdf'});
      expect(plan.upload, ['${d.id}.archive2.pdf']);
      expect(plan.deleteRemote, ['${d.id}.archive1.pdf']);
      expect(plan.download, isEmpty);
      final ro = planFiles(a,
          localFiles: {'${d.id}.pdf'},
          remoteFiles: {'${d.id}.archive1.pdf'},
          canWrite: false);
      expect(ro.upload, isEmpty);
      expect(ro.deleteRemote, isEmpty);
    });

    test('proprietario e autore delle modifiche', () {
      Session.user = 'anna@example.com';
      final d = doc('x', '');
      expect(d.owner, 'anna@example.com');
      Session.user = 'marco@example.com';
      d.touch();
      expect(d.modifiedBy, 'marco@example.com');
      final back = Document.fromJson(
          jsonDecode(jsonEncode(d.toJson())) as Map<String, dynamic>);
      expect(back.owner, 'anna@example.com');
      final a = Archive()..documents[d.id] = d;
      expect(runFilter(a, DocumentFilter(mineOnly: true), SearchIndex()), isEmpty);
      Session.user = 'anna@example.com';
      expect(runFilter(a, DocumentFilter(mineOnly: true), SearchIndex()), [d]);
      Session.user = null;
    });
  });

  group('flussi di lavoro', () {
    late Archive a;
    late Tag inbox, fatture, pagato;
    late NamedEntity enel, bolletta;
    late CustomField importo;
    setUp(() {
      a = Archive();
      inbox = Tag(name: 'Inbox', isInbox: true);
      fatture = Tag(name: 'Fatture');
      pagato = Tag(name: 'Pagato');
      enel = NamedEntity(name: 'Enel');
      bolletta = NamedEntity(name: 'Bolletta');
      importo = CustomField(name: 'Importo', type: CustomFieldType.money);
      for (final t in [inbox, fatture, pagato]) {
        a.tags[t.id] = t;
      }
      a.correspondents[enel.id] = enel;
      a.types[bolletta.id] = bolletta;
      a.fields[importo.id] = importo;
    });

    test('glob', () {
      expect(globToRegExp('*fattura*.pdf').hasMatch('Fattura_marzo.PDF'), isTrue);
      expect(globToRegExp('scan_??.pdf').hasMatch('scan_01.pdf'), isTrue);
      expect(globToRegExp('scan_??.pdf').hasMatch('scan_1.pdf'), isFalse);
    });

    test('condizioni e azioni', () {
      final w = Workflow(
        name: 'Bollette Enel',
        sources: {DocSource.mail},
        filenamePattern: '*.pdf',
        algorithm: MatchAlgorithm.literal,
        pattern: 'enel energia',
        hasNotTags: {pagato.id},
        titleTemplate: '{correspondent} - {document_type} {created_year}-{created_month} {campo:importo}',
        addTags: {fatture.id},
        setCorrespondent: enel.id,
        setType: bolletta.id,
        setFields: {importo.id: '0'},
        assignAsn: true,
        markReviewed: true,
        addNote: 'Importata in automatico',
      );
      a.workflows[w.id] = w;
      final d = Document(
        title: 'x',
        content: 'Enel Energia S.p.A. bolletta',
        originalName: 'bolletta.pdf',
        created: DateTime(2024, 3, 5),
        tagIds: {inbox.id},
        source: DocSource.mail,
      );
      a.documents[d.id] = d;

      expect(applyWorkflows(a, d, WorkflowTrigger.added, source: DocSource.scan), isEmpty);
      expect(applyWorkflows(a, d, WorkflowTrigger.updated), isEmpty);
      expect(applyWorkflows(a, d, WorkflowTrigger.added, source: DocSource.mail),
          ['Bollette Enel']);
      expect(d.title, 'Enel - Bolletta 2024-03 0');
      expect(d.tagIds, {fatture.id});
      expect(d.correspondentId, enel.id);
      expect(d.typeId, bolletta.id);
      expect(d.asn, 1);
      expect(d.notes.single.text, 'Importata in automatico');

      // Con il tag "Pagato" la condizione non vale più.
      d.tagIds.add(pagato.id);
      expect(workflowMatches(w, d, WorkflowTrigger.added, source: DocSource.mail), isFalse);
    });

    test('titolo senza valori vuoti appesi', () {
      final d = Document(title: 'Vecchio', originalName: 'scan 12.pdf', created: DateTime(2025, 1, 2));
      expect(renderTitle('{correspondent} - {original_filename}', a, d), 'scan 12');
      expect(renderTitle('{created} {title}', a, d), '2025-01-02 Vecchio');
    });

    test('ordine e JSON', () {
      final w1 = Workflow(name: 'B', order: 2, addTags: {pagato.id});
      final w2 = Workflow(name: 'A', order: 1, removeAllTags: true, triggers: {WorkflowTrigger.updated});
      a.workflows[w1.id] = w1;
      a.workflows[w2.id] = w2;
      expect(a.activeWorkflows.map((w) => w.name), ['A', 'B']);
      final back = Archive.fromJson(
          jsonDecode(jsonEncode(a.toJson())) as Map<String, dynamic>);
      final w2b = back.workflows[w2.id]!;
      expect(w2b.triggers, {WorkflowTrigger.updated});
      expect(w2b.removeAllTags, isTrue);
      expect(back.workflows[w1.id]!.addTags, {pagato.id});
    });
  });

  group('email', () {
    final rule = MailRule(
      name: 'Fatture',
      accountId: 'a',
      fromFilter: 'enel',
      subjectFilter: 'bolletta',
      attachmentFilter: '*.pdf',
      maxAgeDays: 30,
      onlyUnread: true,
    );

    test('filtri del messaggio', () {
      final ok = MailInfo(from: 'noreply@enel.it', fromName: 'Enel Energia', subject: 'La tua Bolletta di marzo');
      final no = MailInfo(from: 'amico@gmail.com', subject: 'Bolletta?');
      expect(mailMatches(rule, ok), isTrue);
      expect(mailMatches(rule, no), isFalse);
    });

    test('allegati', () {
      expect(attachmentMatches(rule, 'Fattura.PDF'), isTrue);
      expect(attachmentMatches(rule, 'logo.png'), isFalse);
      expect(attachmentMatches(MailRule(name: 'x', accountId: 'a'), 'foto.jpg'), isTrue);
      expect(attachmentMatches(MailRule(name: 'x', accountId: 'a'), 'firma.p7s'), isFalse);
    });

    test('criterio IMAP e mittente', () {
      expect(imapCriteria(rule, DateTime(2026, 10, 18)), 'SINCE 18-Sep-2026 UNSEEN');
      expect(senderName(MailInfo(from: 'info@poste.it', subject: '')), 'Poste');
      expect(senderName(MailInfo(from: 'x@y.it', fromName: '"Mario Rossi"', subject: '')), 'Mario Rossi');
    });

    test('configurazione JSON', () {
      final c = MailConfig();
      final acc = MailAccount(name: 'Gmail', email: 'a@gmail.com', host: 'imap.gmail.com', username: 'a@gmail.com', password: 'pw');
      c.accounts.add(acc);
      c.rules.add(rule);
      c.processed[rule.id] = {'1:5'};
      final back = MailConfig.fromJson(jsonDecode(jsonEncode(c.toJson())) as Map<String, dynamic>);
      expect(back.account(acc.id)!.host, 'imap.gmail.com');
      expect(back.rules.single.after, MailAfter.markRead);
      expect(back.processed[rule.id], {'1:5'});
    });
  });

  group('organizzazione automatica', () {
    late Archive a;
    setUp(() => a = Archive.starter());

    String? typeOf(String text) {
      final d = Document(title: 'x', content: text);
      return a.type(computeMatches(a, d).typeId)?.name;
    }

    test('categorie predefinite: vince la più pertinente', () {
      expect(typeOf('Bolletta luce Enel Energia, consumi fatturati 120 kWh, POD IT001E'), 'Bolletta');
      expect(typeOf('FATTURA n. 12 Partita IVA 0123 Imponibile 100 Aliquota IVA 22%'), 'Fattura');
      expect(typeOf('Referto: esame del sangue. Azienda Sanitaria Locale'), 'Sanità');
      expect(typeOf('Modello F24 - Agenzia delle Entrate - codice tributo 3918'), 'Tasse');
      expect(typeOf('Ciao, ci vediamo domani'), isNull);
    });

    test('nessun doppione tra telefoni diversi', () {
      final (m, _) = mergeArchives(Archive.starter(), Archive.starter());
      expect(m.activeTypes.length, starterTypes.length);
      expect(m.inboxTags.length, 1);
      expect(addStarterEntities(m), 0);
    });

    test('titolo e percorso su Drive', () {
      final enel = NamedEntity(name: 'Enel');
      a.correspondents[enel.id] = enel;
      final d = Document(
        title: 'scan',
        created: DateTime(2024, 3, 5),
        typeId: 'st-bolletta',
        correspondentId: enel.id,
      );
      d.title = autoTitle(a, d)!;
      expect(d.title, 'Bolletta - Enel');
      expect(drivePath(a, d).$1, ['Bolletta', '2024']);
      expect(drivePath(a, d).$2, '2024-03-05 Bolletta - Enel');
      expect(driveFileName(a, d, archived: true), '2024-03-05 Bolletta - Enel (PDF-A).pdf');

      final x = Document(title: 'A/B: prova?', created: DateTime(2023, 1, 9));
      expect(autoTitle(a, x), isNull);
      expect(drivePath(a, x).$1, ['Senza categoria', '2023']);
      expect(drivePath(a, x).$2, '2023-01-09 A-B prova');
      x.inTrash = true;
      expect(drivePath(a, x).$1, ['Cestino', 'Senza categoria', '2023']);

      final p = StoragePath(name: 'Per mittente', template: '{correspondent}/{created_year}/{title}');
      a.storagePaths[p.id] = p;
      d.storagePathId = p.id;
      expect(drivePath(a, d).$1, ['Enel', '2024']);
      expect(drivePath(a, d).$2, 'Bolletta - Enel');
    });

    test('cronologia', () {
      final t = Tag(name: 'Casa');
      a.tags[t.id] = t;
      final d = Document(title: 'Vecchio', created: DateTime(2024, 1, 1));
      final before = d.toJson();
      d
        ..title = 'Nuovo'
        ..typeId = 'st-fattura'
        ..tagIds.add(t.id);
      final ch = describeChanges(a, before, d);
      expect(ch, contains('Titolo: "Vecchio" → "Nuovo"'));
      expect(ch, contains('Tipo: — → Fattura'));
      expect(ch, contains('Tag aggiunti: Casa'));
      expect(logChanges(a, before, d, via: 'Flusso X'), isTrue);
      expect(d.history.single.text, startsWith('Flusso X: Titolo'));
      expect(logChanges(a, d.toJson(), d), isFalse);
      final back = Document.fromJson(jsonDecode(jsonEncode(d.toJson())) as Map<String, dynamic>);
      expect(back.history.single.text, d.history.single.text);
    });

    test('documenti simili', () {
      final d1 = Document(title: 'a', content: 'referto ospedale esame sangue emocromo');
      final d2 = Document(title: 'b', content: 'referto ospedale visita esame');
      final d3 = Document(title: 'c', content: 'contratto affitto appartamento canone');
      for (final d in [d1, d2, d3]) {
        a.documents[d.id] = d;
      }
      final sim = similarDocuments(a, d1);
      expect(sim.first.$1, d2);
      expect(sim.map((e) => e.$1), isNot(contains(d3)));
    });

    test('codici a barre: divisione e ASN', () {
      expect(asnFromBarcode('ASN-00123', 'ASN'), 123);
      expect(asnFromBarcode('XYZ1', 'ASN'), isNull);
      final parts = planBarcodeSplit(
        [[], ['ASN00042'], ['PATCHT'], [], ['PATCH T']],
        split: true,
        separator: 'PATCHT',
        readAsn: true,
        asnPrefix: 'ASN',
      );
      expect(parts.map((p) => p.pages), [[0, 1], [3]]);
      expect(parts.map((p) => p.asn), [42, null]);
      final noSplit = planBarcodeSplit([[], ['PATCHT']],
          split: false, separator: 'PATCHT', readAsn: false, asnPrefix: 'ASN');
      expect(noSplit.single.pages, [0, 1]);
    });
  });

  group('lettura specifica e nomi', () {
    const bonifico = 'Intesa Sanpaolo\nEsito bonifico SEPA\nOrdinante: Domenico Venturino\n'
        'Beneficiario: MARIO ROSSI\nIBAN IT60X0542811101000000123456\nImporto: EUR 1.250,00\n'
        'Causale: affitto ottobre\nData esecuzione 15/10/2026';
    const visura = 'Agenzia delle Entrate\nDirezione Provinciale di Milano\nUfficio Provinciale - Territorio\n'
        'Servizi Catastali\nVisura per immobile\nComune di MILANO (Codice: F205)\nFoglio 12 Particella 345\n'
        'Rendita Euro 812,34';

    test('cosa è, chi lo emette, dati chiave', () {
      final f = extractFacts(bonifico);
      expect(f.kind, 'Bonifico');
      expect(f.issuer, 'Intesa Sanpaolo');
      expect(f.amount, '1.250,00 €');
      expect(f.beneficiary, 'Mario Rossi');
      expect(f.details, 'a Mario Rossi');
      final v = extractFacts(visura);
      expect(v.kind, 'Visura catastale');
      expect(v.issuer, 'Agenzia delle Entrate');
      expect(v.municipality, 'Milano');
      expect(v.details, 'Comune di Milano');
      expect(v.amountUseful, isFalse);
      expect(detectKind('ESTRATTO CONTO al 30/09 ... bonifico a favore di X'), 'Estratto conto');
      expect(detectNumber('FATTURA N. 2024/123 del 3 marzo'), '2024/123');
      expect(detectAmount('Totale da pagare 89.90'), '89,90 €');
    });

    test('nomi di file generici o descrittivi', () {
      for (final g in [
        'IMG_20241015_123456.jpg',
        'scan001.pdf',
        'Documento (3).pdf',
        'WhatsApp Image 2024-10-15 at 12.30.45.jpeg',
        'Ricevuta_123456789.pdf',
        'Contratto.pdf',
        'download (1).pdf',
        'Scansione 18-10-2026 12.30',
      ]) {
        expect(meaningfulFileName(g), isNull, reason: g);
      }
      expect(meaningfulFileName('visura_catastale_casa_via_Roma.pdf'), 'Visura catastale casa via Roma');
      expect(meaningfulFileName('Contratto affitto-Milano.pdf'), 'Contratto affitto - Milano');
    });

    test('titolo automatico completo', () {
      final a = Archive.starter();
      final intesa = NamedEntity(name: 'Intesa Sanpaolo');
      a.correspondents[intesa.id] = intesa;
      final d = Document(title: 'x', originalName: 'Ricevuta_123.pdf', content: bonifico)
        ..correspondentId = intesa.id;
      applyMatches(a, d);
      expect(a.type(d.typeId)?.name, 'Banca');
      expect(autoTitle(a, d), 'Bonifico a Mario Rossi 1.250,00 € - Intesa Sanpaolo');

      final ade = NamedEntity(name: 'Agenzia delle Entrate');
      a.correspondents[ade.id] = ade;
      final v = Document(title: 'x', originalName: 'documento.pdf', content: visura)..correspondentId = ade.id;
      expect(autoTitle(a, v), 'Visura catastale Comune di Milano - Agenzia delle Entrate');
      final named = Document(title: 'x', originalName: 'Visura catastale casa via Roma.pdf', content: visura);
      expect(autoTitle(a, named), 'Visura catastale casa via Roma');
      a.config.keepFileName = false;
      expect(autoTitle(a, named), 'Visura catastale Comune di Milano');
    });

    test('vecchio modello del titolo aggiornato', () {
      final c = ArchiveConfig.fromJson({'title': ArchiveConfig.oldTitleTemplate});
      expect(c.titleTemplate, ArchiveConfig.defaultTitleTemplate);
      final custom = ArchiveConfig.fromJson({'title': '{title} {asn}'});
      expect(custom.titleTemplate, '{title} {asn}');
    });
  });
}
