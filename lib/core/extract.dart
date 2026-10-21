/// Lettura "specifica" di un documento: che cos'è esattamente (bonifico,
/// visura catastale, F24…), chi l'ha emesso, importo, beneficiario, numero.
/// Serve a dare nomi descrittivi in automatico.
library;

import 'text_utils.dart';

/// Un tipo specifico di documento.
class DocKind {
  const DocKind(this.name, this.category, this.phrases, {this.weak = false});

  /// Nome usato nel titolo (es. "Visura catastale").
  final String name;

  /// Id della categoria predefinita (es. `st-casa`), o null.
  final String? category;

  /// Frasi che lo identificano (senza maiuscole e accenti).
  final List<String> phrases;

  /// Tipo generico: vince solo se non c'è niente di più preciso.
  final bool weak;
}

/// Tipi di documento riconosciuti. A parità di punteggio vince il primo.
const List<DocKind> documentKinds = [
  // --- Casa e immobili
  DocKind('Visura catastale', 'st-casa', ['visura catastale', 'visura per immobile', 'visura per soggetto', 'visura storica', 'catasto fabbricati', 'catasto terreni', 'dati derivanti da']),
  DocKind('Visura ipotecaria', 'st-casa', ['visura ipotecaria', 'ispezione ipotecaria', 'nota di trascrizione']),
  DocKind('Planimetria catastale', 'st-casa', ['planimetria catastale', 'planimetria di u.i.u', 'scheda planimetrica']),
  DocKind('Visura camerale', null, ['visura camerale', 'visura ordinaria societa', 'registro delle imprese', 'camera di commercio']),
  DocKind('Attestato di prestazione energetica', 'st-casa', ['attestato di prestazione energetica', 'classe energetica', 'a.p.e.']),
  DocKind('Estratto conto condominiale', 'st-casa', ['estratto conto condomino', 'estratto conto condominiale', 'rendiconto condominiale', 'situazione contabile condomino', 'rate condominiali', 'rata ordinaria', 'gestione ordinaria', 'condomino']),
  DocKind('Convocazione assemblea condominiale', 'st-casa', ['convocazione assemblea', 'avviso di convocazione', 'ordine del giorno', 'prima convocazione', 'seconda convocazione']),
  DocKind('Verbale di assemblea condominiale', 'st-casa', ['verbale di assemblea', 'verbale dell\'assemblea', 'assemblea condominiale', 'l\'assemblea delibera']),
  DocKind('Preventivo condominiale', 'st-casa', ['preventivo di gestione', 'riparto preventivo', 'bilancio preventivo', 'riparto spese']),
  DocKind('Contratto di locazione', 'st-casa', ['contratto di locazione', 'locazione ad uso abitativo', 'contratto di affitto', 'canone di locazione', 'il locatore', 'il conduttore', 'cedolare secca']),
  DocKind('Registrazione contratto di locazione', 'st-casa', ['modello rli', 'registrazione del contratto', 'ricevuta di registrazione']),
  DocKind('Atto di compravendita', 'st-casa', ['atto di compravendita', 'compravendita immobiliare', 'rogito', 'atto di acquisto', 'la parte venditrice', 'la parte acquirente']),
  DocKind('Pratica edilizia', 'st-casa', ['permesso di costruire', 'segnalazione certificata di inizio attivita', 'scia', 'cila', 'comunicazione inizio lavori', 'agibilita']),
  DocKind('Mutuo', 'st-banca', ['contratto di mutuo', 'piano di ammortamento', 'rata del mutuo', 'mutuo ipotecario', 'surroga']),

  // --- Bollette e utenze
  DocKind('Bolletta luce e gas', 'st-bolletta', ['luce e gas', 'dual fuel']),
  DocKind('Bolletta luce', 'st-bolletta', ['energia elettrica', 'kwh', 'fornitura di energia', 'codice pod', 'potenza impegnata']),
  DocKind('Bolletta gas', 'st-bolletta', ['gas naturale', 'smc', 'fornitura di gas', 'codice pdr']),
  DocKind('Bolletta acqua', 'st-bolletta', ['servizio idrico', 'fornitura idrica', 'acquedotto', 'consumo acqua', 'metri cubi']),
  DocKind('Bolletta telefono e internet', 'st-bolletta', ['fibra ottica', 'linea fissa', 'telefonia', 'traffico dati', 'offerta mobile', 'adsl', 'ftth', 'numero di telefono']),
  DocKind('Canone RAI', 'st-tasse', ['canone rai', 'canone di abbonamento alla televisione', 'canone tv']),

  // --- Fatture e pagamenti
  DocKind('Nota di credito', 'st-fattura', ['nota di credito']),
  DocKind('Fattura', 'st-fattura', ['fattura elettronica', 'fattura n', 'fattura nr', 'fattura numero', 'numero fattura', 'fattura del', 'fattura accompagnatoria', 'fattura']),
  DocKind('Sollecito di pagamento', null, ['sollecito di pagamento', 'sollecito', 'messa in mora', 'mancato pagamento']),
  DocKind('Preventivo', 'st-garanzia', ['preventivo n', 'preventivo di spesa', 'offerta economica', 'preventivo']),

  // --- Tasse e fisco
  DocKind('F24', 'st-tasse', ['modello f24', 'delega f24', 'f24 semplificato', 'f24 elide', 'f24']),
  DocKind('Certificazione Unica', 'st-tasse', ['certificazione unica', 'certificazione lavoro dipendente']),
  DocKind('Dichiarazione dei redditi', 'st-tasse', ['modello 730', '730/2', '730-3', 'modello redditi', 'dichiarazione dei redditi', 'prospetto di liquidazione', 'unico persone fisiche']),
  DocKind('Ricevuta di presentazione', 'st-tasse', ['ricevuta di presentazione', 'comunicazione di avvenuta ricezione', 'protocollo telematico']),
  DocKind('Avviso di accertamento', 'st-tasse', ['avviso di accertamento', 'atto di accertamento']),
  DocKind('Comunicazione di irregolarità', 'st-tasse', ['comunicazione di irregolarita', 'avviso bonario', 'controllo automatizzato', '36-bis']),
  DocKind('Cartella esattoriale', 'st-tasse', ['cartella di pagamento', 'agenzia delle entrate-riscossione', 'agenzia delle entrate riscossione', 'equitalia', 'intimazione di pagamento']),
  DocKind('Avviso di pagamento PagoPA', 'st-tasse', ['avviso di pagamento', 'pagopa', 'codice avviso', 'iuv']),
  DocKind('IMU', 'st-tasse', ['imposta municipale propria', 'imu']),
  DocKind('TARI', 'st-tasse', ['tassa sui rifiuti', 'tari', 'tariffa rifiuti']),
  DocKind('ISEE', 'st-tasse', ['isee', 'dichiarazione sostitutiva unica', 'dsu', 'indicatore della situazione economica']),
  DocKind('Rimborso fiscale', 'st-tasse', ['rimborso irpef', 'rimborso fiscale', 'credito d\'imposta']),

  // --- Banca e finanza
  DocKind('Estratto conto carta', 'st-banca', ['estratto conto carta', 'rendiconto carta', 'carta di credito', 'movimenti carta']),
  DocKind('Estratto conto', 'st-banca', ['estratto conto', 'estratto di conto', 'saldo contabile', 'saldo iniziale', 'saldo finale', 'riepilogo movimenti']),
  DocKind('Rendiconto titoli', 'st-banca', ['dossier titoli', 'rendiconto titoli', 'portafoglio titoli', 'deposito titoli', 'eseguito', 'fondo comune', 'nota informativa titoli']),
  DocKind('Bonifico', 'st-banca', ['bonifico istantaneo', 'disposizione di bonifico', 'ordine di bonifico', 'esito bonifico', 'sepa credit transfer', 'contabile bonifico', 'bonifico']),
  DocKind('Addebito diretto', 'st-banca', ['addebito diretto', 'sepa direct debit', 'mandato sdd', 'rid']),
  DocKind('Finanziamento', 'st-banca', ['contratto di finanziamento', 'prestito personale', 'credito al consumo', 'taeg', 'piano di rimborso']),
  DocKind('Documento di sintesi', 'st-banca', ['documento di sintesi', 'foglio informativo', 'condizioni economiche']),

  // --- Lavoro e previdenza
  DocKind('Busta paga', 'st-paga', ['busta paga', 'cedolino paga', 'prospetto paga', 'netto in busta', 'retribuzione lorda', 'competenze', 'trattenute']),
  DocKind('Cedolino pensione', 'st-lavoro', ['cedolino pensione', 'rata di pensione', 'obism', 'pensione di']),
  DocKind('Estratto contributivo', 'st-lavoro', ['estratto conto contributivo', 'estratto contributivo', 'ecocert', 'posizione assicurativa']),
  DocKind('NASpI', 'st-lavoro', ['naspi', 'indennita di disoccupazione']),
  DocKind('Contratto di lavoro', 'st-lavoro', ['contratto di lavoro', 'lettera di assunzione', 'contratto individuale di lavoro', 'periodo di prova', 'ccnl']),
  DocKind('Dimissioni', 'st-lavoro', ['dimissioni', 'lettera di licenziamento', 'cessazione del rapporto']),
  DocKind('TFR', 'st-lavoro', ['trattamento di fine rapporto', 'tfr']),
  DocKind('Curriculum vitae', 'st-lavoro', ['curriculum vitae', 'esperienze professionali', 'istruzione e formazione']),

  // --- Sanità
  DocKind('Referto', 'st-sanita', ['referto', 'esito esame', 'conclusioni diagnostiche', 'si refertano']),
  DocKind('Analisi del sangue', 'st-sanita', ['emocromo', 'esami ematochimici', 'analisi di laboratorio', 'valori di riferimento', 'glicemia', 'colesterolo']),
  DocKind('Lettera di dimissione', 'st-sanita', ['lettera di dimissione', 'dimissione ospedaliera', 'decorso clinico', 'ricovero']),
  DocKind('Ricetta medica', 'st-sanita', ['ricetta elettronica', 'promemoria per l\'assistito', 'ricetta medica', 'nre', 'prescrizione']),
  DocKind('Certificato medico', 'st-sanita', ['certificato medico', 'certificato di malattia', 'prognosi']),
  DocKind('Prenotazione sanitaria', 'st-sanita', ['prenotazione visita', 'promemoria prenotazione', 'centro unico di prenotazione', 'prenotazione cup', 'appuntamento ambulatoriale']),
  DocKind('Certificato vaccinale', 'st-sanita', ['certificato vaccinale', 'vaccinazione', 'green pass']),
  DocKind('Esenzione ticket', 'st-sanita', ['esenzione ticket', 'codice di esenzione', 'esenzione per reddito']),

  // --- Assicurazioni
  DocKind('Attestato di rischio', 'st-assicurazione', ['attestato di rischio', 'classe di merito']),
  DocKind('Denuncia di sinistro', 'st-assicurazione', ['denuncia di sinistro', 'constatazione amichevole', 'modulo cai', 'cid']),
  DocKind('Quietanza assicurativa', 'st-assicurazione', ['quietanza di pagamento', 'quietanza']),
  DocKind('Polizza assicurativa', 'st-assicurazione', ['polizza', 'certificato di assicurazione', 'set informativo', 'condizioni di assicurazione', 'premio annuo']),

  // --- Auto e veicoli
  DocKind('Multa', 'st-auto', ['verbale di contestazione', 'codice della strada', 'violazione dell\'art', 'verbale di accertamento', 'infrazione', 'autovelox']),
  DocKind('Bollo auto', 'st-auto', ['tassa automobilistica', 'bollo auto']),
  DocKind('Revisione auto', 'st-auto', ['certificato di revisione', 'esito revisione', 'revisione periodica']),
  DocKind('Carta di circolazione', 'st-auto', ['carta di circolazione', 'libretto di circolazione', 'documento unico di circolazione']),
  DocKind('Certificato di proprietà', 'st-auto', ['certificato di proprieta', 'pubblico registro automobilistico', 'pra']),
  DocKind('Passaggio di proprietà', 'st-auto', ['passaggio di proprieta', 'atto di vendita del veicolo', 'trasferimento di proprieta']),
  DocKind('Patente', 'st-auto', ['patente di guida', 'rinnovo patente']),
  DocKind('Tagliando auto', 'st-auto', ['tagliando', 'manutenzione programmata', 'cambio olio', 'officina']),

  // --- Documenti personali
  DocKind('Carta d\'identità', 'st-personali', ['carta d\'identita', 'carta di identita', 'cie']),
  DocKind('Passaporto', 'st-personali', ['passaporto', 'passport']),
  DocKind('Tessera sanitaria', 'st-personali', ['tessera sanitaria', 'tessera europea di assicurazione malattia']),
  DocKind('Codice fiscale', 'st-personali', ['tesserino del codice fiscale', 'attribuzione del codice fiscale']),
  DocKind('Certificato anagrafico', 'st-personali', ['certificato di residenza', 'stato di famiglia', 'certificato anagrafico', 'certificato di nascita', 'estratto di nascita', 'certificato di matrimonio', 'anagrafe']),
  DocKind('Permesso di soggiorno', 'st-personali', ['permesso di soggiorno', 'carta di soggiorno']),
  DocKind('Tessera elettorale', 'st-personali', ['tessera elettorale']),

  // --- Scuola
  DocKind('Pagella', 'st-scuola', ['pagella', 'scheda di valutazione', 'documento di valutazione', 'scrutinio']),
  DocKind('Iscrizione scolastica', 'st-scuola', ['domanda di iscrizione', 'iscrizione al', 'iscrizione a.s']),
  DocKind('Diploma o laurea', 'st-scuola', ['diploma di', 'certificato di laurea', 'diploma di laurea', 'conseguimento del titolo']),
  DocKind('Tasse universitarie', 'st-scuola', ['tasse universitarie', 'contribuzione studentesca', 'contributo onnicomprensivo']),
  DocKind('Retta scolastica', 'st-scuola', ['retta', 'mensa scolastica', 'servizi scolastici', 'pre-scuola']),

  // --- Viaggi
  DocKind('Biglietto aereo', 'st-viaggi', ['carta d\'imbarco', 'boarding pass', 'e-ticket', 'itinerario elettronico', 'numero volo']),
  DocKind('Biglietto treno', 'st-viaggi', ['biglietto ferroviario', 'frecciarossa', 'intercity', 'regionale veloce', 'carrozza']),
  DocKind('Prenotazione alloggio', 'st-viaggi', ['conferma di prenotazione', 'prenotazione alberghiera', 'check-in', 'check-out', 'numero di prenotazione']),

  // --- Spedizioni e acquisti online
  DocKind('Etichetta di spedizione', 'st-garanzia', ['data stampa etichetta', 'etichetta di spedizione', 'lettera di vettura', 'numero riferimento cliente', 'numero di tracciamento', 'codice di tracciamento', 'tracking number', 'mittente:', 'destinatario:', 'punto di ritiro', 'deposito giro', 'locker', 'collo n', 'peso kg', 'dimensioni']),
  DocKind('Etichetta di reso', 'st-garanzia', ['etichetta di reso', 'modulo di reso', 'autorizzazione al reso', 'codice reso', 'rma']),
  DocKind('Prova di consegna', 'st-garanzia', ['prova di consegna', 'avvenuta consegna', 'ricevuta di consegna', 'proof of delivery']),
  DocKind('Biglietto evento', 'st-viaggi', ['biglietto d\'ingresso', 'ticketone', 'vivaticket', 'settore', 'posto', 'ingresso valido', 'evento']),
  DocKind('Abbonamento', null, ['abbonamento annuale', 'abbonamento mensile', 'rinnovo abbonamento', 'tessera associativa', 'quota associativa', 'iscrizione palestra']),
  DocKind('Buono o coupon', 'st-garanzia', ['buono regalo', 'gift card', 'codice sconto', 'coupon', 'voucher']),

  // --- Acquisti
  DocKind('Scontrino', 'st-scontrino', ['documento commerciale', 'scontrino', 'vendita o prestazione']),
  DocKind('Conferma d\'ordine', 'st-garanzia', ['conferma d\'ordine', 'riepilogo dell\'ordine', 'riepilogo ordine', 'il tuo ordine', 'numero ordine']),
  DocKind('Documento di trasporto', 'st-garanzia', ['documento di trasporto', 'ddt', 'bolla di consegna']),
  DocKind('Garanzia', 'st-garanzia', ['certificato di garanzia', 'garanzia legale', 'garanzia convenzionale']),
  DocKind('Manuale d\'uso', 'st-garanzia', ['manuale d\'uso', 'istruzioni per l\'uso', 'manuale utente', 'user manual']),

  // --- Atti e comunicazioni generiche
  DocKind('Raccomandata', null, ['raccomandata a/r', 'raccomandata con ricevuta di ritorno', 'avviso di ricevimento']),
  DocKind('Delega', null, ['delega', 'il sottoscritto delega', 'con la presente delego']),
  DocKind('Procura', null, ['procura speciale', 'procura generale']),
  DocKind('Dichiarazione sostitutiva', null, ['dichiarazione sostitutiva', 'autocertificazione', 'd.p.r. 445/2000']),
  DocKind('Ricevuta di pagamento', 'st-scontrino', ['ricevuta di pagamento', 'ricevuta di versamento', 'attestazione di pagamento', 'ricevuta'], weak: true),
  DocKind('Verbale', null, ['verbale'], weak: true),
  DocKind('Certificato', null, ['certificato di', 'si certifica', 'si attesta'], weak: true),
  DocKind('Contratto', 'st-contratto', ['contratto', 'le parti convengono', 'tra le parti', 'letto, confermato e sottoscritto'], weak: true),
  DocKind('Comunicazione', null, ['comunicazione', 'gentile cliente', 'egregio', 'informativa'], weak: true),
];

