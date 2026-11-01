#!/usr/bin/env python3
"""Switches the generated Android project from debug signing to the release (upload) key.
Run from the app/ folder in CI after `flutter create`, once android/key.properties exists.
Fails loudly if the expected lines are not found, so a release is never silently debug-signed."""
import os
import sys

kts = "android/app/build.gradle.kts"
groovy = "android/app/build.gradle"

if os.path.exists(kts):
    path, kotlin = kts, True
elif os.path.exists(groovy):
    path, kotlin = groovy, False
else:
    sys.exit("No android/app/build.gradle(.kts) found")

src = open(path).read()
if "keystoreProperties" in src:
    print("Signing already configured")
    sys.exit(0)

if kotlin:
    props = (
        "val keystoreProperties = Properties()\n"
        'val keystorePropertiesFile = rootProject.file("key.properties")\n'
        "if (keystorePropertiesFile.exists()) {\n"
        "    keystoreProperties.load(FileInputStream(keystorePropertiesFile))\n"
        "}\n\n"
    )
    signing = (
        "    signingConfigs {\n"
        '        create("release") {\n'
        '            keyAlias = keystoreProperties["keyAlias"] as String\n'
        '            keyPassword = keystoreProperties["keyPassword"] as String\n'
        '            storeFile = keystoreProperties["storeFile"]?.let { file(it) }\n'
        '            storePassword = keystoreProperties["storePassword"] as String\n'
        "        }\n"
        "    }\n\n"
    )
    if "android {" not in src:
        sys.exit("'android {' not found")
    src = "import java.io.FileInputStream\nimport java.util.Properties\n\n" + src
    src = src.replace("android {", props + "android {\n" + signing, 1)
    old = 'signingConfig = signingConfigs.getByName("debug")'
    if old not in src:
        sys.exit("debug signingConfig line not found")
    src = src.replace(old, 'signingConfig = signingConfigs.getByName("release")', 1)
else:
    props = (
        "def keystoreProperties = new Properties()\n"
        "def keystorePropertiesFile = rootProject.file('key.properties')\n"
        "if (keystorePropertiesFile.exists()) {\n"
        "    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))\n"
        "}\n\n"
    )
    signing = (
        "    signingConfigs {\n"
        "        release {\n"
        "            keyAlias keystoreProperties['keyAlias']\n"
        "            keyPassword keystoreProperties['keyPassword']\n"
        "            storeFile keystoreProperties['storeFile'] ? file(keystoreProperties['storeFile']) : null\n"
        "            storePassword keystoreProperties['storePassword']\n"
        "        }\n"
        "    }\n\n"
    )
    if "android {" not in src:
        sys.exit("'android {' not found")
    src = src.replace("android {", props + "android {\n" + signing, 1)
    old = "signingConfig signingConfigs.debug"
    if old not in src:
        sys.exit("debug signingConfig line not found")
    src = src.replace(old, "signingConfig signingConfigs.release", 1)

open(path, "w").write(src)
print("Release signing configured in", path)
