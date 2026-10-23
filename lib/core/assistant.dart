/// L'assistente "Chiedi": capisce una domanda in italiano ("trovami il
/// referto cardiologico di Maria", "quanto ho speso dal dentista nel
/// 2025"), cerca nell'archivio e risponde. Funziona anche senza AI (regole);
/// con l'AI sul telefono capisce meglio le domande.
///
/// Qui c'è anche l'elenco delle "domande" che l'app fa quando non è sicura
/// (di chi è un documento, che categoria è).
library;

import 'dart:convert';

import 'ai.dart' show findByName;
import 'archive.dart';
import 'dates.dart' show findDates;
import 'extract.dart' show detectAmount;
import 'models.dart';
import 'people.dart';
import 'search.dart' show SearchIndex;
import 'text_utils.dart';

enum AskIntent { find, latest, total, count }

/// La domanda, trasformata in filtri.
class AskQuery {
  AskQuery({
    this.intent = AskIntent.find,
    List<String>? words,
    this.typeId,
    this.correspondentId,
    this.person,
    this.specialty,
    this.healthKind,
    this.year,
    this.from,
    this.to,
  }) : words = words ?? <String>[];

  AskIntent intent;
  List<String> words;
  String? typeId;
  String? correspondentId;
  String? person;
  String? specialty;
  String? healthKind;
  int? year;
  DateTime? from;
  DateTime? to;

  /// Cosa ha capito, in breve (mostrato sopra i risultati).
  String describe(Archive a) {
    final parts = <String>[
      if (typeId != null) a.type(typeId)?.name ?? '',
      if (healthKind != null) healthKind!,
      if (specialty != null) specialty!,
      if (person != null) 'di $person',
      if (correspondentId != null) 'da ${a.correspondent(correspondentId)?.name ?? ''}',
      if (year != null) 'del $year',
      if (from != null && year == null) 'dal ${dateIt(from!)}',
      if (to != null && year == null) 'al ${dateIt(to!)}',
      if (words.isNotEmpty) '"${words.join(' ')}"',
    ].where((e) => e.isNotEmpty).toList();
    return parts.join(' · ');
  }
}

