/// Ricerca e filtro dei documenti.
///
/// Sintassi della ricerca:
/// - `bolletta luce` tutte le parole (anche all'inizio di una parola: "bollet")
/// - `"enel energia"` frase esatta
/// - `-bozza` esclude i documenti con quella parola
/// - `tag:casa`, `corrispondente:enel` (o `da:enel`), `tipo:fattura`
/// - `asn:12`, `anno:2024`
library;

import 'archive.dart';
import 'models.dart';
import 'text_utils.dart';

class ParsedQuery {
  final List<String> words = [];
  final List<String> phrases = [];
  final List<String> excluded = [];
  final List<String> tagNames = [];
  final List<String> correspondentNames = [];
  final List<String> typeNames = [];
  int? asn;
  int? year;

  bool get isEmpty =>
      words.isEmpty &&
      phrases.isEmpty &&
      excluded.isEmpty &&
      tagNames.isEmpty &&
      correspondentNames.isEmpty &&
      typeNames.isEmpty &&
      asn == null &&
      year == null;
}

ParsedQuery parseQuery(String q) {
  final out = ParsedQuery();
  final re = RegExp(r'(-?)(?:(\w+):)?(?:"([^"]*)"|(\S+))');
  for (final m in re.allMatches(q)) {
    final neg = m.group(1) == '-';
    final key = m.group(2) == null ? null : normalize(m.group(2)!);
    final phrase = m.group(3);
    final value = (phrase ?? m.group(4) ?? '').trim();
    if (value.isEmpty) continue;
    switch (key) {
      case 'tag':
        out.tagNames.add(normalize(value));
      case 'corrispondente' || 'da' || 'mittente':
        out.correspondentNames.add(normalize(value));
      case 'tipo':
        out.typeNames.add(normalize(value));
      case 'asn':
        out.asn = int.tryParse(value);
      case 'anno':
        out.year = int.tryParse(value);
      default:
        final full = key == null ? value : '${m.group(2)}:$value';
        if (neg) {
          out.excluded.addAll(tokenize(full));
        } else if (phrase != null) {
          final n = tokenize(full).join(' ');
          if (n.isNotEmpty) out.phrases.add(n);
        } else {
          out.words.addAll(tokenize(full));
        }
    }
  }
  return out;
}

/// Testo indicizzato di un documento (titolo, contenuto, note, nomi).
String searchableText(Archive a, Document d) {
  final b = StringBuffer()
    ..writeln(d.title)
    ..writeln(d.originalName)
    ..writeln(a.correspondent(d.correspondentId)?.name ?? '')
    ..writeln(a.type(d.typeId)?.name ?? '');
  for (final t in d.tagIds) {
    b.writeln(a.tag(t)?.name ?? '');
  }
  for (final n in d.notes) {
    b.writeln(n.text);
  }
  d.customFields.forEach((_, v) => b.writeln(v));
  b.writeln(d.content);
  return b.toString();
}

/// Indice delle parole di ogni documento, ricostruito solo se cambia.
class SearchIndex {
  final Map<String, (int, String, Set<String>)> _cache = {};

  (String, Set<String>) entry(Archive a, Document d) {
    final key = d.modified;
    final hit = _cache[d.id];
    if (hit != null && hit.$1 == key) return (hit.$2, hit.$3);
    final words = tokenize(searchableText(a, d));
    final joined = ' ${words.join(' ')} ';
    final set = words.toSet();
    _cache[d.id] = (key, joined, set);
    return (joined, set);
  }

  void clear() => _cache.clear();
}

bool _hasWordPrefix(Set<String> words, String w) {
  if (words.contains(w)) return true;
  if (w.length < 3) return false;
  for (final x in words) {
    if (x.startsWith(w)) return true;
  }
  return false;
}