/// Enti ed aziende riconosciuti: (nome da usare, varianti nel testo).
const List<(String, List<String>)> knownIssuers = [
  // Banche e pagamenti
  ('Intesa Sanpaolo', ['intesa sanpaolo', 'intesa san paolo']),
  ('UniCredit', ['unicredit']),
  ('Banco BPM', ['banco bpm', 'banco popolare']),
  ('BPER Banca', ['bper banca', 'bper']),
  ('Banca Monte dei Paschi di Siena', ['monte dei paschi', 'banca mps']),
  ('BNL', ['banca nazionale del lavoro', 'bnl bnp paribas', 'bnl']),
  ('Crédit Agricole', ['credit agricole']),
  ('Fineco', ['finecobank', 'fineco']),
  ('Banca Mediolanum', ['banca mediolanum', 'mediolanum']),
  ('ING', ['ing bank', 'ing direct', 'ing italia', 'conto arancio']),
  ('Poste Italiane', ['poste italiane', 'bancoposta', 'postepay', 'poste vita']),
  ('Banca Sella', ['banca sella']),
  ('Credem', ['credem', 'credito emiliano']),
  ('Banca Popolare di Sondrio', ['popolare di sondrio']),
  ('Banca Ifis', ['banca ifis']),
  ('illimity', ['illimity']),
  ('CheBanca!', ['chebanca', 'che banca']),
  ('Deutsche Bank', ['deutsche bank']),
  ('Banca Generali', ['banca generali']),
  ('Allianz Bank', ['allianz bank']),
  ('Banca Etica', ['banca etica']),
  ('BCC', ['credito cooperativo', 'bcc']),
  ('Banco di Desio', ['banco di desio']),
  ('Widiba', ['widiba']),
  ('Hype', ['hype']),
  ('N26', ['n26']),
  ('Revolut', ['revolut']),
  ('Bunq', ['bunq']),
  ('Wise', ['wise payments']),
  ('PayPal', ['paypal']),
  ('Satispay', ['satispay']),
  ('American Express', ['american express']),
  ('Nexi', ['nexi']),
  ('Compass', ['compass banca', 'compass']),
  ('Findomestic', ['findomestic']),
  ('Agos', ['agos ducato', 'agos']),
  ('Santander Consumer Bank', ['santander consumer']),
  ('Cofidis', ['cofidis']),
  ('Klarna', ['klarna']),
  // Energia e acqua
  ('Enel', ['enel energia', 'servizio elettrico nazionale', 'e-distribuzione', 'enel']),
  ('Eni Plenitude', ['eni plenitude', 'plenitude', 'eni gas e luce']),
  ('A2A', ['a2a energia', 'a2a']),
  ('Hera', ['hera comm', 'gruppo hera', 'hera s.p.a']),
  ('Iren', ['iren mercato', 'iren']),
  ('Acea', ['acea energia', 'acea ato', 'acea']),
  ('Edison', ['edison energia', 'edison']),
  ('Sorgenia', ['sorgenia']),
  ('Engie', ['engie']),
  ('Iberdrola', ['iberdrola']),
  ('E.ON', ['e.on energia', 'e.on']),
  ('Illumia', ['illumia']),
  ('Octopus Energy', ['octopus energy']),
  ('NeN', ['nen energia']),
  ('Pulsee', ['pulsee']),
  ('Duferco Energia', ['duferco']),
  ('Gruppo CAP', ['gruppo cap', 'amiacque']),
  ('MM', ['metropolitana milanese', 'mm s.p.a']),
  ('Acquedotto Pugliese', ['acquedotto pugliese']),
  ('Publiacqua', ['publiacqua']),
  ('SMAT', ['smat']),
  ('Abbanoa', ['abbanoa']),
  // Telefonia e TV
  ('TIM', ['telecom italia', 'tim s.p.a', 'tim spa', 'tim business']),
  ('Vodafone', ['vodafone']),
  ('WindTre', ['windtre', 'wind tre']),
  ('Iliad', ['iliad']),
  ('Fastweb', ['fastweb']),
  ('ho. Mobile', ['ho. mobile', 'ho mobile']),
  ('Kena Mobile', ['kena mobile']),
  ('Very Mobile', ['very mobile']),
  ('PosteMobile', ['postemobile', 'poste mobile']),
  ('CoopVoce', ['coopvoce']),
  ('Tiscali', ['tiscali']),
  ('Eolo', ['eolo']),
  ('Sky', ['sky italia']),
  ('DAZN', ['dazn']),
  ('Netflix', ['netflix']),
  // Enti pubblici
  ('Agenzia delle Entrate-Riscossione', ['agenzia delle entrate-riscossione', 'agenzia delle entrate riscossione']),
  ('Agenzia delle Entrate', ['agenzia delle entrate']),
  ('INPS', ['inps', 'istituto nazionale della previdenza sociale']),
  ('INAIL', ['inail']),
  ('ACI', ['automobile club d\'italia']),
  ('Motorizzazione Civile', ['motorizzazione civile']),
  ('Ministero dell\'Interno', ['ministero dell\'interno']),
  ('Polizia di Stato', ['polizia di stato', 'questura']),
  ('Prefettura', ['prefettura']),
  ('Agenzia delle Dogane', ['agenzia delle dogane']),
  ('Camera di Commercio', ['camera di commercio']),
  ('Tribunale', ['tribunale di', 'tribunale ordinario']),
  ('Cassa Forense', ['cassa forense']),
  ('ENPAM', ['enpam']),
  ('RAI', ['rai radiotelevisione', 'canone rai']),
  // Assicurazioni
  ('Generali', ['assicurazioni generali', 'generali italia']),
  ('UnipolSai', ['unipolsai', 'unipol']),
  ('Allianz', ['allianz s.p.a', 'allianz']),
  ('AXA', ['axa assicurazioni', 'axa']),
  ('Reale Mutua', ['reale mutua']),
  ('Zurich', ['zurich']),
  ('Groupama', ['groupama']),
  ('Cattolica Assicurazioni', ['cattolica assicurazioni']),
  ('Vittoria Assicurazioni', ['vittoria assicurazioni']),
  ('Sara Assicurazioni', ['sara assicurazioni']),
  ('HDI Assicurazioni', ['hdi assicurazioni']),
  ('Helvetia', ['helvetia']),
  ('ITAS', ['itas mutua', 'itas assicurazioni']),
  ('Linear', ['linear assicurazioni']),
  ('Prima Assicurazioni', ['prima assicurazioni']),
  ('Verti', ['verti assicurazioni', 'verti']),
  ('Genertel', ['genertel']),
  ('ConTe.it', ['conte.it']),
  ('Quixa', ['quixa']),
  ('Direct Line', ['direct line']),
  ('Poste Assicura', ['poste assicura']),
  // Sanità privata
  ('Synlab', ['synlab']),
  ('Centro Diagnostico Italiano', ['centro diagnostico italiano']),
  ('Humanitas', ['humanitas']),
  ('Ospedale San Raffaele', ['san raffaele']),
  ('Auxologico', ['auxologico']),
  ('Gruppo San Donato', ['gruppo san donato']),
  ('Lifebrain', ['lifebrain']),
  // Commercio, trasporti, servizi
  ('Vinted', ['vinted']),
  ('Subito', ['subito.it']),
  ('InPost', ['inpost']),
  ('SDA', ['sda express']),
  ('Poste Delivery', ['poste delivery', 'crono']),
  ('Mondial Relay', ['mondial relay']),
  ('Packlink', ['packlink']),
  ('FedEx', ['fedex']),
  ('TNT', ['tnt express']),
  ('Shein', ['shein']),
  ('Temu', ['temu']),
  ('AliExpress', ['aliexpress']),
  ('Wallapop', ['wallapop']),
  ('Amazon', ['amazon']),
  ('eBay', ['ebay']),
  ('Zalando', ['zalando']),
  ('IKEA', ['ikea']),
  ('Leroy Merlin', ['leroy merlin']),
  ('MediaWorld', ['mediaworld']),
  ('Unieuro', ['unieuro']),
  ('Euronics', ['euronics']),
  ('Esselunga', ['esselunga']),
  ('Coop', ['coop lombardia', 'coop alleanza', 'unicoop']),
  ('Conad', ['conad']),
  ('Carrefour', ['carrefour']),
  ('Lidl', ['lidl']),
  ('Decathlon', ['decathlon']),
  ('Apple', ['apple distribution', 'apple store', 'apple italia']),
  ('Trenitalia', ['trenitalia']),
  ('Italo', ['italo treno', 'italo s.p.a', 'ntv']),
  ('ATM Milano', ['atm milano', 'azienda trasporti milanesi']),
  ('ATAC', ['atac']),
  ('ITA Airways', ['ita airways']),
  ('Ryanair', ['ryanair']),
  ('easyJet', ['easyjet']),
  ('Wizz Air', ['wizz air']),
  ('Booking.com', ['booking.com']),
  ('Airbnb', ['airbnb']),
  ('Autostrade per l\'Italia', ['autostrade per l\'italia']),
  ('Telepass', ['telepass']),
  ('BRT', ['brt s.p.a', 'bartolini']),
  ('GLS', ['gls italy']),
  ('DHL', ['dhl']),
  ('UPS', ['united parcel service']),
];

