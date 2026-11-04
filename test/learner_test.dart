import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:paperdrive/core/archive.dart';
import 'package:paperdrive/core/learner.dart';
import 'package:paperdrive/core/matching.dart';
import 'package:paperdrive/core/meaning.dart';
import 'package:paperdrive/core/models.dart';

Archive _archive({int fillers = 4}) {
  final a = Archive.starter();
  a.correspondents['enel'] = NamedEntity(id: 'enel', name: 'Enel');
  a.correspondents['asilo'] = NamedEntity(id: 'asilo', name: 'Asilo Arcobaleno');
  void add(String id, String text, {String? corr, String? type}) {
    a.documents[id] = Document(id: id, title: id, content: text, correspondentId: corr, typeId: type);
  }

  add('e1', 'fornitura energia elettrica kwh potenza contatore luce', corr: 'enel', type: 'st-bolletta');
  add('e2', 'energia elettrica consumi kwh lettura contatore luce', corr: 'enel', type: 'st-bolletta');
  add('e3', 'luce energia elettrica kwh bolletta potenza impegnata', corr: 'enel', type: 'st-bolletta');
  add('s1', 'asilo nido retta mensile bambini sezione', corr: 'asilo', type: 'st-scuola');
  add('s2', 'asilo nido iscrizione bambini sezione maestre', corr: 'asilo', type: 'st-scuola');
  for (var i = 0; i < fillers; i++) {
    add('f$i', 'documento vario numero $i parole diverse argomento$i');
  }
  return a;
}

/// Vettore finto "sul tema [axis]": come quelli della rete neurale, ma
/// costruito a mano.
Float32List _topic(int axis, {int other = 200, double mix = 0.15}) {
  final v = List<double>.filled(meaningSize, 0);
  v[axis] = 1;
  v[other] = mix;
  return shrinkMeaning(v);
}

void main() {
  test('chiede ai documenti simili e vince la risposta su cui sono d\'accordo', () {
    final l = Learner.train(_archive())!;
    final g = l.correspondent('bolletta luce energia elettrica kwh dicembre')!;
    expect(g.label, 'enel');
    expect(g.confidence, greaterThan(0.6));
    expect(l.type('retta asilo nido bambini dicembre')?.label, 'st-scuola');
  });

  test('con documenti che non somigliano a nessuno non risponde', () {
    final l = Learner.train(_archive())!;
    expect(l.correspondent('polizza assicurazione auto furto incendio'), isNull);
  });

  test('pochi esempi: aspetta prima di rispondere', () {
    final a = _archive(fillers: 0)..documents.remove('e3');
    final l = Learner.train(a)!;
    expect(l.trainedOn, 4);
    expect(l.correspondent('energia elettrica kwh luce'), isNull);
    expect(Learner.train(a, minTraining: 0)!.correspondent('energia elettrica kwh luce')?.label, 'enel');
  });

  test('si può dire perché: i documenti simili che ha guardato', () {
    final l = Learner.train(_archive())!;
    final ids = l.similar('energia elettrica kwh luce').map((e) => e.$1).toList();
    expect(ids.take(3), containsAll(['e1', 'e2', 'e3']));
  });

  test('una regola scritta da te vince su ciò che ha imparato', () {
    final a = _archive();
    a.correspondents['mio'] = NamedEntity(id: 'mio', name: 'Fornitore mio', algorithm: MatchAlgorithm.any, pattern: 'dicembre');
    final l = Learner.train(a)!;
    final d = Document(title: 'x', content: 'bolletta luce energia elettrica kwh dicembre');
    expect(computeMatches(a, d, classifier: l).correspondentId, 'mio');
  });

  test('ciò che ha imparato vince sulle regole predefinite se è sicuro', () {
    final a = _archive();
    final l = Learner.train(a)!;
    // "iscrizione" farebbe scattare la categoria predefinita Scuola, ma i
    // documenti simili sono bollette.
    final d = Document(title: 'x', content: 'energia elettrica kwh luce contatore potenza iscrizione');
    expect(computeMatches(a, d, classifier: l).typeId, 'st-bolletta');
  });

  test('con la rete neurale riconosce un documento dal significato, anche senza parole in comune', () {
    final a = _archive();
    void add(String id, String text) {
      a.documents[id] = Document(id: id, title: id, content: text, typeId: 'st-casa');
    }

    add('b1', 'box auto posto macchina condominio spese');
    add('b2', 'box condominio saracinesca manutenzione');
    add('b3', 'posto auto box assemblea condominiale');
    const query = 'fattura idraulico garage riparazione tubo';
    final meanings = {
      for (final id in ['b1', 'b2', 'b3']) id: _topic(3),
      for (final id in ['e1', 'e2', 'e3']) id: _topic(7),
      for (final id in ['s1', 's2']) id: _topic(11),
    };
    // A parole non somiglia a nulla.
    expect(Learner.train(a)!.type(query), isNull);
    final l = Learner.train(a, meanings: meanings)!;
    expect(l.withMeaning, 8);
    expect(l.type(query, meaning: _topic(3, mix: 0.3))?.label, 'st-casa');
    // Senza il vettore del documento nuovo si torna alle parole.
    expect(l.type(query), isNull);
    // Il mittente resta una questione di parole.
    expect(l.correspondent(query), isNull);
  });

  test('il significato non abbassa mai la somiglianza a parole', () {
    final a = _archive();
    final meanings = {for (final id in ['e1', 'e2', 'e3']) id: _topic(5)};
    final l = Learner.train(a, meanings: meanings)!;
    // Vettore su un tema del tutto diverso: decidono comunque le parole.
    expect(l.type('bolletta luce energia elettrica kwh dicembre', meaning: _topic(9))?.label, 'st-bolletta');
  });
}
