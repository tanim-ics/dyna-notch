#!/usr/bin/env python3
"""Generates DynaNotch.xcodeproj/project.pbxproj"""
import uuid
import os

def uid():
    return uuid.uuid4().hex[:24].upper()

# ─── UUIDs ────────────────────────────────────────────────────────────────────
PROJ      = uid()
TARGET    = uid()
CFG_LIST  = uid()
TGT_CFG_LIST = uid()
DBG_CFG   = uid()
REL_CFG   = uid()
TGT_DBG   = uid()
TGT_REL   = uid()
SRC_PHASE = uid()
RES_PHASE = uid()
FWK_PHASE = uid()
GRP_ROOT  = uid()
GRP_APP   = uid()
GRP_WIN   = uid()
GRP_VM    = uid()
GRP_VIEWS = uid()
GRP_RES   = uid()
GRP_ASSETS= uid()
FRM_APPKIT= uid()
FRM_SWIFTUI=uid()
FRM_COREAUDIO=uid()
BLD_APPKIT= uid()
BLD_COREAUDIO=uid()

SOURCES_DIR = "DynaNotch"

swift_files = {
    "App/DynaNotchApp.swift":         (uid(), uid()),
    "App/AppDelegate.swift":          (uid(), uid()),
    "Window/NotchWindowController.swift": (uid(), uid()),
    "Window/NotchPanel.swift":        (uid(), uid()),
    "ViewModels/NotchViewModel.swift":(uid(), uid()),
    "ViewModels/MusicViewModel.swift":(uid(), uid()),
    "ViewModels/SystemEventsViewModel.swift": (uid(), uid()),
    "Views/NotchContainerView.swift": (uid(), uid()),
    "Views/MusicPlayerView.swift":    (uid(), uid()),
    "Views/HUDView.swift":            (uid(), uid()),
    "Views/NotificationView.swift":   (uid(), uid()),
    "Views/SettingsView.swift":       (uid(), uid()),
}
PLIST_REF = uid()
ASSETS_REF = uid()
ASSETS_BLD = uid()

def pbx_file_ref(uid, name, path, source_tree="\"<group>\""):
    return f'\t\t{uid} = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; name = "{name}"; path = "{path}"; sourceTree = {source_tree}; }};'

pbxproj = f"""// !$*UTF8*$!
{{
\tarchiveVersion = 1;
\tclasses = {{}};
\tobjectVersion = 56;
\tobjects = {{

/* Begin PBXBuildFile section */
"""

# Build files for swift sources
for relpath, (ref_uid, bld_uid) in swift_files.items():
    name = os.path.basename(relpath)
    pbxproj += f'\t\t{bld_uid} = {{isa = PBXBuildFile; fileRef = {ref_uid}; }};\n'
pbxproj += f'\t\t{ASSETS_BLD} = {{isa = PBXBuildFile; fileRef = {ASSETS_REF}; }};\n'
pbxproj += f'\t\t{BLD_APPKIT} = {{isa = PBXBuildFile; fileRef = {FRM_APPKIT}; }};\n'
pbxproj += f'\t\t{BLD_COREAUDIO} = {{isa = PBXBuildFile; fileRef = {FRM_COREAUDIO}; }};\n'

pbxproj += """
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
"""

for relpath, (ref_uid, bld_uid) in swift_files.items():
    name = os.path.basename(relpath)
    pbxproj += f'\t\t{ref_uid} = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{name}"; sourceTree = "<group>"; }};\n'

pbxproj += f'\t\t{PLIST_REF} = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; }};\n'
pbxproj += f'\t\t{ASSETS_REF} = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>"; }};\n'
pbxproj += f'\t\t{FRM_APPKIT} = {{isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = AppKit.framework; path = System/Library/Frameworks/AppKit.framework; sourceTree = SDKROOT; }};\n'
pbxproj += f'\t\t{FRM_COREAUDIO} = {{isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = CoreAudio.framework; path = System/Library/Frameworks/CoreAudio.framework; sourceTree = SDKROOT; }};\n'

pbxproj += f"""
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
\t\t{FWK_PHASE} = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t\t{BLD_APPKIT},
\t\t\t\t{BLD_COREAUDIO},
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
\t\t{GRP_ROOT} = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{GRP_APP},
\t\t\t\t{GRP_WIN},
\t\t\t\t{GRP_VM},
\t\t\t\t{GRP_VIEWS},
\t\t\t\t{GRP_RES},
\t\t\t\t{ASSETS_REF},
\t\t\t);
\t\t\tname = DynaNotch;
\t\t\tpath = DynaNotch;
\t\t\tsourceTree = "<group>";
\t\t}};
"""

