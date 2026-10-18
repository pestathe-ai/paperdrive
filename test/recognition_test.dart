import 'package:flutter_test/flutter_test.dart';
import 'package:paperdrive/core/archive.dart';
import 'package:paperdrive/core/extract.dart';
import 'package:paperdrive/core/matching.dart';
import 'package:paperdrive/core/models.dart';
import 'package:paperdrive/core/organize.dart';

/// Esempi tipici di documenti italiani (testi di fantasia): per ognuno il
/// tipo specifico e la categoria attesi.
const samples = <(String, String, String)>[
  ('Bolletta luce', 'Bolletta', 'Enel Energia S.p.A.\nBolletta n. 123 del 05/03/2024\nCodice POD IT001E12345678\nConsumi fatturati 250 kWh\nTotale da pagare 89,90 €'),
  ('Bolletta gas', 'Bolletta', 'A2A Energia\nFornitura di gas naturale\nCodice PDR 00881234567890\nConsumo 120 Smc\nTotale bolletta 74,10 euro'),
  ('Bolletta acqua', 'Bolletta', 'Gruppo CAP\nServizio idrico integrato\nConsumo acqua 45 metri cubi\nImporto da pagare 61,30'),
  ('Bolletta telefono e internet', 'Bolletta', 'Fastweb S.p.A.\nFattura n. F123\nOfferta casa fibra ottica FTTH\nLinea fissa 02123456\nTotale 29,95 €'),
  ('F24', 'Tasse', 'MODELLO F24\nAGENZIA DELLE ENTRATE\nSezione Erario\nCodice tributo 4001 anno di riferimento 2024\nSaldo finale 1.234,00'),
  ('Dichiarazione dei redditi', 'Tasse', 'Agenzia delle Entrate\nModello 730/2025 redditi 2024\nProspetto di liquidazione\nRimborso 312,00'),
  ('Certificazione Unica', 'Tasse', 'CERTIFICAZIONE UNICA 2025\nDati relativi al percipiente\nCertificazione lavoro dipendente, assimilati'),
  ('Avviso di pagamento PagoPA', 'Tasse', 'Comune di Milano\nAVVISO DI PAGAMENTO\nCodice avviso 3010 0000 1234 5678\nPagoPA\nImporto 45,00 euro'),
  ('TARI', 'Tasse', 'Comune di Sesto San Giovanni\nTassa sui rifiuti TARI 2025\nPrima rata scadenza 31/05/2025'),
  ('Cartella esattoriale', 'Tasse', 'Agenzia delle Entrate-Riscossione\nCartella di pagamento n. 068 2025 0001234\nTotale da pagare 512,40'),
  ('Estratto conto', 'Banca', 'Intesa Sanpaolo\nEstratto conto al 30/06/2025\nSaldo iniziale 1.200,00\nBonifico a favore di Mario Rossi\nSaldo finale 980,00'),
  ('Estratto conto carta', 'Banca', 'American Express\nEstratto conto carta di credito\nPeriodo 01/05/2025 - 31/05/2025\nTotale movimenti 845,20'),
  ('Bonifico', 'Banca', 'UniCredit\nEsito bonifico SEPA\nBeneficiario: LUIGI VERDI\nImporto: EUR 300,00\nCausale: rimborso cena'),
  ('Mutuo', 'Banca', 'Banco BPM\nContratto di mutuo ipotecario\nPiano di ammortamento\nRata del mutuo 650,00'),
  ('Busta paga', 'Busta paga', 'ACME S.r.l.\nCedolino paga mese di Marzo 2025\nCompetenze\nTrattenute\nNetto in busta 1.850,00'),
  ('Estratto contributivo', 'Lavoro', 'INPS\nEstratto conto contributivo\nPosizione assicurativa del lavoratore'),
  ('Contratto di lavoro', 'Lavoro', 'Lettera di assunzione\nContratto individuale di lavoro a tempo indeterminato\nCCNL Commercio\nPeriodo di prova 60 giorni'),
  ('Referto', 'Sanità', 'ASST Grande Ospedale Metropolitano Niguarda\nREFERTO ECOGRAFIA ADDOME\nConclusioni diagnostiche: nella norma'),
  ('Analisi del sangue', 'Sanità', 'Synlab Italia\nEsami ematochimici\nEmocromo\nGlicemia 92 mg/dl\nColesterolo totale 180 valori di riferimento'),
  ('Ricetta medica', 'Sanità', 'SERVIZIO SANITARIO NAZIONALE\nRicetta elettronica - Promemoria per l\'assistito\nNRE 0301A1234567890'),
  ('Polizza assicurativa', 'Assicurazione', 'UnipolSai Assicurazioni\nPolizza n. 123456 RC Auto\nCertificato di assicurazione\nPremio annuo 480,00'),
  ('Attestato di rischio', 'Assicurazione', 'Generali Italia\nAttestato di rischio\nClasse di merito CU 1'),
  ('Multa', 'Auto e veicoli', 'Polizia Locale di Milano\nVerbale di accertamento di violazione al Codice della Strada\nArt. 142 eccesso di velocità\nImporto 175,00'),
  ('Bollo auto', 'Auto e veicoli', 'Regione Lombardia\nTassa automobilistica (bollo auto)\nTarga AB123CD\nImporto 210,50'),
  ('Revisione auto', 'Auto e veicoli', 'Centro revisioni Rossi\nCertificato di revisione\nEsito revisione: regolare\nTarga AB123CD'),
  ('Carta d\'identità', 'Documenti personali', 'REPUBBLICA ITALIANA\nCarta di identità elettronica\nCognome ROSSI Nome MARIO'),
  ('Certificato anagrafico', 'Documenti personali', 'Comune di Sesto San Giovanni\nCertificato di residenza\nSi certifica che ROSSI MARIO risulta residente'),
  ('Pagella', 'Scuola e studio', 'Istituto Comprensivo Statale "G. Rodari"\nDocumento di valutazione\nAnno scolastico 2024/2025'),
  ('Biglietto aereo', 'Viaggi', 'Ryanair\nCarta d\'imbarco / Boarding pass\nNumero volo FR1234 Milano Bergamo - Londra Stansted'),
  ('Prenotazione alloggio', 'Viaggi', 'Booking.com\nConferma di prenotazione\nNumero di prenotazione 1234567890\nCheck-in 12/08/2025 Check-out 15/08/2025'),
  ('Scontrino', 'Scontrino e ricevuta', 'ESSELUNGA S.p.A.\nDOCUMENTO COMMERCIALE di vendita o prestazione\nTOTALE COMPLESSIVO 34,56'),
  ('Conferma d\'ordine', 'Garanzia e acquisti', 'Amazon.it\nConferma d\'ordine\nNumero ordine 405-1234567-1234567\nTotale ordine 59,99 €'),
  ('Visura catastale', 'Casa', 'Agenzia delle Entrate\nVisura per immobile\nCatasto Fabbricati\nComune di MILANO (Codice F205)'),
  ('Contratto di locazione', 'Casa', 'CONTRATTO DI LOCAZIONE AD USO ABITATIVO\nIl locatore Mario Rossi concede in locazione al conduttore\nCedolare secca'),
  ('Convocazione assemblea condominiale', 'Casa', 'Condominio Via Po 1\nAvviso di convocazione assemblea ordinaria\nPrima convocazione 10/05/2025\nOrdine del giorno'),
];

