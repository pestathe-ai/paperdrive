/// Funzioni di testo condivise: normalizzazione (minuscole, senza accenti)
/// e suddivisione in parole.
library;

const Map<String, String> _accents = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a',
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
  'ò': 'o', 'ó': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o',
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
  'ç': 'c', 'ñ': 'n', 'ß': 'ss', 'ÿ': 'y',
  '’': "'", '‘': "'",
};

/// Minuscolo e senza accenti, così "Società" e "societa" coincidono.
String normalize(String input) {
  final lower = input.toLowerCase();
  final buf = StringBuffer();
  for (final rune in lower.runes) {
    final ch = String.fromCharCode(rune);
    buf.write(_accents[ch] ?? ch);
  }
  return buf.toString();
}

final RegExp _wordSplit = RegExp(r"[^a-z0-9]+");

/// Parole normalizzate (lettere e cifre), senza quelle vuote.
List<String> tokenize(String input) {
  return normalize(input)
      .split(_wordSplit)
      .where((w) => w.isNotEmpty)
      .toList();
}

/// Divide un'espressione in termini, rispettando le frasi tra virgolette:
/// `fattura "enel energia"` -> [fattura, enel energia].
List<String> splitTerms(String pattern) {
  final terms = <String>[];
  final re = RegExp(r'"([^"]*)"|(\S+)');
  for (final m in re.allMatches(pattern)) {
    final t = (m.group(1) ?? m.group(2) ?? '').trim();
    if (t.isNotEmpty) terms.add(t);
  }
  return terms;
}

/// Distanza di modifica minima tra [pattern] e una qualsiasi sottostringa di
/// [text] (algoritmo di Sellers). Serve per la corrispondenza "approssimata".
int bestSubstringDistance(String pattern, String text) {
  final m = pattern.length;
  if (m == 0) return 0;
  if (text.isEmpty) return m;
  var prev = List<int>.generate(m + 1, (i) => i);
  var best = prev[m];
  for (var j = 1; j <= text.length; j++) {
    final cur = List<int>.filled(m + 1, 0);
    cur[0] = 0; // una sottostringa può iniziare ovunque
    final tc = text.codeUnitAt(j - 1);
    for (var i = 1; i <= m; i++) {
      final cost = pattern.codeUnitAt(i - 1) == tc ? 0 : 1;
      final a = prev[i - 1] + cost;
      final b = prev[i] + 1;
      final c = cur[i - 1] + 1;
      cur[i] = a < b ? (a < c ? a : c) : (b < c ? b : c);
    }
    if (cur[m] < best) best = cur[m];
    if (best == 0) return 0;
    prev = cur;
  }
  return best;
}

/// Somiglianza 0..1 tra [pattern] e la parte di [text] più simile.
double partialSimilarity(String pattern, String text) {
  final p = normalize(pattern).trim();
  if (p.isEmpty) return 0;
  final d = bestSubstringDistance(p, normalize(text));
  return 1 - d / p.length;
}