def group_block(gid, name, files):
    children = "\n".join(f"\t\t\t\t{uid}," for uid in files)
    return f'\t\t{gid} = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n{children}\n\t\t\t);\n\t\t\tpath = {name};\n\t\t\tsourceTree = "<group>";\n\t\t}};\n'

app_refs  = [v[0] for k,v in swift_files.items() if k.startswith("App/")]
win_refs  = [v[0] for k,v in swift_files.items() if k.startswith("Window/")]
vm_refs   = [v[0] for k,v in swift_files.items() if k.startswith("ViewModels/")]
view_refs = [v[0] for k,v in swift_files.items() if k.startswith("Views/")]
res_refs  = [PLIST_REF]

pbxproj += group_block(GRP_APP,   "App",        app_refs)
pbxproj += group_block(GRP_WIN,   "Window",     win_refs)
pbxproj += group_block(GRP_VM,    "ViewModels", vm_refs)
pbxproj += group_block(GRP_VIEWS, "Views",      view_refs)
pbxproj += group_block(GRP_RES,   "Resources",  res_refs)

pbxproj += f"""
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
\t\t{TARGET} = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {TGT_CFG_LIST};
\t\t\tbuildPhases = (
\t\t\t\t{SRC_PHASE},
\t\t\t\t{RES_PHASE},
\t\t\t\t{FWK_PHASE},
\t\t\t);
\t\t\tbuildRules = ();
\t\t\tdependencies = ();
\t\t\tname = DynaNotch;
\t\t\tproductName = DynaNotch;
\t\t\tproductType = "com.apple.product-type.application";
\t\t}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
\t\t{PROJ} = {{
\t\t\tisa = PBXProject;
\t\t\tattributes = {{
\t\t\t\tBuildIndependentTargetsInParallel = 1;
\t\t\t\tLastSwiftUpdateCheck = 1500;
\t\t\t\tLastUpgradeCheck = 1500;
\t\t\t}};
\t\t\tbuildConfigurationList = {CFG_LIST};
\t\t\tcompatibilityVersion = "Xcode 14.0";
\t\t\tdevelopmentRegion = en;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (en, Base);
\t\t\tmainGroup = {GRP_ROOT};
\t\t\tproductRefGroup = {GRP_ROOT};
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = ({TARGET});
\t\t}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
\t\t{RES_PHASE} = {{
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t\t{ASSETS_BLD},
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
\t\t{SRC_PHASE} = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
"""
for relpath, (ref_uid, bld_uid) in swift_files.items():
    pbxproj += f'\t\t\t\t{bld_uid},\n'
pbxproj += f"""\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
\t\t{DBG_CFG} = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;
\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 13.0;
\t\t\t\tONLY_ACTIVE_ARCH = YES;
\t\t\t\tSDKROOT = macosx;
\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";
\t\t\t\tSWIFT_VERSION = 5.9;
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{REL_CFG} = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 13.0;
\t\t\t\tSDKROOT = macosx;
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-O";
\t\t\t\tSWIFT_VERSION = 5.9;
\t\t\t}};
\t\t\tname = Release;
\t\t}};
\t\t{TGT_DBG} = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCOMBINE_HIDPI_IMAGES = YES;
\t\t\t\tINFOPLIST_FILE = DynaNotch/Resources/Info.plist;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/../Frameworks";
\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 13.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = "com.tanim.dynanotch";
\t\t\t\tPRODUCT_NAME = DynaNotch;
\t\t\t\tSWIFT_VERSION = 5.9;
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{TGT_REL} = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCOMBINE_HIDPI_IMAGES = YES;
\t\t\t\tINFOPLIST_FILE = DynaNotch/Resources/Info.plist;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/../Frameworks";
\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 13.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = "com.tanim.dynanotch";
\t\t\t\tPRODUCT_NAME = DynaNotch;
\t\t\t\tSWIFT_VERSION = 5.9;
\t\t\t}};
\t\t\tname = Release;
\t\t}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
\t\t{CFG_LIST} = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = ({DBG_CFG}, {REL_CFG});
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
\t\t{TGT_CFG_LIST} = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = ({TGT_DBG}, {TGT_REL});
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
/* End XCConfigurationList section */
\t}};
\trootObject = {PROJ};
}}
"""

os.makedirs("DynaNotch.xcodeproj", exist_ok=True)
with open("DynaNotch.xcodeproj/project.pbxproj", "w") as f:
    f.write(pbxproj)

ws = """<?xml version="1.0" encoding="UTF-8"?>
<Workspace
   version = "1.0">
   <FileRef
      location = "self:">
   </FileRef>
</Workspace>
"""
os.makedirs("DynaNotch.xcodeproj/project.xcworkspace", exist_ok=True)
with open("DynaNotch.xcodeproj/project.xcworkspace/contents.xcworkspacedata", "w") as f:
    f.write(ws)

print("✅ DynaNotch.xcodeproj generated!")
