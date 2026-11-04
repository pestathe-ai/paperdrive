/// L'importo di ogni documento: letto una volta all'importazione (dal testo
/// e, se c'è, dall'AI), salvato nel documento e correggibile a mano. I
/// totali di "Chiedi" si fanno su questo campo.
library;

import 'extract.dart' show detectAmount, looksLikeReceipt;
import 'models.dart';

/// "1.234,56 €", "18.94", "47,82" → numero. Null se non è un importo.
double? parseEuro(String? raw) {
  if (raw == null) return null;
  final s = raw.replaceAll(RegExp(r'[€\s]|eur(o)?', caseSensitive: false), '');
  final it = RegExp(r'^-?(\d{1,3}(?:\.\d{3})+|\d+)(?:,(\d{1,2}))?$').firstMatch(s);
  if (it != null) {
    final v = double.tryParse('${it[1]!.replaceAll('.', '')}.${it[2] ?? '0'}');
    return v == null || v <= 0 ? null : v;
  }
  final en = RegExp(r'^\d+\.\d{2}$').firstMatch(s);
  if (en != null) {
    final v = double.tryParse(s);
    return v == null || v <= 0 ? null : v;
  }
  return null;
}

/// L'importo letto dal testo, oppure dalla cifra alla fine del titolo
/// ("Ticket farmacia 18,94").
double? readAmount(Document d) {
  final fromText = parseEuro(detectAmount(d.content));
  if (fromText != null) return fromText;
  final tm = RegExp(r'(\d+)[.,](\d{2})\s*(?:€|euro|eur)?$', caseSensitive: false).firstMatch(d.title.trim());
  return tm == null ? null : parseEuro('${tm[1]},${tm[2]}');
}

/// La cifra compare davvero nel documento (l'AI non deve inventarla).
bool _inText(String content, double v) {
  final cents = (v * 100).round();
  final whole = cents ~/ 100;
  final dec = (cents % 100).toString().padLeft(2, '0');
  final withDots = whole.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]}.');
  final flat = content.replaceAll(RegExp(r'\s'), '');
  return flat.contains('$whole,$dec') || flat.contains('$withDots,$dec') || flat.contains('$whole.$dec');
}

/// Compila l'importo del documento, se non l'hai scritto tu. [ai] è
/// l'importo proposto dall'AI: vale se compare nel testo. Sugli scontrini
/// vince la lettura dell'app, che conosce come sono stampati. Vero se cambia.
bool fillAmount(Document d, {String? ai}) {
  if (d.amountEdited) return false;
  final read = readAmount(d);
  final fromAi = parseEuro(ai);
  final aiOk = fromAi != null && _inText(d.content, fromAi);
  final double? v;
  if (read != null && looksLikeReceipt(d.content)) {
    v = read;
  } else {
    v = aiOk ? fromAi : (read ?? d.amount);
  }
  if (v == d.amount) return false;
  d.amount = v;
  return true;
}

/// Importo da usare nei totali.
double? amountFor(Document d) => d.amountEdited ? d.amount : (d.amount ?? readAmount(d));
