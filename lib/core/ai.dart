/// AI sul telefono: il prompt per il modello linguistico locale, la lettura
/// della sua risposta e come applicarla al documento.
///
/// Qui c'è solo la logica pura (testata in CI); il modello gira in
/// `services/ai_assistant.dart`.
library;

import 'dart:convert';

import 'archive.dart';
import 'dates.dart';
import 'extract.dart' show meaningfulFileName;
import 'matching.dart' show cosine, matchesRule, matchText, termVector;
import 'models.dart';
import 'organize.dart' show learnedTitle;
import 'text_utils.dart';

/// Cosa ha capito il modello del documento.
class AiResult {
  AiResult({
    this.category,
    this.kind,
    this.title,
    this.sender,
    this.date,
    this.amount,
    this.tags = const [],
  });

  final String? category;
  final String? kind;
  final String? title;
  final String? sender;
  final DateTime? date;
  final String? amount;
  final List<String> tags;

  bool get isEmpty =>
      category == null && kind == null && title == null && sender == null && date == null;

  @override
  String toString() => 'AiResult(categoria: $category, tipo: $kind, titolo: $title, '
      'mittente: $sender, data: $date, importo: $amount, tag: $tags)';
}

/// Il testo del documento, accorciato per stare nel contesto del modello:
/// l'inizio (intestazione, mittente, oggetto) è la parte più utile.
String aiDocumentText(String content, {int maxChars = 5000}) {
  var t = content
      .replaceAll('\r', '')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r'\n\s*\n+'), '\n')
      .trim();
  if (t.length > maxChars) {
    final head = (maxChars * 0.8).round();
    t = '${t.substring(0, head)}\n[…]\n${t.substring(t.length - (maxChars - head))}';
  }
  return t;
}

/// Il prompt: categorie e mittenti già usati nell'archivio, così il modello
/// sceglie quelli invece di inventarne di nuovi.
String buildAiPrompt(Archive a, Document d, {int maxChars = 5000}) {
  final cats = a.activeTypes.map((t) => t.name).toList();
  final senders = a.activeCorrespondents.map((c) => c.name).take(60).toList();
  final tags = a.activeTags.where((t) => !t.isInbox).map((t) => t.name).take(40).toList();
  final b = StringBuffer()
    ..writeln('Sei l\'archivista di un archivio di documenti personali italiano.')
    ..writeln('Leggi il documento e rispondi SOLO con un oggetto JSON, senza altro testo, con queste chiavi:')
    ..writeln('"categoria": una delle categorie esistenti; solo se nessuna va bene, una nuova di una o due parole;')
    ..writeln('"tipo": che documento è, preciso (es. "Fattura luce", "Etichetta di spedizione", "Ricevuta bonifico", "Visura catastale");')
    ..writeln('"titolo": nome del file chiaro e specifico, 3-8 parole: tipo + dettaglio importante + mittente (es. "Fattura luce Enel marzo 2024", "Etichetta spedizione Vinted InPost", "Bonifico affitto a Mario Rossi"); niente data completa, niente estensione;')
    ..writeln('"mittente": chi ha emesso o inviato il documento (azienda, ente o persona), nome breve, oppure null;')
    ..writeln('"data": data del documento in formato AAAA-MM-GG (emissione, non scadenza né date di nascita o di leggi), oppure null;')
    ..writeln('"importo": importo totale con la virgola (es. "123,45"), oppure null;')
    ..writeln('"tag": lista di tag esistenti adatti (anche vuota).')
    ..writeln()
    ..writeln('Categorie esistenti: ${cats.isEmpty ? '(nessuna)' : cats.join(', ')}');
  if (senders.isNotEmpty) b.writeln('Mittenti già in archivio: ${senders.join(', ')}');
  if (tags.isNotEmpty) b.writeln('Tag esistenti: ${tags.join(', ')}');
  b
    ..writeln('Nome del file: ${d.originalName}')
    ..writeln()
    ..writeln('Documento:')
    ..writeln('"""')
    ..writeln(aiDocumentText(d.content, maxChars: maxChars))
    ..writeln('"""');
  return b.toString();
}

String? _str(Object? v, {int max = 120}) {
  if (v == null) return null;
  if (v is List) v = v.isEmpty ? null : v.first;
  if (v == null || v is Map) return null;
  var s = v.toString().trim();
  s = s.replaceAll(RegExp(r'\s+'), ' ');
  // Valori "vuoti" che i modelli piccoli scrivono al posto di null.
  final low = normalize(s);
  if (s.isEmpty ||
      const {'null', 'none', 'n/a', 'na', 'nessuno', 'nessuna', 'sconosciuto', 'non disponibile', 'non specificato', '-', '?'}
          .contains(low)) {
    return null;
  }
  if (s.length > max) s = s.substring(0, max).trim();
  return s;
}