final RegExp _word = RegExp(r'[a-z0-9]');

int _firstIndex(String normText, String phrase) {
  final n = normalize(phrase);
  var from = 0;
  while (true) {
    final i = normText.indexOf(n, from);
    if (i < 0) return -1;
    final beforeOk = i == 0 || !_word.hasMatch(normText[i - 1]);
    final end = i + n.length;
    final afterOk = end >= normText.length || !_word.hasMatch(normText[end]);
    if (beforeOk && afterOk) return i;
    from = i + 1;
  }
}

/// Il tipo di documento più probabile. Ogni frase trovata vale un punto;
/// le frasi nell'intestazione (prime 25 righe) valgono di più; i tipi
/// generici valgono la metà.
DocKind? detectKindEntry(String raw) {
  final text = cleanContent(raw);
  final t = normalize(text.length > 8000 ? text.substring(0, 8000) : text);
  var headEnd = t.length;
  var lines = 0;
  for (var i = 0; i < t.length; i++) {
    if (t.codeUnitAt(i) == 10 && ++lines == 25) {
      headEnd = i;
      break;
    }
  }
  DocKind? best;
  var bestScore = 0.0;
  for (final k in documentKinds) {
    var hits = 0;
    var inHead = false;
    for (final p in k.phrases) {
      final i = _firstIndex(t, p);
      if (i < 0) continue;
      hits++;
      if (i < headEnd) inHead = true;
    }
    if (hits == 0) continue;
    var score = hits * 10.0 + (inHead ? 15 : 0);
    if (k.weak) score /= 2;
    if (score > bestScore) {
      bestScore = score;
      best = k;
    }
  }
  return best;
}

