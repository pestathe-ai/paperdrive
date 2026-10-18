import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart' show md5;
import 'package:flutter/services.dart' show PlatformException, rootBundle;
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart'
    show InputImage, TextRecognizer, TextRecognitionScript;
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart' as pdfl;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart' show PdfDocument, PdfImageExt;

import '../core/models.dart';
import 'pdfa.dart';
import 'storage.dart';

export 'pdfa.dart' show OcrLine, OcrPage;

/// File pronto per l'archivio: un PDF e, se già note, le immagini delle pagine.
class StagedInput {
  StagedInput({
    required this.pdfPath,
    required this.originalName,
    required this.source,
    this.ocrImages = const [],
  });

  final String pdfPath;
  final String originalName;
  final DocSource source;

  /// Immagini delle pagine da leggere con l'OCR (es. dalla scansione).
  final List<String> ocrImages;
}

/// Risultato dell'analisi: il documento e, se c'è stato OCR, le pagine lette.
class Analysis {
  Analysis(this.doc, this.ocrPages);
  final Document doc;
  final List<OcrPage> ocrPages;
}

/// Trasforma scansioni, foto, PDF ed email in documenti.
class Ingestor {
  Ingestor(this.storage);

  final Storage storage;
  TextRecognizer? _recognizer;
  pw.Font? _font;
  Uint8List? _icc;

  static const int maxOcrPages = 40;

  Future<pw.Font> font() async =>
      _font ??= pw.Font.ttf(await rootBundle.load('assets/Lato-Regular.ttf'));

  Future<Uint8List> _iccProfile() async =>
      _icc ??= (await rootBundle.load('assets/sRGB2014.icc')).buffer.asUint8List();

  Future<(int, int)> _imageSize(String path) async {
    final buffer = await ui.ImmutableBuffer.fromFilePath(path);
    final desc = await ui.ImageDescriptor.encoded(buffer);
    final size = (desc.width, desc.height);
    desc.dispose();
    buffer.dispose();
    return size;
  }

  Future<OcrPage> ocrImage(String path) async {
    _recognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
    final r = await _recognizer!.processImage(InputImage.fromFilePath(path));
    var (w, h) = await _imageSize(path);
    final lines = <OcrLine>[];
    var maxRight = 0.0, maxBottom = 0.0;
    for (final block in r.blocks) {
      for (final line in block.lines) {
        final b = line.boundingBox;
        lines.add(OcrLine(line.text, b.left, b.top, b.width, b.height));
        if (b.right > maxRight) maxRight = b.right;
        if (b.bottom > maxBottom) maxBottom = b.bottom;
      }
    }
    // Foto ruotate (EXIF): l'OCR lavora sull'immagine raddrizzata.
    if (w != h && (maxRight > w * 1.05 || maxBottom > h * 1.05)) {
      final t = w;
      w = h;
      h = t;
    }
    return OcrPage(imagePath: path, width: w, height: h, text: r.text, lines: lines);
  }

  /// Apre lo scanner di documenti di Google (ritaglio e raddrizzamento
  /// automatici). Restituisce null se l'utente annulla.
  Future<StagedInput?> scan() async {
    final scanner = DocumentScanner(
      options: DocumentScannerOptions(
        documentFormats: {DocumentFormat.jpeg, DocumentFormat.pdf},
        pageLimit: 100,
        mode: ScannerMode.full,
        isGalleryImport: true,
      ),
    );
    try {
      final r = await scanner.scanDocument();
      final images = r.images ?? const <String>[];
      String? pdfPath = r.pdf?.uri;
      if (pdfPath == null || !await File(pdfPath).exists()) {
        if (images.isEmpty) return null;
        pdfPath = await imagesToPdf(images);
      }
      final now = DateTime.now();
      return StagedInput(
        pdfPath: pdfPath,
        originalName:
            'Scansione ${formatDate(now)} ${now.hour.toString().padLeft(2, '0')}.${now.minute.toString().padLeft(2, '0')}',
        source: DocSource.scan,
        ocrImages: images,
      );
    } on PlatformException catch (e) {
      if ((e.message ?? '').toLowerCase().contains('cancel')) return null;
      rethrow;
    } finally {
      await scanner.close();
    }
  }

