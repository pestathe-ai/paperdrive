/// Motore di D. PaperLink Lab: decide tag, mittente, categoria e cartella di un
/// documento combinando tre fonti, in quest'ordine di fiducia:
///
/// 1. le regole a parole chiave scritte dall'utente;
/// 2. ciò che l'app ha imparato dai documenti già sistemati ([Learner]);
/// 3. le regole a parole chiave predefinite (categorie di partenza).
///
/// Le regole lavorano sulle parole del testo (già lette con l'OCR), non sui
/// caratteri: "Una qualsiasi parola", "Tutte le parole", "Frase esatta",
/// "Espressione regolare" e "Tollerante" (accetta parole scritte male
/// dall'OCR: una lettera sbagliata ogni quattro circa).
///
/// Progetto originale di D. PaperLink Lab (vedi DESIGN.md).
library;

import 'dart:math';

import 'archive.dart';
import 'learner.dart';
import 'models.dart';
import 'text_utils.dart';

/// Testo su cui lavorano regole e apprendimento.
String matchText(Document d) => d.content;

// ---------------------------------------------------------------------------
// Parole del testo

/// Il testo pronto per le regole: parole normalizzate (minuscole, senza
/// accenti) in ordine, e il loro insieme.
class TextWords {
  TextWords._(this.words, this.set, this.flat);

  factory TextWords.of(String text) {
    final words = _wordRe.allMatches(normalize(text)).map((m) => m[0]!).toList();
    return TextWords._(words, words.toSet(), ' ${words.join(' ')} ');
  }

  final List<String> words;
  final Set<String> set;

  /// Le parole separate da uno spazio, con uno spazio prima e dopo.
  final String flat;

  static final Map<String, TextWords> _cache = {};

  /// Con una piccola cache: lo stesso testo viene controllato da molte regole.
  static TextWords cached(String text) {
    final hit = _cache[text];
    if (hit != null) return hit;
    if (_cache.length > 64) _cache.clear();
    return _cache[text] = TextWords.of(text);
  }
}

final RegExp _wordRe = RegExp(r'[\p{L}\p{N}]+', unicode: true);

List<String> _wordsOf(String s) => _wordRe.allMatches(normalize(s)).map((m) => m[0]!).toList();

/// La frase (sequenza di parole) compare nel testo.
bool _hasPhrase(TextWords t, List<String> phrase) {
  if (phrase.isEmpty) return false;
  if (phrase.length == 1) return t.set.contains(phrase.first);
  return t.flat.contains(' ${phrase.join(' ')} ');
}

/// Errori ammessi in una parola letta dall'OCR: nessuno sotto le 4 lettere,
/// poi uno ogni 4 lettere circa.
int _allowedErrors(String w) => w.length < 4 ? 0 : (w.length / 4).floor().clamp(1, 3);

/// Distanza di modifica tra due parole (inserimenti, cancellazioni,
/// sostituzioni), interrotta appena supera [max].
int _editDistance(String a, String b, int max) {
  if ((a.length - b.length).abs() > max) return max + 1;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0);
    cur[0] = i;
    var rowMin = cur[0];
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      cur[j] = min(min(cur[j - 1] + 1, prev[j] + 1), prev[j - 1] + cost);
      if (cur[j] < rowMin) rowMin = cur[j];
    }
    if (rowMin > max) return max + 1;
    prev = cur;
  }
  return prev[b.length];
}

/// La parola compare nel testo, anche con qualche errore dell'OCR.
bool _hasWordTolerant(TextWords t, String w) {
  if (t.set.contains(w)) return true;
  final max = _allowedErrors(w);
  if (max == 0) return false;
  for (final x in t.set) {
    if ((x.length - w.length).abs() <= max && _editDistance(w, x, max) <= max) return true;
  }
  return false;
}

/// Le parole chiave di una regola: separate da spazi; tra virgolette una
/// frase ("enel energia").
List<List<String>> _keywords(String pattern) => [
      for (final term in splitTerms(pattern.trim()))
        if (_wordsOf(term).isNotEmpty) _wordsOf(term),
    ];

// ---------------------------------------------------------------------------
// Regole

