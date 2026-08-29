#!/usr/bin/env python3
"""
Generate a valid Xcode .xcodeproj for the LiveCapture iOS app.
No external tools required — produces a classic-format project.pbxproj.
"""

import os
import hashlib
import json

PROJECT_ROOT = os.path.dirname(os.path.abspath(__file__))
SOURCE_ROOT = os.path.join(PROJECT_ROOT, "LiveCapture")
OUTPUT_DIR = os.path.join(PROJECT_ROOT, "LiveCapture.xcodeproj")
PBXPROJ_PATH = os.path.join(OUTPUT_DIR, "project.pbxproj")

# --- UUID generator (deterministic 24-char hex) ---
_used = set()
def uuid(seed_str):
    h = hashlib.md5(seed_str.encode()).hexdigest()[:24].upper()
    # ensure uniqueness
    while h in _used:
        h = hashlib.md5((seed_str + h).encode()).hexdigest()[:24].upper()
    _used.add(h)
    return h

# --- Collect source files (.swift) and resource files ---
source_files = []
resource_files = []
mlpackage_dirs = []

for dirpath, dirnames, filenames in os.walk(SOURCE_ROOT):
    # sort for deterministic order
    dirnames.sort()
    for fname in sorted(filenames):
        fpath = os.path.join(dirpath, fname)
        relpath = os.path.relpath(fpath, SOURCE_ROOT)
        if fname.endswith('.swift'):
            source_files.append(relpath)
        elif fname == 'Contents.json' or fname.endswith('.jpeg') or fname.endswith('.png') or fname.endswith('.jpg'):
            # skip individual xcassets contents, handle xcassets as a whole
            if '.xcassets' not in relpath:
                resource_files.append(relpath)

# Handle xcassets and startup_bg as resources
xcassets_path = 'Assets.xcassets'
startup_bg_path = 'startup_bg.jpeg'

# Handle .mlpackage as resources (CoreML models)
for dirpath, dirnames, filenames in os.walk(SOURCE_ROOT):
    dirnames.sort()
    for dname in dirnames:
        if dname.endswith('.mlpackage'):
            fpath = os.path.join(dirpath, dname)
            relpath = os.path.relpath(fpath, SOURCE_ROOT)
            mlpackage_dirs.append(relpath)

all_resources = [xcassets_path, startup_bg_path] + mlpackage_dirs

# --- Build PBX objects ---
file_refs = {}      # relpath -> {uuid, path, filetype}
build_files_src = {}  # relpath -> build_file_uuid
build_files_res = {}  # relpath -> build_file_uuid

lines = []
lines.append("// !$*UTF8*$!")
lines.append("{")
lines.append("\tarchiveVersion = 1;")
lines.append("\tclasses = {")
lines.append("\t};")
lines.append("\tobjectVersion = 56;")
lines.append("\tobjects = {")
lines.append("")

# ---- PBXBuildFile section (sources) ----
lines.append("/* Begin PBXBuildFile section */")
for f in source_files:
    ref_uuid = uuid("fileref_" + f)
    bf_uuid = uuid("buildfile_" + f)
    file_refs[f] = ref_uuid
    build_files_src[f] = bf_uuid
    lines.append(f"\t\t{bf_uuid} /* {f} in Sources */ = {{isa = PBXBuildFile; fileRef = {ref_uuid} /* {f} */; }};")
# resources
for f in all_resources:
    ref_uuid = uuid("fileref_" + f)
    bf_uuid = uuid("buildfile_" + f)
    file_refs[f] = ref_uuid
    build_files_res[f] = bf_uuid
    lines.append(f"\t\t{bf_uuid} /* {f} in Resources */ = {{isa = PBXBuildFile; fileRef = {ref_uuid} /* {f} */; }};")
lines.append("/* End PBXBuildFile section */")
lines.append("")

