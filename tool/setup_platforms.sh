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

for G in android/app/build.gradle.kts android/app/build.gradle; do
  if [ -f "$G" ]; then
    sed -i -E 's/minSdk( =|) flutter\.minSdkVersion/minSdk\1 24/' "$G"
  fi
done

flutter pub get