/// Quanto una regola corrisponde al testo: 0 = per niente, 1 = pienamente.
/// Con "Una qualsiasi parola" cresce col numero di parole chiave trovate.
double ruleStrength(Matchable m, String text) {
  final pattern = m.pattern.trim();
  if (pattern.isEmpty) return 0;
  switch (m.algorithm) {
    case MatchAlgorithm.none:
    case MatchAlgorithm.auto:
      return 0;
    case MatchAlgorithm.regex:
      try {
        return RegExp(pattern, caseSensitive: !m.caseInsensitive, multiLine: true).hasMatch(text) ? 1 : 0;
      } on FormatException {
        return 0;
      }
    case MatchAlgorithm.literal:
      if (!m.caseInsensitive) {
        // Maiuscole esatte: si confronta il testo originale, a parole intere.
        final words = _wordRe.allMatches(pattern).map((x) => x[0]!).join(r'\W+');
        if (words.isEmpty) return 0;
        return RegExp('(?<![\\p{L}\\p{N}])$words(?![\\p{L}\\p{N}])', unicode: true).hasMatch(text) ? 1 : 0;
      }
      return _hasPhrase(TextWords.cached(text), _wordsOf(pattern)) ? 1 : 0;
    case MatchAlgorithm.any:
      final t = TextWords.cached(text);
      final kws = _keywords(pattern);
      final found = kws.where((k) => _hasPhrase(t, k)).length;
      if (found == 0) return 0;
      // 1 parola: 0.5; 2: 0.75; 3: 0.875…
      return 1 - pow(0.5, found).toDouble();
    case MatchAlgorithm.all:
      final t = TextWords.cached(text);
      final kws = _keywords(pattern);
      return kws.isNotEmpty && kws.every((k) => _hasPhrase(t, k)) ? 1 : 0;
    case MatchAlgorithm.fuzzy:
      final t = TextWords.cached(text);
      final words = _wordsOf(pattern);
      if (words.isEmpty) return 0;
      return words.every((w) => _hasWordTolerant(t, w)) ? 0.9 : 0;
  }
}

/// Vero se la regola corrisponde al testo.
bool matchesRule(Matchable m, String text) => ruleStrength(m, text) > 0;

/// Punteggio intero (per ordinare le regole che corrispondono).
int ruleScore(Matchable m, String text) => (ruleStrength(m, text) * 100).round();

/// Controlla che un'espressione regolare sia valida; restituisce l'errore.
String? regexError(String pattern) {
  try {
    RegExp(pattern);
    return null;
  } on FormatException catch (e) {
    return e.message;
  }
}

// ---------------------------------------------------------------------------
// Somiglianza tra documenti

/// Frequenza delle parole significative (almeno 3 lettere, senza le più
/// comuni).
Map<String, double> termVector(String text) {
  final v = <String, double>{};
  for (final w in tokenize(text)) {
    if (w.length < 3 || _stop.contains(w)) continue;
    v[w] = (v[w] ?? 0) + 1;
  }
  return v;
}

/// Pesi delle parole sull'archivio: le parole presenti in quasi tutti i
/// documenti (il tuo nome, l'indirizzo, "euro", "totale") non contano;
/// contano quelle tipiche di pochi documenti.
class Idf {
  Idf._(this._w, this._default);
  final Map<String, double> _w;
  final double _default;

  double operator [](String w) => _w[w] ?? _default;

  static Idf? _cache;
  static Object? _cacheKey;

  /// Calcolati sui documenti attivi (con cache finché l'archivio non cambia).
  static Idf of(Archive a) {
    final docs = a.activeDocuments;
    var len = 0;
    for (final d in docs) {
      len += d.content.length;
    }
    final key = (identityHashCode(a), docs.length, len);
    if (_cache != null && _cacheKey == key) return _cache!;
    final df = <String, int>{};
    for (final d in docs) {
      for (final w in termVector(d.content).keys) {
        df[w] = (df[w] ?? 0) + 1;
      }
    }
    final n = docs.length;
    final w = {for (final e in df.entries) e.key: log((n + 1) / (e.value + 1)) + 0.1};
    _cacheKey = key;
    // Una parola mai vista conta come una presente in un solo documento.
    return _cache = Idf._(w, log((n + 1) / 2) + 0.1);
  }
}

/// Vettore pesato (per confrontare documenti dello stesso archivio).
/// Numeri, codici, date e importi non contano: cambiano da un documento
/// all'altro anche quando sono dello stesso tipo.
Map<String, double> weightedVector(String text, Idf idf) => {
      for (final e in termVector(text).entries)
        if (!_hasDigit.hasMatch(e.key)) e.key: e.value * idf[e.key],
    };

final RegExp _hasDigit = RegExp(r'\d');

