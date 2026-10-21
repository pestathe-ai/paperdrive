import 'package:flutter_test/flutter_test.dart';
import 'package:paperdrive/core/archive.dart';
import 'package:paperdrive/core/classifier.dart';
import 'package:paperdrive/core/dates.dart';
import 'package:paperdrive/core/extract.dart';
import 'package:paperdrive/core/matching.dart';
import 'package:paperdrive/core/models.dart';
import 'package:paperdrive/core/organize.dart';
import 'package:paperdrive/core/text_utils.dart';
import 'package:paperdrive/core/workflows.dart';

// Testi nel formato che PDFium (il motore PDF del telefono) restituisce
// davvero: righe con \r\n, nessun allineamento, ordine dei blocchi sparso.
// Ricavati da documenti reali, con nomi e dati personali di fantasia.
const fatturaPdfium = 'AB NOTAI\r\nStudio Notarile Associato \r\n20900 Monza (MB) - Via Roma n. 2 - Tel. 039.000000\r\n'
    'Codice Univoco ABCD12\r\nC.F. e P.IVA 01234567890 \r\n Notaio Paolo Bianchi \r\n'
    " Il presente documento è copia dell'originale della fattura elettronica trasmessa con i canali istituzionali.\r\n"
    'Pagina 1 di 1 \r\nFattura n.634 - MG del 29/09/2025\r\nGentili Signori\r\nROSSI MARIO \r\nvia Verdi, 1\r\n'
    '20099 Sesto San Giovanni (MI)\r\nCodice Fiscale RSSMRA80A01F205X\r\nOggetto: \r\n'
    'Atto di acquisto in data 29/9/2025 - rep 4321/3465\r\n Descrizione Onorari Anticipazioni\r\nescluse IVA \r\n'
    'Imposta di Registro 1.503,00\r\nTotale Compensi 1.260,49\r\nIVA 22 % su 1.260,49 277,31\r\n'
    'Totale Lordo 3.180,00 \r\nImporto Pagato 3.180,00 \r\nPAGATO il 29/09/2025 ';

const condominioPdfium = '94511010152\r\n20099 SESTO SAN GIOVANNI MI\r\nvia Po 124/126/128\r\nPO 124\r\n'
    "Iscritto all'A.N.A.C.I. al n° 915 02/0000000 02/0000001\r\nBNCLCU57E12I690Z\r\n20099 SESTO SAN GIOVANNI MI\r\n"
    'Piazza Garibaldi 19/b\r\nSTUDIO di AMM.NI IMM.RI di BIANCHI arch. Luca\r\nCod. fisc. P.I. 01234567890\r\n'
    'Telefono Fax\r\nE-mail luca@example.com Sito Professione esercitata ai sensi della legge 14/01/2013, n. 4 '
    '(G.U. n. 22 del 26/01/2013)\r\n20095 Cusano Milanino MI\r\nVia Manzoni, 89\r\nROSSI Mario\r\n'
    'Movimenti dal al\r\n01/06/2025 - 31/05/2026\r\nordinaria 2025/2026\r\nEstratto conto condomino\r\n 12\r\n'
    '01/06/2025 31/05/2026\r\nEgr. Sig.\r\nGest. Mov. Data Descrizione Dare Avere\r\n'
    ' 31 30/09/2025 RATA N. 1 ordinaria 2025/2026 260,44\r\n 1.465,70 1.205,58\r\nSaldo a suo debito 260,12\r\nTotale\r\n';

