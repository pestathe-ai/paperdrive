import 'package:flutter/services.dart';

/// I file originali sul telefono (es. nella cartella Download): scelta con
/// il selettore di Android tenendo il permesso di modificarli, ed
/// eliminazione dopo che il documento è arrivato su Drive.
class Originals {
  static const MethodChannel _channel = MethodChannel('paperdrive/share');

  /// File scelti: (copia nella cache, nome, indirizzo dell'originale).
  /// Null se il selettore nativo non c'è (si usa quello generico).
  static Future<List<(String, String, String?)>?> pick() async {
    try {
      final raw = await _channel.invokeListMethod<Map<dynamic, dynamic>>('pickDocuments');
      return [
        for (final m in raw ?? const <Map<dynamic, dynamic>>[])
          if (m['path'] != null) ('${m['path']}', '${m['name'] ?? 'documento.pdf'}', m['uri'] as String?),
      ];
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Elimina l'originale. Vero se ci è riuscito.
  static Future<bool> delete(String uri) async {
    try {
      return await _channel.invokeMethod<bool>('deleteOriginal', {'uri': uri}) ?? false;
    } catch (_) {
      return false;
    }
  }
}
