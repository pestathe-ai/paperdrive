/// Classificatore automatico, come quello di Paperless-ngx
/// (`documents/classifier.py`):
///
/// - impara solo dai documenti che NON hanno un tag "da esaminare";
/// - impara solo le etichette con algoritmo "Automatica";
/// - testo → parole minuscole (`\b\w+\b`) → conteggio di parole singole e
///   coppie di parole (CountVectorizer, ngram 1-2, min_df 1%);
/// - una rete neurale con uno strato nascosto da 100 neuroni (MLPClassifier,
///   ReLU, Adam, tol 0.01), con pesi bilanciati tra le classi;
/// - corrispondente, tipo e percorso: assegnati solo se la probabilità
///   supera 0.3 (CLASSIFIER_MATCH_THRESHOLD); tag: probabilità > 0.5.
library;

import 'dart:math';
import 'dart:typed_data';

import 'archive.dart';
import 'models.dart';

final RegExp _wordRe = RegExp(r'[\p{L}\p{N}_]+', unicode: true);

/// Come `preprocess_content`: parole minuscole separate da spazi.
List<String> preprocess(String content) =>
    _wordRe.allMatches(content.toLowerCase()).map((m) => m.group(0)!).toList();

List<String> _features(List<String> words) {
  final out = <String>[...words];
  for (var i = 0; i + 1 < words.length; i++) {
    out.add('${words[i]} ${words[i + 1]}');
  }
  return out;
}

/// Vettore sparso: indice della parola -> conteggio.
typedef Sparse = Map<int, double>;

class Vectorizer {
  Vectorizer(this.vocabulary);

  final Map<String, int> vocabulary;

  int get size => vocabulary.length;

  /// Costruisce il vocabolario: tiene i termini presenti in almeno l'1% dei
  /// documenti (e in almeno 1), al massimo [maxFeatures] (i più frequenti).
  factory Vectorizer.fit(List<String> texts, {int maxFeatures = 3000}) {
    final df = <String, int>{};
    for (final t in texts) {
      for (final f in _features(preprocess(t)).toSet()) {
        df[f] = (df[f] ?? 0) + 1;
      }
    }
    final minDf = max(1, (texts.length * 0.01).ceil());
    final kept = df.entries.where((e) => e.value >= minDf).toList()
      ..sort((a, b) {
        final c = b.value.compareTo(a.value);
        return c != 0 ? c : a.key.compareTo(b.key);
      });
    final vocab = <String, int>{};
    for (final e in kept.take(maxFeatures)) {
      vocab[e.key] = vocab.length;
    }
    return Vectorizer(vocab);
  }

  Sparse transform(String text) {
    final v = <int, double>{};
    for (final f in _features(preprocess(text))) {
      final i = vocabulary[f];
      if (i != null) v[i] = (v[i] ?? 0) + 1;
    }
    return v;
  }
}

/// Rete con uno strato nascosto (ReLU). [multiLabel]: uscite indipendenti
/// (sigmoide, per i tag); altrimenti softmax (una sola classe).
class Mlp {
  Mlp(this.inputs, this.outputs, {this.hidden = 100, required this.multiLabel, int seed = 0})
      : w1 = List.generate(inputs, (_) => Float64List0(hidden)),
        b1 = List.filled(hidden, 0.0),
        w2 = List.generate(hidden, (_) => Float64List0(outputs)),
        b2 = List.filled(outputs, 0.0) {
    // Inizializzazione Glorot come scikit-learn.
    final r = Random(seed);
    final f1 = sqrt(6 / (inputs + hidden));
    final f2 = sqrt(6 / (hidden + outputs));
    for (final row in w1) {
      for (var j = 0; j < hidden; j++) {
        row[j] = (r.nextDouble() * 2 - 1) * f1;
      }
    }
    for (final row in w2) {
      for (var k = 0; k < outputs; k++) {
        row[k] = (r.nextDouble() * 2 - 1) * f2;
      }
    }
  }

  final int inputs;
  final int outputs;
  final int hidden;
  final bool multiLabel;
  final List<List<double>> w1;
  final List<double> b1;
  final List<List<double>> w2;
  final List<double> b2;

