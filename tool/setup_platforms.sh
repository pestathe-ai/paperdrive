#!/usr/bin/env bash
# Genera la cartella android/ (non salvata nel repository) e la configura.
set -euo pipefail
cd "$(dirname "$0")/.."

flutter create --project-name paperdrive --org dev.paperdrive --platforms=android .
rm -f test/widget_test.dart

MANIFEST=android/app/src/main/AndroidManifest.xml
grep -q 'android.permission.INTERNET' "$MANIFEST" || \
  sed -i 's#<application#<uses-permission android:name="android.permission.INTERNET"/>\n    <application#' "$MANIFEST"
sed -i 's#android:label="paperdrive"#android:label="D. Paper Lab"#' "$MANIFEST"

# Icona Dom Studio (adattiva, con versione a tema per Android 13+).
cp -r tool/android/res/. android/app/src/main/res/

# "Condividi" e "Apri con": codice nativo e filtri nel manifest.
ACT=$(find android/app/src/main -name 'MainActivity.*' | head -1)
echo "MainActivity: $ACT"
rm -f "$ACT"
mkdir -p android/app/src/main/kotlin/dev/paperdrive/paperdrive
cp tool/android/MainActivity.kt android/app/src/main/kotlin/dev/paperdrive/paperdrive/MainActivity.kt
python3 - "$MANIFEST" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
filters = '''
            <intent-filter>
                <action android:name="android.intent.action.SEND"/>
                <category android:name="android.intent.category.DEFAULT"/>
                <data android:mimeType="application/pdf"/>
                <data android:mimeType="image/*"/>
                <data android:mimeType="text/plain"/>
                <data android:mimeType="text/csv"/>
                <data android:mimeType="text/html"/>
                <data android:mimeType="message/rfc822"/>
                <data android:mimeType="application/rtf"/>
                <data android:mimeType="application/msword"/>
                <data android:mimeType="application/vnd.ms-excel"/>
                <data android:mimeType="application/vnd.ms-powerpoint"/>
                <data android:mimeType="application/vnd.openxmlformats-officedocument.wordprocessingml.document"/>
                <data android:mimeType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"/>
                <data android:mimeType="application/vnd.openxmlformats-officedocument.presentationml.presentation"/>
                <data android:mimeType="application/vnd.oasis.opendocument.text"/>
                <data android:mimeType="application/vnd.oasis.opendocument.spreadsheet"/>
                <data android:mimeType="application/vnd.oasis.opendocument.presentation"/>
            </intent-filter>
            <intent-filter>
                <action android:name="android.intent.action.SEND_MULTIPLE"/>
                <category android:name="android.intent.category.DEFAULT"/>
                <data android:mimeType="application/pdf"/>
                <data android:mimeType="image/*"/>
                <data android:mimeType="text/plain"/>
                <data android:mimeType="text/csv"/>
                <data android:mimeType="text/html"/>
                <data android:mimeType="message/rfc822"/>
                <data android:mimeType="application/rtf"/>
                <data android:mimeType="application/msword"/>
                <data android:mimeType="application/vnd.ms-excel"/>
                <data android:mimeType="application/vnd.ms-powerpoint"/>
                <data android:mimeType="application/vnd.openxmlformats-officedocument.wordprocessingml.document"/>
                <data android:mimeType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"/>
                <data android:mimeType="application/vnd.openxmlformats-officedocument.presentationml.presentation"/>
                <data android:mimeType="application/vnd.oasis.opendocument.text"/>
                <data android:mimeType="application/vnd.oasis.opendocument.spreadsheet"/>
                <data android:mimeType="application/vnd.oasis.opendocument.presentation"/>
            </intent-filter>
            <intent-filter>
                <action android:name="android.intent.action.VIEW"/>
                <category android:name="android.intent.category.DEFAULT"/>
                <category android:name="android.intent.category.BROWSABLE"/>
                <data android:scheme="content"/>
                <data android:mimeType="application/pdf"/>
                <data android:mimeType="image/*"/>
                <data android:mimeType="text/plain"/>
                <data android:mimeType="text/csv"/>
                <data android:mimeType="text/html"/>
                <data android:mimeType="message/rfc822"/>
                <data android:mimeType="application/rtf"/>
                <data android:mimeType="application/msword"/>
                <data android:mimeType="application/vnd.ms-excel"/>
                <data android:mimeType="application/vnd.ms-powerpoint"/>
                <data android:mimeType="application/vnd.openxmlformats-officedocument.wordprocessingml.document"/>
                <data android:mimeType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"/>
                <data android:mimeType="application/vnd.openxmlformats-officedocument.presentationml.presentation"/>
                <data android:mimeType="application/vnd.oasis.opendocument.text"/>
                <data android:mimeType="application/vnd.oasis.opendocument.spreadsheet"/>
                <data android:mimeType="application/vnd.oasis.opendocument.presentation"/>
            </intent-filter>
'''
if 'android.intent.action.SEND"' not in s:
    i = s.index('</activity>')
    s = s[:i] + filters + '        ' + s[i:]
open(p, 'w').write(s)
PY
grep -c 'intent.action.SEND' "$MANIFEST" || { cat "$MANIFEST"; exit 1; }

for G in android/app/build.gradle.kts android/app/build.gradle; do
  if [ -f "$G" ]; then
    sed -i -E 's/minSdk( =|) flutter\.minSdkVersion/minSdk\1 30/' "$G"
    # Niente R8: rinomina classi usate via JNI/riflessione (ML Kit, AI,
    # shared_preferences) e rompe l'app solo nella versione release.
    sed -i -E 's/^( *)signingConfig = signingConfigs\.getByName\("debug"\)/\1signingConfig = signingConfigs.getByName("debug")\n\1isMinifyEnabled = false\n\1isShrinkResources = false/' "$G"
    grep -q 'isMinifyEnabled = false' "$G" || { echo "minify non disattivato"; cat "$G"; exit 1; }
  fi
done

# ML Kit fa riferimento ai moduli OCR per cinese, giapponese, coreano e
# devanagari, che non includiamo: R8 non deve fermarsi per questo.
cat > android/app/proguard-rules.pro <<'RULES'
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
# Le librerie ML Kit e Play services non vanno ottimizzate: lo scanner di
# documenti si rompe (NullPointerException all'avvio) se R8 le modifica.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_** { *; }
-keep class com.google.android.gms.vision.** { *; }
-keep class com.google_mlkit_** { *; }
# Plugin chiamati da Dart via JNI (shared_preferences, download del modello
# AI): R8 non deve rinominare le classi né i tipi Kotlin nelle firme,
# altrimenti NoSuchMethodError.
-keep class io.flutter.plugins.** { *; }
-keep class kotlin.coroutines.** { *; }
-keep class kotlin.jvm.functions.** { *; }
-keep class kotlinx.coroutines.** { *; }
-keep class com.bbflight.** { *; }
-keep class com.github.dart_lang.jni.** { *; }
-keep class dev.flutterberlin.** { *; }
RULES

flutter pub get