# ---- PBXFileReference section ----
lines.append("/* Begin PBXFileReference section */")
# The project product (the .app)
app_ref_uuid = uuid("app_product")
lines.append(f"\t\t{app_ref_uuid} /* LiveCapture.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = LiveCapture.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
for f in source_files:
    ref = file_refs[f]
    lines.append(f"\t\t{ref} /* {f} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {os.path.basename(f)}; sourceTree = \"<group>\"; }};")
for f in all_resources:
    ref = file_refs[f]
    if f.endswith('.xcassets'):
        ft = "folder.assetcatalog"
    elif f.endswith('.mlpackage'):
        ft = "folder.mlpackage"
    elif f.endswith('.jpeg') or f.endswith('.jpg'):
        ft = "image.jpeg"
    elif f.endswith('.png'):
        ft = "image.png"
    else:
        ft = "file"
    lines.append(f"\t\t{ref} /* {f} */ = {{isa = PBXFileReference; lastKnownFileType = {ft}; path = {os.path.basename(f)}; sourceTree = \"<group>\"; }};")
lines.append("/* End PBXFileReference section */")
lines.append("")

# ---- Helper: build group tree from file paths ----
# We need PBXGroup entries that mirror the directory structure
class GroupNode:
    def __init__(self, name):
        self.name = name
        self.children = []   # list of (name, GroupNode)
        self.files = []      # list of relpaths
        self.uuid = None

root_group = GroupNode("LiveCapture")
root_group.uuid = uuid("group_root")

def add_to_group(relpath, group_root):
    parts = relpath.split(os.sep)
    cur = group_root
    # navigate/create intermediate groups
    for i, part in enumerate(parts[:-1]):
        found = None
        child = None
        for cn, cg in cur.children:
            if cn == part:
                child = cg
                break
        if child is None:
            child = GroupNode(part)
            child.uuid = uuid("group_" + os.sep.join(parts[:i+1]))
            cur.children.append((part, child))
        cur = child
    # add file to leaf group
    cur.files.append(relpath)

for f in source_files + all_resources:
    add_to_group(f, root_group)

# ---- PBXGroup section ----
lines.append("/* Begin PBXGroup section */")

def emit_group(node, is_root=False):
    children_refs = []
    # subgroups
    for name, child in node.children:
        children_refs.append(f"\t\t\t{child.uuid} /* {name} */")
    # files
    for f in node.files:
        ref = file_refs[f]
        children_refs.append(f"\t\t\t{ref} /* {os.path.basename(f)} */")

    if is_root:
        # main group also includes the app product and a Products group
        lines.append(f"\t\t{node.uuid} /* {node.name} */ = {{")
        lines.append("\t\t\tisa = PBXGroup;")
        lines.append(f"\t\t\tchildren = (")
        for cr in children_refs:
            lines.append(cr + ",")
        # Products group reference
        products_group_uuid = uuid("group_products")
        lines.append(f"\t\t\t{products_group_uuid} /* Products */,")
        lines.append("\t\t\t);")
        lines.append(f"\t\t\tpath = {node.name};")
        lines.append("\t\t\tsourceTree = \"<group>\";")
        lines.append("\t\t};")
    else:
        lines.append(f"\t\t{node.uuid} /* {node.name} */ = {{")
        lines.append("\t\t\tisa = PBXGroup;")
        lines.append(f"\t\t\tchildren = (")
        for cr in children_refs:
            lines.append(cr + ",")
        lines.append("\t\t\t);")
        lines.append(f"\t\t\tpath = {node.name};")
        lines.append("\t\t\tsourceTree = \"<group>\";")
        lines.append("\t\t};")

def walk_groups(node):
    for name, child in node.children:
        walk_groups(child)
        emit_group(child)

walk_groups(root_group)
emit_group(root_group, is_root=True)

# Products group
products_group_uuid = uuid("group_products")
lines.append(f"\t\t{products_group_uuid} /* Products */ = {{")
lines.append("\t\t\tisa = PBXGroup;")
lines.append("\t\t\tchildren = (")
lines.append(f"\t\t\t\t{app_ref_uuid} /* LiveCapture.app */,")
lines.append("\t\t\t);")
lines.append("\t\t\tname = Products;")
lines.append("\t\t\tsourceTree = \"<group>\";")
lines.append("\t\t};")
lines.append("/* End PBXGroup section */")
lines.append("")

# ---- PBXFrameworksBuildPhase (empty - system frameworks auto-linked) ----
fw_build_phase_uuid = uuid("fw_build_phase")
lines.append("/* Begin PBXFrameworksBuildPhase section */")
lines.append(f"\t\t{fw_build_phase_uuid} /* Frameworks */ = {{")
lines.append("\t\t\tisa = PBXFrameworksBuildPhase;")
lines.append("\t\t\tbuildActionMask = 2147483647;")
lines.append("\t\t\tfiles = (")
lines.append("\t\t\t);")
lines.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
lines.append("\t\t};")
lines.append("/* End PBXFrameworksBuildPhase section */")
lines.append("")

# ---- PBXResourcesBuildPhase ----
res_build_phase_uuid = uuid("res_build_phase")
lines.append("/* Begin PBXResourcesBuildPhase section */")
lines.append(f"\t\t{res_build_phase_uuid} /* Resources */ = {{")
lines.append("\t\t\tisa = PBXResourcesBuildPhase;")
lines.append("\t\t\tbuildActionMask = 2147483647;")
lines.append("\t\t\tfiles = (")
for f in all_resources:
    bf = build_files_res[f]
    lines.append(f"\t\t\t\t{bf} /* {f} in Resources */,")
lines.append("\t\t\t);")
lines.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
lines.append("\t\t};")
lines.append("/* End PBXResourcesBuildPhase section */")
lines.append("")

# ---- PBXSourcesBuildPhase ----
src_build_phase_uuid = uuid("src_build_phase")
lines.append("/* Begin PBXSourcesBuildPhase section */")
lines.append(f"\t\t{src_build_phase_uuid} /* Sources */ = {{")
lines.append("\t\t\tisa = PBXSourcesBuildPhase;")
lines.append("\t\t\tbuildActionMask = 2147483647;")
lines.append("\t\t\tfiles = (")
for f in source_files:
    bf = build_files_src[f]
    lines.append(f"\t\t\t\t{bf} /* {f} in Sources */,")
lines.append("\t\t\t);")
lines.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
lines.append("\t\t};")
lines.append("/* End PBXSourcesBuildPhase section */")
lines.append("")

# ---- XCBuildConfiguration (Debug + Release) ----
debug_cfg_uuid = uuid("xcconfig_debug")
release_cfg_uuid = uuid("xcconfig_release")
project_debug_cfg_uuid = uuid("xcconfig_proj_debug")
project_release_cfg_uuid = uuid("xcconfig_proj_release")

common_settings = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "CLANG_ANALYZER_NONNULL": "YES",
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    "CLANG_ENABLE_OBJC_WEAK": "YES",
    "CLANG_WARN__DUPLICATE_METHOD_MATCH": "YES",
    "COPY_PHASE_STRIP": "NO",
    "DEBUG_INFORMATION_FORMAT": None,  # set per-config
    "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "ENABLE_TESTABILITY": "YES",
    "ENABLE_USER_SCRIPT_SANDBOXING": "NO",
    "GCC_C_LANGUAGE_STANDARD": "gnu17",
    "GCC_DYNAMIC_NO_PIC": "NO",
    "GCC_NO_COMMON_BLOCKS": "YES",
    "GCC_OPTIMIZATION_LEVEL": None,  # set per-config
    "GCC_PREPROCESSOR_DEFINITIONS": None,  # set per-config
    "INFOPLIST_FILE": "LiveCapture/Info.plist",
    "INFOPLIST_KEY_NSCameraUsageDescription": "LiveCapture 需要使用相机来实时分析构图并提供拍摄建议。",
    "INFOPLIST_KEY_NSPhotoLibraryAddUsageDescription": "LiveCapture 需要保存分享卡片到您的相册。",
    "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
    "INFOPLIST_KEY_UISupportedInterfaceOrientations": "UIInterfaceOrientationPortrait",
    "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
    "LD_RUNPATH_SEARCH_CATEGORIES": "@executable_path/Frameworks",
    "PRODUCT_BUNDLE_IDENTIFIER": "com.livecompose.livecapture",
    "PRODUCT_NAME": "$(TARGET_NAME)",
    "SWIFT_VERSION": "5.0",
    "TARGETED_DEVICE_FAMILY": "1",
    "CODE_SIGN_IDENTITY": "",
    "CODE_SIGNING_REQUIRED": "NO",
    "CODE_SIGNING_ALLOWED": "NO",
    "SWIFT_STRICT_CONCURRENCY": "minimal",
    "GENERATE_INFOPLIST_FILE": "NO",
}

