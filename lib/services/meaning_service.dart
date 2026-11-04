import 'dart:typed_data';

import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_edge_ai_litertlm/flutter_edge_ai_litertlm.dart';
import 'package:material_ui/material_ui.dart';

import '../core/meaning.dart';
import 'ai_assistant.dart' show edgeAiReady;

/// La rete neurale della somiglianza per significato: EmbeddingGemma 2 Text
/// 270M di Google (licenza Apache 2.0, 165 MB, più di 100 lingue). Gira sul
/// processore del telefono, in pochi centesimi di secondo per documento.
class MeaningService extends ChangeNotifier {
  static final LiteRtEmbedderVariant variant = LiteRtEmbedders.embeddinggemma2Text270m.generic;

  /// Dimensione del download, per l'utente.
  static const String sizeLabel = '165 MB';

  EmbeddingModel? _model;
  CancelToken? _cancel;

  /// Percentuale di download in corso, o null.
  int? progress;
  String? error;

  bool get downloading => progress != null;

  /// Il modello è installato su questo telefono.
  Future<bool> installed() async {
    try {
      await edgeAiReady();
      return FlutterEdgeAi.hasActiveEmbedder();
    } catch (_) {
      return false;
    }
  }

  Future<void> install() async {
    if (downloading) return;
    error = null;
    progress = 0;
    notifyListeners();
    _cancel = CancelToken();
    try {
      await edgeAiReady();
      await release();
      await FlutterEdgeAi.installEmbedder()
          .fromCatalog(variant)
          .withCancelToken(_cancel!)
          .withProgress((p) {
            progress = p;
            notifyListeners();
          })
          .install();
    } catch (e) {
      error = e is DownloadCancelledException ? 'Download annullato' : '$e';
      rethrow;
    } finally {
      progress = null;
      _cancel = null;
      notifyListeners();
    }
  }

  void cancelDownload() => _cancel?.cancel('Annullato');

  Future<void> uninstall() async {
    await release();
    try {
      await edgeAiReady();
      await FlutterEdgeAi.uninstallEmbedder();
    } catch (_) {
      // Già cancellato.
    }
    notifyListeners();
  }

  Future<EmbeddingModel> _ensure() async {
    final m = _model;
    if (m != null && !m.isClosed) return m;
    await edgeAiReady();
    // Sul processore: è il modo più affidabile e per testi brevi è veloce.
    return _model = await FlutterEdgeAi.getActiveEmbedder(preferredBackend: PreferredBackend.cpu);
  }

  /// Il vettore (già accorciato e normalizzato) del testo. Null se il
  /// modello non risponde. Se il testo è troppo lungo lo accorcia e riprova.
  Future<Float32List?> embed(String text) async {
    var t = text.trim();
    if (t.isEmpty) return null;
    try {
      final model = await _ensure();
      for (var attempt = 0; attempt < 4; attempt++) {
        try {
          final v = await model.embed(EmbeddingInput.text(t), taskType: TaskType.classification);
          error = null;
          return shrinkMeaning(v);
        } on EmbeddingInputTooLongException {
          t = t.substring(0, t.length ~/ 2);
        }
      }
    } catch (e) {
      error = '$e';
    }
    return null;
  }

  /// Libera la memoria.
  Future<void> release() async {
    final m = _model;
    _model = null;
    if (m != null) {
      try {
        await m.close();
      } catch (_) {}
    }
  }
}
