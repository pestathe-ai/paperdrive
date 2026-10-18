import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/pdf.dart' as pdfl;
import 'package:pdf/widgets.dart' as pw;

/// Una riga di testo riconosciuta, con la sua posizione nell'immagine (pixel).
class OcrLine {
  OcrLine(this.text, this.left, this.top, this.width, this.height);
  final String text;
  final double left, top, width, height;
}

/// Risultato dell'OCR di una pagina.
class OcrPage {
  OcrPage({
    required this.imagePath,
    required this.width,
    required this.height,
    required this.text,
    required this.lines,
  });

  final String imagePath;
  final int width;
  final int height;
  final String text;
  final List<OcrLine> lines;
}

String cleanPdfText(String s) =>
    s.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), ' ');

/// Crea un PDF/A (parte 3, livello B): l'immagine di ogni pagina con sopra
/// il testo dell'OCR invisibile, nello stesso punto, così si può cercare,
/// selezionare e copiare. Font incorporato e profilo colore sRGB.
Future<Uint8List> buildArchivePdfBytes(
  List<OcrPage> pages, {
  required String title,
  required pw.Font font,
  required Uint8List iccProfile,
  String author = 'Paperdrive',
}) async {
  final cleanTitle = cleanPdfText(title);
  final doc = pw.Document(
    title: cleanTitle,
    author: author,
    creator: 'Paperdrive',
    producer: 'Paperdrive',
    metadata: pdfl.PdfaRdf(
      title: cleanTitle,
      author: author,
      creator: 'Paperdrive',
      producer: 'Paperdrive',
    ).create(),
  );
  pdfl.PdfaColorProfile(doc.document, iccProfile);
  final textStyle = pw.TextStyle(
    font: font,
    fontSize: 12,
    renderingMode: pdfl.PdfTextRenderingMode.invisible,
  );
  for (final page in pages) {
    final img = pw.MemoryImage(await File(page.imagePath).readAsBytes());
    const w = 595.0;
    final h = page.width > 0 ? w * page.height / page.width : 842.0;
    final s = page.width > 0 ? w / page.width : 1.0;
    doc.addPage(pw.Page(
      pageFormat: pdfl.PdfPageFormat(w, h),
      margin: pw.EdgeInsets.zero,
      build: (_) => pw.Stack(
        children: [
          pw.Positioned(
            left: 0,
            top: 0,
            child: pw.Image(img, width: w, height: h, fit: pw.BoxFit.fill),
          ),
          for (final l in page.lines)
            if (l.width > 2 && l.height > 2 && l.text.trim().isNotEmpty)
              pw.Positioned(
                left: l.left * s,
                top: l.top * s,
                child: pw.SizedBox(
                  width: l.width * s,
                  height: l.height * s,
                  child: pw.FittedBox(
                    fit: pw.BoxFit.fill,
                    child: pw.Text(cleanPdfText(l.text.trim()), style: textStyle),
                  ),
                ),
              ),
        ],
      ),
    ));
  }
  return doc.save();
}