def emit_build_config(uuid_str, name, is_debug):
    settings = dict(common_settings)
    if is_debug:
        settings["DEBUG_INFORMATION_FORMAT"] = "dwarf"
        settings["GCC_OPTIMIZATION_LEVEL"] = "0"
        settings["GCC_PREPROCESSOR_DEFINITIONS"] = "DEBUG=1"
        settings["MTL_ENABLE_DEBUG_INFO"] = "INCLUDE_SOURCE"
        settings["ONLY_ACTIVE_ARCH"] = "YES"
        settings["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = "DEBUG"
        settings["SWIFT_OPTIMIZATION_LEVEL"] = "-Onone"
        settings["ENABLE_PREVIEWS"] = "YES"
    else:
        settings["DEBUG_INFORMATION_FORMAT"] = "dwarf-with-dsym"
        settings["GCC_OPTIMIZATION_LEVEL"] = "s"
        settings["MTL_ENABLE_DEBUG_INFO"] = "NO"
        settings["ONLY_ACTIVE_ARCH"] = "NO"
        settings["SWIFT_OPTIMIZATION_LEVEL"] = "-O"
        settings["ENABLE_PREVIEWS"] = "NO"

    lines.append(f"\t\t{uuid_str} /* {name} */ = {{")
    lines.append("\t\t\tisa = XCBuildConfiguration;")
    lines.append("\t\t\tbuildSettings = {")
    for key in sorted(settings.keys()):
        val = settings[key]
        if val is None:
            continue
        if val in ("YES", "NO") or val.isdigit() or val.startswith("-") or val.startswith("$(TARGET") or val == "" or val.startswith("@executable"):
            lines.append(f"\t\t\t\t{key} = {val};")
        else:
            lines.append(f"\t\t\t\t{key} = \"{val}\";")
    lines.append("\t\t\t};")
    lines.append(f"\t\t\tname = {name};")
    lines.append("\t\t};")

lines.append("/* Begin XCBuildConfiguration section */")
emit_build_config(debug_cfg_uuid, "Debug", True)
emit_build_config(release_cfg_uuid, "Release", False)

# Project-level configs
lines.append(f"\t\t{project_debug_cfg_uuid} /* Project Debug */ = {{")
lines.append("\t\t\tisa = XCBuildConfiguration;")
lines.append("\t\t\tbuildSettings = {")
lines.append("\t\t\t\tCLANG_CXX_LANGUAGE_STANDARD = \"gnu++20\";")
lines.append("\t\t\t\tCLANG_WARN_UNSIGNED_ENUM = YES;")
lines.append("\t\t\t\tCODE_SIGN_STYLE = Automatic;")
lines.append("\t\t\t\tDEAD_CODE_STRIPPING = YES;")
lines.append("\t\t\t\tSDKROOT = iphoneos;")
lines.append("\t\t\t};")
lines.append("\t\t\tname = Debug;")
lines.append("\t\t};")
lines.append(f"\t\t{project_release_cfg_uuid} /* Project Release */ = {{")
lines.append("\t\t\tisa = XCBuildConfiguration;")
lines.append("\t\t\tbuildSettings = {")
lines.append("\t\t\t\tCLANG_CXX_LANGUAGE_STANDARD = \"gnu++20\";")
lines.append("\t\t\t\tCLANG_WARN_UNSIGNED_ENUM = YES;")
lines.append("\t\t\t\tCODE_SIGN_STYLE = Automatic;")
lines.append("\t\t\t\tDEAD_CODE_STRIPPING = YES;")
lines.append("\t\t\t\tSDKROOT = iphoneos;")
lines.append("\t\t\t};")
lines.append("\t\t\tname = Release;")
lines.append("\t\t};")
lines.append("/* End XCBuildConfiguration section */")
lines.append("")

# ---- XCConfigurationList ----
target_config_list_uuid = uuid("configlist_target")
project_config_list_uuid = uuid("configlist_project")

lines.append("/* Begin XCConfigurationList section */")
# Project config list
lines.append(f"\t\t{project_config_list_uuid} /* Build configuration list for PBXProject */ = {{")
lines.append("\t\t\tisa = XCConfigurationList;")
lines.append("\t\t\tbuildConfigurations = (")
lines.append(f"\t\t\t\t{project_debug_cfg_uuid} /* Project Debug */,")
lines.append(f"\t\t\t\t{project_release_cfg_uuid} /* Project Release */,")
lines.append("\t\t\t);")
lines.append("\t\t\tdefaultConfigurationName = Release;")
lines.append("\t\t};")
# Target config list
lines.append(f"\t\t{target_config_list_uuid} /* Build configuration list for PBXNativeTarget */ = {{")
lines.append("\t\t\tisa = XCConfigurationList;")
lines.append("\t\t\tbuildConfigurations = (")
lines.append(f"\t\t\t\t{debug_cfg_uuid} /* Debug */,")
lines.append(f"\t\t\t\t{release_cfg_uuid} /* Release */,")
lines.append("\t\t\t);")
lines.append("\t\t\tdefaultConfigurationName = Release;")
lines.append("\t\t};")
lines.append("/* End XCConfigurationList section */")
lines.append("")

# ---- PBXNativeTarget ----
target_uuid = uuid("native_target")
lines.append("/* Begin PBXNativeTarget section */")
lines.append(f"\t\t{target_uuid} /* LiveCapture */ = {{")
lines.append("\t\t\tisa = PBXNativeTarget;")
lines.append("\t\t\tbuildConfigurationList = " + target_config_list_uuid + " /* Build configuration list for PBXNativeTarget */;")
lines.append("\t\t\tbuildPhases = (")
lines.append(f"\t\t\t\t{src_build_phase_uuid} /* Sources */,")
lines.append(f"\t\t\t\t{fw_build_phase_uuid} /* Frameworks */,")
lines.append(f"\t\t\t\t{res_build_phase_uuid} /* Resources */,")
lines.append("\t\t\t);")
lines.append("\t\t\tbuildRules = (")
lines.append("\t\t\t);")
lines.append("\t\t\tdependencies = (")
lines.append("\t\t\t);")
lines.append("\t\t\tname = LiveCapture;")
lines.append("\t\t\tproductName = LiveCapture;")
lines.append(f"\t\t\tproductReference = {app_ref_uuid} /* LiveCapture.app */;")
lines.append("\t\t\tproductType = \"com.apple.product-type.application\";")
lines.append("\t\t};")
lines.append("/* End PBXNativeTarget section */")
lines.append("")

# ---- PBXProject ----
project_uuid = uuid("pbx_project")
lines.append("/* Begin PBXProject section */")
lines.append(f"\t\t{project_uuid} /* Project object */ = {{")
lines.append("\t\t\tisa = PBXProject;")
lines.append("\t\t\tbuildConfigurationList = " + project_config_list_uuid + " /* Build configuration list for PBXProject */;")
lines.append("\t\t\tcompatibilityVersion = \"Xcode 14.0\";")
lines.append("\t\t\tdevelopmentRegion = zh-Hans;")
lines.append("\t\t\thasScannedForEncodings = 0;")
lines.append("\t\t\tknownRegions = (")
lines.append("\t\t\t\tzh-Hans,")
lines.append("\t\t\t\tBase,")
lines.append("\t\t\t);")
lines.append("\t\t\tmainGroup = " + root_group.uuid + " /* LiveCapture */;")
lines.append(f"\t\t\tproductRefGroup = {products_group_uuid} /* Products */;")
lines.append("\t\t\tprojectDirPath = \"\";")
lines.append("\t\t\tprojectRoot = \"\";")
lines.append("\t\t\ttargets = (")
lines.append(f"\t\t\t\t{target_uuid} /* LiveCapture */,")
lines.append("\t\t\t);")
lines.append("\t\t};")
lines.append("/* End PBXProject section */")
lines.append("")

lines.append("\t};")
lines.append(f"\trootObject = {project_uuid} /* Project object */;")
lines.append("}")

# --- Write ---
os.makedirs(OUTPUT_DIR, exist_ok=True)
with open(PBXPROJ_PATH, 'w', encoding='utf-8') as f:
    f.write('\n'.join(lines))

print(f"Generated: {PBXPROJ_PATH}")
print(f"Source files: {len(source_files)}")
print(f"Resource files: {len(all_resources)}")
print(f"ML models: {len(mlpackage_dirs)}")
