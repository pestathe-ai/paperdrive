/// Assegnazione automatica di tag, corrispondenti, tipi e percorsi, come
/// `documents/matching.py` di Paperless-ngx: algoritmi Nessuna, Una qualsiasi
/// parola, Tutte le parole, Testo esatto, Regex, Approssimata (partial ratio
/// ≥ 90) e Automatica (classificatore addestrato sui tuoi documenti).
library;

import 'dart:math';

import 'archive.dart';
import 'classifier.dart';
import 'models.dart';
import 'text_utils.dart';

/// Soglia della corrispondenza approssimata (rapidfuzz partial_ratio ≥ 90).
const double fuzzyThreshold = 0.90;

/// Testo su cui si cercano le regole: come Paperless, il contenuto.
String matchText(Document d) => d.content;

String _flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

/// `re.search(rf"\b{word}\b", content)`; le frasi tra virgolette accettano
/// qualsiasi spazio tra le parole (`\s+`).
bool _containsWord(String haystack, String needle, bool ci) {
  final h = _flat(ci ? normalize(haystack) : haystack);
  final n = _flat((ci ? normalize(needle) : needle).trim());
  if (n.isEmpty) return false;
  final re = RegExp('(^|[^\\p{L}\\p{N}_])${RegExp.escape(n)}(\$|[^\\p{L}\\p{N}_])', unicode: true);
  return re.hasMatch(h);
}

/// Quanto bene una regola corrisponde (0 = per niente). Con "una qualsiasi
/// parola" conta quante parole diverse compaiono, così vince la categoria
/// più pertinente.
int ruleScore(Matchable m, String text) {
  if (!matchesRule(m, text)) return 0;
  switch (m.algorithm) {
    case MatchAlgorithm.any:
      return splitTerms(m.pattern.trim())
          .where((t) => _containsWord(text, t, m.caseInsensitive))
          .length;
    case MatchAlgorithm.all:
      return splitTerms(m.pattern.trim()).length + 1;
    case MatchAlgorithm.literal:
    case MatchAlgorithm.regex:
      return 3;
    default:
      return 1;
  }
}

/// Vero se la regola (non automatica) corrisponde al testo.
bool matchesRule(Matchable m, String text) {
  final pattern = m.pattern.trim();
  switch (m.algorithm) {
    case MatchAlgorithm.none:
    case MatchAlgorithm.auto:
      return false;
    case MatchAlgorithm.any:
      final terms = splitTerms(pattern);
      return terms.any((t) => _containsWord(text, t, m.caseInsensitive));
    case MatchAlgorithm.all:
      final terms = splitTerms(pattern);
      return terms.isNotEmpty &&
          terms.every((t) => _containsWord(text, t, m.caseInsensitive));
    case MatchAlgorithm.literal:
      return _containsWord(text, pattern, m.caseInsensitive);
    case MatchAlgorithm.regex:
      if (pattern.isEmpty) return false;
      try {
        return RegExp(pattern, caseSensitive: !m.caseInsensitive, multiLine: true)
            .hasMatch(text);
      } on FormatException {
        return false;
      }
    case MatchAlgorithm.fuzzy:
      // Come Paperless: via la punteggiatura, poi somiglianza parziale.
      final p = pattern.replaceAll(RegExp(r'[^\p{L}\p{N}_\s]', unicode: true), '');
      if (p.trim().isEmpty) return false;
      final t = text.replaceAll(RegExp(r'[^\p{L}\p{N}_\s]', unicode: true), '');
      return partialSimilarity(p, t) >= fuzzyThreshold;
  }
}

/// Controlla che un'espressione regolare sia valida; restituisce l'errore.
String? regexError(String pattern) {
  try {
    RegExp(pattern);
    return null;
  } on FormatException catch (e) {
    return e.message;
  }
}

