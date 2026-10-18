/// Assegnazione automatica di tag, corrispondenti e tipi, con gli stessi
/// algoritmi di Paperless-ngx (una parola, tutte, testo esatto, regex,
/// approssimata, automatica).
library;

import 'dart:math';

import 'archive.dart';
import 'models.dart';
import 'text_utils.dart';

/// Soglia per la corrispondenza approssimata (0..1).
const double fuzzyThreshold = 0.85;

/// Soglia di somiglianza per l'algoritmo automatico.
const double autoThreshold = 0.30;

/// Testo su cui si cercano le regole: titolo, nome del file e contenuto.
String matchText(Document d) => '${d.title}\n${d.originalName}\n${d.content}';

bool _containsWord(String haystack, String needle, bool ci) {
  final h = ci ? normalize(haystack) : haystack;
  final n = ci ? normalize(needle) : needle;
  if (n.isEmpty) return false;
  final re = RegExp('(^|[^A-Za-z0-9])${RegExp.escape(n)}(\$|[^A-Za-z0-9])');
  return re.hasMatch(h);
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
      if (pattern.isEmpty) return false;
      return partialSimilarity(pattern, text) >= fuzzyThreshold;
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

/// Media normalizzata dei vettori dei documenti di esempio.
Map<String, double> centroid(Iterable<Map<String, double>> vectors) {
  final out = <String, double>{};
  var count = 0;
  for (final v in vectors) {
    final n = _norm(v);
    if (n == 0) continue;
    count++;
    v.forEach((k, x) => out[k] = (out[k] ?? 0) + x / n);
  }
  if (count == 0) return out;
  out.updateAll((k, x) => x / count);
  return out;
}

/// Risultato delle regole: cosa assegnare al documento.
class MatchResult {
  MatchResult({required this.tagIds, this.correspondentId, this.typeId});
  final Set<String> tagIds;
  final String? correspondentId;
  final String? typeId;
}

/// Calcola tag, corrispondente e tipo suggeriti per [doc].
///
/// I documenti dell'archivio (escluso [doc]) servono da esempi per
/// l'algoritmo automatico.
MatchResult computeMatches(Archive archive, Document doc) {
  final text = matchText(doc);
  final examples = archive.activeDocuments.where((d) => d.id != doc.id).toList();
  Map<String, double>? docVec;
  Map<String, Map<String, double>>? exampleVecs;

  Map<String, double> vecOf(Document d) {
    exampleVecs ??= {};
    return exampleVecs!.putIfAbsent(d.id, () => termVector(matchText(d)));
  }

  double autoScore(bool Function(Document) hasLabel) {
    final positives = examples.where(hasLabel).toList();
    if (positives.length < 2) return 0;
    docVec ??= termVector(text);
    return cosine(docVec!, centroid(positives.map(vecOf)));
  }

  final tags = <String>{};
  for (final t in archive.activeTags) {
    if (t.algorithm == MatchAlgorithm.auto) {
      if (autoScore((d) => d.tagIds.contains(t.id)) >= autoThreshold) {
        tags.add(t.id);
      }
    } else if (matchesRule(t, text)) {
      tags.add(t.id);
    }
  }

  String? pickOne(
    List<NamedEntity> entities,
    String? Function(Document) labelOf,
  ) {
    // Prima le regole esplicite, poi l'automatica con il punteggio migliore.
    for (final e in entities) {
      if (e.algorithm != MatchAlgorithm.auto && matchesRule(e, text)) {
        return e.id;
      }
    }
    String? best;
    var bestScore = autoThreshold;
    for (final e in entities.where((e) => e.algorithm == MatchAlgorithm.auto)) {
      final s = autoScore((d) => labelOf(d) == e.id);
      if (s >= bestScore) {
        bestScore = s;
        best = e.id;
      }
    }
    return best;
  }

  return MatchResult(
    tagIds: tags,
    correspondentId:
        pickOne(archive.activeCorrespondents, (d) => d.correspondentId),
    typeId: pickOne(archive.activeTypes, (d) => d.typeId),
  );
}

/// Applica le regole a un documento. Con [overwrite] falso non sostituisce
/// corrispondente e tipo già scelti; i tag vengono sempre aggiunti.
/// Restituisce vero se qualcosa è cambiato.
bool applyMatches(Archive archive, Document doc, {bool overwrite = false}) {
  final r = computeMatches(archive, doc);
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
  if (changed) doc.touch();
  return changed;
}

const Set<String> _stop = {
  'the', 'and', 'for', 'with', 'from', 'that', 'this', 'are', 'was',
  'del', 'della', 'delle', 'dei', 'degli', 'dal', 'dalla', 'nel', 'nella',
  'per', 'con', 'che', 'una', 'uno', 'non', 'sono', 'alla', 'alle', 'agli',
  'gli', 'les', 'des', 'der', 'die', 'das', 'und', 'pdf', 'pag', 'pagina',
};
