#!/usr/bin/env python3
"""Apply the Android host-project changes Pranaya needs, on a freshly
scaffolded Flutter project. Fails loudly if the template has moved."""
import pathlib
import sys

root = pathlib.Path("android")


def edit(path, pairs, required=True):
    p = root / path
    if not p.exists():
        if required:
            sys.exit(f"missing expected file: {p}")
        return
    s = p.read_text()
    for old, new in pairs:
        if old not in s:
            sys.exit(f"pattern not found in {p}:\n{old}")
        s = s.replace(old, new)
    p.write_text(s)


# 1. Manifest: biometric permissions, a real label, no cloud backup of the vault.
edit("app/src/main/AndroidManifest.xml", [
    ('<manifest xmlns:android="http://schemas.android.com/apk/res/android">',
     '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n'
     '    <uses-permission android:name="android.permission.USE_BIOMETRIC"/>\n'
     '    <uses-permission android:name="android.permission.USE_FINGERPRINT"/>'),
    ('android:label="pranaya"', 'android:label="Pranaya"'),
    ('android:icon="@mipmap/ic_launcher">',
     'android:icon="@mipmap/ic_launcher"\n'
     '        android:allowBackup="false"\n'
     '        android:fullBackupContent="false">'),
])

# 2. MainActivity must be a FlutterFragmentActivity for local_auth.
main_activity = root / "app/src/main/kotlin/ai/pranaya/pranaya/MainActivity.kt"
if not main_activity.exists():
    sys.exit(f"missing expected file: {main_activity}")
main_activity.write_text(
    "package ai.pranaya.pranaya\n\n"
    "import io.flutter.embedding.android.FlutterFragmentActivity\n\n"
    "class MainActivity : FlutterFragmentActivity()\n"
)

# 3. minSdk 23 (flutter_secure_storage / local_auth), Java 17, release signing.
edit("app/build.gradle", [
    ("minSdk = flutter.minSdkVersion", "minSdk = 23"),
    ("sourceCompatibility = JavaVersion.VERSION_1_8",
     "sourceCompatibility = JavaVersion.VERSION_17"),
    ("targetCompatibility = JavaVersion.VERSION_1_8",
     "targetCompatibility = JavaVersion.VERSION_17"),
    ("jvmTarget = JavaVersion.VERSION_1_8", "jvmTarget = JavaVersion.VERSION_17"),
    ("""    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.debug
        }
    }""",
     """    signingConfigs {
        release {
            def propsFile = rootProject.file("key.properties")
            if (propsFile.exists()) {
                def props = new Properties()
                propsFile.withInputStream { props.load(it) }
                storeFile = file(props['storeFile'])
                storePassword = props['storePassword']
                keyAlias = props['keyAlias']
                keyPassword = props['keyPassword']
            }
        }
    }

    buildTypes {
        release {
            signingConfig = rootProject.file("key.properties").exists() ? signingConfigs.release : signingConfigs.debug
        }
    }"""),
])

# 4. Keep the Gradle daemon inside the runner's memory budget.
p = root / "gradle.properties"
s = p.read_text()
if "org.gradle.jvmargs" in s:
    s = "\n".join(
        "org.gradle.jvmargs=-Xmx2048m -XX:MaxMetaspaceSize=512m"
        if line.startswith("org.gradle.jvmargs") else line
        for line in s.splitlines()
    ) + "\n"
    p.write_text(s)

print("Android host project patched.")
