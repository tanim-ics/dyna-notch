"""Validates Packaging/Info.plist for scripts/check.sh (kept in its own file: macOS bash 3.2 can't parse it inline)."""
import plistlib
import re
import sys

path = sys.argv[1]
with open(path, "rb") as fh:
    p = plistlib.load(fh)

expected = {
    "CFBundleExecutable": "DynaNotch",
    "CFBundleIdentifier": "com.tanim.dynanotch",
    "CFBundleName": "DynaNotch",
    "CFBundleDisplayName": "DynaNotch",
    "CFBundlePackageType": "APPL",
    "CFBundleIconFile": "AppIcon",
    "LSMinimumSystemVersion": "14.0",
    "LSUIElement": True,
    "NSPrincipalClass": "NSApplication",
    "NSHighResolutionCapable": True,
    "LSApplicationCategoryType": "public.app-category.utilities",
}
problems = []
for k, v in expected.items():
    if p.get(k) != v:
        problems.append("%s = %r (expected %r)" % (k, p.get(k), v))
if not re.fullmatch(r"\d+\.\d+\.\d+", str(p.get("CFBundleShortVersionString", ""))):
    problems.append("CFBundleShortVersionString %r is not x.y.z" % p.get("CFBundleShortVersionString"))
if not re.fullmatch(r"\d+", str(p.get("CFBundleVersion", ""))):
    problems.append("CFBundleVersion %r is not a number" % p.get("CFBundleVersion"))
# Every privacy-sensitive API the app touches needs its usage string, or macOS kills the app on first use.
for k in ("NSAppleEventsUsageDescription", "NSBluetoothAlwaysUsageDescription",
          "NSCalendarsFullAccessUsageDescription", "NSCalendarsUsageDescription",
          "NSCameraUsageDescription", "NSRemindersFullAccessUsageDescription",
          "NSLocationUsageDescription", "NSHumanReadableCopyright"):
    if not isinstance(p.get(k), str) or not p.get(k):
        problems.append("%s missing" % k)
for k, v in p.items():
    if isinstance(v, str) and "$(" in v:
        problems.append("%s contains unexpanded variable %r" % (k, v))
if problems:
    print("\n".join(problems))
    sys.exit(1)
print("%d keys OK" % len(p))