  List<double> _hidden(Sparse x) {
    final h = List<double>.from(b1);
    x.forEach((i, v) {
      final row = w1[i];
      for (var j = 0; j < hidden; j++) {
        h[j] += row[j] * v;
      }
    });
    for (var j = 0; j < hidden; j++) {
      if (h[j] < 0) h[j] = 0;
    }
    return h;
  }

  List<double> _out(List<double> h) {
    final o = List<double>.from(b2);
    for (var j = 0; j < hidden; j++) {
      final hj = h[j];
      if (hj == 0) continue;
      final row = w2[j];
      for (var k = 0; k < outputs; k++) {
        o[k] += row[k] * hj;
      }
    }
    if (multiLabel) {
      for (var k = 0; k < outputs; k++) {
        o[k] = 1 / (1 + exp(-o[k]));
      }
    } else {
      final m = o.reduce(max);
      var s = 0.0;
      for (var k = 0; k < outputs; k++) {
        o[k] = exp(o[k] - m);
        s += o[k];
      }
      for (var k = 0; k < outputs; k++) {
        o[k] /= s;
      }
    }
    return o;
  }

  List<double> predictProba(Sparse x) => _out(_hidden(x));

  /// Addestramento con Adam (lr 0.001, batch 200, alpha 1e-4, max 200 epoche,
  /// stop quando la perdita migliora meno di [tol] per 10 epoche di fila),
  /// come i valori predefiniti di MLPClassifier.
  void fit(List<Sparse> xs, List<List<double>> ys, List<double> weights,
      {int maxEpochs = 100, double tol = 0.01, int seed = 0}) {
    const lr = 0.001, beta1 = 0.9, beta2 = 0.999, eps = 1e-8, alpha = 1e-4;
    final n = xs.length;
    final batch = min(200, n);
    final r = Random(seed);
    // Momenti di Adam.
    final mW1 = List.generate(inputs, (_) => Float64List0(hidden));
    final vW1 = List.generate(inputs, (_) => Float64List0(hidden));
    final mB1 = List.filled(hidden, 0.0), vB1 = List.filled(hidden, 0.0);
    final mW2 = List.generate(hidden, (_) => Float64List0(outputs));
    final vW2 = List.generate(hidden, (_) => Float64List0(outputs));
    final mB2 = List.filled(outputs, 0.0), vB2 = List.filled(outputs, 0.0);
    var t = 0;
    var best = double.infinity;
    var noImprove = 0;
    final order = List<int>.generate(n, (i) => i);
    for (var epoch = 0; epoch < maxEpochs; epoch++) {
      order.shuffle(r);
      var loss = 0.0;
      for (var start = 0; start < n; start += batch) {
        final idx = order.sublist(start, min(n, start + batch));
        final gW1 = <int, List<double>>{};
        final gB1 = List.filled(hidden, 0.0);
        final gW2 = List.generate(hidden, (_) => Float64List0(outputs));
        final gB2 = List.filled(outputs, 0.0);
        var wsum = 0.0;
        for (final i in idx) {
          wsum += weights[i];
        }
        for (final i in idx) {
          final x = xs[i], y = ys[i], w = weights[i] / wsum;
          final h = _hidden(x);
          final p = _out(h);
          // Perdita (log-loss) e gradiente sull'uscita.
          final d2 = List<double>.filled(outputs, 0);
          for (var k = 0; k < outputs; k++) {
            final pk = p[k].clamp(1e-10, 1 - 1e-10);
            if (multiLabel) {
              loss -= weights[i] * (y[k] * log(pk) + (1 - y[k]) * log(1 - pk));
            } else if (y[k] > 0) {
              loss -= weights[i] * log(pk);
            }
            d2[k] = (p[k] - y[k]) * w;
          }
          final d1 = List<double>.filled(hidden, 0);
          for (var j = 0; j < hidden; j++) {
            final hj = h[j];
            final row = w2[j];
            var s = 0.0;
            for (var k = 0; k < outputs; k++) {
              if (hj != 0) gW2[j][k] += hj * d2[k];
              s += row[k] * d2[k];
            }
            d1[j] = hj > 0 ? s : 0;
          }
          for (var k = 0; k < outputs; k++) {
            gB2[k] += d2[k];
          }
          for (var j = 0; j < hidden; j++) {
            gB1[j] += d1[j];
          }
          x.forEach((fi, v) {
            final g = gW1.putIfAbsent(fi, () => List.filled(hidden, 0.0));
            for (var j = 0; j < hidden; j++) {
              g[j] += d1[j] * v;
            }
          });
        }
        t++;
        final c1 = 1 - pow(beta1, t), c2 = 1 - pow(beta2, t);
        void step(List<double> p, List<double> g, List<double> m, List<double> v, bool reg) {
          for (var j = 0; j < p.length; j++) {
            final gj = g[j] + (reg ? alpha * p[j] / idx.length : 0);
            m[j] = beta1 * m[j] + (1 - beta1) * gj;
            v[j] = beta2 * v[j] + (1 - beta2) * gj * gj;
            p[j] -= lr * (m[j] / c1) / (sqrt(v[j] / c2) + eps);
          }
        }

        gW1.forEach((fi, g) => step(w1[fi], g, mW1[fi], vW1[fi], true));
        step(b1, gB1, mB1, vB1, false);
        for (var j = 0; j < hidden; j++) {
          step(w2[j], gW2[j], mW2[j], vW2[j], true);
        }
        step(b2, gB2, mB2, vB2, false);
      }
      loss /= n;
      if (loss > best - tol) {
        noImprove++;
        if (noImprove >= 10) break;
      } else {
        noImprove = 0;
      }
      if (loss < best) best = loss;
    }
  }
}

