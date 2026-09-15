from pathlib import Path

manifest = Path('android/app/src/main/AndroidManifest.xml')
text = manifest.read_text()
text = text.replace('android:label="openstock"', 'android:label="OpenStock"')
manifest.write_text(text)

main = Path('android/app/src/main/res/drawable/launch_background.xml')
main.write_text('''<?xml version="1.0" encoding="utf-8"?>
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item android:drawable="#0B1220" />
</layer-list>
''')

values = Path('android/app/src/main/res/values/colors.xml')
values.write_text('''<?xml version="1.0" encoding="utf-8"?>
<resources><color name="ic_launcher_background">#0B1220</color></resources>
''')

drawable = Path('android/app/src/main/res/drawable/ic_openstock_foreground.xml')
drawable.write_text('''<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp" android:height="108dp"
    android:viewportWidth="108" android:viewportHeight="108">
    <path android:fillColor="#00000000" android:strokeColor="#39E58C"
        android:strokeWidth="7" android:strokeLineCap="round"
        android:strokeLineJoin="round" android:pathData="M24,72 L42,54 L56,64 L82,34" />
    <path android:fillColor="#39E58C" android:pathData="M67,30 L86,30 L86,49 Z" />
    <path android:fillColor="#FFFFFF" android:pathData="M24,79 L84,79 L84,84 L24,84 Z" />
</vector>
''')

for folder in ('mipmap-anydpi-v26',):
    target = Path('android/app/src/main/res') / folder
    target.mkdir(parents=True, exist_ok=True)
    (target / 'ic_launcher.xml').write_text('''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@drawable/ic_openstock_foreground" />
</adaptive-icon>
''')
    (target / 'ic_launcher_round.xml').write_text((target / 'ic_launcher.xml').read_text())