/// Che documento è, nello specifico (es. "Bonifico", "Visura catastale").
String? detectKind(String text) => detectKindEntry(text)?.name;

/// L'ente o l'azienda che compare per primo nel testo (di solito
/// l'intestazione); se non è tra quelli noti, cerca professionisti
/// (notaio, avvocato, studio…) e società (S.p.A., S.r.l.…) nell'intestazione.
String? detectIssuer(String raw) {
  final text = cleanContent(raw);
  return _knownIssuer(text) ?? _publicBody(text) ?? _professional(text) ?? _company(text);
}

/// Enti con un nome proprio: Comune di X, ASL/ATS/ASST X, scuole, ospedali…
/// Solo se compaiono nell'intestazione (prime righe).
String? _publicBody(String text) {
  final head = text.split('\n').take(15).join('\n');
  final patterns = <RegExp>[
    RegExp(r"\b(Comune di|Citt[àa] di|Regione|Provincia di|Citt[àa] Metropolitana di)\s+([A-ZÀ-Ý][A-Za-zÀ-ÿ'\- ]{2,30}?)(?=\s{2,}|\s*\n|\s*[,(\-]|$)"),
    RegExp(r"\b(ASL|ATS|ASST|ASP|AUSL|ULSS|AOU|ASUR|ASLT)\s+([A-ZÀ-Ý0-9][A-Za-zÀ-ÿ0-9'\- ]{1,60}?)(?=\s{2,}|\s*\n|\s*[,(]|$)"),
    RegExp(r'''\b(Universit[àa] degli Studi di|Politecnico di|Istituto Comprensivo|Istituto Tecnico|Istituto Professionale|Liceo(?: Scientifico| Classico| Linguistico| Artistico)?|Scuola (?:Primaria|Secondaria|dell'Infanzia))\s+([A-ZÀ-Ý"][A-Za-zÀ-ÿ'". ]{1,40}?)(?=\s{2,}|\s*\n|\s*[,(\-]|$)'''),
    RegExp(r"\b(Ospedale|Policlinico|Azienda Ospedaliera|Fondazione|Casa di Cura|Poliambulatorio|Farmacia)\s+([A-ZÀ-Ý][A-Za-zÀ-ÿ'. ]{2,40}?)(?=\s{2,}|\s*\n|\s*[,(\-]|$)"),
  ];
  for (final re in patterns) {
    final m = re.firstMatch(head);
    if (m == null) continue;
    final name = _cleanName(m.group(2)!.replaceAll('"', ''));
    if (name.length < 2) continue;
    return '${m.group(1)!} $name';
  }
  return null;
}

