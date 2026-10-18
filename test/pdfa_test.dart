import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:paperdrive/services/pdfa.dart';
import 'package:pdf/widgets.dart' as pw;

/// Immagine bianca 200x100 (PNG).
const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAMgAAABkCAIAAABM5OhcAAAAxklEQVR42u3SMQ0AAAzDsPIn3aKYtMOGECWFA5EAY2EsjAXGwlgYC4yFsTAWGAtjYSwwFsbCWGAsjIWxwFgYC2OBsTAWxgJjYSyMBcbCWBgLjIWxMBYYC2NhLDAWxsJYYCyMhbHAWBgLY4GxMBbGAmNhLIwFxsJYGAuMhbEwFhgLY2EsMBbGwlhgLIyFscBYGAtjgbEwFsYCY2EsjAXGwlgYC4yFsTAWGAtjYSwwFsbCWBgLjIWxMBYYC2NhLDAWxsJYYCx+GyYcg0iDFNMFAAAAAElFTkSuQmCC';

void main() {
  test('versione archiviata PDF/A con testo invisibile', () async {
    final dir = await Directory.systemTemp.createTemp('pdfa');
    final img = File('${dir.path}/page.png')..writeAsBytesSync(base64Decode(_png));
    final font = pw.Font.ttf(
        File('assets/Lato-Regular.ttf').readAsBytesSync().buffer.asByteData());
    final icc = File('assets/sRGB2014.icc').readAsBytesSync();
    final pages = [
      OcrPage(
        imagePath: img.path,
        width: 200,
        height: 100,
        text: 'Fattura numero 123\nTotale 45,30 €',
        lines: [
          OcrLine('Fattura numero 123', 10, 10, 150, 14),
          OcrLine('Totale 45,30 € — società', 10, 40, 120, 12),
          OcrLine('', 0, 0, 0, 0),
        ],
      ),
      OcrPage(imagePath: img.path, width: 200, height: 100, text: '', lines: const []),
    ];
    final bytes = await buildArchivePdfBytes(
      pages,
      title: 'Prova "PDF/A"',
      font: font,
      iccProfile: icc,
    );
    final head = latin1.decode(bytes.sublist(0, 8));
    expect(head.startsWith('%PDF-'), isTrue);
    expect(bytes.length, greaterThan(1000));

    final out = Platform.environment['PDFA_OUT'];
    if (out != null && out.isNotEmpty) File(out).writeAsBytesSync(bytes);
  });
}
