#!/usr/bin/env python3
"""Small fixes to the generated Android project (run from app/ after `flutter create`).
- Firebase needs minSdk 23 or higher."""
import os
import re

for path in ("android/app/build.gradle.kts", "android/app/build.gradle"):
    if not os.path.exists(path):
        continue
    src = open(path).read()
    new = re.sub(r"minSdk\s*=\s*flutter\.minSdkVersion", "minSdk = 24", src)
    new = re.sub(r"minSdkVersion\s+flutter\.minSdkVersion", "minSdkVersion 24", new)
    if new != src:
        open(path, "w").write(new)
        print("minSdk set to 24 in", path)
    else:
        print("minSdk line not found in", path, "(left unchanged)")