// ignore: non_constant_identifier_names
List<double> Float64List0(int n) => Float64List(n);

/// Esempi minimi per imparare un'etichetta.
const int minExamples = 3;

/// Un classificatore a classe singola (corrispondente, tipo, percorso).
class _Single {
  _Single(this.classes, this.net);
  final List<String?> classes; // null = "nessuno" (-1 in Paperless)
  final Mlp net;

  String? predict(Sparse x, double threshold) {
    final p = net.predictProba(x);
    var best = 0;
    for (var k = 1; k < p.length; k++) {
      if (p[k] > p[best]) best = k;
    }
    final c = classes[best];
    if (c == null) return null;
    if (threshold > 0 && p[best] < threshold) return null;
    return c;
  }
}

/// Pesi bilanciati come `compute_sample_weight("balanced")`.
List<double> _balanced(List<String?> labels) {
  final counts = <String?, int>{};
  for (final l in labels) {
    counts[l] = (counts[l] ?? 0) + 1;
  }
  final n = labels.length, k = counts.length;
  return [for (final l in labels) n / (k * counts[l]!)];
}

_Single? _trainSingle(List<Sparse> xs, List<String?> rawLabels, int inputs) {
  // Con pochi esempi l'app tirerebbe a indovinare: servono almeno 3
  // documenti per etichetta, gli altri contano come "nessuna".
  final counts = <String, int>{};
  for (final l in rawLabels.whereType<String>()) {
    counts[l] = (counts[l] ?? 0) + 1;
  }
  final labels = [for (final l in rawLabels) l != null && counts[l]! >= minExamples ? l : null];
  final distinct = labels.whereType<String>().toSet();
  if (distinct.isEmpty) return null;
  final classes = <String?>[null, ...distinct.toList()..sort()];
  if (!labels.contains(null)) classes.remove(null);
  if (classes.length == 1) {
    // Una sola classe possibile: Paperless la assegna sempre; qui solo con
    // abbastanza esempi.
    if (labels.length < 10) return null;
    return _Single(classes, Mlp(inputs, 1, multiLabel: false));
  }
  final ys = [
    for (final l in labels) [for (final c in classes) c == l ? 1.0 : 0.0],
  ];
  final net = Mlp(inputs, classes.length, multiLabel: false);
  net.fit(xs, ys, _balanced(labels));
  return _Single(classes, net);
}

