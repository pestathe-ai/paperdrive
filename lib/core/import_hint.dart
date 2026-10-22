/// Cartella di importazione (come la "consume folder" di Paperless): i
/// documenti già ordinati a mano portano con sé le cartelle in cui stavano,
/// che diventano categoria, tag e anno.
library;

import 'ai.dart' show findByName;
import 'archive.dart';
import 'dates.dart';
import 'extract.dart' show meaningfulFileName;
import 'formats.dart';
import 'models.dart';
import 'text_utils.dart';

/// Nome della cartella su Drive (dentro "Paperdrive").
const String inboxFolderName = 'Da importare';

/// Formati che si possono importare.
bool importableFile(String name, {String? mimeType}) =>
    fileKind(name, mimeType: mimeType) != FileKind.unsupported;

final RegExp _year = RegExp(r'^(19|20)\d{2}$');

const Set<String> _months = {
  'gennaio', 'febbraio', 'marzo', 'aprile', 'maggio', 'giugno', 'luglio',
  'agosto', 'settembre', 'ottobre', 'novembre', 'dicembre',
  'gen', 'feb', 'mar', 'apr', 'mag', 'giu', 'lug', 'ago', 'set', 'ott', 'nov', 'dic',
};

/// Cartelle che non dicono nulla sul documento.
const Set<String> _generic = {
  'dropbox', 'documenti', 'documents', 'archivio', 'paperdrive', 'pdf',
  'scansioni', 'scans', 'file', 'files', 'nuova cartella', 'new folder',
};

/// L'anno indicato dalle cartelle (il più interno), se c'è.
int? folderYear(List<String> folders) {
  for (final f in folders.reversed) {
    final m = RegExp(r'(?<!\d)((?:19|20)\d{2})(?!\d)').firstMatch(f.trim());
    if (m != null && f.trim().length <= 12) return int.parse(m[1]!);
  }
  return null;
}

/// Le cartelle che hanno un significato (niente anni, mesi, numeri,
/// nomi generici).
List<String> meaningfulFolders(List<String> folders) {
  final out = <String>[];
  for (final raw in folders) {
    final f = raw.trim();
    final n = normalize(f).replaceAll(RegExp(r'^\d+\s*[-_.]?\s*'), '').trim();
    if (f.isEmpty || _year.hasMatch(f) || RegExp(r'^[\d\s._-]+$').hasMatch(f)) continue;
    if (_months.contains(n) || _generic.contains(n)) continue;
    // "2023 Tasse", "01 - Casa" → "Tasse", "Casa".
    out.add(f.replaceFirst(RegExp(r'^\d+\s*[-_.)]?\s*'), '').trim());
  }
  return out.where((e) => e.isNotEmpty).toList();
}

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Applica ciò che dicono le cartelle e il nome del file. Ha la precedenza
/// su regole e AI: è l'ordine scelto da te. Il documento conta come
/// corretto a mano, così l'app impara dal tuo archivio.
void applyFolderHint(Archive a, Document d, List<String> folders) {
  final names = meaningfulFolders(folders);
  if (names.isNotEmpty) {
    var t = findByName(a.activeTypes, names.first);
    if (t == null) {
      t = NamedEntity(name: _cap(names.first), algorithm: MatchAlgorithm.auto);
      a.types[t.id] = t;
    }
    d.typeId = t.id;
    for (final sub in names.skip(1)) {
      var tag = findByName(a.activeTags.where((x) => !x.isInbox), sub);
      if (tag == null) {
        tag = Tag(name: _cap(sub), algorithm: MatchAlgorithm.auto);
        a.tags[tag.id] = tag;
      }
      d.tagIds.add(tag.id);
    }
  }

  final year = folderYear(folders);
  if (year != null && d.created.year != year) {
    final dates = findDates(d.content);
    final sameYear = dates.where((x) => x.year == year);
    if (sameYear.isNotEmpty) {
      d.created = sameYear.first;
    } else if (dates.isEmpty) {
      d.created = DateTime(year);
    }
  }

  final name = meaningfulFileName(d.originalName);
  if (name != null) {
    d.title = name;
    d.titleEdited = true;
  }
  d.userEdited = true;
}