String dateIt(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

const Set<String> _stop = {
  'trova', 'trovami', 'cerca', 'cercami', 'mostra', 'mostrami', 'fammi', 'vedere', 'dammi', 'apri', 'aprimi',
  'dove', 'quale', 'quali', 'qual', 'che', 'chi', 'come', 'quando', 'quanto', 'quanta', 'quanti', 'quante',
  'ho', 'hai', 'abbiamo', 'ha', 'sono', 'stato', 'stata', 'messo', 'messa', 'salvato', 'archiviato',
  'il', 'lo', 'la', 'i', 'gli', 'le', 'un', 'uno', 'una', 'di', 'del', 'della', 'dello', 'dei', 'degli', 'delle',
  'da', 'dal', 'dalla', 'dallo', 'dai', 'dagli', 'dalle', 'a', 'al', 'alla', 'allo', 'ai', 'agli', 'alle',
  'in', 'nel', 'nella', 'nello', 'nei', 'negli', 'nelle', 'per', 'con', 'su', 'sul', 'sulla', 'tra', 'fra',
  'e', 'o', 'ed', 'mio', 'mia', 'miei', 'mie', 'tuo', 'tua', 'suo', 'sua', 'nostro', 'nostra',
  'documento', 'documenti', 'file', 'pdf', 'carta', 'carte', 'tutti', 'tutte', 'ogni',
  'ultimo', 'ultima', 'ultimi', 'ultime', 'recente', 'speso', 'spesi', 'pagato', 'pagati', 'spesa', 'spese',
  'totale', 'anno', 'mese', 'questo', 'questa', 'scorso', 'scorsa', 'quest', 'mi', 'me', 'ti', 'si', 'ci',
  'favore', 'grazie', 'avere', 'voglio', 'vorrei', 'serve', 'servirebbe',
};

const List<String> _monthNames = [
  'gennaio', 'febbraio', 'marzo', 'aprile', 'maggio', 'giugno',
  'luglio', 'agosto', 'settembre', 'ottobre', 'novembre', 'dicembre',
];

/// Parole che indicano la sanità e il tipo di documento sanitario.
const Map<String, String> _healthWords = {
  'referto': 'Referti', 'referti': 'Referti', 'esito': 'Referti', 'esiti': 'Referti', 'esami': 'Referti',
  'analisi': 'Referti', 'ricetta': 'Prescrizioni', 'ricette': 'Prescrizioni', 'prescrizione': 'Prescrizioni',
  'prescrizioni': 'Prescrizioni', 'impegnativa': 'Prescrizioni', 'impegnative': 'Prescrizioni',
};

bool _wordIn(String flat, String w) => RegExp('(?<![a-z0-9])${RegExp.escape(w)}(?![a-z0-9])').hasMatch(flat);

/// Capisce la domanda con le regole (senza AI).
AskQuery parseQuestion(Archive a, String question, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final q = AskQuery();
  final flat = ' ${normalize(question).replaceAll(RegExp(r"[^a-z0-9àèéìòù]+"), ' ').trim()} ';
  final used = <String>{};

  if (RegExp(r'quanto (ho|abbiamo|hai) (speso|pagato)|totale|quanto (costa|e costato|sono costat)|spes[ae] (di|del|per|in)').hasMatch(flat)) {
    q.intent = AskIntent.total;
  } else if (RegExp(r'\bquant[ie]\b').hasMatch(flat)) {
    q.intent = AskIntent.count;
  } else if (RegExp(r'\b(ultim[oaie]|piu recente|recente)\b').hasMatch(flat)) {
    q.intent = AskIntent.latest;
  }

  // Tempo.
  final y = RegExp(r'(?<!\d)(19\d{2}|20\d{2})(?!\d)').firstMatch(flat);
  if (y != null) {
    q.year = int.parse(y[1]!);
    used.add(y[1]!);
  } else if (flat.contains(' quest anno ') || flat.contains(' questo anno ')) {
    q.year = n.year;
  } else if (flat.contains(' anno scorso ') || flat.contains(' scorso anno ')) {
    q.year = n.year - 1;
  }
  for (var m = 0; m < 12; m++) {
    if (_wordIn(flat, _monthNames[m])) {
      final year = q.year ?? (m + 1 > n.month ? n.year - 1 : n.year);
      q
        ..from = DateTime(year, m + 1)
        ..to = DateTime(year, m + 2).subtract(const Duration(days: 1))
        ..year = null;
      used.add(_monthNames[m]);
      break;
    }
  }

  // Persona della famiglia.
  for (final p in a.config.people) {
    for (final alias in [p.name, ...p.aliases]) {
      final words = normalize(alias).split(RegExp(r'\s+')).where((w) => w.length >= 2).toList();
      if (words.isNotEmpty && words.every((w) => _wordIn(flat, w))) {
        q.person = p.name;
        used.addAll(words);
      }
    }
    if (q.person != null) break;
  }

  // Sanità: referti / prescrizioni e specialità.
  for (final e in _healthWords.entries) {
    if (_wordIn(flat, e.key)) {
      q.healthKind = e.value;
      used.add(e.key);
      if (a.type(healthTypeId) != null) q.typeId = healthTypeId;
    }
  }
  final spec = detectSpecialty(flat);
  if (spec != null) {
    q.specialty = spec;
    if (a.type(healthTypeId) != null) q.typeId = healthTypeId;
    for (final (name, words) in specialties) {
      if (name != spec) continue;
      for (final w in words) {
        for (final m in RegExp('(?<![a-z0-9])${RegExp.escape(normalize(w).trim())}[a-z]*').allMatches(flat)) {
          used.add(m[0]!);
        }
      }
    }
  }

  // Categoria (per nome, anche solo la prima parola: "bolletta", "busta paga").
  if (q.typeId == null) {
    for (final t in a.activeTypes) {
      final tn = normalize(t.name);
      final first = tn.split(' ').first;
      if (_wordIn(flat, tn) || (first.length >= 4 && RegExp('(?<![a-z0-9])${RegExp.escape(first.substring(0, first.length - 1))}[a-z]?(?![a-z0-9])').hasMatch(flat))) {
        q.typeId = t.id;
        used.addAll(tn.split(' '));
        used.add(first.substring(0, first.length - 1));
        break;
      }
    }
  }

  // Mittente.
  for (final c in a.activeCorrespondents) {
    final cn = normalize(c.name).replaceAll(RegExp(r'[^a-z0-9 ]'), ' ').trim();
    final words = cn.split(RegExp(r'\s+')).where((w) => w.length >= 3).toList();
    if (words.isEmpty) continue;
    if (_wordIn(flat, cn) || _wordIn(flat, words.first)) {
      q.correspondentId = c.id;
      used.addAll(words);
      break;
    }
  }

  // Le parole rimaste servono per la ricerca nel testo.
  for (final w in flat.trim().split(' ')) {
    if (w.length < 3 || _stop.contains(w) || used.contains(w)) continue;
    if (used.any((u) => u.length >= 4 && w.startsWith(u.substring(0, u.length - 1)))) continue;
    if (RegExp(r'^\d+$').hasMatch(w)) continue;
    q.words.add(w);
  }
  return q;
}

/// Prompt per far capire la domanda all'AI sul telefono.
String buildAskPrompt(Archive a, String question) {
  final b = StringBuffer()
    ..writeln('Trasforma la domanda in una ricerca in un archivio di documenti. Rispondi SOLO con un oggetto JSON con queste chiavi:')
    ..writeln('"intento": "trova", "ultimo", "totale" (quanto si è speso) o "conta";')
    ..writeln('"parole": parole da cercare nel testo dei documenti (lista, solo quelle utili);')
    ..writeln('"categoria": una delle categorie esistenti oppure null;')
    ..writeln('"mittente": chi ha emesso il documento oppure null;')
    ..writeln('"persona": a chi è intestato, tra le persone della famiglia, oppure null;')
    ..writeln('"specialita": specialità medica oppure null;')
    ..writeln('"tipo_sanitario": "Referti", "Prescrizioni" oppure null;')
    ..writeln('"anno": anno (numero) oppure null.')
    ..writeln()
    ..writeln('Categorie: ${a.activeTypes.map((t) => t.name).join(', ')}');
  if (a.config.people.isNotEmpty) b.writeln('Persone della famiglia: ${a.config.people.map((p) => p.name).join(', ')}');
  final senders = a.activeCorrespondents.map((c) => c.name).take(60).toList();
  if (senders.isNotEmpty) b.writeln('Mittenti in archivio: ${senders.join(', ')}');
  b
    ..writeln()
    ..writeln('Domanda: $question');
  return b.toString();
}

/// Unisce ciò che ha capito l'AI a ciò che hanno capito le regole: l'AI
/// completa, le regole (che leggono nomi esatti) restano dove sono sicure.
AskQuery mergeAskResponse(Archive a, AskQuery base, String raw) {
  final start = raw.indexOf('{');
  final end = raw.lastIndexOf('}');
  if (start < 0 || end <= start) return base;
  Map<String, dynamic> j;
  try {
    j = (jsonDecode(raw.substring(start, end + 1)) as Map).cast<String, dynamic>();
  } catch (_) {
    return base;
  }
  final m = {for (final e in j.entries) normalize(e.key).replaceAll(RegExp(r'[^a-z]'), ''): e.value};
  String? s(String k) {
    final v = m[k];
    if (v == null || v is Map || v is List) return null;
    final t = '$v'.trim();
    return t.isEmpty || normalize(t) == 'null' ? null : t;
  }

  switch (normalize(s('intento') ?? '')) {
    case 'ultimo':
      if (base.intent == AskIntent.find) base.intent = AskIntent.latest;
    case 'totale':
      base.intent = AskIntent.total;
    case 'conta':
      if (base.intent == AskIntent.find) base.intent = AskIntent.count;
  }
  final cat = s('categoria');
  if (base.typeId == null && cat != null) base.typeId = findByName(a.activeTypes, cat)?.id;
  final sender = s('mittente');
  if (base.correspondentId == null && sender != null) {
    base.correspondentId = findByName(a.activeCorrespondents, sender)?.id;
  }
  final person = s('persona');
  if (base.person == null && person != null) {
    for (final p in a.config.people) {
      if (normalize(p.name) == normalize(person)) base.person = p.name;
    }
  }
  base.specialty ??= s('specialita');
  final hk = s('tiposanitario');
  if (base.healthKind == null && hk != null) {
    final n = normalize(hk);
    if (n.startsWith('refert')) base.healthKind = 'Referti';
    if (n.startsWith('prescri') || n.startsWith('ricett')) base.healthKind = 'Prescrizioni';
  }
  if (base.year == null && base.from == null) {
    final y = int.tryParse(s('anno') ?? '');
    if (y != null && y > 1900 && y < 2200) base.year = y;
  }
  final words = m['parole'];
  if (base.words.isEmpty && words is List) {
    base.words.addAll(words.map((e) => normalize('$e').trim()).where((w) => w.length >= 3 && !_stop.contains(w)));
  }
  return base;
}

/// Un documento trovato, con il punteggio.
typedef AskHit = (Document, double);

bool _passes(Archive a, Document d, AskQuery q) {
  if (q.typeId != null && d.typeId != q.typeId) return false;
  if (q.correspondentId != null && d.correspondentId != q.correspondentId) return false;
  if (q.person != null && normalize(d.customFields[personFieldId] ?? '') != normalize(q.person!)) return false;
  if (q.specialty != null && normalize(d.customFields[specialtyFieldId] ?? '') != normalize(q.specialty!)) return false;
  if (q.healthKind != null && (d.customFields[healthKindFieldId] ?? '') != q.healthKind) return false;
  if (q.year != null && d.created.year != q.year) return false;
  if (q.from != null && d.created.isBefore(q.from!)) return false;
  if (q.to != null && d.created.isAfter(q.to!.add(const Duration(days: 1)))) return false;
  return true;
}

/// Cerca nell'archivio. Se i filtri sono troppo stretti (es. persona o
/// specialità non ancora assegnate), li allarga un passo alla volta.
List<AskHit> runAsk(Archive a, AskQuery q, SearchIndex index) {
  List<AskHit> search(AskQuery q) {
    final out = <AskHit>[];
    for (final d in a.activeDocuments) {
      if (!_passes(a, d, q)) continue;
      var score = 1.0;
      if (q.words.isNotEmpty) {
        final (_, words) = index.entry(a, d);
        final title = tokenize(d.title).toSet();
        var hits = 0.0;
        for (final w in q.words) {
          if (title.any((t) => t.startsWith(w))) {
            hits += 3;
          } else if (words.contains(w) || (w.length >= 4 && words.any((x) => x.startsWith(w)))) {
            hits += 1;
          }
        }
        if (hits == 0) continue;
        score += hits;
      }
      out.add((d, score));
    }
    out.sort((x, y) {
      final c = y.$2.compareTo(x.$2);
      return c != 0 ? c : y.$1.created.compareTo(x.$1.created);
    });
    return out;
  }

  var hits = search(q);
  // Allarga: prima le parole, poi i campi che potrebbero mancare.
  if (hits.isEmpty && q.words.isNotEmpty) hits = search(AskQuery(
        typeId: q.typeId, correspondentId: q.correspondentId, person: q.person,
        specialty: q.specialty, healthKind: q.healthKind, year: q.year, from: q.from, to: q.to));
  if (hits.isEmpty && (q.specialty != null || q.healthKind != null)) {
    hits = search(AskQuery(words: [...q.words, if (q.specialty != null) ...tokenize(q.specialty!)],
        typeId: q.typeId, correspondentId: q.correspondentId, person: q.person, year: q.year, from: q.from, to: q.to));
  }
  if (q.intent == AskIntent.latest) {
    hits.sort((x, y) => y.$1.created.compareTo(x.$1.created));
  }
  return hits;
}

/// Importo in euro letto dal testo ("1.234,56 €" → 1234.56).
double? amountOf(Document d) {
  final s = detectAmount(d.content);
  if (s == null) return null;
  final m = RegExp(r'(\d{1,3}(?:\.\d{3})*|\d+),(\d{2})').firstMatch(s);
  if (m == null) return double.tryParse(s.replaceAll(RegExp(r'[^\d.]'), ''));
  return double.parse('${m[1]!.replaceAll('.', '')}.${m[2]}');
}

String euro(double v) {
  final parts = v.toStringAsFixed(2).split('.');
  final whole = parts[0].replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]}.');
  return '$whole,${parts[1]} €';
}

