/// Lettura "specifica" di un documento: che cos'è esattamente (bonifico,
/// visura catastale, F24…), chi l'ha emesso, importo, beneficiario, numero.
/// Serve a dare nomi descrittivi in automatico.
library;

import 'text_utils.dart';

/// Tipi specifici di documento: (nome, frasi che lo identificano).
/// L'ordine conta: i più specifici prima.
const List<(String, List<String>)> documentKinds = [
  ('Visura catastale', ['visura catastale', 'visura per immobile', 'visura per soggetto', 'catasto fabbricati', 'catasto terreni', 'visura storica per immobile']),
  ('Visura camerale', ['visura camerale', 'visura ordinaria societa', 'registro delle imprese']),
  ('Planimetria catastale', ['planimetria catastale', 'planimetria di u.i.u']),
  ('Atto di compravendita', ['atto di compravendita', 'rogito', 'compravendita immobiliare']),
  ('Contratto di locazione', ['contratto di locazione', 'locazione ad uso abitativo', 'contratto di affitto']),
  ('Certificazione Unica', ['certificazione unica']),
  ('Dichiarazione dei redditi', ['modello 730', '730/2', '730-3', 'modello redditi', 'dichiarazione dei redditi']),
  ('F24', ['modello f24', 'delega f24', 'f24 semplificato', 'f24']),
  ('Avviso di pagamento PagoPA', ['avviso di pagamento', 'pagopa']),
  ('Cartella esattoriale', ['cartella di pagamento', 'agenzia delle entrate-riscossione', 'agenzia delle entrate riscossione']),
  ('IMU', ['imposta municipale propria', 'imu']),
  ('TARI', ['tassa sui rifiuti', 'tari']),
  ('Multa', ['verbale di contestazione', 'codice della strada', 'violazione dell\'art']),
  ('Bollo auto', ['tassa automobilistica', 'bollo auto']),
  ('Busta paga', ['busta paga', 'cedolino', 'prospetto paga', 'netto in busta']),
  ('Estratto conto', ['estratto conto', 'estratto di conto', 'rendiconto carta', 'documento di sintesi']),
  ('Bonifico', ['bonifico istantaneo', 'disposizione di bonifico', 'ordine di bonifico', 'esito bonifico', 'sepa credit transfer', 'bonifico']),
  ('Nota di credito', ['nota di credito']),
  ('Bolletta luce', ['energia elettrica', 'kwh', 'fornitura di energia']),
  ('Bolletta gas', ['gas naturale', 'smc', 'fornitura di gas']),
  ('Bolletta acqua', ['servizio idrico', 'fornitura idrica', 'acquedotto']),
  ('Bolletta telefono e internet', ['fibra ottica', 'linea fissa', 'telefonia', 'traffico dati']),
  ('Fattura', ['fattura elettronica', 'fattura n', 'fattura nr', 'fattura numero', 'fattura']),
  ('Preventivo', ['preventivo', 'offerta economica']),
  ('Conferma d\'ordine', ['conferma d\'ordine', 'riepilogo dell\'ordine', 'riepilogo ordine']),
  ('Scontrino', ['documento commerciale', 'scontrino']),
  ('Ricevuta di pagamento', ['ricevuta di pagamento', 'quietanza', 'ricevuta']),
  ('Referto', ['referto', 'esito esame']),
  ('Ricetta medica', ['ricetta elettronica', 'promemoria per l\'assistito', 'ricetta medica']),
  ('Certificato medico', ['certificato medico', 'certificato di malattia']),
  ('Polizza assicurativa', ['polizza', 'certificato di assicurazione']),
  ('Carta di circolazione', ['carta di circolazione', 'libretto di circolazione']),
  ('Verbale di assemblea', ['verbale di assemblea', 'assemblea condominiale']),
  ('Certificato', ['certificato di', 'si certifica']),
  ('Contratto', ['contratto', 'le parti convengono']),
  ('Garanzia', ['certificato di garanzia', 'garanzia legale']),
];

