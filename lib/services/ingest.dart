import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart' show md5;
import 'package:flutter/services.dart' show PlatformException;
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart'
    show InputImage, TextRecognizer, TextRecognitionScript;
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart' as pdfl;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart' show PdfDocument, PdfImageExt;

import '../core/models.dart';
import 'storage.dart';

/// File pronto per l'archivio: un PDF e, se già noto, il testo delle pagine.
class StagedInput {
  StagedInput({
    required this.pdfPath,
    required this.originalName,
    this.ocrImages = const [],
  });

  final String pdfPath;
  final String originalName;

  /// Immagini delle pagine da leggere con l'OCR (es. dalla scansione).
  final List<String> ocrImages;
}

/// Trasforma scansioni, foto e PDF in documenti: OCR, testo, anteprima.
class Ingestor {
  Ingestor(this.storage);

  final Storage storage;
  TextRecognizer? _recognizer;

  static const int maxOcrPages = 40;

  Future<String> ocrImage(String path) async {
    _recognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
    final r = await _recognizer!.processImage(InputImage.fromFilePath(path));
    return r.text;
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

  /// Prepara un file scelto dall'utente (PDF o immagine).
  Future<StagedInput> stageFile(String name, Uint8List bytes) async {
    final ext = p.extension(name).toLowerCase();
    if (ext == '.pdf') {
      final path = storage.tmpPath('${newId()}.pdf');
      await File(path).writeAsBytes(bytes, flush: true);
      return StagedInput(pdfPath: path, originalName: name);
    }
    final img = storage.tmpPath('${newId()}$ext');
    await File(img).writeAsBytes(bytes, flush: true);
    final pdf = await imagesToPdf([img]);
    return StagedInput(pdfPath: pdf, originalName: name, ocrImages: [img]);
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
  Future<String> ocrPdf(String path, {void Function(int, int)? progress}) async {
    final d = await PdfDocument.openFile(path);
    try {
      final b = StringBuffer();
      final n = d.pages.length.clamp(0, maxOcrPages);
      for (var i = 0; i < n; i++) {
        progress?.call(i + 1, n);
        final page = d.pages[i];
        final scale = 1700 / page.width;
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
        b.writeln((await ocrImage(png)).trim());
        b.writeln();
        try {
          await File(png).delete();
        } catch (_) {}
      }
      return b.toString().trim();
    } finally {
      await d.dispose();
    }
  }

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
  /// Il PDF viene copiato nell'archivio solo da [commit].
  Future<Document> analyze(
    StagedInput input, {
    required bool ocr,
    void Function(String)? status,
  }) async {
    final bytes = await File(input.pdfPath).readAsBytes();
    var (text, pages) = await pdfText(input.pdfPath);
    if (ocr && text.replaceAll(RegExp(r'\s'), '').length < 30) {
      if (input.ocrImages.isNotEmpty) {
        final b = StringBuffer();
        var i = 0;
        for (final img in input.ocrImages) {
          i++;
          status?.call('Lettura del testo: pagina $i di ${input.ocrImages.length}');
          b.writeln((await ocrImage(img)).trim());
          b.writeln();
        }
        text = b.toString().trim();
      } else {
        text = await ocrPdf(input.pdfPath,
            progress: (i, n) => status?.call('Lettura del testo: pagina $i di $n'));
      }
    }
    final base = p.basenameWithoutExtension(input.originalName);
    return Document(
      title: base.isEmpty ? 'Documento' : base,
      content: text,
      originalName: input.originalName,
      pageCount: pages,
      checksum: checksumOf(bytes),
      fileSize: bytes.length,
    );
  }

  /// Copia il PDF nell'archivio e crea l'anteprima.
  Future<void> commit(StagedInput input, Document doc) async {
    await File(input.pdfPath).copy(storage.docFile(doc.fileName).path);
    try {
      await makeThumbnail(storage.docFile(doc.fileName).path, doc.id);
    } catch (_) {
      // L'anteprima non è indispensabile.
    }
  }

  Future<void> dispose() async {
    await _recognizer?.close();
    _recognizer = null;
  }
}