  /// Unisce delle immagini in un PDF (una pagina per immagine, larghezza A4).
  Future<String> imagesToPdf(List<String> imagePaths) async {
    final out = pw.Document();
    for (final path in imagePaths) {
      final bytes = await File(path).readAsBytes();
      final img = pw.MemoryImage(bytes);
      const w = 595.0;
      final iw = img.width, ih = img.height;
      final h = (iw != null && ih != null && iw > 0) ? w * ih / iw : 842.0;
      out.addPage(pw.Page(
        pageFormat: pdfl.PdfPageFormat(w, h),
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Image(img, fit: pw.BoxFit.fill),
      ));
    }
    final path = storage.tmpPath('${newId()}.pdf');
    await File(path).writeAsBytes(await out.save(), flush: true);
    return path;
  }

  /// Prepara un file (PDF o immagine) per l'archivio.
  Future<StagedInput> stageFile(
    String name,
    Uint8List bytes, {
    DocSource source = DocSource.file,
  }) async {
    final ext = p.extension(name).toLowerCase();
    if (ext == '.pdf') {
      final path = storage.tmpPath('${newId()}.pdf');
      await File(path).writeAsBytes(bytes, flush: true);
      return StagedInput(pdfPath: path, originalName: name, source: source);
    }
    final img = storage.tmpPath('${newId()}$ext');
    await File(img).writeAsBytes(bytes, flush: true);
    final pdf = await imagesToPdf([img]);
    return StagedInput(pdfPath: pdf, originalName: name, source: source, ocrImages: [img]);
  }

  static String _clean(String s) => cleanPdfText(s);

  /// Trasforma il testo di un'email in un PDF leggibile (font incorporato).
  Future<StagedInput> textToPdf({
    required String name,
    required String title,
    required List<(String, String)> header,
    required String body,
    DocSource source = DocSource.mail,
  }) async {
    final f = await font();
    final doc = pw.Document(title: title, creator: 'Paperdrive', producer: 'Paperdrive');
    final style = pw.TextStyle(font: f, fontSize: 10.5, lineSpacing: 2);
    final paragraphs = _clean(body).split(RegExp(r'\n')).toList();
    doc.addPage(pw.MultiPage(
      pageFormat: pdfl.PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(48),
      build: (_) => [
        pw.Text(_clean(title), style: pw.TextStyle(font: f, fontSize: 16)),
        pw.SizedBox(height: 8),
        for (final (k, v) in header)
          pw.Text('$k: ${_clean(v)}', style: pw.TextStyle(font: f, fontSize: 9, color: pdfl.PdfColors.grey700)),
        pw.Divider(color: pdfl.PdfColors.grey400),
        for (final para in paragraphs) pw.Text(para.isEmpty ? ' ' : para, style: style),
      ],
    ));
    final path = storage.tmpPath('${newId()}.pdf');
    await File(path).writeAsBytes(await doc.save(), flush: true);
    return StagedInput(pdfPath: path, originalName: name, source: source);
  }

  /// Testo già presente nel PDF (PDF digitali).
  Future<(String, int)> pdfText(String path) async {
    final d = await PdfDocument.openFile(path);
    try {
      final b = StringBuffer();
      for (final page in d.pages) {
        final t = await page.loadText();
        if (t != null && t.fullText.trim().isNotEmpty) {
          b.writeln(t.fullText.trim());
          b.writeln();
        }
      }
      return (b.toString().trim(), d.pages.length);
    } finally {
      await d.dispose();
    }
  }

  /// Rende ogni pagina come immagine e la legge con l'OCR.
  Future<List<OcrPage>> ocrPdf(String path, {void Function(int, int)? progress}) async {
    final d = await PdfDocument.openFile(path);
    final pages = <OcrPage>[];
    try {
      final n = d.pages.length.clamp(0, maxOcrPages);
      for (var i = 0; i < n; i++) {
        progress?.call(i + 1, n);
        final page = d.pages[i];
        final scale = 1600 / page.width;
        final w = (page.width * scale).round();
        final h = (page.height * scale).round();
        final img = await page.render(
          width: w,
          height: h,
          fullWidth: w.toDouble(),
          fullHeight: h.toDouble(),
          backgroundColor: 0xFFFFFFFF,
        );
        if (img == null) continue;
        final png = storage.tmpPath('ocr_${newId()}.png');
        try {
          final uiImage = await img.createImage();
          final data = await uiImage.toByteData(format: ui.ImageByteFormat.png);
          uiImage.dispose();
          if (data == null) continue;
          await File(png).writeAsBytes(data.buffer.asUint8List(), flush: true);
        } finally {
          img.dispose();
        }
        pages.add(await ocrImage(png));
      }
      return pages;
    } finally {
      await d.dispose();
    }
  }