/// Enti ed aziende riconosciuti: (nome da usare, varianti nel testo).
const List<(String, List<String>)> knownIssuers = [
  // Banche e pagamenti
  ('Intesa Sanpaolo', ['intesa sanpaolo', 'intesa san paolo']),
  ('UniCredit', ['unicredit']),
  ('Banco BPM', ['banco bpm']),
  ('BPER Banca', ['bper banca', 'bper']),
  ('Banca Monte dei Paschi di Siena', ['monte dei paschi', 'mps']),
  ('BNL', ['banca nazionale del lavoro', 'bnl']),
  ('Crédit Agricole', ['credit agricole']),
  ('Fineco', ['fineco']),
  ('Mediolanum', ['mediolanum']),
  ('ING', ['ing bank', 'ing direct', 'ing italia']),
  ('Poste Italiane', ['poste italiane', 'bancoposta', 'postepay']),
  ('Banca Sella', ['banca sella']),
  ('Credem', ['credem', 'credito emiliano']),
  ('Banca Popolare di Sondrio', ['popolare di sondrio']),
  ('Widiba', ['widiba']),
  ('Hype', ['hype']),
  ('N26', ['n26']),
  ('Revolut', ['revolut']),
  ('PayPal', ['paypal']),
  ('Satispay', ['satispay']),
  ('American Express', ['american express']),
  ('Nexi', ['nexi']),
  // Energia, acqua, telefonia
  ('Enel', ['enel energia', 'servizio elettrico nazionale', 'enel']),
  ('Eni Plenitude', ['eni plenitude', 'plenitude', 'eni gas e luce']),
  ('A2A', ['a2a']),
  ('Hera', ['hera comm', 'gruppo hera']),
  ('Iren', ['iren']),
  ('Acea', ['acea']),
  ('Edison', ['edison energia', 'edison']),
  ('Sorgenia', ['sorgenia']),
  ('Engie', ['engie']),
  ('Illumia', ['illumia']),
  ('TIM', ['telecom italia', 'tim s.p.a', 'tim spa']),
  ('Vodafone', ['vodafone']),
  ('WindTre', ['windtre', 'wind tre']),
  ('Iliad', ['iliad']),
  ('Fastweb', ['fastweb']),
  ('Sky', ['sky italia']),
  // Enti pubblici
  ('Agenzia delle Entrate', ['agenzia delle entrate']),
  ('Agenzia delle Entrate-Riscossione', ['agenzia delle entrate-riscossione', 'agenzia delle entrate riscossione']),
  ('INPS', ['inps', 'istituto nazionale della previdenza sociale']),
  ('INAIL', ['inail']),
  ('ACI', ['automobile club d\'italia', 'aci']),
  ('Motorizzazione Civile', ['motorizzazione civile']),
  ('Ministero dell\'Interno', ['ministero dell\'interno']),
  // Assicurazioni
  ('Generali', ['assicurazioni generali', 'generali italia']),
  ('UnipolSai', ['unipolsai', 'unipol']),
  ('Allianz', ['allianz']),
  ('AXA', ['axa']),
  ('Reale Mutua', ['reale mutua']),
  ('Zurich', ['zurich']),
  ('Linear', ['linear assicurazioni']),
  ('Prima Assicurazioni', ['prima assicurazioni']),
  ('Verti', ['verti']),
  ('Genertel', ['genertel']),
  // Commercio e servizi
  ('Amazon', ['amazon']),
  ('IKEA', ['ikea']),
  ('MediaWorld', ['mediaworld']),
  ('Unieuro', ['unieuro']),
  ('Trenitalia', ['trenitalia']),
  ('Italo', ['italo treno', 'ntv']),
  ('Autostrade per l\'Italia', ['autostrade per l\'italia', 'telepass']),
];

final RegExp _word = RegExp(r'[a-z0-9]');

