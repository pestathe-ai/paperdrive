/// Correzioni fatte fuori dall'app (su Google Drive) o scrivendo a mano la
/// cartella di un documento: l'app le interpreta e impara.
///
/// - `Tasse/2026` → categoria Tasse.
/// - `Sanità/Luca/…` → persona Luca.
/// - `Casa/Box via Roma/2026` → categoria Casa e una sottocartella "Box via
///   Roma" che diventa un percorso: i documenti simili ci finiranno da soli.
library;

import 'ai.dart' show correctedExample, findByName;
import 'archive.dart';
import 'models.dart';
import 'organize.dart' show drivePath;
import 'people.dart';
import 'workflows.dart' show stripLeadingDate;
import 'text_utils.dart';

final RegExp _yearRe = RegExp(r'^(19|20)\d{2}$');
final RegExp _monthRe = RegExp(
  r'^(\d{1,2}\s*[-_.]?\s*)?(gennaio|febbraio|marzo|aprile|maggio|giugno|luglio|agosto|settembre|ottobre|novembre|dicembre)?$',
  caseSensitive: false,
);

bool _isMonth(String s) {
  final t = s.trim();
  if (t.isEmpty) return false;
  final m = _monthRe.firstMatch(t);
  if (m == null) return false;
  // "03", "3", "03 Marzo", "Marzo": numero 1-12 o nome del mese.
  final num = int.tryParse((m[1] ?? '').replaceAll(RegExp(r'[^0-9]'), ''));
  return m[2] != null || (num != null && num >= 1 && num <= 12 && m[1]!.trim().length <= 2);
}

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Il titolo dal nome del file su Drive: senza ".pdf", " (PDF-A)" e la data
/// che l'app mette davanti.
String titleFromDriveName(String name) {
  var t = name.trim();
  t = t.replaceFirst(RegExp(r'\.pdf$', caseSensitive: false), '');
  t = t.replaceFirst(RegExp(r'\s*\(PDF-A\)$'), '');
  t = stripLeadingDate(t);
  t = t.replaceFirst(RegExp(r'\s+(\d{2}-\d{2}-\d{4}|\d{4}-\d{2}-\d{2})$'), '');
  return t.trim();
}

/// Applica una cartella scelta a mano ([folders], dalla cartella principale
/// in giù, senza il nome del file) e/o un nuovo nome del file. Il documento
/// conta come corretto a mano. Restituisce i campi cambiati.
List<String> applyFolderCorrection(Archive a, Document d, {List<String>? folders, String? fileName}) {
  ensurePeopleEntities(a);
  final changed = <String>[];

  if (fileName != null) {
    final t = titleFromDriveName(fileName);
    final (_, expected) = drivePath(a, d);
    if (t.isNotEmpty && t != d.title && titleFromDriveName(expected) != t) {
      d.title = t;
      d.titleEdited = true;
      changed.add('titolo');
    }
  }

  if (folders != null) {
    var segs = folders.map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    // Rimesso in "Da importare": non è una categoria, si ignora lo spostamento.
    if (segs.isNotEmpty && const {'da importare', 'pdf-a'}.contains(normalize(segs.first))) segs = const [];
    if (segs.isNotEmpty && normalize(segs.first) == 'cestino') {
      if (!d.inTrash) {
        d
          ..inTrash = true
          ..trashedAt = nowMs();
        changed.add('cestino');
      }
      return changed;
    }
    if (d.inTrash) {
      d
        ..inTrash = false
        ..trashedAt = null;
      changed.add('ripristinato');
    }
    if (segs.isNotEmpty) {
      // Categoria: la prima cartella (creata se non esiste).
      var type = findByName(a.activeTypes, segs.first);
      if (type == null) {
        type = NamedEntity(name: _cap(segs.first), algorithm: MatchAlgorithm.auto);
        a.types[type.id] = type;
      }
      if (d.typeId != type.id) {
        d.typeId = type.id;
        changed.add('categoria');
      }

      // Le altre cartelle: anni, mesi, persona, specialità, referti… o
      // sottocartelle personali.
      // La categoria scritta per esteso: la sottocartella vale solo lì.
      final template = <String>[type.name];
      final custom = <String>[];
      String? person;
      for (final s in segs.skip(1)) {
        final n = normalize(s);
        if (_yearRe.hasMatch(s)) {
          template.add('{created_year}');
          continue;
        }
        if (_isMonth(s)) {
          template.add('{mese}');
          continue;
        }
        final p = a.config.people.where((p) => normalize(p.name) == n).firstOrNull;
        if (p != null) {
          person = p.name;
          template.add('{persona}');
          continue;
        }
        if (d.typeId == healthTypeId) {
          if (n == 'referti' || n == 'prescrizioni' || n == 'altro') {
            if (d.customFields[healthKindFieldId] != _cap(n)) changed.add('tipo sanitario');
            d.customFields[healthKindFieldId] = _cap(n);
            template.add('{tipo_sanitario}');
            continue;
          }
          if (specialties.any((e) => normalize(e.$1) == n)) {
            final spec = specialties.firstWhere((e) => normalize(e.$1) == n).$1;
            if (d.customFields[specialtyFieldId] != spec) changed.add('specialità');
            d.customFields[specialtyFieldId] = spec;
            template.add('{specialita}');
            continue;
          }
        }
        template.add(s);
        custom.add(s);
      }
      if (person != null && d.customFields[personFieldId] != person) {
        d.customFields[personFieldId] = person;
        changed.add('persona');
      }

      if (custom.isEmpty) {
        // Struttura standard: basta il modello generale (o quello della sanità).
        final want = d.typeId == healthTypeId ? healthPathId : null;
        if (d.storagePathId != want && (want == null || a.storagePath(want) != null)) {
          d.storagePathId = want;
          changed.add('cartella');
        }
      } else {
        // Sottocartella personale: diventa un percorso che l'app impara.
        final tpl = '${template.join('/')}/{title} {data}';
        var path = a.activeStoragePaths.where((p) => p.template == tpl).firstOrNull;
        if (path == null) {
          // Niente classificatore: ci vanno solo i documenti molto simili
          // (applyLearnedFolder) o quelli che sposti tu.
          path = StoragePath(name: custom.join(' / '), template: tpl);
          a.storagePaths[path.id] = path;
        }
        if (d.storagePathId != path.id) {
          d.storagePathId = path.id;
          changed.add('cartella');
        }
      }
    }
  }
  if (changed.isNotEmpty) d.userEdited = true;
  return changed;
}

