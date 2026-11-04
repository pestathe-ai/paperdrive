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

/// Pulisce il testo estratto dai PDF (PDFium usa `\r\n`, a volte `\r` da
/// solo, spazi non separabili e trattini morbidi): righe con `\n`, spazi
/// normali, niente spazi in fondo alle righe.
String cleanContent(String s) {
  var t = s
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll('\u00A0', ' ')
      .replaceAll('\u00AD', '')
      .replaceAll('\uFFFE', '')
      .replaceAll('\u0002', '-')
      .replaceAll('\t', ' ');
  t = t.split('\n').map((l) => l.trimRight()).join('\n');
  return t.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
}
