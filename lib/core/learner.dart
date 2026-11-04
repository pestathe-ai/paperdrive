/// Apprendimento per esempi: l'app guarda i documenti che hai già sistemato
/// (o corretto a mano) e, per un documento nuovo, chiede ai più simili:
/// "voi che mittente, che categoria, che cartella avete?". Vince la
/// risposta su cui i vicini sono d'accordo, pesata da quanto sono simili.
///
/// Rispetto a un modello statistico addestrato una volta, funziona già con
/// pochi esempi, ogni correzione conta subito e si può sempre dire perché
/// ha deciso così (i documenti simili che ha guardato).
///
/// Progetto originale di D. Paper Lab (vedi DESIGN.md).
library;

import 'archive.dart';
import 'matching.dart' show Idf, cosine, weightedVector;
import 'models.dart';

/// Una risposta dell'apprendimento, con la fiducia (0..1).
class Guess {
  const Guess(this.label, this.confidence);
  final String label;
  final double confidence;

  @override
  String toString() => 'Guess($label, ${confidence.toStringAsFixed(2)})';
}

class _Example {
  _Example(this.id, this.vector, this.correspondent, this.type, this.path, this.tags);
  final String id;
  final Map<String, double> vector;
  final String? correspondent;
  final String? type;
  final String? path;
  final Set<String> tags;
}

class Learner {
  Learner._(this._idf, this._examples, this._minTraining);

  final Idf _idf;
  final List<_Example> _examples;
  final int _minTraining;

  /// Quanti documenti fanno da esempio.
  int get trainedOn => _examples.length;

  /// Esempi minimi prima di dare risposte.
  static const int minTraining = 6;

  /// Vicini considerati e somiglianza minima per contare come vicino.
  static const int neighbours = 7;
  static const double minSimilarity = 0.25;

  /// Prepara gli esempi: i documenti già esaminati e quelli corretti a mano.
  /// Null se non ce n'è nessuno.
  static Learner? train(Archive a, {int minTraining = Learner.minTraining}) {
    final inbox = a.inboxTags.map((t) => t.id).toSet();
    final idf = Idf.of(a);
    final examples = <_Example>[];
    for (final d in a.activeDocuments) {
      if (d.content.trim().isEmpty) continue;
      if (d.tagIds.any(inbox.contains) && !d.userEdited) continue;
      final path = a.storagePath(d.storagePathId);
      examples.add(_Example(
        d.id,
        weightedVector(d.content, idf),
        a.correspondent(d.correspondentId)?.id,
        a.type(d.typeId)?.id,
        // Le sottocartelle create spostando i file non si indovinano: valgono
        // solo per i documenti molto simili (vedi drive_learning.dart).
        path?.algorithm == MatchAlgorithm.auto ? path!.id : null,
        d.tagIds.where((t) => !inbox.contains(t) && a.tag(t) != null).toSet(),
      ));
    }
    if (examples.isEmpty) return null;
    return Learner._(idf, examples, minTraining);
  }

  /// I documenti d'esempio più simili al testo, con la somiglianza.
  List<(String, double)> similar(String text, {int limit = neighbours}) =>
      [for (final (e, s) in _neighbours(text, limit: limit)) (e.id, s)];

  List<(_Example, double)> _neighbours(String text, {int limit = neighbours}) {
    final v = weightedVector(text, _idf);
    if (v.isEmpty) return const [];
    final out = <(_Example, double)>[];
    for (final e in _examples) {
      final s = cosine(v, e.vector);
      if (s >= minSimilarity) out.add((e, s));
    }
    out.sort((x, y) => y.$2.compareTo(x.$2));
    return out.take(limit).toList();
  }

  /// Il voto dei vicini per un campo.
  Guess? _vote(String text, String? Function(_Example) field) {
    if (trainedOn < _minTraining) return null;
    final near = _neighbours(text);
    if (near.isEmpty) return null;
    final weight = <String, double>{};
    final count = <String, int>{};
    final best = <String, double>{};
    var total = 0.0;
    for (final (e, s) in near) {
      final w = s * s;
      total += w;
      final label = field(e);
      if (label == null) continue;
      weight[label] = (weight[label] ?? 0) + w;
      count[label] = (count[label] ?? 0) + 1;
      if (s > (best[label] ?? 0)) best[label] = s;
    }
    if (weight.isEmpty || total == 0) return null;
    final top = weight.entries.reduce((x, y) => x.value >= y.value ? x : y);
    final share = top.value / total;
    final maxSim = best[top.key]!;
    // Servono almeno due vicini d'accordo, oppure uno quasi identico.
    if ((count[top.key] ?? 0) < 2 && maxSim < 0.75) return null;
    final confidence = share * (0.5 + maxSim / 2);
    if (share < 0.5 || confidence < 0.3) return null;
    return Guess(top.key, confidence.clamp(0, 1).toDouble());
  }

  Guess? correspondent(String text) => _vote(text, (e) => e.correspondent);
  Guess? type(String text) => _vote(text, (e) => e.type);
  Guess? storagePath(String text) => _vote(text, (e) => e.path);

  /// I tag che hanno almeno metà dei vicini (pesati) e almeno due esempi.
  List<String> tags(String text) {
    if (trainedOn < _minTraining) return const [];
    final near = _neighbours(text);
    if (near.isEmpty) return const [];
    var total = 0.0;
    final weight = <String, double>{};
    final count = <String, int>{};
    for (final (e, s) in near) {
      final w = s * s;
      total += w;
      for (final t in e.tags) {
        weight[t] = (weight[t] ?? 0) + w;
        count[t] = (count[t] ?? 0) + 1;
      }
    }
    return [
      for (final e in weight.entries)
        if (e.value / total >= 0.5 && (count[e.key] ?? 0) >= 2) e.key,
    ];
  }

  // Nomi brevi usati nel resto dell'app.
  String? predictCorrespondent(String text) => correspondent(text)?.label;
  String? predictDocumentType(String text) => type(text)?.label;
  String? predictStoragePath(String text) => storagePath(text)?.label;
  List<String> predictTags(String text) => tags(text);
}