/// La risposta da mostrare sopra i risultati.
String answerText(Archive a, AskQuery q, List<AskHit> hits) {
  if (hits.isEmpty) {
    return 'Non ho trovato documenti. Prova con meno parole, oppure controlla che persona e categoria siano assegnate.';
  }
  switch (q.intent) {
    case AskIntent.latest:
      final d = hits.first.$1;
      return 'Il più recente è "${d.title}" del ${dateIt(d.created)}.';
    case AskIntent.count:
      return hits.length == 1 ? 'C\'è 1 documento.' : 'Ci sono ${hits.length} documenti.';
    case AskIntent.total:
      var sum = 0.0, withAmount = 0;
      for (final (d, _) in hits) {
        final v = amountOf(d);
        if (v != null) {
          sum += v;
          withAmount++;
        }
      }
      if (withAmount == 0) return 'Ho trovato ${hits.length} documenti, ma in nessuno ho letto un importo.';
      final missing = hits.length - withAmount;
      return 'Totale: ${euro(sum)} in $withAmount documenti'
          '${missing > 0 ? ' ($missing senza importo leggibile)' : ''}.';
    case AskIntent.find:
      return hits.length == 1 ? 'Ho trovato 1 documento.' : 'Ho trovato ${hits.length} documenti.';
  }
}

