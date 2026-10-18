import 'package:flutter/services.dart';

/// Riceve i file mandati all'app con "Condividi" o "Apri con".
/// Il codice Android (MainActivity) copia i file e li tiene in attesa.
class ShareReceiver {
  ShareReceiver(this.onFiles);

  /// Riceve coppie (percorso, nome del file).
  final Future<void> Function(List<(String, String)>) onFiles;

  static const MethodChannel _channel = MethodChannel('paperdrive/share');
  bool _busy = false;

  void start() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'shared') await check();
      return null;
    });
    check();
  }

  /// Prende i file in attesa (all'avvio e a ogni nuova condivisione).
  Future<void> check() async {
    if (_busy) return;
    _busy = true;
    try {
      while (true) {
        final raw = await _channel.invokeListMethod<Map<dynamic, dynamic>>('takePending');
        if (raw == null || raw.isEmpty) break;
        final files = [
          for (final m in raw)
            if (m['path'] != null) ('${m['path']}', '${m['name'] ?? 'documento.pdf'}'),
        ];
        await onFiles(files);
      }
    } on MissingPluginException {
      // Piattaforma senza il codice nativo (es. test).
    } catch (_) {
    } finally {
      _busy = false;
    }
  }
}