bool _hasPhrase(String normText, String phrase) {
  final n = normalize(phrase);
  var from = 0;
  while (true) {
    final i = normText.indexOf(n, from);
    if (i < 0) return false;
    final beforeOk = i == 0 || !_word.hasMatch(normText[i - 1]);
    final end = i + n.length;
    final afterOk = end >= normText.length || !_word.hasMatch(normText[end]);
    if (beforeOk && afterOk) return true;
    from = i + 1;
  }
}

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

/// Che documento è, nello specifico (es. "Bonifico", "Visura catastale").
String? detectKind(String text) {
  final t = normalize(text.length > 6000 ? text.substring(0, 6000) : text);
  for (final (name, phrases) in documentKinds) {
    if (phrases.any((p) => _hasPhrase(t, p))) return name;
  }
  return null;
}

/// L'ente o l'azienda che compare per primo nel testo (di solito
/// l'intestazione); se non è tra quelli noti, cerca professionisti
/// (notaio, avvocato, studio…) e società (S.p.A., S.r.l.…) nell'intestazione.
String? detectIssuer(String text) => _knownIssuer(text) ?? _professional(text) ?? _company(text);

String? _professional(String text) {
  final head = text.length > 2500 ? text.substring(0, 2500) : text;
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
  });
  final String? kind;
  final String? issuer;
  final String? amount;
  final String? beneficiary;
  final String? number;
  final String? municipality;
  final String? subject;

  /// Dettaglio da mettere nel nome, a seconda del tipo.
  String get details {
    final parts = <String>[];
    if (kind == 'Bonifico' && beneficiary != null) parts.add('a $beneficiary');
    if (number != null &&
        const {'Fattura', 'Nota di credito', 'Preventivo', 'Multa', 'Polizza assicurativa', 'Conferma d\'ordine'}
            .contains(kind)) {
      parts.add('n. $number');
    }
    if (municipality != null &&
        const {'Visura catastale', 'Planimetria catastale', 'Atto di compravendita', 'IMU', 'TARI'}.contains(kind)) {
      parts.add('Comune di $municipality');
    }
    if (subject != null &&
        const {'Fattura', 'Nota di credito', 'Ricevuta di pagamento', 'Bonifico', 'Preventivo', 'Scontrino', 'Avviso di pagamento PagoPA', null}
            .contains(kind) &&
        !parts.any((p) => p.toLowerCase().contains(subject!.toLowerCase()))) {
      parts.add('($subject)');
    }
    return parts.join(' ');
  }

  /// L'importo ha senso nel nome solo per pagamenti e simili.
  bool get amountUseful =>
      amount != null &&
      !const {
        'Visura catastale',
        'Visura camerale',
        'Planimetria catastale',
        'Atto di compravendita',
        'Contratto di locazione',
        'Contratto',
        'Certificazione Unica',
        'Dichiarazione dei redditi',
        'Estratto conto',
        'Referto',
        'Ricetta medica',
        'Certificato medico',
        'Certificato',
        'Carta di circolazione',
        'Verbale di assemblea',
        'Garanzia',
        'Busta paga',
      }.contains(kind);
}

DocFacts extractFacts(String text) {
  final kind = detectKind(text);
  return DocFacts(
    kind: kind,
    issuer: detectIssuer(text),
    amount: detectAmount(text),
    beneficiary: kind == 'Bonifico' ? detectBeneficiary(text) : null,
    number: detectNumber(text),
    municipality: detectMunicipality(text),
    subject: detectSubject(text),
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
  // Codici tipo hash o numeri di pratica non sono nomi.
  if (RegExp(r'^[a-f0-9\- ]{12,}$', caseSensitive: false).hasMatch(base)) return null;
  // Spaziature dopo trattini/punti.
  base = base.replaceAll(RegExp(r'\s*-\s*'), ' - ').replaceAll(RegExp(r'\s+'), ' ').trim();
  return base[0].toUpperCase() + base.substring(1);
}
