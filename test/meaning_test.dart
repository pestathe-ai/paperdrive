import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:paperdrive/core/meaning.dart';
import 'package:paperdrive/core/models.dart';

void main() {
  test('vettore accorciato e normalizzato', () {
    final v = shrinkMeaning(List<double>.generate(768, (i) => i < 2 ? 3.0 : 0.0));
    expect(v.length, meaningSize);
    expect(meaningCosine(v, v), closeTo(1, 1e-6));
  });

  test('scala del coseno e unione con le parole', () {
    expect(meaningScore(0.3), 0);
    expect(meaningScore(0.95), 1);
    expect(blendSimilarity(0.5, null), 0.5);
    expect(blendSimilarity(0.5, 0), 0.5);
    expect(blendSimilarity(0.1, 0.8), greaterThan(0.25));
  });

  test('i vettori si salvano e valgono solo per lo stesso testo', () {
    final d = Document(id: 'x', title: 't', content: 'contratto di affitto box');
    final s = MeaningStore()..put(d, shrinkMeaning([1, 2, 3]));
    final back = MeaningStore.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
    expect(back.of(d), isNotNull);
    expect(meaningCosine(back.of(d)!, s.of(d)!), closeTo(1, 1e-6));
    // Il titolo può cambiare, il contenuto no.
    d.title = 'altro';
    expect(back.has(d), isTrue);
    d.content = 'testo diverso';
    expect(back.has(d), isFalse);
    back.retain({});
    expect(back.length, 0);
  });
}
