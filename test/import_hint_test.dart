import 'package:flutter_test/flutter_test.dart';
import 'package:paperdrive/core/archive.dart';
import 'package:paperdrive/core/import_hint.dart';
import 'package:paperdrive/core/models.dart';

void main() {
  test('cartelle utili, anni e mesi', () {
    expect(meaningfulFolders(['Dropbox', 'Casa', '2023', 'Condominio']), ['Casa', 'Condominio']);
    expect(meaningfulFolders(['01 - Gennaio', 'Tasse']), ['Tasse']);
    expect(meaningfulFolders(['2023 Tasse']), ['Tasse']);
    expect(meaningfulFolders(['01 - Casa']), ['Casa']);
    expect(folderYear(['Casa', '2023', 'Condominio']), 2023);
    expect(folderYear(['Tasse 2021']), 2021);
    expect(folderYear(['Casa']), isNull);
  });

  test('formati importabili', () {
    expect(importableFile('a.PDF'), isTrue);
    expect(importableFile('foto.jpeg'), isTrue);
    expect(importableFile('foglio.xlsx'), isFalse);
  });

  group('documento da cartelle', () {
    test('cartella esistente, tag nuovo, anno e nome del file', () {
      final a = Archive.starter();
      final d = Document(
        title: 'x',
        originalName: 'Verbale assemblea condominio giugno.pdf',
        content: 'Verbale del 12/06/2023. Prossima assemblea 10/01/2024.',
        created: DateTime(2024, 1, 10),
      );
      applyFolderHint(a, d, ['Casa', '2023', 'Condominio']);
      expect(d.typeId, 'st-casa');
      expect(d.tagIds.map((id) => a.tag(id)!.name), ['Condominio']);
      expect(d.created, DateTime(2023, 6, 12));
      expect(d.title, 'Verbale assemblea condominio giugno');
      expect(d.userEdited, isTrue);
      expect(d.titleEdited, isTrue);
    });

    test('categoria nuova, nessuna data nel testo, nome casuale', () {
      final a = Archive.starter();
      final d = Document(
        title: 'Titolo automatico',
        originalName: 'IMG_20230412_0001.jpg',
        content: 'Ricevuta veterinario',
        created: DateTime(2026, 10, 22),
      );
      applyFolderHint(a, d, ['Animali', '2021']);
      expect(a.type(d.typeId)?.name, 'Animali');
      expect(d.created, DateTime(2021));
      expect(d.title, 'Titolo automatico');
      expect(d.titleEdited, isFalse);
    });

    test('nessuna cartella: resta la classificazione automatica', () {
      final a = Archive.starter();
      final d = Document(title: 't', originalName: 'scan001.pdf', typeId: 'st-banca');
      applyFolderHint(a, d, const []);
      expect(d.typeId, 'st-banca');
    });
  });
}
