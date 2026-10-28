#!/usr/bin/env python3
"""Apply the Android host-project changes Pranaya needs on a freshly
scaffolded Flutter project. Fails loudly if the template has moved."""
import pathlib
import shutil
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


# 1. Permissions, label, no cloud backup of the vault.
edit("app/src/main/AndroidManifest.xml", [
    ('<manifest xmlns:android="http://schemas.android.com/apk/res/android">',
     '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n'
     '    <uses-permission android:name="android.permission.USE_BIOMETRIC"/>\n'
     '    <uses-permission android:name="android.permission.USE_FINGERPRINT"/>\n'
     '    <uses-permission android:name="android.permission.READ_SMS"/>\n'
     '    <uses-permission android:name="android.permission.RECEIVE_SMS"/>\n'
     '    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>\n'
     '    <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>\n'
     '    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>\n'
     '    <uses-permission android:name="android.permission.VIBRATE"/>'),
    ('android:label="pranaya"', 'android:label="Pranaya"'),
    ('android:icon="@mipmap/ic_launcher">',
     'android:icon="@mipmap/ic_launcher"\n'
     '        android:allowBackup="false"\n'
     '        android:fullBackupContent="false">'),
])

# 2. MainActivity: FlutterFragmentActivity (local_auth) + SMS inbox channel.
main_activity = root / "app/src/main/kotlin/ai/pranaya/pranaya/MainActivity.kt"
if not main_activity.exists():
    sys.exit(f"missing expected file: {main_activity}")
main_activity.write_text('''package ai.pranaya.pranaya

import android.Manifest
import android.content.pm.PackageManager
import android.database.Cursor
import android.net.Uri
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pranaya/sms")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "readInbox" -> {
                        val granted = ContextCompat.checkSelfPermission(
                            this,
                            Manifest.permission.READ_SMS
                        ) == PackageManager.PERMISSION_GRANTED
                        if (granted) {
                            result.success(readSms())
                        } else {
                            pendingResult = result
                            ActivityCompat.requestPermissions(
                                this,
                                arrayOf(Manifest.permission.READ_SMS),
                                4242
                            )
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 4242) {
            val pending = pendingResult
            pendingResult = null
            if (grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            ) {
                pending?.success(readSms())
            } else {
                pending?.error("denied", "SMS permission denied", null)
            }
        }
    }

    private fun readSms(): List<Map<String, String>> {
        val out = mutableListOf<Map<String, String>>()
        val uri = Uri.parse("content://sms/inbox")
        val cursor: Cursor? = try {
            contentResolver.query(
                uri,
                arrayOf("address", "body", "date"),
                null,
                null,
                "date DESC"
            )
        } catch (e: Exception) {
            null
        }
        cursor?.use { c ->
            val bodyIdx = c.getColumnIndex("body")
            val addrIdx = c.getColumnIndex("address")
            val dateIdx = c.getColumnIndex("date")
            var count = 0
            while (c.moveToNext() && count < 80) {
                val body = if (bodyIdx >= 0) c.getString(bodyIdx) else ""
                val addr = if (addrIdx >= 0) c.getString(addrIdx) else ""
                val date = if (dateIdx >= 0) c.getLong(dateIdx) else 0L
                out.add(
                    mapOf(
                        "address" to (addr ?: ""),
                        "body" to (body ?: ""),
                        "date" to date.toString()
                    )
                )
                count++
            }
        }
        return out
    }
}
''')

# 3. minSdk 23, Java 17, core library desugaring (needed by
#    flutter_local_notifications), release signing.
edit("app/build.gradle", [
    ("minSdk = flutter.minSdkVersion", "minSdk = 23"),
    ("sourceCompatibility = JavaVersion.VERSION_1_8",
     "coreLibraryDesugaringEnabled true\n        sourceCompatibility = JavaVersion.VERSION_17"),
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

gradle = root / "app/build.gradle"
with gradle.open("a") as f:
    f.write("""

dependencies {
    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'
}
""")

# 4. Launcher icons: copy the generated PNGs over the template ones.
icon_src = pathlib.Path("assets/android_icon")
sizes = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}
if icon_src.exists():
    for folder, px in sizes.items():
        src = icon_src / f"ic_launcher_{px}.png"
        dest_dir = root / "app/src/main/res" / folder
        dest_dir.mkdir(parents=True, exist_ok=True)
        if src.exists():
            shutil.copy(src, dest_dir / "ic_launcher.png")
        round_src = icon_src / f"ic_launcher_round_{px}.png"
        if round_src.exists():
            shutil.copy(round_src, dest_dir / "ic_launcher_round.png")

# 5. Keep the Gradle daemon inside the runner's memory budget.
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
