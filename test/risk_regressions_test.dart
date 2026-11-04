import 'package:flutter_test/flutter_test.dart';
import 'package:paperdrive/core/amounts.dart';
import 'package:paperdrive/core/archive.dart';
import 'package:paperdrive/core/drive_learning.dart';
import 'package:paperdrive/core/import_hint.dart';
import 'package:paperdrive/core/models.dart';
import 'package:paperdrive/core/organize.dart';
import 'package:paperdrive/core/people.dart';
import 'package:paperdrive/core/sync_merge.dart';
import 'package:paperdrive/core/workflows.dart';

void main() {
  group('la sincronizzazione non toglie mai l\'ultima copia', () {
    test('nuova revisione segnata ma il file non c\'è da nessuna parte: resta l\'originale', () {
      final a = Archive();
      final d = Document(id: 'abc', title: 'x', fileRev: 1);
      a.documents[d.id] = d;
      final plan = planFiles(a, localFiles: {'abc.pdf'}, remoteFiles: {'abc.pdf'});
      expect(plan.deleteRemote, isEmpty);
      expect(plan.deleteLocal, isEmpty);
    });

    test('PDF/A segnato ma mancante (solo elenco sul telefono): l\'originale resta su Drive', () {
      final a = Archive();
      a.documents['abc'] = Document(id: 'abc', title: 'x', archiveRev: 1);
      final plan = planFiles(a, localFiles: <String>{}, remoteFiles: {'abc.pdf'}, downloadMissing: false);
      expect(plan.deleteRemote, isEmpty);
    });

    test('quando la nuova versione è su Drive, la vecchia si toglie', () {
      final a = Archive();
      a.documents['abc'] = Document(id: 'abc', title: 'x', fileRev: 1);
      final plan = planFiles(a, localFiles: {'abc.v1.pdf'}, remoteFiles: {'abc.pdf', 'abc.v1.pdf'});
      expect(plan.deleteRemote, ['abc.pdf']);
      expect(plan.deleteLocal, isEmpty);
      expect(plan.upload, isEmpty);
    });

    test('un telefono con l\'indice vecchio non riporta indietro il file', () {
      final phoneA = Archive()..documents['d'] = Document(id: 'd', title: 'Vecchio', fileRev: 1, modified: 100);
      final phoneB = Archive()..documents['d'] = Document(id: 'd', title: 'Rinominato', fileRev: 0, modified: 200);
      final (merged, _) = mergeArchives(phoneB, phoneA);
      expect(merged.documents['d']!.title, 'Rinominato');
      expect(merged.documents['d']!.fileRev, 1);
    });
  });

  group('stessa data di modifica su due telefoni', () {
    Document version(String title) => Document(id: 'd1', title: title, modified: 500);

    test('vince la stessa versione in tutte e due le direzioni', () {
      final phone = Archive()..documents['d1'] = version('Bolletta luce');
      final drive = Archive()..documents['d1'] = version('Bolletta gas');
      final (onPhone, report) = mergeArchives(phone, drive);
      final (onOther, _) = mergeArchives(drive, phone);
      expect(onPhone.documents['d1']!.title, onOther.documents['d1']!.title);
      if (onPhone.documents['d1']!.title == 'Bolletta luce') expect(report.remoteChanged, isTrue);
    });

    test('a pari data vince la cancellazione', () {
      final alive = Archive()..documents['d1'] = version('x');
      final gone = Archive()..documents['d1'] = (version('')..deleted = true);
      expect(mergeArchives(alive, gone).$1.documents['d1']!.deleted, isTrue);
      expect(mergeArchives(gone, alive).$1.documents['d1']!.deleted, isTrue);
    });
  });

  test('un percorso creato da te con una cartella scritta per esteso viene rispettato', () {
    final a = Archive.starter();
    final p = StoragePath(name: 'Lavoro', template: 'Lavoro/{created_year}/{title} {data}', learned: false);
    a.storagePaths[p.id] = p;
    final d = Document(title: 'Fattura consulenza', typeId: 'st-fattura', created: DateTime(2024, 3, 5), storagePathId: p.id);
    a.documents[d.id] = d;
    final (folders, name) = drivePath(a, d);
    expect(folders, ['Lavoro', '2024']);
    expect(name, 'Fattura consulenza 05-03-2024');
    expect(dropUnfitPath(a, d), isFalse);
    expect(d.storagePathId, p.id);
  });

  test('un modello che finisce con "/" non trasforma una cartella nel nome del file', () {
    final a = Archive.starter();
    final p = StoragePath(name: 'Solo cartelle', template: '{document_type}/{created_year}/');
    a.storagePaths[p.id] = p;
    final d = Document(title: 'Bolletta Enel', typeId: 'st-bolletta', created: DateTime(2024, 3, 5), storagePathId: p.id);
    final (folders, name) = drivePath(a, d);
    expect(folders, ['Bolletta', '2024']);
    expect(name, 'Bolletta Enel');
  });

  group('cartelle "mese anno"', () {
    test('spostare in Bollette/Marzo 2026 non crea una sottocartella imparata', () {
      final a = Archive.starter();
      ensurePeopleEntities(a);
      final before = a.storagePaths.length;
      final d = Document(title: 'Luce', content: 'bolletta luce', typeId: 'st-bolletta', created: DateTime(2026, 3, 5));
      a.documents[d.id] = d;
      applyFolderCorrection(a, d, folders: ['Bollette', 'Marzo 2026']);
      expect(d.typeId, 'st-bolletta');
      expect(a.storagePaths.length, before);
    });

    test('importazione: "Marzo 2023" non è né categoria né tag', () {
      expect(meaningfulFolders(['Bollette', 'Marzo 2023']), ['Bollette']);
      expect(folderYear(['Bollette', 'Marzo 2023']), 2023);
    });
  });

  test('importi: negativi esclusi, migliaia nel titolo', () {
    expect(parseEuro('-50,00'), isNull);
    expect(readAmount(Document(title: 'Rata mutuo 1.234,56', content: '')), 1234.56);
    expect(readAmount(Document(title: 'Ticket 18.94', content: '')), 18.94);
  });

  test('la data nel titolo si riconosce solo intera', () {
    expect(titleHasDate('Verbale 15-3-2024', DateTime(2024, 3, 5)), isFalse);
    expect(titleHasDate('Verbale 05-03-2024', DateTime(2024, 3, 5)), isTrue);
  });

  test('una data rovinata nell\'indice non blocca tutto', () {
    final d = Document.fromJson({'id': 'x', 'title': 't', 'created': '2024-xx-01'});
    expect(d.id, 'x');
  });

  test('un id pericoloso arrivato da un indice condiviso viene reso innocuo', () {
    final d = Document.fromJson({'id': '../../evil', 'title': 't'});
    expect(d.id.contains('/'), isFalse);
    expect(safeDocId(d.id), isTrue);
  });
}
