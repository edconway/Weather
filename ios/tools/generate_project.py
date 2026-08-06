#!/usr/bin/env python3
"""Generate ios/WeatherScope.xcodeproj/project.pbxproj.

The project is generated rather than hand-maintained so that adding a target
(e.g. the Phase 8 iOS widget extension) is a one-line change here instead of a
few hundred lines of hand-edited pbxproj.

Source files live in PBXFileSystemSynchronizedRootGroups (Xcode 16+), so files
added to ios/<Target>/ are picked up by Xcode without regenerating. Only
structural changes (new targets, new build settings) require a re-run:

    python3 ios/tools/generate_project.py
"""

import hashlib
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJECT_DIR = os.path.join(ROOT, "WeatherScope.xcodeproj")

# Set this to build for a real iPhone/Apple Watch:
#
#     WEATHERSCOPE_TEAM_ID=ABCDE12345 python3 ios/tools/generate_project.py
#
# With a team, targets use automatic signing and Xcode registers the bundle IDs
# and the App Group for you. Without one they fall back to ad-hoc signing, which
# is simulator-only but needs no account — and still applies the App Group
# entitlement, which `CODE_SIGNING_ALLOWED = NO` would not.
TEAM_ID = os.environ.get("WEATHERSCOPE_TEAM_ID", "").strip()

BUNDLE_APP = "com.edconway.weatherworld"
BUNDLE_WATCH = "com.edconway.weatherworld.watchkitapp"
BUNDLE_WATCH_WIDGETS = "com.edconway.weatherworld.watchkitapp.widgets"
BUNDLE_IOS_WIDGETS = "com.edconway.weatherworld.widgets"

IOS_MIN = "17.0"
WATCH_MIN = "10.0"

_seen = {}


def uid(*parts):
    """Deterministic 24-hex-char pbxproj identifier."""
    key = "/".join(parts)
    digest = hashlib.md5(key.encode()).hexdigest()[:24].upper()
    if _seen.get(digest, key) != key:
        raise SystemExit(f"pbxproj id collision between {_seen[digest]!r} and {key!r}")
    _seen[digest] = key
    return digest


class Target:
    def __init__(self, name, product_type, product_name, platform, bundle_id,
                 embeds=(), settings=None):
        self.name = name
        self.product_type = product_type
        self.product_name = product_name
        self.platform = platform  # "ios" | "watchos"
        self.bundle_id = bundle_id
        self.embeds = list(embeds)  # target names embedded into this one
        self.settings = settings or {}

    @property
    def id(self):
        return uid("target", self.name)

    @property
    def product_ref(self):
        return uid("product", self.name)

    @property
    def sync_group(self):
        return uid("syncgroup", self.name)

    @property
    def package_dep(self):
        return uid("packagedep", self.name)

    @property
    def package_build_file(self):
        return uid("packagebuildfile", self.name)


APP = Target(
    name="WeatherApp",
    product_type="com.apple.product-type.application",
    product_name="WeatherScope.app",
    platform="ios",
    bundle_id=BUNDLE_APP,
    embeds=["WeatherWatch"],
    settings={
        "INFOPLIST_FILE": "Support/WeatherApp-Info.plist",
        "CODE_SIGN_ENTITLEMENTS": "Support/WeatherApp.entitlements",
        "TARGETED_DEVICE_FAMILY": '"1,2"',
        "IPHONEOS_DEPLOYMENT_TARGET": IOS_MIN,
        "PRODUCT_NAME": '"Weather World"',
        "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
        "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone":
            '"UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown"',
        "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad":
            '"UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown '
            'UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight"',
    },
)