DateTime? _date(Object? v, {DateTime? now}) {
  final s = _str(v);
  if (s == null) return null;
  final n = now ?? DateTime.now();
  DateTime? d;
  final iso = RegExp(r'(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(s);
  if (iso != null) {
    d = _valid(int.parse(iso[1]!), int.parse(iso[2]!), int.parse(iso[3]!));
  } else {
    final found = findDates(s, now: n);
    if (found.isNotEmpty) d = found.first;
  }
  if (d == null || d.year < 1900 || d.isAfter(n.add(const Duration(days: 1)))) return null;
  return d;
}

DateTime? _valid(int y, int m, int d) {
  if (m < 1 || m > 12 || d < 1 || d > 31) return null;
  final dt = DateTime(y, m, d);
  return dt.month == m ? dt : null;
}

/// Legge la risposta del modello: accetta JSON dentro ```…```, testo prima o
/// dopo, chiavi in italiano o in inglese.
AiResult? parseAiResponse(String raw, {DateTime? now}) {
  final start = raw.indexOf('{');
  final end = raw.lastIndexOf('}');
  if (start < 0 || end <= start) return null;
  var body = raw.substring(start, end + 1);
  Map<String, dynamic>? j;
  for (var attempt = 0; attempt < 2 && j == null; attempt++) {
    try {
      final v = jsonDecode(body);
      if (v is Map<String, dynamic>) j = v;
    } catch (_) {
      // Errori tipici: virgola finale, apici singoli.
      body = body
          .replaceAllMapped(RegExp(r',\s*([}\]])'), (m) => m[1]!)
          .replaceAllMapped(RegExp(r"([{,]\s*)'([^'\n]*)'\s*:"), (m) => '${m[1]}"${m[2]}":')
          .replaceAllMapped(RegExp(r":\s*'([^'\n]*)'(\s*[,}])"), (m) => ': "${m[1]}"${m[2]}');
    }
  }
  if (j == null) return null;
  final m = {for (final e in j.entries) normalize(e.key).replaceAll(RegExp(r'[^a-z]'), ''): e.value};
  Object? pick(List<String> keys) {
    for (final k in keys) {
      if (m.containsKey(k)) return m[k];
    }
    return null;
  }

  final tagsRaw = pick(['tag', 'tags', 'etichette']);
  final tags = <String>[];
  if (tagsRaw is List) {
    for (final t in tagsRaw) {
      final s = _str(t, max: 40);
      if (s != null) tags.add(s);
    }
  } else {
    final s = _str(tagsRaw);
    if (s != null) tags.addAll(s.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty));
  }
  var title = _str(pick(['titolo', 'title', 'nome', 'nomefile']), max: 90);
  if (title != null) {
    title = title.replaceAll(RegExp(r'\.(pdf|jpe?g|png)$', caseSensitive: false), '').trim();
    title = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (title.isEmpty) title = null;
  }
  final amount = _str(pick(['importo', 'amount', 'totale']), max: 20);
  final r = AiResult(
    category: _str(pick(['categoria', 'category']), max: 40),
    kind: _str(pick(['tipo', 'type', 'tipodocumento', 'documenttype']), max: 60),
    title: title,
    sender: _str(pick(['mittente', 'sender', 'correspondent', 'corrispondente', 'emittente']), max: 60),
    date: _date(pick(['data', 'date']), now: now),
    amount: amount != null && RegExp(r'\d').hasMatch(amount) ? amount : null,
    tags: tags,
  );
  return r.isEmpty ? null : r;
}

/// Nome confrontabile: senza accenti, maiuscole, punteggiatura e forme
/// societarie.
String _key(String s) => normalize(s)
    .replaceAll(RegExp(r'\b(s\.?\s?r\.?\s?l|s\.?\s?p\.?\s?a|s\.?\s?n\.?\s?c|s\.?\s?a\.?\s?s|spa|srl|snc|sas|ltd|inc|gmbh)\b\.?'), ' ')
    .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
    .trim();

T? findByName<T extends Matchable>(Iterable<T> items, String name) {
  final k = _key(name);
  if (k.isEmpty) return null;
  for (final e in items) {
    if (_key(e.name) == k) return e;
  }
  // "Enel Energia" ↔ "Enel": uno contenuto nell'altro, a parole intere.
  for (final e in items) {
    final ek = _key(e.name);
    if (ek.length < 3 || k.length < 3) continue;
    if (' $k '.contains(' $ek ') || ' $ek '.contains(' $k ')) return e;
  }
  return null;
}