double _norm(Map<String, double> v) => sqrt(v.values.fold<double>(0, (s, x) => s + x * x));

/// Somiglianza del coseno (0..1).
double cosine(Map<String, double> a, Map<String, double> b) {
  if (a.isEmpty || b.isEmpty) return 0;
  final small = a.length < b.length ? a : b;
  final big = identical(small, a) ? b : a;
  var dot = 0.0;
  small.forEach((k, x) {
    final y = big[k];
    if (y != null) dot += x * y;
  });
  final n = _norm(a) * _norm(b);
  return n == 0 ? 0 : dot / n;
}

// ---------------------------------------------------------------------------
// Decisione

/// Cosa assegnare al documento.
class MatchResult {
  MatchResult({
    required this.tagIds,
    this.correspondentId,
    this.typeId,
    this.storagePathId,
  });
  final Set<String> tagIds;
  final String? correspondentId;
  final String? typeId;
  final String? storagePathId;
}

/// Sceglie un valore tra le regole e l'apprendimento.
///
/// - Una regola scritta dall'utente vince sempre.
/// - Ciò che l'app ha imparato vince sulle regole predefinite se è
///   abbastanza sicuro (≥ 0.6), altrimenti valgono le predefinite.
/// - Senza regole che corrispondono vale l'apprendimento.
String? _decide<T extends Matchable>(List<T> entities, String text, Guess? learned) {
  T? bestUser, bestStarter;
  var userScore = 0.0, starterScore = 0.0;
  for (final e in entities) {
    final s = ruleStrength(e, text);
    if (s <= 0) continue;
    if (e.id.startsWith('st-')) {
      if (s > starterScore) {
        starterScore = s;
        bestStarter = e;
      }
    } else if (s > userScore) {
      userScore = s;
      bestUser = e;
    }
  }
  if (bestUser != null) return bestUser.id;
  final known = learned != null && entities.any((e) => e.id == learned.label);
  if (known && (bestStarter == null || learned.confidence >= 0.6)) return learned.label;
  return bestStarter?.id;
}

/// Calcola tag, mittente, categoria e cartella per [doc].
MatchResult computeMatches(Archive archive, Document doc, {Learner? classifier}) {
  final text = matchText(doc);
  final learner = classifier;
  final tags = <String>{};
  final learnedTags = learner?.tags(text) ?? const <String>[];
  for (final t in archive.activeTags) {
    if (t.isInbox) continue;
    if (ruleStrength(t, text) > 0 || learnedTags.contains(t.id)) tags.add(t.id);
  }
  return MatchResult(
    tagIds: tags,
    correspondentId: _decide(archive.activeCorrespondents, text, learner?.correspondent(text)),
    typeId: _decide(archive.activeTypes, text, learner?.type(text)),
    storagePathId: _decide(archive.activeStoragePaths, text, learner?.storagePath(text)),
  );
}

/// Applica il risultato al documento. Con [overwrite] falso non sostituisce
/// valori già scelti; i tag vengono sempre aggiunti. Vero se cambia qualcosa.
bool applyMatches(
  Archive archive,
  Document doc, {
  bool overwrite = false,
  Learner? classifier,
}) {
  final r = computeMatches(archive, doc, classifier: classifier);
  var changed = false;
  for (final t in r.tagIds) {
    if (doc.tagIds.add(t)) changed = true;
  }
  if (r.correspondentId != null && (overwrite || doc.correspondentId == null) && doc.correspondentId != r.correspondentId) {
    doc.correspondentId = r.correspondentId;
    changed = true;
  }
  if (r.typeId != null && (overwrite || doc.typeId == null) && doc.typeId != r.typeId) {
    doc.typeId = r.typeId;
    changed = true;
  }
  if (r.storagePathId != null && (overwrite || doc.storagePathId == null) && doc.storagePathId != r.storagePathId) {
    doc.storagePathId = r.storagePathId;
    changed = true;
  }
  if (changed) doc.touch();
  return changed;
}

const Set<String> _stop = {
  'the', 'and', 'for', 'with', 'from', 'that', 'this', 'are', 'was',
  'del', 'della', 'delle', 'dei', 'degli', 'dal', 'dalla', 'nel', 'nella',
  'per', 'con', 'che', 'una', 'uno', 'non', 'sono', 'alla', 'alle', 'agli',
  'gli', 'les', 'des', 'der', 'die', 'das', 'und', 'pdf', 'pag', 'pagina',
};