WATCH = Target(
    name="WeatherWatch",
    product_type="com.apple.product-type.application",
    product_name="WeatherScope Watch App.app",
    platform="watchos",
    bundle_id=BUNDLE_WATCH,
    embeds=["WeatherWatchWidgets"],
    settings={
        "INFOPLIST_FILE": "Support/WeatherWatch-Info.plist",
        "CODE_SIGN_ENTITLEMENTS": "Support/WeatherWatch.entitlements",
        "TARGETED_DEVICE_FAMILY": "4",
        "WATCHOS_DEPLOYMENT_TARGET": WATCH_MIN,
        "PRODUCT_NAME": '"Weather World Watch App"',
        "SDKROOT": "watchos",
        "SUPPORTED_PLATFORMS": '"watchsimulator watchos"',
        "SKIP_INSTALL": "YES",
    },
)

WATCH_WIDGETS = Target(
    name="WeatherWatchWidgets",
    product_type="com.apple.product-type.app-extension",
    product_name="WeatherWatchWidgets.appex",
    platform="watchos",
    bundle_id=BUNDLE_WATCH_WIDGETS,
    settings={
        "INFOPLIST_FILE": "Support/WeatherWatchWidgets-Info.plist",
        "CODE_SIGN_ENTITLEMENTS": "Support/WeatherWatchWidgets.entitlements",
        "TARGETED_DEVICE_FAMILY": "4",
        "WATCHOS_DEPLOYMENT_TARGET": WATCH_MIN,
        "PRODUCT_NAME": "WeatherWatchWidgets",
        "SDKROOT": "watchos",
        "SUPPORTED_PLATFORMS": '"watchsimulator watchos"',
        "SKIP_INSTALL": "YES",
    },
)

IOS_WIDGETS = Target(
    name="WeatherWidgets",
    product_type="com.apple.product-type.app-extension",
    product_name="WeatherWidgets.appex",
    platform="ios",
    bundle_id=BUNDLE_IOS_WIDGETS,
    settings={
        "INFOPLIST_FILE": "Support/WeatherWidgets-Info.plist",
        "CODE_SIGN_ENTITLEMENTS": "Support/WeatherWidgets.entitlements",
        "TARGETED_DEVICE_FAMILY": '"1,2"',
        "IPHONEOS_DEPLOYMENT_TARGET": IOS_MIN,
        "PRODUCT_NAME": "WeatherWidgets",
        "SKIP_INSTALL": "YES",
    },
)

TARGETS = [APP, WATCH, WATCH_WIDGETS, IOS_WIDGETS]
APP.embeds.append("WeatherWidgets")
BY_NAME = {t.name: t for t in TARGETS}

SUPPORT_FILES = sorted(
    [f"{t.name}-Info.plist" for t in TARGETS] +
    [f"{t.name}.entitlements" for t in TARGETS]
)

SHARED_SETTINGS = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES",
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES",
    "CODE_SIGN_STYLE": "Automatic",
    "COPY_PHASE_STRIP": "NO",
    "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
    "GCC_NO_COMMON_BLOCKS": "YES",
    "GCC_WARN_UNDECLARED_SELECTOR": "YES",
    "GCC_WARN_UNUSED_FUNCTION": "YES",
    "GCC_WARN_UNUSED_VARIABLE": "YES",
    "IPHONEOS_DEPLOYMENT_TARGET": IOS_MIN,
    "WATCHOS_DEPLOYMENT_TARGET": WATCH_MIN,
    "LOCALIZATION_PREFERS_STRING_CATALOGS": "YES",
    "MTL_FAST_MATH": "YES",
    "SDKROOT": "iphoneos",
    "SWIFT_EMIT_LOC_STRINGS": "YES",
    # Swift 6 compiler, Swift 5 language mode (plan §1.3).
    "SWIFT_VERSION": "5.0",
}

DEBUG_ONLY = {
    "DEBUG_INFORMATION_FORMAT": "dwarf",
    "ENABLE_TESTABILITY": "YES",
    "GCC_OPTIMIZATION_LEVEL": "0",
    "GCC_PREPROCESSOR_DEFINITIONS": '(\n\t\t\t\t\t"DEBUG=1",\n\t\t\t\t\t"$(inherited)",\n\t\t\t\t)',
    "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
    "ONLY_ACTIVE_ARCH": "YES",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": '"DEBUG $(inherited)"',
    "SWIFT_OPTIMIZATION_LEVEL": '"-Onone"',
}