/// La cartella attuale del documento, da mostrare e modificare
/// (es. "Casa/Box via Roma/2026").
String folderOf(Archive a, Document d) => drivePath(a, d).$1.join('/');

/// Se un documento simile corretto a mano sta in una sottocartella
/// personale, ci va anche questo (stessa categoria). Restituisce true se
/// cambia.
bool applyLearnedFolder(Archive a, Document d) {
  if (d.storagePathId != null) return false;
  final (example, score) = correctedExample(a, d, min: 0.6);
  final pathId = example?.storagePathId;
  if (example == null || pathId == null || pathId == healthPathId) return false;
  final path = a.storagePath(pathId);
  if (path == null || example.typeId != d.typeId || !learnedPathFits(a, path, d)) return false;
  // Mittente diverso: serve una somiglianza molto alta.
  if (d.correspondentId != null &&
      example.correspondentId != null &&
      d.correspondentId != example.correspondentId &&
      score < 0.8) {
    return false;
  }
  d.storagePathId = pathId;
  return true;
}

/// Una sottocartella creata spostando i file (percorso senza
/// classificatore, con cartelle scritte per esteso).
bool isLearnedPath(StoragePath p) =>
    p.algorithm == MatchAlgorithm.none &&
    p.template.split('/').any((seg) => seg.isNotEmpty && !seg.contains('{'));

/// Una sottocartella imparata vale solo per la sua categoria: un documento
/// di un'altra categoria non ci finisce (es. un'iscrizione all'asilo nella
/// cartella del box).
bool learnedPathFits(Archive a, StoragePath p, Document d) {
  if (!isLearnedPath(p)) return true;
  final first = p.template.split('/').first;
  if (first.contains('{')) return true; // percorsi vecchi: vedi migrateLearnedPaths
  final t = a.type(d.typeId);
  return t != null && normalize(t.name) == normalize(first);
}

/// Percorsi imparati delle versioni precedenti ("{document_type}/…"): la
/// categoria diventa quella dei documenti che ci hai messo tu.
int migrateLearnedPaths(Archive a) {
  var n = 0;
  for (final p in a.storagePaths.values) {
    if (p.deleted || !isLearnedPath(p) || !p.template.startsWith('{document_type}/')) continue;
    final counts = <String, int>{};
    for (final d in a.activeDocuments) {
      if (d.storagePathId == p.id && d.userEdited && d.typeId != null) {
        counts[d.typeId!] = (counts[d.typeId!] ?? 0) + 1;
      }
    }
    if (counts.isEmpty) continue;
    final best = counts.entries.reduce((x, y) => x.value >= y.value ? x : y).key;
    final name = a.type(best)?.name;
    if (name == null) continue;
    p
      ..template = '$name${p.template.substring('{document_type}'.length)}'
      ..modified = nowMs();
    n++;
  }
  return n;
}

/// Toglie le sottocartelle imparate che non c'entrano con la categoria.
bool dropUnfitPath(Archive a, Document d) {
  final p = a.storagePath(d.storagePathId);
  if (p == null || learnedPathFits(a, p, d)) return false;
  d.storagePathId = null;
  return true;
}