/// Prima riga che sembra un titolo (es. "Comunicazione variazione tariffe"),
/// per i documenti di tipo sconosciuto.
String? detectHeading(String raw) {
  final text = cleanContent(raw);
  const keywords = [
    'oggetto', 'comunicazione', 'avviso', 'richiesta', 'conferma', 'attestazione', 'attestato',
    'certificato', 'certificazione', 'dichiarazione', 'modulo', 'domanda', 'informativa', 'notifica',
    'sollecito', 'ricevuta', 'verbale', 'contratto', 'autorizzazione', 'esito', 'convocazione',
    'rendiconto', 'prospetto', 'riepilogo', 'relazione', 'preventivo', 'offerta', 'proposta',
    'lettera', 'delibera', 'decreto', 'sentenza', 'ordinanza', 'istanza', 'ricorso', 'denuncia',
    'segnalazione', 'scheda', 'piano', 'regolamento', 'condizioni', 'nota', 'variazione', 'rinnovo',
  ];
  final skip = RegExp(
    r"(@|www\.|https?:|\btel\b|\bfax\b|p\.?\s?iva|c\.?\s?f\.|codice fiscale|\bvia\b|\bviale\b|\bpiazza\b|\bcorso\b|\bcap\b|\biban\b|pagina \d|^\s*\d)",
    caseSensitive: false,
  );
  String? best;
  var bestScore = 0;
  var n = 0;
  for (final raw in text.split('\n')) {
    if (++n > 60) break;
    for (final part in raw.split(RegExp(r'\s{3,}'))) {
      final line = part.trim();
      if (line.length < 6 || line.length > 80 || skip.hasMatch(line)) continue;
      final letters = RegExp(r'[A-Za-zÀ-ÿ]').allMatches(line).length;
      if (letters < line.replaceAll(' ', '').length * 0.75) continue;
      final words = line.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
      if (words.length < 2 || words.length > 10) continue;
      final lower = normalize(line);
      var score = 1;
      if (keywords.any((k) => RegExp('\\b$k\\b').hasMatch(lower))) score += 4;
      if (words.length >= 3 && words.length <= 8) score += 1;
      if (line == line.toUpperCase() && words.length <= 3) score -= 2; // probabilmente un nome
      if (RegExp(r'^(egr|gent|spett|alla|al|ai|sig)\b', caseSensitive: false).hasMatch(line)) score -= 3;
      if (score > bestScore) {
        bestScore = score;
        best = line;
      }
    }
  }
  if (best == null || bestScore < 5) return null;
  var h = best.replaceAll(RegExp(r'^oggetto\s*[:\-]\s*', caseSensitive: false), '');
  if (h == h.toUpperCase()) h = _cleanName(h);
  if (h.length > 60) h = '${h.substring(0, 60).trim()}…';
  return h[0].toUpperCase() + h.substring(1);
}