RELEASE_ONLY = {
    "DEBUG_INFORMATION_FORMAT": '"dwarf-with-dsym"',
    "ENABLE_NS_ASSERTIONS": "NO",
    "MTL_ENABLE_DEBUG_INFO": "NO",
    "SWIFT_COMPILATION_MODE": "wholemodule",
    "VALIDATE_PRODUCT": "YES",
}

TARGET_COMMON = {
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "CURRENT_PROJECT_VERSION": "1",
    "GENERATE_INFOPLIST_FILE": "YES",
    "MARKETING_VERSION": "1.0",
    "SWIFT_EMIT_LOC_STRINGS": "YES",
}

# Ad-hoc signing keeps the App Group entitlement applied on the simulator without
# needing an account; `CODE_SIGNING_ALLOWED = NO` would drop it entirely and the
# app/widget cache sharing would silently not exist.
if TEAM_ID:
    TARGET_COMMON.update({
        "CODE_SIGN_STYLE": "Automatic",
        "DEVELOPMENT_TEAM": TEAM_ID,
    })
else:
    TARGET_COMMON.update({
        "CODE_SIGN_STYLE": "Manual",
        "CODE_SIGN_IDENTITY": '"-"',
        "PROVISIONING_PROFILE_SPECIFIER": '""',
        "DEVELOPMENT_TEAM": '""',
    })


def fmt_settings(settings, indent=4):
    pad = "\t" * indent
    lines = []
    for key in sorted(settings):
        lines.append(f"{pad}{key} = {settings[key]};")
    return "\n".join(lines)