void main() {
  late Archive a;
  setUp(() => a = Archive.starter());

  for (final (kind, category, text) in samples) {
    test('$kind → $category', () {
      expect(detectKind(text), kind);
      final d = Document(title: 'x', originalName: 'documento.pdf', content: text);
      applyMatches(a, d);
      applyKindCategory(a, d);
      expect(a.type(d.typeId)?.name, category);
      final title = autoTitle(a, d);
      expect(title, isNotNull);
      expect(title, startsWith(kind));
    });
  }

  test('enti riconosciuti', () {
    expect(detectIssuer(samples[0].$3), 'Enel');
    expect(detectIssuer('Comune di Sesto San Giovanni\nUfficio Tributi'), 'Comune di Sesto San Giovanni');
    expect(detectIssuer('ASST Grande Ospedale Metropolitano Niguarda\nReferto'), 'ASST Grande Ospedale Metropolitano Niguarda');
    expect(detectIssuer('Istituto Comprensivo "G. Rodari"\nComunicazione'), 'Istituto Comprensivo G. Rodari');
    expect(detectIssuer('Gruppo CAP\nServizio idrico'), 'Gruppo CAP');
  });

  test('documento sconosciuto: titolo dall\'intestazione', () {
    const text = 'ACME S.r.l.\nVia Roma 1 - 20100 Milano\nTel. 02 123456\n\n'
        'Spett.le Cliente\n\nComunicazione di variazione delle condizioni contrattuali\n\n'
        'Con la presente le comunichiamo che dal 1 gennaio...';
    final d = Document(title: 'x', originalName: 'scan001.pdf', content: text);
    final t = autoTitle(a, d);
    expect(t, contains('variazione delle condizioni'));
  });

  test('la categoria scelta da una regola dell\'utente resta', () {
    final mia = NamedEntity(name: 'Fornitori');
    a.types[mia.id] = mia;
    final d = Document(title: 'x', content: samples[0].$3)..typeId = mia.id;
    expect(applyKindCategory(a, d), isFalse);
    expect(d.typeId, mia.id);
  });
}
