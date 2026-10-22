/// Formati di file che l'archivio sa importare, come Paperless-ngx (che usa
/// Tika e Gotenberg): PDF, immagini, testo, email e documenti Office.
library;

enum FileKind {
  /// PDF: entra così com'è.
  pdf,

  /// JPEG e PNG: diventano un PDF e vengono letti con l'OCR.
  image,

  /// Altre immagini (HEIC delle foto, WEBP, GIF, BMP, AVIF): convertite in JPEG sul telefono.
  otherImage,

  /// TIFF, anche a più pagine (tipico degli scanner e dei fax).
  tiff,

  /// Testo semplice: impaginato in un PDF.
  text,

  /// Email salvata (.eml): il testo diventa un PDF, gli allegati documenti a parte.
  mail,

  /// Word, Excel, PowerPoint, OpenDocument, RTF, HTML, CSV: convertiti in PDF da Google Drive.
  office,

  unsupported,
}

const Map<String, FileKind> _byExt = {
  'pdf': FileKind.pdf,
  'jpg': FileKind.image, 'jpeg': FileKind.image, 'png': FileKind.image,
  'heic': FileKind.otherImage, 'heif': FileKind.otherImage, 'webp': FileKind.otherImage,
  'gif': FileKind.otherImage, 'bmp': FileKind.otherImage, 'avif': FileKind.otherImage,
  'tif': FileKind.tiff, 'tiff': FileKind.tiff,
  'txt': FileKind.text, 'md': FileKind.text, 'log': FileKind.text,
  'eml': FileKind.mail,
  'doc': FileKind.office, 'docx': FileKind.office, 'odt': FileKind.office, 'rtf': FileKind.office,
  'htm': FileKind.office, 'html': FileKind.office,
  'xls': FileKind.office, 'xlsx': FileKind.office, 'ods': FileKind.office, 'csv': FileKind.office,
  'ppt': FileKind.office, 'pptx': FileKind.office, 'odp': FileKind.office,
};

/// Le estensioni importabili (per il selettore dei file).
List<String> get pickerExtensions => _byExt.keys.toList();

String fileExtension(String name) {
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
}

/// Documenti nativi di Google (Documenti, Fogli, Presentazioni, Disegni):
/// Drive li esporta direttamente in PDF.
bool isGoogleNative(String? mimeType) =>
    mimeType != null &&
    mimeType.startsWith('application/vnd.google-apps.') &&
    const {
      'application/vnd.google-apps.document',
      'application/vnd.google-apps.spreadsheet',
      'application/vnd.google-apps.presentation',
      'application/vnd.google-apps.drawing',
    }.contains(mimeType);

FileKind fileKind(String name, {String? mimeType}) {
  if (isGoogleNative(mimeType)) return FileKind.office;
  return _byExt[fileExtension(name)] ?? FileKind.unsupported;
}

/// In quale tipo di Google Drive convertire un file Office per averne il PDF.
String? googleTypeFor(String name) => switch (fileExtension(name)) {
      'doc' || 'docx' || 'odt' || 'rtf' || 'htm' || 'html' || 'txt' || 'md' =>
        'application/vnd.google-apps.document',
      'xls' || 'xlsx' || 'ods' || 'csv' => 'application/vnd.google-apps.spreadsheet',
      'ppt' || 'pptx' || 'odp' => 'application/vnd.google-apps.presentation',
      _ => null,
    };

/// Tipo MIME del file originale (per caricarlo su Drive).
String sourceMimeType(String name) => switch (fileExtension(name)) {
      'doc' => 'application/msword',
      'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'odt' => 'application/vnd.oasis.opendocument.text',
      'rtf' => 'application/rtf',
      'htm' || 'html' => 'text/html',
      'xls' => 'application/vnd.ms-excel',
      'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'ods' => 'application/vnd.oasis.opendocument.spreadsheet',
      'csv' => 'text/csv',
      'ppt' => 'application/vnd.ms-powerpoint',
      'pptx' => 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      'odp' => 'application/vnd.oasis.opendocument.presentation',
      'txt' || 'md' || 'log' => 'text/plain',
      _ => 'application/octet-stream',
    };

/// Descrizione breve per l'utente.
const String supportedFormatsLabel =
    'PDF, foto (JPG, PNG, HEIC, WEBP, TIFF…), Word, Excel, PowerPoint, '
    'OpenDocument, RTF, testo ed email (.eml)';