/// Il classificatore addestrato.
class DocumentClassifier {
  DocumentClassifier._(this.vectorizer, this._corr, this._type, this._path, this._tagIds, this._tags,
      this.trainedOn, this._minTraining);

  final int _minTraining;

  final Vectorizer vectorizer;
  final _Single? _corr;
  final _Single? _type;
  final _Single? _path;
  final List<String> _tagIds;
  final Mlp? _tags;

  /// Quanti documenti sono stati usati.
  final int trainedOn;

  /// Più severa di Paperless (0.3): gli archivi sul telefono sono piccoli e
  /// un'etichetta sbagliata manda il documento nella cartella sbagliata.
  static const double matchThreshold = 0.55;

  /// Sotto questo numero di documenti esaminati non si prevede nulla.
  static const int minTraining = 10;

  bool get _ready => trainedOn >= _minTraining;

  String? predictCorrespondent(String content) =>
      _ready ? _corr?.predict(vectorizer.transform(content), matchThreshold) : null;
  String? predictDocumentType(String content) =>
      _ready ? _type?.predict(vectorizer.transform(content), matchThreshold) : null;
  String? predictStoragePath(String content) =>
      _ready ? _path?.predict(vectorizer.transform(content), 0.7) : null;

  List<String> predictTags(String content) {
    final net = _tags;
    if (net == null || !_ready) return const [];
    final p = net.predictProba(vectorizer.transform(content));
    return [
      for (var k = 0; k < _tagIds.length; k++)
        if (p[k] > 0.5) _tagIds[k],
    ];
  }

  /// Addestra sui documenti dell'archivio. Restituisce null se non ci sono
  /// documenti utilizzabili (come il "No training data available").
  static DocumentClassifier? train(Archive a, {int minTraining = DocumentClassifier.minTraining}) {
    final inbox = a.inboxTags.map((t) => t.id).toSet();
    // Come Paperless i documenti esaminati; in più quelli corretti a mano.
    final docs = a.activeDocuments
        .where((d) => (!d.tagIds.any(inbox.contains) || d.userEdited) && d.content.trim().isNotEmpty)
        .toList()
      ..sort((x, y) => x.id.compareTo(y.id));
    if (docs.isEmpty) return null;

    // Paperless impara solo le voci "Automatica"; qui anche quelle assegnate
    // a mano con altre regole, così ogni correzione insegna qualcosa.
    bool auto(Matchable? m) => m != null;
    final labelsCorr = [for (final d in docs) auto(a.correspondent(d.correspondentId)) ? d.correspondentId : null];
    final labelsType = [for (final d in docs) auto(a.type(d.typeId)) ? d.typeId : null];
    final labelsPath = [for (final d in docs) auto(a.storagePath(d.storagePathId)) ? d.storagePathId : null];
    final autoTags = a.activeTags.where((t) => !t.isInbox).map((t) => t.id).toSet();
    final labelsTags = [for (final d in docs) d.tagIds.where(autoTags.contains).toSet()];

    final hasAny = labelsCorr.any((l) => l != null) ||
        labelsType.any((l) => l != null) ||
        labelsPath.any((l) => l != null) ||
        labelsTags.any((l) => l.isNotEmpty);
    if (!hasAny) return null;

    final vec = Vectorizer.fit([for (final d in docs) d.content]);
    if (vec.size == 0) return null;
    final xs = [for (final d in docs) vec.transform(d.content)];

    final tagIds = labelsTags.expand((s) => s).toSet().toList()..sort();
    Mlp? tagNet;
    if (tagIds.isNotEmpty) {
      tagNet = Mlp(vec.size, tagIds.length, multiLabel: true);
      final ys = [
        for (final s in labelsTags) [for (final t in tagIds) s.contains(t) ? 1.0 : 0.0],
      ];
      tagNet.fit(xs, ys, List.filled(xs.length, 1.0));
    }
    return DocumentClassifier._(
      vec,
      _trainSingle(xs, labelsCorr, vec.size),
      _trainSingle(xs, labelsType, vec.size),
      _trainSingle(xs, labelsPath, vec.size),
      tagIds,
      tagNet,
      docs.length,
      minTraining,
    );
  }
}