/// Vettore di frequenza delle parole (parole di almeno 3 lettere).
Map<String, double> termVector(String text) {
  final v = <String, double>{};
  for (final w in tokenize(text)) {
    if (w.length < 3 || _stop.contains(w)) continue;
    v[w] = (v[w] ?? 0) + 1;
  }
  return v;
}

/// Pesi delle parole sull'archivio (IDF): le parole presenti in quasi tutti
/// i documenti (il tuo nome, l'indirizzo, "euro", "totale") non contano;
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

/// Vettore pesato con l'IDF (per confrontare documenti dello stesso archivio).
/// Numeri, codici, date e importi non contano: cambiano da un documento
/// all'altro anche quando sono dello stesso tipo.
Map<String, double> weightedVector(String text, Idf idf) => {
      for (final e in termVector(text).entries)
        if (!_hasDigit.hasMatch(e.key)) e.key: e.value * idf[e.key],
    };

final RegExp _hasDigit = RegExp(r'\d');

double _norm(Map<String, double> v) =>
    sqrt(v.values.fold<double>(0, (s, x) => s + x * x));

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

/// Risultato delle regole: cosa assegnare al documento.
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

/// Calcola tag, corrispondente, tipo e percorso per [doc], come
/// `match_tags` / `match_correspondents` / ... di Paperless: un elemento
/// corrisponde se la sua regola corrisponde, oppure se è "Automatica" e il
/// classificatore lo prevede. Tra più candidati vince la previsione del
/// classificatore, poi la regola più pertinente, poi il nome.
MatchResult computeMatches(Archive archive, Document doc, {DocumentClassifier? classifier}) {
  final text = matchText(doc);
  final predTags = classifier?.predictTags(text) ?? const <String>[];
  final tags = <String>{};
  for (final t in archive.activeTags) {
    if (matchesRule(t, text) || (!t.isInbox && predTags.contains(t.id))) {
      tags.add(t.id);
    }
  }

  String? pickOne(List<Matchable> entities, String? predicted) {
    String? best;
    var bestScore = 0;
    for (final e in entities) {
      final score = e.algorithm == MatchAlgorithm.auto
          ? (e.id == predicted ? 1000 : 0)
          : ruleScore(e, text);
      if (score > bestScore) {
        bestScore = score;
        best = e.id;
      }
    }
    // Nessuna regola: vale quello che l'app ha imparato dalle correzioni.
    if (best == null && predicted != null && entities.any((e) => e.id == predicted)) {
      return predicted;
    }
    return best;
  }

  return MatchResult(
    tagIds: tags,
    correspondentId:
        pickOne(archive.activeCorrespondents, classifier?.predictCorrespondent(text)),
    typeId: pickOne(archive.activeTypes, classifier?.predictDocumentType(text)),
    storagePathId: pickOne(archive.activeStoragePaths, classifier?.predictStoragePath(text)),
  );
}

/// Applica le regole a un documento. Con [overwrite] falso non sostituisce
/// corrispondente e tipo già scelti; i tag vengono sempre aggiunti.
/// Restituisce vero se qualcosa è cambiato.
bool applyMatches(
  Archive archive,
  Document doc, {
  bool overwrite = false,
  DocumentClassifier? classifier,
}) {
  final r = computeMatches(archive, doc, classifier: classifier);
  var changed = false;
  for (final t in r.tagIds) {
    if (doc.tagIds.add(t)) changed = true;
  }
  if (r.correspondentId != null &&
      (overwrite || doc.correspondentId == null) &&
      doc.correspondentId != r.correspondentId) {
    doc.correspondentId = r.correspondentId;
    changed = true;
  }
  if (r.typeId != null &&
      (overwrite || doc.typeId == null) &&
      doc.typeId != r.typeId) {
    doc.typeId = r.typeId;
    changed = true;
  }
  if (r.storagePathId != null &&
      (overwrite || doc.storagePathId == null) &&
      doc.storagePathId != r.storagePathId) {
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
