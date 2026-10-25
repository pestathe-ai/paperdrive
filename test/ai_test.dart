import 'package:flutter_test/flutter_test.dart';
import 'package:paperdrive/core/ai.dart';
import 'package:paperdrive/core/archive.dart';
import 'package:paperdrive/core/models.dart';

// Etichetta di spedizione di fantasia, nel formato del telefono.
const etichetta = 'InPost\r\nLocker to Locker\r\nMittente: Vinted Go\r\nDestinatario: M. Rossi\r\n'
    'Codice spedizione 6200123456789\r\nData 11/10/2026\r\nPunto di ritiro: Locker MI-1234 Via Roma 1\r\n';

void main() {
  group('risposta del modello', () {
    final now = DateTime(2026, 10, 20);

    test('JSON pulito', () {
      final r = parseAiResponse(
        '{"categoria": "Garanzia e acquisti", "tipo": "Etichetta di spedizione", '
        '"titolo": "Etichetta spedizione Vinted InPost", "mittente": "Vinted", '
        '"data": "2026-10-11", "importo": null, "tag": []}',
        now: now,
      )!;
      expect(r.category, 'Garanzia e acquisti');
      expect(r.kind, 'Etichetta di spedizione');
      expect(r.title, 'Etichetta spedizione Vinted InPost');
      expect(r.sender, 'Vinted');
      expect(r.date, DateTime(2026, 10, 11));
      expect(r.amount, isNull);
      expect(r.tags, isEmpty);
    });

    test('dentro ```json``` con testo intorno, virgola finale e chiavi inglesi', () {
      final r = parseAiResponse(
        'Ecco il risultato:\n```json\n{"category": "Bolletta", "title": "Bolletta luce Enel marzo 2024.pdf", '
        '"sender": "Enel Energia S.p.A.", "date": "05/03/2024", "amount": "84,20", "tags": ["Casa",],}\n```',
        now: now,
      )!;
      expect(r.category, 'Bolletta');
      expect(r.title, 'Bolletta luce Enel marzo 2024');
      expect(r.sender, 'Enel Energia S.p.A.');
      expect(r.date, DateTime(2024, 3, 5));
      expect(r.amount, '84,20');
      expect(r.tags, ['Casa']);
    });

    test('valori vuoti e date impossibili', () {
      final r = parseAiResponse(
        '{"categoria": "Banca", "mittente": "N/A", "data": "2031-01-01", "titolo": "null", "importo": "nessuno"}',
        now: now,
      )!;
      expect(r.category, 'Banca');
      expect(r.sender, isNull);
      expect(r.date, isNull);
      expect(r.title, isNull);
      expect(r.amount, isNull);
    });

    test('risposta inutilizzabile', () {
      expect(parseAiResponse('Non so', now: now), isNull);
      expect(parseAiResponse('{"foo": 1}', now: now), isNull);
    });

    test('caratteri non ammessi nel nome del file', () {
      final r = parseAiResponse('{"titolo": "Fattura n. 12/2024: Rossi"}', now: now)!;
      expect(r.title, 'Fattura n. 12 2024 Rossi');
    });
  });

  test('il prompt contiene categorie, mittenti e testo', () {
    final a = Archive.starter();
    a.correspondents['c1'] = NamedEntity(id: 'c1', name: 'Enel');
    final d = Document(title: 'x', originalName: 'scan001.pdf', content: etichetta);
    final p = buildAiPrompt(a, d);
    expect(p, contains('Garanzia e acquisti'));
    expect(p, contains('Enel'));
    expect(p, contains('scan001.pdf'));
    expect(p, contains('Locker to Locker'));
    expect(p, isNot(contains('\r')));
  });

  test('testo lungo accorciato tenendo inizio e fine', () {
    final t = aiDocumentText('INIZIO ${'parola ' * 3000} FINE', maxChars: 1000);
    expect(t.length, lessThan(1100));
    expect(t, startsWith('INIZIO'));
    expect(t, endsWith('FINE'));
  });

  group('applicazione', () {
    Document doc() => Document(
          title: 'scan001',
          originalName: 'scan001.pdf',
          content: etichetta,
          created: DateTime(2026, 10, 20),
          typeId: 'st-scontrino',
        );
    final result = AiResult(
      category: 'garanzia e acquisti',
      kind: 'Etichetta di spedizione',
      title: 'Etichetta spedizione Vinted InPost',
      sender: 'Vinted',
      date: DateTime(2026, 10, 11),
    );

    test('l\'AI corregge categoria predefinita, mittente, data e titolo', () {
      final a = Archive.starter();
      a.correspondents['v'] = NamedEntity(id: 'v', name: 'Vinted S.r.l.');
      final d = doc();
      final changed = applyAiResult(a, d, result);
      expect(d.typeId, 'st-garanzia');
      expect(d.correspondentId, 'v');
      expect(d.created, DateTime(2026, 10, 11));
      expect(d.title, 'Etichetta spedizione Vinted InPost');
      expect(changed, containsAll(['categoria', 'mittente', 'data', 'titolo']));
    });

    test('mittente nuovo creato, data inventata ignorata', () {
      final a = Archive.starter();
      final d = doc();
      applyAiResult(a, d, AiResult(sender: 'InPost', date: DateTime(2026, 9, 1)));
      expect(a.correspondent(d.correspondentId)?.name, 'InPost');
      expect(d.created, DateTime(2026, 10, 20));
    });

    test('un documento simile corretto a mano vale più dell\'AI', () {
      final a = Archive.starter();
      final mine = NamedEntity(id: 'sp', name: 'Spedizioni');
      a.types['sp'] = mine;
      a.correspondents['ip'] = NamedEntity(id: 'ip', name: 'InPost');
      final corrected = Document(
        title: 'Etichetta InPost 01-10-2026',
        content: etichetta.replaceAll('11/10/2026', '01/10/2026').replaceAll('6200123456789', '6200999999999'),
        typeId: 'sp',
        correspondentId: 'ip',
        userEdited: true,
        titleEdited: true,
        created: DateTime(2026, 10, 1),
      );
      a.documents[corrected.id] = corrected;
      final d = doc();
      applyAiResult(a, d, result);
      expect(d.typeId, 'sp');
      expect(d.correspondentId, 'ip');
      // Il titolo segue quello che hai scelto tu per i documenti simili.
      expect(d.title, isNot('Etichetta spedizione Vinted InPost'));
    });

    test('regola dell\'utente vince sull\'AI', () {
      final a = Archive.starter();
      a.types['r'] = NamedEntity(id: 'r', name: 'Resi', algorithm: MatchAlgorithm.any, pattern: 'locker');
      final d = doc()..typeId = 'r';
      applyAiResult(a, d, result);
      expect(d.typeId, 'r');
    });

    test('nome del file già descrittivo: titolo non toccato', () {
      final a = Archive.starter();
      final d = doc()
        ..originalName = 'Etichetta reso giacca blu.pdf'
        ..title = 'Etichetta reso giacca blu';
      applyAiResult(a, d, result);
      expect(d.title, 'Etichetta reso giacca blu');
    });

    test('categoria nuova creata solo se breve', () {
      final a = Archive.starter();
      final d = doc();
      applyAiResult(a, d, AiResult(category: 'Animali domestici'));
      expect(a.type(d.typeId)?.name, 'Animali domestici');
      final d2 = doc();
      applyAiResult(a, d2, AiResult(category: 'una categoria troppo lunga per essere vera'));
      expect(d2.typeId, 'st-scontrino');
    });
  });

  test('il nome e l\'indirizzo presenti ovunque non rendono simili due documenti', () {
    final a = Archive.starter();
    const me = 'Mario Rossi via Verdi 1 20099 Sesto San Giovanni codice fiscale RSSMRA80A01F205X totale euro';
    for (var i = 0; i < 6; i++) {
      final o = Document(title: 'altro $i', content: '$me documento numero $i varie parole diverse $i');
      a.documents[o.id] = o;
    }
    final box = Document(
      title: 'Rata box',
      content: '$me condominio box auto rata spese condominiali amministratore',
      typeId: 'st-casa',
      userEdited: true,
    );
    a.documents[box.id] = box;
    final bolletta = Document(title: 'x', content: '$me bolletta luce kwh energia elettrica consumi');
    final (example, _) = correctedExample(a, bolletta);
    expect(example, isNull);
  });
}
