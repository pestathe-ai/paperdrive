/// Riconosce la data di un documento dal suo testo (come fa Paperless-ngx).
library;

import 'text_utils.dart';

const Map<String, int> _months = {
  'gennaio': 1, 'gen': 1, 'january': 1, 'jan': 1, 'janvier': 1, 'januar': 1,
  'febbraio': 2, 'feb': 2, 'february': 2, 'fevrier': 2, 'februar': 2,
  'marzo': 3, 'mar': 3, 'march': 3, 'mars': 3, 'marz': 3,
  'aprile': 4, 'apr': 4, 'april': 4, 'avril': 4,
  'maggio': 5, 'mag': 5, 'may': 5, 'mai': 5,
  'giugno': 6, 'giu': 6, 'june': 6, 'jun': 6, 'juin': 6, 'juni': 6,
  'luglio': 7, 'lug': 7, 'july': 7, 'jul': 7, 'juillet': 7, 'juli': 7,
  'agosto': 8, 'ago': 8, 'august': 8, 'aug': 8, 'aout': 8,
  'settembre': 9, 'set': 9, 'sett': 9, 'september': 9, 'sep': 9, 'sept': 9,
  'ottobre': 10, 'ott': 10, 'october': 10, 'oct': 10, 'octobre': 10,
  'oktober': 10, 'okt': 10,
  'novembre': 11, 'nov': 11, 'november': 11,
  'dicembre': 12, 'dic': 12, 'december': 12, 'dec': 12, 'decembre': 12,
  'dezember': 12, 'dez': 12,
};

DateTime? _make(int y, int m, int d, DateTime now) {
  if (y < 100) y += y > (now.year % 100) + 1 ? 1900 : 2000;
  if (m < 1 || m > 12 || d < 1 || d > 31) return null;
  final dt = DateTime(y, m, d);
  // Scarta date inesistenti (es. 31/02) e fuori intervallo.
  if (dt.month != m || dt.day != d) return null;
  if (y < 1900 || dt.isAfter(now.add(const Duration(days: 366)))) return null;
  return dt;
}

/// Tutte le date trovate nel testo, nell'ordine in cui compaiono.
List<DateTime> findDates(String text, {DateTime? now}) {
  final ref = now ?? DateTime.now();
  final t = normalize(text);
  final found = <(int, DateTime)>[];

  // gg/mm/aaaa, gg-mm-aa, gg.mm.aaaa (ordine europeo).
  final numeric = RegExp(r'(?<![0-9])(\d{1,2})[./-](\d{1,2})[./-](\d{4}|\d{2})(?![0-9])');
  for (final m in numeric.allMatches(t)) {
    final d = _make(int.parse(m.group(3)!), int.parse(m.group(2)!),
        int.parse(m.group(1)!), ref);
    if (d != null) found.add((m.start, d));
  }

  // aaaa-mm-gg (ISO).
  final iso = RegExp(r'(?<![0-9])(\d{4})[./-](\d{1,2})[./-](\d{1,2})(?![0-9])');
  for (final m in iso.allMatches(t)) {
    final d = _make(int.parse(m.group(1)!), int.parse(m.group(2)!),
        int.parse(m.group(3)!), ref);
    if (d != null) found.add((m.start, d));
  }

  // 12 marzo 2024, 1° gen. 2024, 3 March 2023.
  final textual = RegExp(
      r'(?<![0-9])(\d{1,2})(?:°|o|st|nd|rd|th)?\.?\s+([a-z]{3,9})\.?\s+(\d{4})(?![0-9])');
  for (final m in textual.allMatches(t)) {
    final month = _months[m.group(2)!];
    if (month == null) continue;
    final d = _make(int.parse(m.group(3)!), month, int.parse(m.group(1)!), ref);
    if (d != null) found.add((m.start, d));
  }

  // March 12, 2024.
  final us = RegExp(r'([a-z]{3,9})\.?\s+(\d{1,2}),?\s+(\d{4})(?![0-9])');
  for (final m in us.allMatches(t)) {
    final month = _months[m.group(1)!];
    if (month == null) continue;
    final d = _make(int.parse(m.group(3)!), month, int.parse(m.group(2)!), ref);
    if (d != null) found.add((m.start, d));
  }

  found.sort((a, b) => a.$1.compareTo(b.$1));
  return found.map((e) => e.$2).toList();
}

/// La prima data plausibile del testo, o null.
DateTime? detectDate(String text, {DateTime? now}) {
  final all = findDates(text, now: now);
  return all.isEmpty ? null : all.first;
}

/// Titolo suggerito dal testo: la prima riga significativa.
String? suggestTitle(String text) {
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    final letters = RegExp(r'[A-Za-zÀ-ÿ]').allMatches(line).length;
    if (letters >= 4 && line.length >= 4) {
      return line.length > 60 ? '${line.substring(0, 60).trim()}…' : line;
    }
  }
  return null;
}