def build():
    out = []
    w = out.append

    w("// !$*UTF8*$!")
    w("{")
    w("\tarchiveVersion = 1;")
    w("\tclasses = {")
    w("\t};")
    w("\tobjectVersion = 77;")
    w("\tobjects = {")

    # ── PBXBuildFile ────────────────────────────────────────────────────────
    w("\n/* Begin PBXBuildFile section */")
    for t in TARGETS:
        w(f"\t\t{t.package_build_file} /* WeatherCore in Frameworks */ = {{isa = PBXBuildFile; "
          f"productRef = {t.package_dep} /* WeatherCore */; }};")
    for host in TARGETS:
        for child_name in host.embeds:
            child = BY_NAME[child_name]
            bf = uid("embedbuildfile", host.name, child_name)
            w(f"\t\t{bf} /* {child.product_name} in Embed */ = {{isa = PBXBuildFile; "
              f"fileRef = {child.product_ref} /* {child.product_name} */; "
              "settings = {ATTRIBUTES = (RemoveHeadersOnCopy, ); }; };")
    w("/* End PBXBuildFile section */")

    # ── PBXContainerItemProxy ───────────────────────────────────────────────
    w("\n/* Begin PBXContainerItemProxy section */")
    for host in TARGETS:
        for child_name in host.embeds:
            child = BY_NAME[child_name]
            w(f"\t\t{uid('proxy', host.name, child_name)} /* PBXContainerItemProxy */ = {{")
            w("\t\t\tisa = PBXContainerItemProxy;")
            w(f"\t\t\tcontainerPortal = {uid('project')} /* Project object */;")
            w("\t\t\tproxyType = 1;")
            w(f"\t\t\tremoteGlobalIDString = {child.id};")
            w(f"\t\t\tremoteInfo = {child.name};")
            w("\t\t};")
    w("/* End PBXContainerItemProxy section */")

    # ── PBXCopyFilesBuildPhase ──────────────────────────────────────────────
    w("\n/* Begin PBXCopyFilesBuildPhase section */")
    for host in TARGETS:
        for child_name in host.embeds:
            child = BY_NAME[child_name]
            is_watch_app = child.product_type == "com.apple.product-type.application"
            phase = uid("embedphase", host.name, child_name)
            bf = uid("embedbuildfile", host.name, child_name)
            label = "Embed Watch Content" if is_watch_app else "Embed Foundation Extensions"
            w(f"\t\t{phase} /* {label} */ = {{")
            w("\t\t\tisa = PBXCopyFilesBuildPhase;")
            w("\t\t\tbuildActionMask = 2147483647;")
            if is_watch_app:
                w('\t\t\tdstPath = "$(CONTENTS_FOLDER_PATH)/Watch";')
                w("\t\t\tdstSubfolderSpec = 16;")
            else:
                w('\t\t\tdstPath = "";')
                w("\t\t\tdstSubfolderSpec = 13;")
            w("\t\t\tfiles = (")
            w(f"\t\t\t\t{bf} /* {child.product_name} in {label} */,")
            w("\t\t\t);")
            w(f'\t\t\tname = "{label}";')
            w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
            w("\t\t};")
    w("/* End PBXCopyFilesBuildPhase section */")

    # ── PBXFileReference ────────────────────────────────────────────────────
    w("\n/* Begin PBXFileReference section */")
    for name in SUPPORT_FILES:
        file_type = "text.plist.entitlements" if name.endswith(".entitlements") \
            else "text.plist.xml"
        w(f'\t\t{uid("supportfile", name)} /* {name} */ = {{isa = PBXFileReference; '
          f'lastKnownFileType = {file_type}; path = "{name}"; sourceTree = "<group>"; }};')
    for t in TARGETS:
        ext = "wrapper.application" if t.product_type.endswith("application") \
            else "wrapper.app-extension"
        w(f'\t\t{t.product_ref} /* {t.product_name} */ = {{isa = PBXFileReference; '
          f'explicitFileType = "{ext}"; includeInIndex = 0; '
          f'path = "{t.product_name}"; sourceTree = BUILT_PRODUCTS_DIR; }};')
    w("/* End PBXFileReference section */")

    # ── PBXFileSystemSynchronizedRootGroup ──────────────────────────────────
    w("\n/* Begin PBXFileSystemSynchronizedRootGroup section */")
    for t in TARGETS:
        w(f"\t\t{t.sync_group} /* {t.name} */ = {{")
        w("\t\t\tisa = PBXFileSystemSynchronizedRootGroup;")
        w(f"\t\t\tpath = {t.name};")
        w("\t\t\tsourceTree = \"<group>\";")
        w("\t\t};")
    w("/* End PBXFileSystemSynchronizedRootGroup section */")

    # ── PBXFrameworksBuildPhase ─────────────────────────────────────────────
    w("\n/* Begin PBXFrameworksBuildPhase section */")
    for t in TARGETS:
        w(f"\t\t{uid('frameworks', t.name)} /* Frameworks */ = {{")
        w("\t\t\tisa = PBXFrameworksBuildPhase;")
        w("\t\t\tbuildActionMask = 2147483647;")
        w("\t\t\tfiles = (")
        w(f"\t\t\t\t{t.package_build_file} /* WeatherCore in Frameworks */,")
        w("\t\t\t);")
        w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
        w("\t\t};")
    w("/* End PBXFrameworksBuildPhase section */")

    # ── PBXGroup ────────────────────────────────────────────────────────────
    w("\n/* Begin PBXGroup section */")
    w(f"\t\t{uid('group', 'root')} = {{")
    w("\t\t\tisa = PBXGroup;")
    w("\t\t\tchildren = (")
    for t in TARGETS:
        w(f"\t\t\t\t{t.sync_group} /* {t.name} */,")
    w(f"\t\t\t\t{uid('group', 'support')} /* Support */,")
    w(f"\t\t\t\t{uid('group', 'packages')} /* Packages */,")
    w(f"\t\t\t\t{uid('group', 'products')} /* Products */,")
    w("\t\t\t);")
    w("\t\t\tsourceTree = \"<group>\";")
    w("\t\t};")

    w(f"\t\t{uid('group', 'products')} /* Products */ = {{")
    w("\t\t\tisa = PBXGroup;")
    w("\t\t\tchildren = (")
    for t in TARGETS:
        w(f"\t\t\t\t{t.product_ref} /* {t.product_name} */,")
    w("\t\t\t);")
    w("\t\t\tname = Products;")
    w("\t\t\tsourceTree = \"<group>\";")
    w("\t\t};")

    w(f"\t\t{uid('group', 'support')} /* Support */ = {{")
    w("\t\t\tisa = PBXGroup;")
    w("\t\t\tchildren = (")
    for name in SUPPORT_FILES:
        w(f"\t\t\t\t{uid('supportfile', name)} /* {name} */,")
    w("\t\t\t);")
    w("\t\t\tpath = Support;")
    w("\t\t\tsourceTree = \"<group>\";")
    w("\t\t};")

    w(f"\t\t{uid('group', 'packages')} /* Packages */ = {{")
    w("\t\t\tisa = PBXGroup;")
    w("\t\t\tchildren = (")
    w("\t\t\t);")
    w("\t\t\tname = Packages;")
    w("\t\t\tsourceTree = \"<group>\";")
    w("\t\t};")
    w("/* End PBXGroup section */")

    # ── PBXNativeTarget ─────────────────────────────────────────────────────
    w("\n/* Begin PBXNativeTarget section */")
    for t in TARGETS:
        w(f"\t\t{t.id} /* {t.name} */ = {{")
        w("\t\t\tisa = PBXNativeTarget;")
        w(f"\t\t\tbuildConfigurationList = {uid('configlist', t.name)} "
          f"/* Build configuration list for PBXNativeTarget \"{t.name}\" */;")
        w("\t\t\tbuildPhases = (")
        w(f"\t\t\t\t{uid('sources', t.name)} /* Sources */,")
        w(f"\t\t\t\t{uid('frameworks', t.name)} /* Frameworks */,")
        w(f"\t\t\t\t{uid('resources', t.name)} /* Resources */,")
        for child_name in t.embeds:
            w(f"\t\t\t\t{uid('embedphase', t.name, child_name)} /* Embed */,")
        w("\t\t\t);")
        w("\t\t\tbuildRules = (")
        w("\t\t\t);")
        w("\t\t\tdependencies = (")
        for child_name in t.embeds:
            w(f"\t\t\t\t{uid('dependency', t.name, child_name)} /* PBXTargetDependency */,")
        w("\t\t\t);")
        w("\t\t\tfileSystemSynchronizedGroups = (")
        w(f"\t\t\t\t{t.sync_group} /* {t.name} */,")
        w("\t\t\t);")
        w(f"\t\t\tname = {t.name};")
        w("\t\t\tpackageProductDependencies = (")
        w(f"\t\t\t\t{t.package_dep} /* WeatherCore */,")
        w("\t\t\t);")
        w(f'\t\t\tproductName = {t.name};')
        w(f"\t\t\tproductReference = {t.product_ref} /* {t.product_name} */;")
        w(f'\t\t\tproductType = "{t.product_type}";')
        w("\t\t};")
    w("/* End PBXNativeTarget section */")

    # ── PBXProject ──────────────────────────────────────────────────────────
    w("\n/* Begin PBXProject section */")
    w(f"\t\t{uid('project')} /* Project object */ = {{")
    w("\t\t\tisa = PBXProject;")
    w("\t\t\tattributes = {")
    w("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
    w("\t\t\t\tLastSwiftUpdateCheck = 1600;")
    w("\t\t\t\tLastUpgradeCheck = 1600;")
    w("\t\t\t\tTargetAttributes = {")
    for t in TARGETS:
        w(f"\t\t\t\t\t{t.id} = {{")
        w("\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;")
        w("\t\t\t\t\t};")
    w("\t\t\t\t};")
    w("\t\t\t};")
    w(f"\t\t\tbuildConfigurationList = {uid('configlist', 'project')} "
      "/* Build configuration list for PBXProject \"WeatherScope\" */;")
    w("\t\t\tdevelopmentRegion = en;")
    w("\t\t\thasScannedForEncodings = 0;")
    w("\t\t\tknownRegions = (")
    w("\t\t\t\ten,")
    w("\t\t\t\tBase,")
    w("\t\t\t);")
    w(f"\t\t\tmainGroup = {uid('group', 'root')};")
    w("\t\t\tminimizedProjectReferenceProxies = 1;")
    w("\t\t\tpackageReferences = (")
    w(f"\t\t\t\t{uid('localpackage', 'WeatherCore')} /* XCLocalSwiftPackageReference \"WeatherCore\" */,")
    w("\t\t\t);")
    w("\t\t\tpreferredProjectObjectVersion = 77;")
    w(f"\t\t\tproductRefGroup = {uid('group', 'products')} /* Products */;")
    w('\t\t\tprojectDirPath = "";')
    w('\t\t\tprojectRoot = "";')
    w("\t\t\ttargets = (")
    for t in TARGETS:
        w(f"\t\t\t\t{t.id} /* {t.name} */,")
    w("\t\t\t);")
    w("\t\t};")
    w("/* End PBXProject section */")

    # ── PBXResourcesBuildPhase ──────────────────────────────────────────────
    w("\n/* Begin PBXResourcesBuildPhase section */")
    for t in TARGETS:
        w(f"\t\t{uid('resources', t.name)} /* Resources */ = {{")
        w("\t\t\tisa = PBXResourcesBuildPhase;")
        w("\t\t\tbuildActionMask = 2147483647;")
        w("\t\t\tfiles = (")
        w("\t\t\t);")
        w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
        w("\t\t};")
    w("/* End PBXResourcesBuildPhase section */")

    # ── PBXSourcesBuildPhase ────────────────────────────────────────────────
    w("\n/* Begin PBXSourcesBuildPhase section */")
    for t in TARGETS:
        w(f"\t\t{uid('sources', t.name)} /* Sources */ = {{")
        w("\t\t\tisa = PBXSourcesBuildPhase;")
        w("\t\t\tbuildActionMask = 2147483647;")
        w("\t\t\tfiles = (")
        w("\t\t\t);")
        w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
        w("\t\t};")
    w("/* End PBXSourcesBuildPhase section */")

    # ── PBXTargetDependency ─────────────────────────────────────────────────
    w("\n/* Begin PBXTargetDependency section */")
    for host in TARGETS:
        for child_name in host.embeds:
            child = BY_NAME[child_name]
            w(f"\t\t{uid('dependency', host.name, child_name)} /* PBXTargetDependency */ = {{")
            w("\t\t\tisa = PBXTargetDependency;")
            w(f"\t\t\ttarget = {child.id} /* {child.name} */;")
            w(f"\t\t\ttargetProxy = {uid('proxy', host.name, child_name)} /* PBXContainerItemProxy */;")
            w("\t\t};")
    w("/* End PBXTargetDependency section */")

    # ── XCBuildConfiguration ────────────────────────────────────────────────
    w("\n/* Begin XCBuildConfiguration section */")
    for cfg, extra in (("Debug", DEBUG_ONLY), ("Release", RELEASE_ONLY)):
        settings = dict(SHARED_SETTINGS)
        settings.update(extra)
        w(f"\t\t{uid('config', 'project', cfg)} /* {cfg} */ = {{")
        w("\t\t\tisa = XCBuildConfiguration;")
        w("\t\t\tbuildSettings = {")
        w(fmt_settings(settings))
        w("\t\t\t};")
        w(f"\t\t\tname = {cfg};")
        w("\t\t};")

    for t in TARGETS:
        for cfg in ("Debug", "Release"):
            settings = dict(TARGET_COMMON)
            settings.update(t.settings)
            settings["PRODUCT_BUNDLE_IDENTIFIER"] = t.bundle_id
            if t.platform == "watchos":
                settings["SUPPORTS_MACCATALYST"] = "NO"
            w(f"\t\t{uid('config', t.name, cfg)} /* {cfg} */ = {{")
            w("\t\t\tisa = XCBuildConfiguration;")
            w("\t\t\tbuildSettings = {")
            w(fmt_settings(settings))
            w("\t\t\t};")
            w(f"\t\t\tname = {cfg};")
            w("\t\t};")
    w("/* End XCBuildConfiguration section */")

    # ── XCConfigurationList ─────────────────────────────────────────────────
    w("\n/* Begin XCConfigurationList section */")
    for owner in ["project"] + [t.name for t in TARGETS]:
        kind = "PBXProject \\\"WeatherScope\\\"" if owner == "project" \
            else f"PBXNativeTarget \\\"{owner}\\\""
        w(f"\t\t{uid('configlist', owner)} /* Build configuration list for {kind} */ = {{")
        w("\t\t\tisa = XCConfigurationList;")
        w("\t\t\tbuildConfigurations = (")
        w(f"\t\t\t\t{uid('config', owner, 'Debug')} /* Debug */,")
        w(f"\t\t\t\t{uid('config', owner, 'Release')} /* Release */,")
        w("\t\t\t);")
        w("\t\t\tdefaultConfigurationIsVisible = 0;")
        w("\t\t\tdefaultConfigurationName = Release;")
        w("\t\t};")
    w("/* End XCConfigurationList section */")

    # ── XCLocalSwiftPackageReference ────────────────────────────────────────
    w("\n/* Begin XCLocalSwiftPackageReference section */")
    w(f"\t\t{uid('localpackage', 'WeatherCore')} /* XCLocalSwiftPackageReference \"WeatherCore\" */ = {{")
    w("\t\t\tisa = XCLocalSwiftPackageReference;")
    w("\t\t\trelativePath = WeatherCore;")
    w("\t\t};")
    w("/* End XCLocalSwiftPackageReference section */")

    # ── XCSwiftPackageProductDependency ─────────────────────────────────────
    w("\n/* Begin XCSwiftPackageProductDependency section */")
    for t in TARGETS:
        w(f"\t\t{t.package_dep} /* WeatherCore */ = {{")
        w("\t\t\tisa = XCSwiftPackageProductDependency;")
        w("\t\t\tproductName = WeatherCore;")
        w("\t\t};")
    w("/* End XCSwiftPackageProductDependency section */")

    w("\t};")
    w(f"\trootObject = {uid('project')} /* Project object */;")
    w("}")
    return "\n".join(out) + "\n"


SCHEME_TEMPLATE = """<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "1600" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{target_id}"
               BuildableName = "{product_name}"
               BlueprintName = "{name}"
               ReferencedContainer = "container:WeatherScope.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{target_id}"
            BuildableName = "{product_name}"
            BlueprintName = "{name}"
            ReferencedContainer = "container:WeatherScope.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{target_id}"
            BuildableName = "{product_name}"
            BlueprintName = "{name}"
            ReferencedContainer = "container:WeatherScope.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""


def main():
    os.makedirs(os.path.join(PROJECT_DIR, "xcshareddata", "xcschemes"), exist_ok=True)
    with open(os.path.join(PROJECT_DIR, "project.pbxproj"), "w") as f:
        f.write(build())

    for t in TARGETS:
        path = os.path.join(PROJECT_DIR, "xcshareddata", "xcschemes", f"{t.name}.xcscheme")
        with open(path, "w") as f:
            f.write(SCHEME_TEMPLATE.format(
                target_id=t.id, product_name=t.product_name, name=t.name))

    print(f"wrote {PROJECT_DIR}/project.pbxproj and {len(TARGETS)} schemes")


if __name__ == "__main__":
    main()