String? _professional(String text) {
  final head = text.length > 2500 ? text.substring(0, 2500) : text;
  // "Giuliani arch. Guido", "ROSSI dott. Mario" -> "Arch. Guido Giuliani".
  final inverted = RegExp(
    r"\b([A-ZÀ-Ý][A-Za-zÀ-ÿ']{2,})[ \t]+(arch|geom|dott|ing|avv|rag|notaio)\.?[ \t]+([A-ZÀ-Ý][a-zà-ÿ]{2,})\b",
    caseSensitive: false,
  ).firstMatch(head);
  if (inverted != null &&
      RegExp(r'^[A-ZÀ-Ý]').hasMatch(inverted.group(1)!) &&
      RegExp(r'^[A-ZÀ-Ý]').hasMatch(inverted.group(3)!)) {
    final t = inverted.group(2)!.toLowerCase();
    final title = t == 'notaio' ? 'Notaio' : '${t[0].toUpperCase()}${t.substring(1)}.';
    return '$title ${_cleanName(inverted.group(3)!)} ${_cleanName(inverted.group(1)!)}';
  }
  final re = RegExp(
    r"\b(Notaio(?: Dott\.?)?|Avv\.|Avvocato|Studio (?:Notarile|Legale|Medico|Dentistico|Tecnico|Commercialista)|Dott\.(?:ssa)?|Dr\.|Geom\.|Ing\.|Arch\.|Rag\.)[ \t]+([A-ZÀ-Ý][A-Za-zÀ-ÿ'.]+(?:[ \t][A-ZÀ-Ý][A-Za-zÀ-ÿ'.]+){0,3})",
  );
  String? studio;
  for (final m in re.allMatches(head)) {
    final title = m.group(1)!.replaceAll(RegExp(r'\s+'), ' ');
    final name = _cleanName(m.group(2)!.split(RegExp(r'\s{2,}')).first);
    final words = name.split(' ').where((w) => w.length > 1).toList();
    if (title.startsWith('Studio')) {
      studio ??= '$title $name';
      continue;
    }
    // Un professionista con nome e cognome è il più preciso.
    if (words.length >= 2) return '$title $name';
  }
  return studio;
}

String? _company(String text) {
  final head = text.length > 2500 ? text.substring(0, 2500) : text;
  final m = RegExp(
    r"([A-ZÀ-Ý0-9][A-Za-zÀ-ÿ0-9&'.\- ]{1,40}?)\s*(S\.?\s?p\.?\s?A\.?|S\.?\s?r\.?\s?l\.?(?:s\.?)?|S\.?\s?n\.?\s?c\.?|S\.?\s?a\.?\s?s\.?)(?![A-Za-z])",
  ).firstMatch(head);
  if (m == null) return null;
  final name = _cleanName(m.group(1)!.trim().split(RegExp(r'\s{2,}')).last);
  if (name.length < 2) return null;
  return name;
}

String? _knownIssuer(String text) {
  final t = normalize(text.length > 8000 ? text.substring(0, 8000) : text);
  String? best;
  var bestPos = 1 << 30;
  for (final (name, aliases) in knownIssuers) {
    for (final a in aliases) {
      final i = _firstIndex(t, a);
      if (i >= 0 && i < bestPos) {
        bestPos = i;
        best = name;
      }
    }
  }
  return best;
}

String? _normalizeAmount(String raw) {
  var s = raw.replaceAll(' ', '');
  if (!s.contains(',') && s.contains('.')) {
    // 150.00 -> 150,00
    final dot = s.lastIndexOf('.');
    s = '${s.substring(0, dot)},${s.substring(dot + 1)}';
  }
  final intPart = s.split(',').first.replaceAll('.', '');
  final dec = s.contains(',') ? s.split(',').last : '00';
  final n = int.tryParse(intPart);
  if (n == null) return null;
  final digits = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) b.write('.');
    b.write(digits[i]);
  }
  return '$b,$dec €';
}

/// Parole che precedono l'importo principale, dalla più affidabile.
const List<String> _amountLabels = [
  r'importo\s+pagato',
  r'totale\s+pagato',
  r'netto\s+(?:a|da)\s+pagare',
  r'totale\s+da\s+pagare',
  r'importo\s+da\s+pagare',
  r'totale\s+(?:documento|fattura|bolletta|complessivo|lordo|generale)',
  r'importo\s+(?:bonifico|operazione|disposto|totale|addebitato|accreditato)',
  r'da\s+pagare',
  r'saldo\s+finale',
  r'importo',
  r'totale',
  r'ammontare',
];