// ---------------------------------------------------------------------------
// Domande quando l'app non è sicura

enum QuestionKind { person, category }

class DocQuestion {
  DocQuestion(this.doc, this.kind, this.options);
  final Document doc;
  final QuestionKind kind;

  /// Scelte proposte (nomi delle persone o id delle categorie).
  final List<String> options;

  String get text => switch (kind) {
        QuestionKind.person => 'Di chi è questo documento?',
        QuestionKind.category => 'Che documento è?',
      };
}

/// I documenti su cui l'app ha un dubbio: categoria non riconosciuta, o
/// persona mancante quando la categoria è personale. Si chiede solo per i
/// documenti ancora "da esaminare" e non corretti a mano.
List<DocQuestion> openQuestions(Archive a) {
  final inbox = a.inboxTags.map((t) => t.id).toSet();
  final out = <DocQuestion>[];
  final types = a.activeTypes;
  for (final d in a.activeDocuments) {
    if (d.userEdited || !d.tagIds.any(inbox.contains)) continue;
    if (a.type(d.typeId) == null) {
      out.add(DocQuestion(d, QuestionKind.category, [for (final t in types) t.id]));
      continue;
    }
    if (a.config.people.isNotEmpty &&
        !a.config.sharedTypeIds.contains(d.typeId) &&
        (d.customFields[personFieldId] ?? '').isEmpty) {
      out.add(DocQuestion(d, QuestionKind.person, [for (final p in a.config.people) p.name, ''] ));
    }
  }
  out.sort((x, y) => y.doc.added.compareTo(x.doc.added));
  return out;
}

/// Le date del documento (per l'anteprima nella domanda).
String firstDateIt(Document d) {
  final ds = findDates(d.content);
  return ds.isEmpty ? dateIt(d.created) : dateIt(ds.first);
}