  static String joinText(List<OcrPage> pages) =>
      pages.map((p) => p.text.trim()).where((t) => t.isNotEmpty).join('\n\n');

  /// Anteprima della prima pagina in PNG.
  Future<void> makeThumbnail(String pdfPath, String docId) async {
    final d = await PdfDocument.openFile(pdfPath);
    try {
      if (d.pages.isEmpty) return;
      final page = d.pages.first;
      const w = 360;
      final h = (w * page.height / page.width).round();
      final img = await page.render(
        width: w,
        height: h,
        fullWidth: w.toDouble(),
        fullHeight: h.toDouble(),
        backgroundColor: 0xFFFFFFFF,
      );
      if (img == null) return;
      try {
        final uiImage = await img.createImage();
        final data = await uiImage.toByteData(format: ui.ImageByteFormat.png);
        uiImage.dispose();
        if (data != null) {
          await storage
              .thumbFile(docId)
              .writeAsBytes(data.buffer.asUint8List(), flush: true);
        }
      } finally {
        img.dispose();
      }
    } finally {
      await d.dispose();
    }
  }

  static String checksumOf(Uint8List bytes) => md5.convert(bytes).toString();

  /// Legge il testo (dal PDF o con l'OCR) e crea il documento.
  Future<Analysis> analyze(
    StagedInput input, {
    required bool ocr,
    void Function(String)? status,
  }) async {
    final bytes = await File(input.pdfPath).readAsBytes();
    var (text, pages) = await pdfText(input.pdfPath);
    var ocrPages = <OcrPage>[];
    if (ocr && text.replaceAll(RegExp(r'\s'), '').length < 30) {
      if (input.ocrImages.isNotEmpty) {
        var i = 0;
        for (final img in input.ocrImages) {
          i++;
          status?.call('Lettura del testo: pagina $i di ${input.ocrImages.length}');
          ocrPages.add(await ocrImage(img));
        }
      } else {
        ocrPages = await ocrPdf(input.pdfPath,
            progress: (i, n) => status?.call('Lettura del testo: pagina $i di $n'));
      }
      text = joinText(ocrPages);
    }
    final base = p.basenameWithoutExtension(input.originalName);
    final doc = Document(
      title: base.isEmpty ? 'Documento' : base,
      content: text,
      originalName: input.originalName,
      pageCount: pages,
      checksum: checksumOf(bytes),
      fileSize: bytes.length,
      source: input.source,
    );
    return Analysis(doc, ocrPages);
  }

  /// Crea la versione archiviata: PDF/A con le immagini delle pagine e il
  /// testo dell'OCR invisibile sopra, così si può cercare e copiare.
  Future<String> buildArchivePdf(List<OcrPage> pages, {required String title}) async {
    final bytes = await buildArchivePdfBytes(
      pages,
      title: title,
      font: await font(),
      iccProfile: await _iccProfile(),
      author: Session.user ?? 'Paperdrive',
    );
    final path = storage.tmpPath('${newId()}.archive.pdf');
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }

  /// Copia il PDF (ed eventualmente la versione archiviata) nell'archivio.
  Future<void> commit(StagedInput input, Analysis a, {required bool makeArchive}) async {
    final doc = a.doc;
    await File(input.pdfPath).copy(storage.docFile(doc.fileName).path);
    if (makeArchive && a.ocrPages.isNotEmpty) {
      try {
        await saveArchive(doc, a.ocrPages);
      } catch (_) {
        // La versione archiviata è un di più: l'originale resta.
      }
    }
    try {
      await makeThumbnail(storage.docFile(doc.fileName).path, doc.id);
    } catch (_) {}
  }

  /// Crea (o ricrea) la versione archiviata e aggiorna il documento.
  Future<void> saveArchive(Document doc, List<OcrPage> pages) async {
    final path = await buildArchivePdf(pages, title: doc.title);
    final old = doc.hasArchive ? storage.docFile(doc.archiveFileName) : null;
    doc.archiveRev += 1;
    final target = storage.docFile(doc.archiveFileName);
    await File(path).copy(target.path);
    doc.archiveSize = await target.length();
    if (old != null && await old.exists()) await old.delete();
  }

  Future<void> dispose() async {
    await _recognizer?.close();
    _recognizer = null;
  }
}
