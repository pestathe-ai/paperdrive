/// Somiglianza per significato: una piccola rete neurale sul telefono
/// (EmbeddingGemma 2) trasforma ogni documento in un vettore di numeri, e
/// documenti che parlano della stessa cosa hanno vettori vicini anche
/// quando usano parole diverse ("idraulico garage" vicino a "box").
///
/// Qui c'è solo la parte di calcolo, senza il modello: i vettori arrivano da
/// `services/meaning_service.dart` e restano sul telefono (non vanno su
/// Drive).
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'models.dart';

/// Lunghezza dei vettori salvati. Il modello ne produce 768, ma è addestrato
/// perché i primi 256 bastino (Matryoshka): un quarto dello spazio, quasi la
/// stessa qualità.
const int meaningSize = 256;

/// Testo massimo passato al modello: l'inizio del documento dice quasi
/// sempre di cosa si tratta, e il modello rifiuta i testi troppo lunghi.
const int meaningChars = 2400;

/// Il testo che rappresenta il documento (solo il contenuto: il titolo
/// cambia spesso e lo decide l'app stessa).
String meaningText(Document d) {
  final t = d.content.replaceAll(RegExp(r'\s+'), ' ').trim();
  return t.length <= meaningChars ? t : t.substring(0, meaningChars);
}

/// Impronta del testo: se il documento cambia, il vettore va rifatto.
String meaningKey(Document d) => meaningText(d).hashCode.toRadixString(36);

/// Accorcia a [meaningSize] e normalizza (lunghezza 1), così la somiglianza
/// è un semplice prodotto scalare.
Float32List shrinkMeaning(List<double> v) {
  final n = math.min(v.length, meaningSize);
  final out = Float32List(n);
  var norm = 0.0;
  for (var i = 0; i < n; i++) {
    norm += v[i] * v[i];
  }
  norm = math.sqrt(norm);
  if (norm == 0) return out;
  for (var i = 0; i < n; i++) {
    out[i] = v[i] / norm;
  }
  return out;
}

/// Coseno tra due vettori normalizzati (−1..1).
double meaningCosine(Float32List a, Float32List b) {
  if (a.length != b.length || a.isEmpty) return 0;
  var s = 0.0;
  for (var i = 0; i < a.length; i++) {
    s += a[i] * b[i];
  }
  return s;
}

/// Coseno da cui due testi iniziano a contare come "sullo stesso tema", e
/// coseno da cui sono praticamente lo stesso tipo di documento. Con questo
/// modello due testi italiani qualsiasi stanno spesso intorno a 0,4.
const double meaningFloor = 0.45;
const double meaningCeil = 0.9;

/// Porta il coseno della rete sulla stessa scala della somiglianza a
/// parole (0 = niente in comune, 1 = stessa cosa).
double meaningScore(double cosine) =>
    ((cosine - meaningFloor) / (meaningCeil - meaningFloor)).clamp(0.0, 1.0).toDouble();

/// Unisce somiglianza a parole e per significato. Non è mai più bassa di
/// quella a parole: il significato può solo avvicinare documenti che le
/// parole non bastano a riconoscere.
double blendSimilarity(double words, double? meaning) {
  if (meaning == null) return words;
  final mixed = 0.4 * words + 0.6 * meaning;
  return mixed > words ? mixed : words;
}

/// I vettori dei documenti, salvati sul telefono.
class MeaningStore {
  final Map<String, Float32List> vectors = {};
  final Map<String, String> keys = {};

  /// Il vettore di [d], se è aggiornato al suo testo.
  Float32List? of(Document d) => keys[d.id] == meaningKey(d) ? vectors[d.id] : null;

  void put(Document d, Float32List v) {
    vectors[d.id] = v;
    keys[d.id] = meaningKey(d);
  }

  bool has(Document d) => of(d) != null;

  /// Toglie i documenti che non ci sono più.
  void retain(Set<String> ids) {
    vectors.removeWhere((k, _) => !ids.contains(k));
    keys.removeWhere((k, _) => !ids.contains(k));
  }

  void clear() {
    vectors.clear();
    keys.clear();
  }

  int get length => vectors.length;

  /// Solo i vettori aggiornati dei documenti dati.
  Map<String, Float32List> current(Iterable<Document> docs) => {
        for (final d in docs)
          if (of(d) != null) d.id: vectors[d.id]!,
      };

  Map<String, dynamic> toJson() => {
        'size': meaningSize,
        'docs': {
          for (final e in vectors.entries)
            e.key: {'k': keys[e.key], 'v': base64Encode(e.value.buffer.asUint8List(e.value.offsetInBytes, e.value.lengthInBytes))},
        },
      };

  static MeaningStore fromJson(Map<String, dynamic> j) {
    final s = MeaningStore();
    if (j['size'] != meaningSize) return s;
    final docs = (j['docs'] as Map?)?.cast<String, dynamic>() ?? const {};
    for (final e in docs.entries) {
      final m = (e.value as Map).cast<String, dynamic>();
      final bytes = base64Decode(m['v'] as String);
      s.vectors[e.key] = Float32List.fromList(bytes.buffer.asFloat32List(bytes.offsetInBytes, bytes.lengthInBytes ~/ 4));
      s.keys[e.key] = m['k'] as String;
    }
    return s;
  }
}