const String _number = r'(\d{1,3}(?:[.\s]\d{3})*,\d{2}|\d+,\d{2}|\d+\.\d{2}(?!\d))';

/// L'importo principale (es. "150,00 €"), cercato vicino a parole come
/// "importo pagato", "totale da pagare", "importo".
String? detectAmount(String text) {
  final t = text.replaceAll(' ', ' ');
  for (final label in _amountLabels) {
    // Sulla stessa riga, dopo l'etichetta (al massimo qualche parola in mezzo).
    final m = RegExp(
      '\\b$label\\b[^\\n\\d]{0,25}?(?:euro|eur|€)?\\s*$_number',
      caseSensitive: false,
    ).firstMatch(t);
    if (m != null) return _normalizeAmount(m.group(1)!);
  }
  final euro = RegExp(
    r'(?:€|eur|euro)\s*(\d{1,3}(?:[.\s]\d{3})*,\d{2}|\d+,\d{2})|(\d{1,3}(?:[.\s]\d{3})*,\d{2}|\d+,\d{2})\s*(?:€|eur\b|euro)',
    caseSensitive: false,
  ).firstMatch(t);
  if (euro != null) return _normalizeAmount(euro.group(1) ?? euro.group(2)!);
  return null;
}

String _cleanName(String s) {
  var out = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  out = out.replaceAll(RegExp(r'[\s,;:.\-]+$'), '');
  if (out.length > 40) out = out.substring(0, 40).trim();
  // Nomi tutti maiuscoli -> iniziali maiuscole.
  if (out == out.toUpperCase() && RegExp(r'[A-Z]').hasMatch(out)) {
    out = out
        .toLowerCase()
        .split(' ')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }
  return out;
}

/// Beneficiario di un bonifico.
String? detectBeneficiary(String text) {
  final m = RegExp(
    r"(?:beneficiario|a favore di|destinatario|intestatario conto beneficiario)\s*[:\-]?\s*\n?\s*([A-Za-zÀ-ÿ][A-Za-zÀ-ÿ' .&]{2,60})",
    caseSensitive: false,
  ).firstMatch(text);
  if (m == null) return null;
  var name = m.group(1)!.split('\n').first;
  // Si ferma prima di altre etichette sulla stessa riga.
  name = name.split(RegExp(r'\s{2,}|\b(?:iban|bic|banca|indirizzo|causale|importo)\b', caseSensitive: false)).first;
  final c = _cleanName(name);
  return c.length < 3 ? null : c;
}

/// Numero del documento (fattura, verbale, polizza…).
String? detectNumber(String text) {
  final m = RegExp(
    r'(?:fattura|nota di credito|verbale|polizza|preventivo|ordine|documento)\s*(?:n\.?|nr\.?|num\.?|numero|no\.?)\s*[:°]?\s*([A-Z0-9][A-Z0-9/\-_.]{0,20})',
    caseSensitive: false,
  ).firstMatch(text);
  final n = m?.group(1)?.replaceAll(RegExp(r'[.\-/]+$'), '');
  return n == null || n.isEmpty ? null : n;
}

/// Gestione o periodo (es. "ordinaria 2025/2026").
String? detectPeriod(String text) {
  final m = RegExp(
    r'\b(ordinaria|straordinaria|riscaldamento|esercizio|gestione)\s+(?:anno\s+)?(\d{4}\s*[/-]\s*\d{2,4}|\d{4})\b',
    caseSensitive: false,
  ).firstMatch(text);
  if (m == null) return null;
  return '${m.group(1)!.toLowerCase()} ${m.group(2)!.replaceAll(' ', '')}';
}

/// Oggetto o causale (es. "Atto di acquisto", "affitto ottobre").
String? detectSubject(String text) {
  final m = RegExp(
    r'(?:^|\n)\s*(?:oggetto|causale|descrizione operazione|motivazione)\s*[:\-]?\s*\n?\s*([^\n]{3,90})',
    caseSensitive: false,
  ).firstMatch(text);
  if (m == null) return null;
  var s = m.group(1)!.split(RegExp(r'\s{3,}')).first;
  // Toglie date, riferimenti e numeri di repertorio in coda.
  s = s.replaceAll(
    RegExp(r'\s+(?:in data|del|dd\.?|data|rep\.?|repertorio|prot\.?|n\.)\s+.*$', caseSensitive: false),
    '',
  );
  s = s.replaceAll(RegExp(r'\s*[-–,;:]\s*$'), '').trim();
  if (s.length > 40) s = '${s.substring(0, 40).trim()}…';
  if (RegExp(r'[A-Za-zÀ-ÿ]{3,}').allMatches(s).isEmpty) return null;
  return s;
}

/// Comune citato (utile per visure e atti).
String? detectMunicipality(String text) {
  final m = RegExp(r"\b[Cc]omune\s+di\s*[:\-]?\s*([A-ZÀ-Ý][A-Za-zÀ-ÿ' ]{1,30}?)(?=\s*(?:\(|\n|,|-|\bcodice\b|\bprovincia\b|$))")
      .firstMatch(text);
  if (m == null) return null;
  final c = _cleanName(m.group(1)!);
  return c.length < 2 ? null : c;
}

/// Dati principali letti dal documento.
class DocFacts {
  DocFacts({
    this.kind,
    this.issuer,
    this.amount,
    this.beneficiary,
    this.number,
    this.municipality,
    this.subject,
    this.period,
    this.heading,
    this.weakKind = false,
  });
  final String? kind;
  final String? issuer;
  final String? amount;
  final String? beneficiary;
  final String? number;
  final String? municipality;
  final String? subject;
  final String? period;

  /// Intestazione, usata come titolo se il tipo non è riconosciuto.
  final String? heading;

  /// Il tipo trovato è generico (es. "Comunicazione").
  final bool weakKind;

  /// Cosa mettere all'inizio del titolo: il tipo, o l'intestazione se il
  /// tipo è generico o sconosciuto.
  String? get label => (kind == null || weakKind) && heading != null ? heading : kind;