/// Categoria scelta da una regola dell'utente (non quelle predefinite e non
/// l'algoritmo automatico): ha la precedenza sull'AI.
bool _userRule(Matchable? m, Document d) =>
    m != null &&
    !m.id.startsWith('st-') &&
    m.algorithm != MatchAlgorithm.none &&
    m.algorithm != MatchAlgorithm.auto &&
    matchesRule(m, matchText(d));

/// Il documento corretto a mano dall'utente più simile a [d], con la
/// somiglianza (≥ [min]), oppure (null, 0).
(Document?, double) correctedExample(Archive a, Document d, {double min = 0.5}) {
  final v = termVector(d.content);
  if (v.isEmpty) return (null, 0);
  Document? best;
  var bestScore = min;
  for (final o in a.activeDocuments) {
    if (o.id == d.id || !o.userEdited || o.content.isEmpty) continue;
    final s = cosine(v, termVector(o.content));
    if (s >= bestScore) {
      bestScore = s;
      best = o;
    }
  }
  return best == null ? (null, 0) : (best, bestScore);
}

/// Il nome di file scelto dall'utente o imparato dalle sue correzioni ha la
/// precedenza sul titolo dell'AI.
bool aiMayRetitle(Archive a, Document d) {
  if (!a.config.autoTitle) return false;
  if (learnedTitle(a, d) != null) return false;
  if (a.config.keepFileName && meaningfulFileName(d.originalName) != null) return false;
  return true;
}

/// Applica la risposta dell'AI. Precedenza: regole dell'utente e documenti
/// simili corretti a mano > AI > regole predefinite e classificatore.
/// Restituisce i campi cambiati.
List<String> applyAiResult(
  Archive a,
  Document d,
  AiResult r, {
  bool retitle = true,
}) {
  final changed = <String>[];

  // Un documento simile corretto a mano dall'utente vale più dell'AI.
  final (example, score) = correctedExample(a, d);
  final exType = a.type(example?.typeId);
  final exSender = score >= 0.6 ? a.correspondent(example?.correspondentId) : null;
  final keepType = exType != null;
  final keepSender = exSender != null;
  if (exType != null && d.typeId != exType.id) {
    d.typeId = exType.id;
    changed.add('categoria');
  }
  if (exSender != null && d.correspondentId != exSender.id) {
    d.correspondentId = exSender.id;
    changed.add('mittente');
  }

  // Categoria.
  if (r.category != null && !keepType && !_userRule(a.type(d.typeId), d)) {
    var t = findByName(a.activeTypes, r.category!);
    if (t == null && r.category!.split(' ').length <= 3) {
      final name = r.category![0].toUpperCase() + r.category!.substring(1);
      t = NamedEntity(name: name, algorithm: MatchAlgorithm.auto);
      a.types[t.id] = t;
    }
    if (t != null && t.id != d.typeId) {
      d.typeId = t.id;
      changed.add('categoria');
    }
  }

  // Mittente.
  if (r.sender != null && !keepSender && !_userRule(a.correspondent(d.correspondentId), d)) {
    var c = findByName(a.activeCorrespondents, r.sender!);
    if (c == null) {
      c = NamedEntity(name: r.sender!, algorithm: MatchAlgorithm.auto);
      a.correspondents[c.id] = c;
    }
    if (c.id != d.correspondentId) {
      d.correspondentId = c.id;
      changed.add('mittente');
    }
  }

  // Data: solo se compare davvero nel testo (niente date inventate).
  if (r.date != null) {
    final inText = findDates(d.content).any((x) => x.year == r.date!.year && x.month == r.date!.month && x.day == r.date!.day);
    final cur = d.created;
    final same = cur.year == r.date!.year && cur.month == r.date!.month && cur.day == r.date!.day;
    if (inText && !same) {
      d.created = r.date!;
      changed.add('data');
    }
  }

  // Tag esistenti (mai crearne di nuovi).
  for (final name in r.tags) {
    final t = findByName(a.activeTags.where((t) => !t.isInbox), name);
    if (t != null && d.tagIds.add(t.id)) changed.add('tag');
  }

  // Titolo.
  if (retitle && r.title != null && aiMayRetitle(a, d) && r.title != d.title) {
    d.title = r.title!;
    changed.add('titolo');
  }
  return changed;
}