void main() {
  test('testo PDFium ripulito', () {
    final t = cleanContent('A \r\nB\rC D\r\n\r\n\r\n\r\nE');
    expect(t, 'A\nB\nC D\n\nE');
  });

  group('fattura del notaio (formato del telefono)', () {
    test('lettura', () {
      final f = extractFacts(fatturaPdfium);
      expect(f.kind, 'Fattura');
      expect(f.issuer, 'Notaio Paolo Bianchi');
      expect(f.amount, '3.180,00 €');
      expect(f.number, '634');
      expect(f.subject, 'Atto di acquisto');
      expect(detectDate(fatturaPdfium), DateTime(2025, 9, 29));
    });

    test('titolo e cartella', () {
      final a = Archive.starter();
      final d = Document(
        title: 'Stampa_Fatt._Elettr.MG_634_29_09_2025_1_1',
        originalName: 'Stampa_Fatt._Elettr.MG_634_29_09_2025_1_1.pdf',
        content: cleanContent(fatturaPdfium),
        created: DateTime(2025, 9, 29),
      );
      applyMatches(a, d);
      applyKindCategory(a, d);
      final c = NamedEntity(name: detectIssuer(d.content)!);
      a.correspondents[c.id] = c;
      d.correspondentId = c.id;
      d.title = autoTitle(a, d)!;
      expect(d.title, 'Fattura n. 634 (Atto di acquisto) 3.180,00 € - Notaio Paolo Bianchi');
      expect(drivePath(a, d).$1, ['Fattura', '2025']);
    });
  });

  group('estratto conto del condominio (formato del telefono)', () {
    test('lettura', () {
      final f = extractFacts(condominioPdfium);
      expect(f.kind, 'Estratto conto condominiale');
      expect(f.issuer, 'Arch. Luca Bianchi');
      expect(f.period, 'ordinaria 2025/2026');
      // La data della legge del 2013 va ignorata.
      expect(detectDate(condominioPdfium), DateTime(2025, 6, 1));
    });

    test('titolo e cartella', () {
      final a = Archive.starter();
      final d = Document(
        title: 'x',
        originalName: '2013-01-14_AACJebECKw4DkMemKj0QWP4qQBY2_estratto_conto_ROSSI.pdf',
        content: cleanContent(condominioPdfium),
        created: DateTime(2025, 6, 1),
      );
      applyMatches(a, d);
      applyKindCategory(a, d);
      expect(a.type(d.typeId)?.name, 'Casa');
      final c = NamedEntity(name: detectIssuer(d.content)!);
      a.correspondents[c.id] = c;
      d.correspondentId = c.id;
      expect(autoTitle(a, d), 'Estratto conto condominiale ordinaria 2025/2026 - Arch. Luca Bianchi');
      expect(drivePath(a, d).$1, ['Casa', '2025']);
    });
  });

  group('regole come Paperless (matching.py)', () {
    Tag rule(MatchAlgorithm algo, String p) => Tag(name: 'x', algorithm: algo, pattern: p);
    const text = 'Gentile cliente,\nla fattura   ENEL ENERGIA\r\ndi marzo';

    test('frasi tra virgolette con spazi qualsiasi', () {
      expect(matchesRule(rule(MatchAlgorithm.any, '"enel energia"'), cleanContent(text)), isTrue);
      expect(matchesRule(rule(MatchAlgorithm.all, 'fattura "enel energia" marzo'), cleanContent(text)), isTrue);
      expect(matchesRule(rule(MatchAlgorithm.all, 'fattura aprile'), cleanContent(text)), isFalse);
    });

    test('parole intere anche con lettere accentate', () {
      expect(matchesRule(rule(MatchAlgorithm.any, 'citta'), 'Comune della città di Roma'), isTrue);
      expect(matchesRule(rule(MatchAlgorithm.any, 'citt'), 'Comune della città di Roma'), isFalse);
    });

    test('approssimata ignora la punteggiatura (soglia 90)', () {
      expect(matchesRule(rule(MatchAlgorithm.fuzzy, 'Agenzia delle Entrate'), 'AGENZIA DELLE-ENTRATE, Roma'), isTrue);
      expect(matchesRule(rule(MatchAlgorithm.fuzzy, 'Agenzia delle Entrate'), 'Agenzia Viaggi Roma'), isFalse);
    });

    test('segnaposti con la sintassi di Paperless', () {
      final a = Archive();
      final enel = NamedEntity(name: 'Enel');
      a.correspondents[enel.id] = enel;
      final d = Document(title: 't', created: DateTime(2024, 3, 5), correspondentId: enel.id);
      expect(renderTitle('{{ correspondent }} {{created_year}}-{{ created_month }} {created_month_name}', a, d),
          'Enel 2024-03 marzo');
    });
  });

  group('classificatore come Paperless (classifier.py)', () {
    Archive build() {
      final a = Archive.starter();
      final enel = NamedEntity(id: 'enel', name: 'Enel', algorithm: MatchAlgorithm.auto);
      final a2a = NamedEntity(id: 'a2a', name: 'A2A', algorithm: MatchAlgorithm.auto);
      final casa = Tag(id: 'casa', name: 'Casa mia', algorithm: MatchAlgorithm.auto);
      a.correspondents[enel.id] = enel;
      a.correspondents[a2a.id] = a2a;
      a.tags[casa.id] = casa;
      var i = 0;
      for (final t in [
        'servizio elettrico nazionale bolletta luce kwh potenza impegnata',
        'servizio elettrico nazionale fattura energia kwh codice pod',
        'servizio elettrico nazionale consumi luce kwh lettura contatore',
      ]) {
        a.documents['e${i++}'] = Document(id: 'e$i', title: 'x', content: t, correspondentId: 'enel', tagIds: {'casa'});
      }
      for (final t in [
        'teleriscaldamento milano calore fornitura acqua calda sanitaria',
        'teleriscaldamento milano calore lettura gennaio',
        'teleriscaldamento milano calore conguaglio annuale',
      ]) {
        a.documents['a${i++}'] = Document(id: 'a$i', title: 'x', content: t, correspondentId: 'a2a');
      }
      return a;
    }

    test('impara corrispondenti e tag dagli esempi', () {
      final a = build();
      final clf = DocumentClassifier.train(a)!;
      expect(clf.trainedOn, 6);
      expect(clf.predictCorrespondent('servizio elettrico nazionale nuova bolletta kwh'), 'enel');
      expect(clf.predictCorrespondent('teleriscaldamento milano calore febbraio'), 'a2a');
      expect(clf.predictTags('servizio elettrico nazionale kwh'), contains('casa'));
      final d = Document(title: 'x', content: 'teleriscaldamento milano calore marzo');
      applyMatches(a, d, classifier: clf);
      expect(d.correspondentId, 'a2a');
    });

    test('i documenti "da esaminare" non insegnano nulla', () {
      final a = build();
      for (final d in a.documents.values) {
        d.tagIds.add(a.inboxTags.first.id);
      }
      expect(DocumentClassifier.train(a), isNull);
    });

    test('impara anche le voci con regole a parole chiave (assegnate a mano)', () {
      final a = build();
      for (final c in a.correspondents.values) {
        c.algorithm = MatchAlgorithm.any;
      }
      final clf = DocumentClassifier.train(a)!;
      expect(clf.predictCorrespondent('teleriscaldamento milano calore febbraio'), 'a2a');
    });
  });

  test('preprocess come RE_WORD di Paperless', () {
    expect(preprocess('Fattura N.634 — Città'), ['fattura', 'n', '634', 'città']);
    final v = Vectorizer.fit(['a b c', 'a b d']);
    expect(v.vocabulary.keys, containsAll(['a', 'b', 'a b']));
  });

  test('workflow con segnaposti al momento dell\'aggiunta', () {
    final a = Archive();
    final w = Workflow(name: 'Titolo', titleTemplate: '{{ document_type }} {{ created }}');
    a.workflows[w.id] = w;
    final t = NamedEntity(name: 'Bolletta');
    a.types[t.id] = t;
    final d = Document(title: 'scan', created: DateTime(2025, 1, 2), typeId: t.id);
    expect(applyWorkflows(a, d, WorkflowTrigger.added, source: DocSource.share), ['Titolo']);
    expect(d.title, 'Bolletta 2025-01-02');
  });

  test('etichetta di spedizione Vinted (formato del telefono)', () {
    // Struttura reale di un'etichetta per punto di ritiro (dati di fantasia).
    const label = 'DEPOSITO GIRO\r\nORI15\r\nVA\r\nMITTENTE:\r\nDESTINATARIO:\r\nGiulia Vinted user\r\nITGAL110054F\r\n'
        'Via Roma 20\r\nDIMENSIONI A\r\nStazione di servizio ROSSI PETROLI\r\nMI2\r\n21013 Gallarate\r\n'
        'NUMERO RIFERIMENTO CLIENTE:\r\n11b8ef45-aa2b-4022-baad￾e132147d8846\r\nPROVINCIA\r\nmario rossi\r\n'
        '20095 Cusano Milanino\r\nVia Verdi 89\r\n2026.10.11\r\nDATA STAMPA ETICHETTA\r\n800144617621013014689095';
    final f = extractFacts(label);
    expect(f.kind, 'Etichetta di spedizione');
    expect(f.issuer, 'Vinted');
    expect(detectDate(label, now: DateTime(2026, 10, 21)), DateTime(2026, 10, 11));
    final a = Archive.starter();
    final d = Document(
      title: 'x',
      originalName: '11b8ef45-aa2b-4022-baad-e132147d8846_2.pdf',
      content: cleanContent(label),
      created: DateTime(2026, 10, 11),
    );
    expect(meaningfulFileName(d.originalName), isNull);
    applyMatches(a, d);
    applyKindCategory(a, d);
    expect(a.type(d.typeId)?.name, 'Garanzia e acquisti');
    final c = NamedEntity(name: f.issuer!);
    a.correspondents[c.id] = c;
    d.correspondentId = c.id;
    expect(autoTitle(a, d), 'Etichetta di spedizione - Vinted');
    expect(drivePath(a, d).$1, ['Garanzia e acquisti', '2026']);
  });

  group('impara dalle correzioni', () {
    String label(String date, String ref) => cleanContent(
        'DEPOSITO GIRO\r\nMITTENTE:\r\nDESTINATARIO:\r\nGiulia Vinted user\r\nStazione di servizio ROSSI PETROLI\r\n'
        'NUMERO RIFERIMENTO CLIENTE:\r\n$ref\r\nmario rossi\r\n20095 Cusano Milanino\r\n$date\r\nDATA STAMPA ETICHETTA\r\n');

    test('rinomina come hai rinominato un documento simile', () {
      final a = Archive.starter();
      final first = Document(
        title: 'Spedizione Vinted punto ritiro 11-10-2026',
        content: label('2026.10.11', 'aaa111'),
        created: DateTime(2026, 10, 11),
      )..titleEdited = true;
      a.documents[first.id] = first;
      expect(titleToTemplate(a, first), 'Spedizione Vinted punto ritiro {created_day}-{created_month}-{created_year}');
      final second = Document(title: 'x', originalName: 'bbb222_2.pdf', content: label('2026.10.15', 'bbb222'), created: DateTime(2026, 10, 15));
      expect(autoTitle(a, second), 'Spedizione Vinted punto ritiro 15-10-2026');
      // Un documento diverso non copia quel nome.
      final other = Document(title: 'x', originalName: 'scan.pdf', content: 'Referto visita cardiologica ospedale', created: DateTime(2026, 1, 2));
      expect(learnedTitle(a, other), isNull);
    });

    test('mittente, importo e mese diventano segnaposti', () {
      final a = Archive();
      final enel = NamedEntity(name: 'Enel');
      a.correspondents[enel.id] = enel;
      final d = Document(
        title: 'Luce Enel marzo 2024 89,90 €',
        content: 'Enel Energia bolletta luce kwh totale da pagare 89,90 €',
        created: DateTime(2024, 3, 5),
        correspondentId: enel.id,
      );
      expect(titleToTemplate(a, d), 'Luce {correspondent} {created_month_name} {created_year} {importo}');
    });

    test('le correzioni insegnano anche senza "esaminato" e con categorie a parole chiave', () {
      final a = Archive.starter();
      final inbox = a.inboxTags.first.id;
      for (var i = 0; i < 3; i++) {
        final d = Document(
          id: 'l$i',
          title: 'x',
          content: label('2026.10.1$i', 'r$i'),
          typeId: 'st-garanzia',
          tagIds: {inbox},
        )..userEdited = true;
        a.documents[d.id] = d;
      }
      a.documents['o'] = Document(id: 'o', title: 'y', content: 'referto ospedale visita cardiologica esame', typeId: 'st-sanita')
        ..userEdited = true;
      final clf = DocumentClassifier.train(a)!;
      final n = Document(title: 'z', content: label('2026.10.20', 'zzz'));
      // Le parole chiave predefinite non bastano: decide ciò che ha imparato.
      final r = computeMatches(a, n, classifier: clf);
      expect(r.typeId, 'st-garanzia');
    });
  });
}