  /// Dettaglio da mettere nel nome, a seconda del tipo.
  String get details {
    final parts = <String>[];
    if (kind == 'Bonifico' && beneficiary != null) parts.add('a $beneficiary');
    if (number != null &&
        const {'Fattura', 'Nota di credito', 'Preventivo', 'Multa', 'Polizza assicurativa', 'Conferma d\'ordine', 'Cartella esattoriale', 'Avviso di accertamento', 'Sollecito di pagamento'}
            .contains(kind)) {
      parts.add('n. $number');
    }
    if (municipality != null &&
        const {'Visura catastale', 'Visura ipotecaria', 'Planimetria catastale', 'Atto di compravendita', 'IMU', 'TARI', 'Pratica edilizia', 'Certificato anagrafico'}.contains(kind)) {
      parts.add('Comune di $municipality');
    }
    if (period != null &&
        const {'Estratto conto condominiale', 'Verbale di assemblea condominiale', 'Convocazione assemblea condominiale', 'Preventivo condominiale', 'Estratto conto', 'Busta paga', 'Certificazione Unica', 'Dichiarazione dei redditi', 'Pagella'}.contains(kind)) {
      parts.add(period!);
    }
    if (subject != null &&
        const {'Fattura', 'Nota di credito', 'Ricevuta di pagamento', 'Bonifico', 'Preventivo', 'Scontrino', 'Avviso di pagamento PagoPA', 'Sollecito di pagamento', 'Raccomandata', 'Comunicazione', null}
            .contains(kind) &&
        !parts.any((p) => p.toLowerCase().contains(subject!.toLowerCase()))) {
      parts.add('($subject)');
    }
    return parts.join(' ');
  }

  /// L'importo ha senso nel nome solo per pagamenti e simili.
  bool get amountUseful =>
      amount != null &&
      (kind == null ||
          kind!.startsWith('Bolletta') ||
          const {
            'Fattura', 'Nota di credito', 'Bonifico', 'Ricevuta di pagamento', 'Scontrino', 'F24',
            'Avviso di pagamento PagoPA', 'Cartella esattoriale', 'Avviso di accertamento',
            'Comunicazione di irregolarità', 'IMU', 'TARI', 'Multa', 'Bollo auto', 'Canone RAI',
            'Quietanza assicurativa', 'Preventivo', 'Conferma d\'ordine', 'Sollecito di pagamento',
            'Addebito diretto', 'Biglietto aereo', 'Biglietto treno', 'Prenotazione alloggio',
            'Tasse universitarie', 'Retta scolastica', 'Rimborso fiscale', 'Tagliando auto',
          }.contains(kind));
}

DocFacts extractFacts(String raw) {
  final text = cleanContent(raw);
  final entry = detectKindEntry(text);
  final kind = entry?.name;
  final weak = entry?.weak ?? false;
  return DocFacts(
    kind: kind,
    issuer: detectIssuer(text),
    amount: detectAmount(text),
    beneficiary: kind == 'Bonifico' ? detectBeneficiary(text) : null,
    number: detectNumber(text),
    municipality: detectMunicipality(text),
    subject: detectSubject(text),
    period: detectPeriod(text),
    heading: kind == null || weak ? detectHeading(text) : null,
    weakKind: weak,
  );
}

// ---------------------------------------------------------------------------
// Nome del file originale

final RegExp _genericName = RegExp(
  r'^(?:img|image|immagine|pxl|dsc|dcim|photo|foto|screenshot|schermata|whatsapp\s*(?:image|immagine)?|'
  r'scan|scansione|scanned|document|documento|doc|file|download|pdf|stampa|print|allegato|attachment|'
  r'cam|camscanner|adobe\s*scan|untitled|senza\s*titolo|nuovo\s*documento|new\s*document)?'
  r'[\s_\-.()\d]*(?:at|alle|del)?[\s_\-.()\d]*$',
  caseSensitive: false,
);

bool _looksRandom(String t) {
  if (t.length < 10) return false;
  final hasDigit = RegExp(r'\d').hasMatch(t);
  final hasLetter = RegExp(r'[A-Za-z]').hasMatch(t);
  final caseChanges = RegExp(r'[a-z][A-Z]|[A-Z]{2}[a-z]').allMatches(t).length;
  return (hasDigit && hasLetter) || caseChanges >= 2;
}

/// Il nome del file, ripulito, se è già descrittivo (es. "Visura catastale
/// casa via Roma"); null se è generico (IMG_1234, scan001, documento…).
String? meaningfulFileName(String originalName) {
  var base = originalName;
  final dot = base.lastIndexOf('.');
  if (dot > 0) base = base.substring(0, dot);
  base = base.replaceAll(RegExp(r'[_]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (base.isEmpty || _genericName.hasMatch(base)) return null;
  if (RegExp(r'^scansione \d', caseSensitive: false).hasMatch(base)) return null;
  // Servono almeno due parole "vere" (3+ lettere) oppure una parola lunga.
  final words = RegExp(r'[A-Za-zÀ-ÿ]{3,}').allMatches(base).map((m) => m.group(0)!).toList();
  final letters = RegExp(r'[A-Za-zÀ-ÿ]').allMatches(base).length;
  final chars = base.replaceAll(' ', '').length;
  final digits = RegExp(r'\d').allMatches(base).length;
  if (words.length < 2 || letters < chars * 0.5 || digits > chars * 0.25) return null;
  // Parole abbreviate ("Fatt.", "Elettr.") o di servizio non descrivono il documento.
  const filler = {
    'stampa', 'copia', 'file', 'scan', 'pdf', 'doc', 'documento', 'allegato', 'print',
    'fatt', 'elettr', 'ric', 'rif', 'prot', 'img', 'download', 'definitivo', 'firmato', 'final',
  };
  final real = words.where((w) {
    final lw = w.toLowerCase();
    if (filler.contains(lw)) return false;
    final i = base.indexOf(w) + w.length;
    final abbreviated = i < base.length && base[i] == '.' && w.length <= 6;
    return !abbreviated && w.length >= 4;
  }).toList();
  if (real.length < 2) return null;
  // Nomi generati da un programma: contengono codici casuali (es. "AACJebECKw4Dk").
  for (final token in base.split(RegExp(r'[\s_\-.]+'))) {
    if (_looksRandom(token)) return null;
  }
  // Codici tipo hash o numeri di pratica non sono nomi.
  if (RegExp(r'^[a-f0-9\- ]{12,}$', caseSensitive: false).hasMatch(base)) return null;
  // Spaziature dopo trattini/punti.
  base = base.replaceAll(RegExp(r'\s*-\s*'), ' - ').replaceAll(RegExp(r'\s+'), ' ').trim();
  return base[0].toUpperCase() + base.substring(1);
}