/// Punteggio di pertinenza (0 = non corrisponde).
double scoreDocument(Archive a, Document d, ParsedQuery q, SearchIndex index) {
  if (q.asn != null && d.asn != q.asn) return 0;
  if (q.year != null && d.created.year != q.year) return 0;
  for (final t in q.tagNames) {
    final ok = d.tagIds.any((id) {
      final n = normalize(a.tag(id)?.name ?? '');
      return n == t || n.startsWith(t);
    });
    if (!ok) return 0;
  }
  for (final c in q.correspondentNames) {
    final n = normalize(a.correspondent(d.correspondentId)?.name ?? '');
    if (n.isEmpty || !n.contains(c)) return 0;
  }
  for (final c in q.typeNames) {
    final n = normalize(a.type(d.typeId)?.name ?? '');
    if (n.isEmpty || !n.contains(c)) return 0;
  }
  final (joined, words) = index.entry(a, d);
  for (final x in q.excluded) {
    if (words.contains(x)) return 0;
  }
  var score = 1.0;
  final title = tokenize(d.title).toSet();
  for (final w in q.words) {
    if (!_hasWordPrefix(words, w)) return 0;
    score += _hasWordPrefix(title, w) ? 5 : 1;
  }
  for (final p in q.phrases) {
    if (!joined.contains(' $p ')) return 0;
    score += normalize(d.title).contains(p) ? 6 : 2;
  }
  return score;
}

bool passesFilter(Archive a, Document d, DocumentFilter f) {
  if (f.tagIds.isNotEmpty && !f.tagIds.every(d.tagIds.contains)) return false;
  if (f.excludedTagIds.any(d.tagIds.contains)) return false;
  if (f.correspondentId != null && d.correspondentId != f.correspondentId) {
    return false;
  }
  if (f.typeId != null && d.typeId != f.typeId) return false;
  if (f.from != null && d.created.isBefore(f.from!)) return false;
  if (f.to != null && d.created.isAfter(f.to!)) return false;
  if (f.untaggedOnly && d.tagIds.any((t) => a.tag(t) != null)) return false;
  if (f.inboxOnly) {
    final inbox = a.inboxTags.map((t) => t.id).toSet();
    if (!d.tagIds.any(inbox.contains)) return false;
  }
  return true;
}

int _compare(Document x, Document y, SortField s) => switch (s) {
      SortField.created => x.created.compareTo(y.created),
      SortField.added => x.added.compareTo(y.added),
      SortField.title => x.title.toLowerCase().compareTo(y.title.toLowerCase()),
      SortField.asn => (x.asn ?? 1 << 30).compareTo(y.asn ?? 1 << 30),
    };

/// Applica filtro e ricerca. Con una ricerca testuale i risultati sono
/// ordinati per pertinenza, altrimenti secondo il filtro.
List<Document> runFilter(Archive a, DocumentFilter f, SearchIndex index) {
  final q = parseQuery(f.query);
  final docs = a.activeDocuments.where((d) => passesFilter(a, d, f));
  if (q.isEmpty) {
    final list = docs.toList()
      ..sort((x, y) {
        final c = _compare(x, y, f.sort);
        final r = f.descending ? -c : c;
        return r != 0 ? r : y.added.compareTo(x.added);
      });
    return list;
  }
  final scored = <(double, Document)>[];
  for (final d in docs) {
    final s = scoreDocument(a, d, q, index);
    if (s > 0) scored.add((s, d));
  }
  final textual = q.words.isNotEmpty || q.phrases.isNotEmpty;
  scored.sort((x, y) {
    if (textual) {
      final c = y.$1.compareTo(x.$1);
      if (c != 0) return c;
    }
    final c = _compare(x.$2, y.$2, f.sort);
    return f.descending ? -c : c;
  });
  return scored.map((e) => e.$2).toList();
}

/// Breve estratto del contenuto intorno alla prima parola cercata.
String snippet(Document d, String query, {int radius = 60}) {
  final q = parseQuery(query);
  final terms = [...q.phrases, ...q.words];
  final text = d.content.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text.isEmpty) return '';
  if (terms.isEmpty) {
    return text.length > radius * 2 ? '${text.substring(0, radius * 2)}…' : text;
  }
  final norm = normalize(text);
  var pos = -1;
  for (final t in terms) {
    pos = norm.indexOf(t);
    if (pos >= 0) break;
  }
  if (pos < 0 || norm.length != text.length) {
    return text.length > radius * 2 ? '${text.substring(0, radius * 2)}…' : text;
  }
  final start = (pos - radius).clamp(0, text.length);
  final end = (pos + radius).clamp(0, text.length);
  return '${start > 0 ? '…' : ''}${text.substring(start, end)}${end < text.length ? '…' : ''}';
}
