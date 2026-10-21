#!/usr/bin/env bash
# Genera la cartella android/ (non salvata nel repository) e la configura.
set -euo pipefail
cd "$(dirname "$0")/.."

flutter create --project-name paperdrive --org dev.paperdrive --platforms=android .
rm -f test/widget_test.dart

MANIFEST=android/app/src/main/AndroidManifest.xml
grep -q 'android.permission.INTERNET' "$MANIFEST" || \
  sed -i 's#<application#<uses-permission android:name="android.permission.INTERNET"/>\n    <application#' "$MANIFEST"
sed -i 's#android:label="paperdrive"#android:label="Paperdrive"#' "$MANIFEST"

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
            </intent-filter>
            <intent-filter>
                <action android:name="android.intent.action.SEND_MULTIPLE"/>
                <category android:name="android.intent.category.DEFAULT"/>
                <data android:mimeType="application/pdf"/>
                <data android:mimeType="image/*"/>
            </intent-filter>
            <intent-filter>
                <action android:name="android.intent.action.VIEW"/>
                <category android:name="android.intent.category.DEFAULT"/>
                <category android:name="android.intent.category.BROWSABLE"/>
                <data android:scheme="content"/>
                <data android:mimeType="application/pdf"/>
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
RULES

flutter pub get
