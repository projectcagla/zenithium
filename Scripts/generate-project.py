#!/usr/bin/env python3
"""Generate Zenithium.xcodeproj from the source tree.

ASSUMPTION BUILD-1: `project.yml` is the authoritative project definition and this script
is what turns it into a checked-in `.xcodeproj`, so the repository opens in Xcode without
XcodeGen installed. Both describe the same thing; if they ever disagree, `project.yml` is
right and this script is the bug.

Deterministic by construction: object identifiers are derived from a hash of the object's
role and path, so regenerating after an unrelated change produces a minimal diff rather
than reshuffling every identifier in the file.
"""

from __future__ import annotations

import hashlib
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROJECT_NAME = "Zenithium"
BUNDLE_PREFIX = "com.zenithium"
DEPLOYMENT_TARGET = "18.0"
WATCH_DEPLOYMENT_TARGET = "11.0"
SWIFT_VERSION = "6.0"

# Files the widget extension compiles as well as the app. The extension deliberately does
# not compile Health, Persistence (beyond the shared snapshot) or Orchestration: a widget
# has no business opening a HealthKit store.
WIDGET_SHARED = [
    "Zenithium/Support/ZenithiumLog.swift",
    "Zenithium/Support/AppGroup.swift",
    "Zenithium/Engines/EngineConstants.swift",
    "Zenithium/Engines/MathSupport.swift",
    "Zenithium/Persistence/WidgetSnapshot.swift",
    "Zenithium/Persistence/PendingJournalStore.swift",
    "Zenithium/Views/DesignSystem/ZenithiumColor.swift",
    "Zenithium/Views/DesignSystem/ZenithiumPalette.swift",
    "Zenithium/Views/DesignSystem/ZenithiumColorAsset.swift",
    "Zenithium/Views/DesignSystem/ZenithiumFont.swift",
    "Zenithium/Views/DesignSystem/ZenithiumMetrics.swift",
    # The Live Activity's shape, compiled by the app that starts it and the extension that
    # draws it — and by neither the watch nor the tests. Yol haritası v4, C10.
    "Zenithium/Live/LiveSessionAttributes.swift",
]
WIDGET_SHARED_DIRS = ["Zenithium/Domain"]

# Files the watch app compiles as well as the app. It is a reader: it opens no HealthKit
# store and no SwiftData container, so it needs the snapshot, the shared outbox, the design
# tokens and the domain vocabulary — and nothing else.
WATCH_SHARED = [
    "Zenithium/Support/AppGroup.swift",
    "Zenithium/Support/ZenithiumLog.swift",
    "Zenithium/Engines/EngineConstants.swift",
    "Zenithium/Engines/MathSupport.swift",
    "Zenithium/Persistence/WidgetSnapshot.swift",
    "Zenithium/Persistence/PendingJournalStore.swift",
    "Zenithium/Views/DesignSystem/ZenithiumColor.swift",
    "Zenithium/Views/DesignSystem/ZenithiumPalette.swift",
    "Zenithium/Views/DesignSystem/ZenithiumColorAsset.swift",
    "Zenithium/Views/DesignSystem/ZenithiumFont.swift",
    "Zenithium/Views/DesignSystem/ZenithiumMetrics.swift",
]
WATCH_SHARED_DIRS = ["Zenithium/Domain"]

# The colour asset catalog. Every target that draws needs it in its own bundle, because
# `Color(_:bundle:)` resolves against the bundle it is asked from and an extension's bundle is
# its own. Written by Scripts/generate-colors.py. Yol haritası v4, B6.
COLOR_CATALOG = "Zenithium/Resources/Zenithium.xcassets"

# The privacy manifest, one per bundle. Apple requires it for App Store submission and it
# must live in the bundle it describes — an extension's manifest is not covered by the app's.
PRIVACY_MANIFESTS = {
    "Zenithium": "Zenithium/PrivacyInfo.xcprivacy",
    "ZenithiumWidgets": "ZenithiumWidgets/PrivacyInfo.xcprivacy",
    "ZenithiumWatch": "ZenithiumWatch/PrivacyInfo.xcprivacy",
}
CATALOG_TARGETS = ["Zenithium", "ZenithiumWidgets", "ZenithiumWatch"]

# App icons live beside the target that shows them, not in the shared catalog.
#
# An app icon entry is tagged with the platform it belongs to. One shared `AppIcon` holding
# both platforms therefore left every iOS entry looking like an unassigned child to the watch
# build and every watchOS entry looking that way to the iOS builds — two warnings — and gave
# the watch no applicable content at all, which is an error: a watch app with no icon does not
# install. Each catalog now carries exactly one platform's set, so `AppIcon` resolves to
# exactly one thing in every target that compiles it. The widget names none: an app extension
# does not display an app icon.
ICON_CATALOGS = {
    "Zenithium": "Zenithium/Resources/AppIcon.xcassets",
    "ZenithiumWatch": "ZenithiumWatch/AppIconWatch.xcassets",
}


def catalogs_for(target: str) -> list[str]:
    """Every asset catalog one target compiles, in a stable order."""
    catalogs = [COLOR_CATALOG]
    if icon := ICON_CATALOGS.get(target):
        catalogs.append(icon)
    return catalogs


def uid(*parts: str) -> str:
    """A stable 24-hex-character object identifier."""
    digest = hashlib.sha256("::".join(parts).encode("utf-8")).hexdigest()
    return digest[:24].upper()


def swift_files(directory: str) -> list[str]:
    base = ROOT / directory
    if not base.exists():
        return []
    found = [
        str(path.relative_to(ROOT))
        for path in base.rglob("*.swift")
    ]
    return sorted(found)


def catalog_phase_entry(project: "Project", target: str) -> str:
    """The Resources phase's entries for a target."""
    if target not in CATALOG_TARGETS:
        return ""
    entries = ""
    for catalog in catalogs_for(target):
        name = Path(catalog).name
        identifier = project.build_file(catalog, target)
        entries += f"\t\t\t\t{identifier} /* {name} in Resources */,\n"
    if manifest := PRIVACY_MANIFESTS.get(target):
        entries += (
            f"\t\t\t\t{project.build_file(manifest, target)} "
            f"/* PrivacyInfo.xcprivacy in Resources */,\n"
        )
    return entries


def watch_sources() -> list[str]:
    sources = swift_files("ZenithiumWatch")
    for directory in WATCH_SHARED_DIRS:
        sources.extend(swift_files(directory))
    sources.extend(WATCH_SHARED)
    return sorted(set(sources))


def widget_sources() -> list[str]:
    sources = swift_files("ZenithiumWidgets")
    for directory in WIDGET_SHARED_DIRS:
        sources.extend(swift_files(directory))
    sources.extend(WIDGET_SHARED)
    return sorted(set(sources))


class Project:
    def __init__(self) -> None:
        self.lines: list[str] = []
        self.build_files: list[str] = []
        self.file_refs: dict[str, str] = {}
        self.groups: list[str] = []

    # -- object emission ---------------------------------------------------

    def file_ref(self, path: str) -> str:
        if path in self.file_refs:
            return self.file_refs[path]
        identifier = uid("fileRef", path)
        self.file_refs[path] = identifier
        return identifier

    def build_file(self, path: str, target: str) -> str:
        return uid("buildFile", target, path)


# Characters Xcode's own plist writer leaves unquoted. Anything else has to be quoted, and
# `+` is the one that mattered: `AppearancePreference+SwiftUI.swift` went out as
#
#     path = AppearancePreference+SwiftUI.swift;
#
# which Xcode refuses to parse at all — the whole project opens as "damaged", with no hint
# about which line. The generator had no quoting function; it interpolated names straight in
# and had simply never met a file name outside the safe set. XcodeGen quotes correctly, so
# `project.yml` builds were fine and only the checked-in project was broken.
PBX_SAFE = set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_$/:.-")


def pbx(value: str) -> str:
    """One string, quoted if Xcode's parser needs it."""
    if value and all(character in PBX_SAFE for character in value):
        return value
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def file_type_for(path: str) -> str:
    if path.endswith(".xcassets"):
        return "folder.assetcatalog"
    if path.endswith(".swift"):
        return "sourcecode.swift"
    if path.endswith(".plist"):
        return "text.plist.xml"
    if path.endswith(".entitlements"):
        return "text.plist.entitlements"
    if path.endswith(".app"):
        return "wrapper.application"
    if path.endswith(".appex"):
        return "wrapper.app-extension"
    if path.endswith(".xctest"):
        return "wrapper.cfbundle"
    return "text"


def build_tree(paths: list[str]) -> dict:
    """Nest a list of repo-relative paths into a directory tree."""
    tree: dict = {}
    for path in paths:
        parts = path.split("/")
        node = tree
        for part in parts[:-1]:
            node = node.setdefault(part, {})
        node.setdefault("__files__", []).append(path)
    return tree


def main() -> int:
    app_sources = swift_files("Zenithium")
    ext_sources = widget_sources()
    watch_target_sources = watch_sources()
    test_sources = swift_files("ZenithiumTests")

    if not app_sources:
        print("No app sources found — run this from the repository root.", file=sys.stderr)
        return 1

    project = Project()
    objects: list[str] = []

    # ---- products ----
    product_refs = {
        "Zenithium": (uid("product", "Zenithium"), "Zenithium.app", "wrapper.application"),
        "ZenithiumWidgets": (uid("product", "ZenithiumWidgets"), "ZenithiumWidgets.appex", "wrapper.app-extension"),
        "ZenithiumWatch": (uid("product", "ZenithiumWatch"), "ZenithiumWatch.app", "wrapper.application"),
        "ZenithiumTests": (uid("product", "ZenithiumTests"), "ZenithiumTests.xctest", "wrapper.cfbundle"),
    }

    # ---- PBXBuildFile ----
    objects.append("/* Begin PBXBuildFile section */")
    for target, sources in (
        ("Zenithium", app_sources),
        ("ZenithiumWidgets", ext_sources),
        ("ZenithiumWatch", watch_target_sources),
        ("ZenithiumTests", test_sources),
    ):
        for path in sources:
            name = Path(path).name
            objects.append(
                f"\t\t{project.build_file(path, target)} /* {name} in Sources */ = "
                f"{{isa = PBXBuildFile; fileRef = {project.file_ref(path)} /* {name} */; }};"
            )
    # The extension embedded into the app.
    ext_product_id = product_refs["ZenithiumWidgets"][0]
    objects.append(
        f"\t\t{uid('embed', 'ZenithiumWidgets')} /* ZenithiumWidgets.appex in Embed Foundation Extensions */ = "
        f"{{isa = PBXBuildFile; fileRef = {ext_product_id} /* ZenithiumWidgets.appex */; "
        f"settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};"
    )
    watch_product_id = product_refs["ZenithiumWatch"][0]
    objects.append(
        f"\t\t{uid('embed', 'ZenithiumWatch')} /* ZenithiumWatch.app in Embed Watch Content */ = "
        f"{{isa = PBXBuildFile; fileRef = {watch_product_id} /* ZenithiumWatch.app */; "
        f"settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};"
    )
    for target in CATALOG_TARGETS:
        for catalog in catalogs_for(target):
            name = Path(catalog).name
            objects.append(
                f"\t\t{project.build_file(catalog, target)} /* {name} in Resources */ = "
                f"{{isa = PBXBuildFile; fileRef = {project.file_ref(catalog)} /* {name} */; }};"
            )
        if manifest := PRIVACY_MANIFESTS.get(target):
            objects.append(
                f"\t\t{project.build_file(manifest, target)} /* PrivacyInfo.xcprivacy in Resources */ = "
                f"{{isa = PBXBuildFile; fileRef = {project.file_ref(manifest)} /* PrivacyInfo.xcprivacy */; }};"
            )
    objects.append("/* End PBXBuildFile section */\n")

    # ---- PBXContainerItemProxy ----
    objects.append("/* Begin PBXContainerItemProxy section */")
    project_id = uid("project", PROJECT_NAME)
    for dependent, dependency in (
        ("Zenithium", "ZenithiumWidgets"),
        ("Zenithium", "ZenithiumWatch"),
        ("ZenithiumTests", "Zenithium"),
    ):
        objects.append(
            f"\t\t{uid('proxy', dependent, dependency)} /* PBXContainerItemProxy */ = {{\n"
            f"\t\t\tisa = PBXContainerItemProxy;\n"
            f"\t\t\tcontainerPortal = {project_id} /* Project object */;\n"
            f"\t\t\tproxyType = 1;\n"
            f"\t\t\tremoteGlobalIDString = {uid('target', dependency)};\n"
            f"\t\t\tremoteInfo = {pbx(dependency)};\n"
            f"\t\t}};"
        )
    objects.append("/* End PBXContainerItemProxy section */\n")

    # ---- PBXCopyFilesBuildPhase ----
    objects.append("/* Begin PBXCopyFilesBuildPhase section */")
    objects.append(
        f"\t\t{uid('copyPhase', 'Zenithium')} /* Embed Foundation Extensions */ = {{\n"
        f"\t\t\tisa = PBXCopyFilesBuildPhase;\n"
        f"\t\t\tbuildActionMask = 2147483647;\n"
        f"\t\t\tdstPath = \"\";\n"
        f"\t\t\tdstSubfolderSpec = 13;\n"
        f"\t\t\tfiles = (\n"
        f"\t\t\t\t{uid('embed', 'ZenithiumWidgets')} /* ZenithiumWidgets.appex in Embed Foundation Extensions */,\n"
        f"\t\t\t);\n"
        f"\t\t\tname = \"Embed Foundation Extensions\";\n"
        f"\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
        f"\t\t}};"
    )
    objects.append(
        f"\t\t{uid('copyPhase', 'ZenithiumWatch')} /* Embed Watch Content */ = {{\n"
        f"\t\t\tisa = PBXCopyFilesBuildPhase;\n"
        f"\t\t\tbuildActionMask = 2147483647;\n"
        f"\t\t\tdstPath = \"$(CONTENTS_FOLDER_PATH)/Watch\";\n"
        f"\t\t\tdstSubfolderSpec = 16;\n"
        f"\t\t\tfiles = (\n"
        f"\t\t\t\t{uid('embed', 'ZenithiumWatch')} /* ZenithiumWatch.app in Embed Watch Content */,\n"
        f"\t\t\t);\n"
        f"\t\t\tname = \"Embed Watch Content\";\n"
        f"\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
        f"\t\t}};"
    )
    objects.append("/* End PBXCopyFilesBuildPhase section */\n")

    # ---- PBXFileReference ----
    objects.append("/* Begin PBXFileReference section */")
    resource_files = [
        COLOR_CATALOG,
        *ICON_CATALOGS.values(),
        *PRIVACY_MANIFESTS.values(),
        "Zenithium/Info.plist",
        "Zenithium/Zenithium.entitlements",
        "ZenithiumWidgets/Info.plist",
        "ZenithiumWidgets/ZenithiumWidgets.entitlements",
        "ZenithiumWatch/Info.plist",
        "ZenithiumWatch/ZenithiumWatch.entitlements",
    ]
    all_files = sorted(
        set(app_sources + ext_sources + watch_target_sources + test_sources + resource_files)
    )
    for path in all_files:
        name = Path(path).name
        objects.append(
            f"\t\t{project.file_ref(path)} /* {name} */ = {{isa = PBXFileReference; "
            f"lastKnownFileType = {file_type_for(path)}; path = {pbx(name)}; sourceTree = \"<group>\"; }};"
        )
    for identifier, name, filetype in product_refs.values():
        objects.append(
            f"\t\t{identifier} /* {name} */ = {{isa = PBXFileReference; explicitFileType = {filetype}; "
            f"includeInIndex = 0; path = {pbx(name)}; sourceTree = BUILT_PRODUCTS_DIR; }};"
        )
    objects.append("/* End PBXFileReference section */\n")

    # ---- PBXFrameworksBuildPhase ----
    # Empty: Swift auto-links every framework these targets `import`, so an explicit
    # frameworks phase would only be a second place to keep in sync.
    objects.append("/* Begin PBXFrameworksBuildPhase section */")
    for target in ("Zenithium", "ZenithiumWidgets", "ZenithiumWatch", "ZenithiumTests"):
        objects.append(
            f"\t\t{uid('frameworks', target)} /* Frameworks */ = {{\n"
            f"\t\t\tisa = PBXFrameworksBuildPhase;\n"
            f"\t\t\tbuildActionMask = 2147483647;\n"
            f"\t\t\tfiles = (\n\t\t\t);\n"
            f"\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
            f"\t\t}};"
        )
    objects.append("/* End PBXFrameworksBuildPhase section */\n")

    # ---- PBXGroup ----
    objects.append("/* Begin PBXGroup section */")
    group_lines: list[str] = []

    def emit_group(name: str, node: dict, path_prefix: str) -> str:
        identifier = uid("group", path_prefix or name)
        children: list[str] = []
        for key in sorted(k for k in node if k != "__files__"):
            child_prefix = f"{path_prefix}/{key}" if path_prefix else key
            child_id = emit_group(key, node[key], child_prefix)
            children.append(f"\t\t\t\t{child_id} /* {key} */,")
        for file_path in sorted(node.get("__files__", [])):
            children.append(
                f"\t\t\t\t{project.file_ref(file_path)} /* {Path(file_path).name} */,"
            )
        body = "\n".join(children)
        group_lines.append(
            f"\t\t{identifier} /* {name} */ = {{\n"
            f"\t\t\tisa = PBXGroup;\n"
            f"\t\t\tchildren = (\n{body}\n\t\t\t);\n"
            f"\t\t\tpath = {pbx(name)};\n"
            f"\t\t\tsourceTree = \"<group>\";\n"
            f"\t\t}};"
        )
        return identifier

    tree = build_tree(all_files)
    top_level_ids: list[str] = []
    for key in sorted(tree):
        if key == "__files__":
            continue
        top_level_ids.append((emit_group(key, tree[key], key), key))

    products_group = uid("group", "Products")
    product_children = "\n".join(
        f"\t\t\t\t{identifier} /* {name} */,"
        for identifier, name, _ in product_refs.values()
    )
    group_lines.append(
        f"\t\t{products_group} /* Products */ = {{\n"
        f"\t\t\tisa = PBXGroup;\n"
        f"\t\t\tchildren = (\n{product_children}\n\t\t\t);\n"
        f"\t\t\tname = Products;\n"
        f"\t\t\tsourceTree = \"<group>\";\n"
        f"\t\t}};"
    )

    root_group = uid("group", "__root__")
    root_children = "\n".join(
        f"\t\t\t\t{identifier} /* {name} */," for identifier, name in top_level_ids
    )
    group_lines.append(
        f"\t\t{root_group} = {{\n"
        f"\t\t\tisa = PBXGroup;\n"
        f"\t\t\tchildren = (\n{root_children}\n"
        f"\t\t\t\t{products_group} /* Products */,\n"
        f"\t\t\t);\n"
        f"\t\t\tsourceTree = \"<group>\";\n"
        f"\t\t}};"
    )
    objects.extend(group_lines)
    objects.append("/* End PBXGroup section */\n")

    # ---- PBXNativeTarget ----
    objects.append("/* Begin PBXNativeTarget section */")
    target_specs = {
        "Zenithium": ("com.apple.product-type.application", "Zenithium.app"),
        "ZenithiumWidgets": ("com.apple.product-type.app-extension", "ZenithiumWidgets.appex"),
        "ZenithiumWatch": ("com.apple.product-type.application", "ZenithiumWatch.app"),
        "ZenithiumTests": ("com.apple.product-type.bundle.unit-test", "ZenithiumTests.xctest"),
    }
    for target, (product_type, product_name) in target_specs.items():
        phases = [
            f"\t\t\t\t{uid('sources', target)} /* Sources */,",
            f"\t\t\t\t{uid('frameworks', target)} /* Frameworks */,",
            f"\t\t\t\t{uid('resources', target)} /* Resources */,",
        ]
        if target == "Zenithium":
            phases.append(f"\t\t\t\t{uid('copyPhase', 'Zenithium')} /* Embed Foundation Extensions */,")
            phases.append(f"\t\t\t\t{uid('copyPhase', 'ZenithiumWatch')} /* Embed Watch Content */,")
        dependencies = ""
        if target == "Zenithium":
            dependencies = (
                f"\t\t\t\t{uid('dependency', 'Zenithium', 'ZenithiumWidgets')} /* PBXTargetDependency */,\n"
                f"\t\t\t\t{uid('dependency', 'Zenithium', 'ZenithiumWatch')} /* PBXTargetDependency */,\n"
            )
        elif target == "ZenithiumTests":
            dependencies = f"\t\t\t\t{uid('dependency', 'ZenithiumTests', 'Zenithium')} /* PBXTargetDependency */,\n"
        objects.append(
            f"\t\t{uid('target', target)} /* {target} */ = {{\n"
            f"\t\t\tisa = PBXNativeTarget;\n"
            f"\t\t\tbuildConfigurationList = {uid('configList', target)} /* Build configuration list for PBXNativeTarget \"{target}\" */;\n"
            f"\t\t\tbuildPhases = (\n" + "\n".join(phases) + "\n\t\t\t);\n"
            f"\t\t\tbuildRules = (\n\t\t\t);\n"
            f"\t\t\tdependencies = (\n{dependencies}\t\t\t);\n"
            f"\t\t\tname = {pbx(target)};\n"
            f"\t\t\tproductName = {pbx(target)};\n"
            f"\t\t\tproductReference = {product_refs[target][0]} /* {product_name} */;\n"
            f"\t\t\tproductType = \"{product_type}\";\n"
            f"\t\t}};"
        )
    objects.append("/* End PBXNativeTarget section */\n")

    # ---- PBXProject ----
    objects.append("/* Begin PBXProject section */")
    target_list = "\n".join(
        f"\t\t\t\t{uid('target', target)} /* {target} */," for target in target_specs
    )
    objects.append(
        f"\t\t{project_id} /* Project object */ = {{\n"
        f"\t\t\tisa = PBXProject;\n"
        f"\t\t\tattributes = {{\n"
        f"\t\t\t\tBuildIndependentTargetsInParallel = 1;\n"
        f"\t\t\t\tLastSwiftUpdateCheck = 1600;\n"
        f"\t\t\t\tLastUpgradeCheck = 1600;\n"
        f"\t\t\t\tTargetAttributes = {{\n"
        f"\t\t\t\t\t{uid('target', 'ZenithiumTests')} = {{\n"
        f"\t\t\t\t\t\tTestTargetID = {uid('target', 'Zenithium')};\n"
        f"\t\t\t\t\t}};\n"
        f"\t\t\t\t}};\n"
        f"\t\t\t}};\n"
        f"\t\t\tbuildConfigurationList = {uid('configList', '__project__')} /* Build configuration list for PBXProject \"{PROJECT_NAME}\" */;\n"
        f"\t\t\tcompatibilityVersion = \"Xcode 15.0\";\n"
        # project.yml declares `developmentLanguage: tr`, and this line used to say `en` —
        # so an XcodeGen build and the checked-in project disagreed about
        # CFBundleDevelopmentRegion, which is the localization the App Store falls back to.
        f"\t\t\tdevelopmentRegion = tr;\n"
        f"\t\t\thasScannedForEncodings = 0;\n"
        f"\t\t\tknownRegions = (\n\t\t\t\ttr,\n\t\t\t\tBase,\n\t\t\t);\n"
        f"\t\t\tmainGroup = {root_group};\n"
        f"\t\t\tproductRefGroup = {products_group} /* Products */;\n"
        f"\t\t\tprojectDirPath = \"\";\n"
        f"\t\t\tprojectRoot = \"\";\n"
        f"\t\t\ttargets = (\n{target_list}\n\t\t\t);\n"
        f"\t\t}};"
    )
    objects.append("/* End PBXProject section */\n")

    # ---- PBXResourcesBuildPhase ----
    objects.append("/* Begin PBXResourcesBuildPhase section */")
    for target in target_specs:
        objects.append(
            f"\t\t{uid('resources', target)} /* Resources */ = {{\n"
            f"\t\t\tisa = PBXResourcesBuildPhase;\n"
            f"\t\t\tbuildActionMask = 2147483647;\n"
            f"\t\t\tfiles = (\n{catalog_phase_entry(project, target)}\t\t\t);\n"
            f"\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
            f"\t\t}};"
        )
    objects.append("/* End PBXResourcesBuildPhase section */\n")

    # ---- PBXSourcesBuildPhase ----
    objects.append("/* Begin PBXSourcesBuildPhase section */")
    for target, sources in (
        ("Zenithium", app_sources),
        ("ZenithiumWidgets", ext_sources),
        ("ZenithiumWatch", watch_target_sources),
        ("ZenithiumTests", test_sources),
    ):
        entries = "\n".join(
            f"\t\t\t\t{project.build_file(path, target)} /* {Path(path).name} in Sources */,"
            for path in sources
        )
        objects.append(
            f"\t\t{uid('sources', target)} /* Sources */ = {{\n"
            f"\t\t\tisa = PBXSourcesBuildPhase;\n"
            f"\t\t\tbuildActionMask = 2147483647;\n"
            f"\t\t\tfiles = (\n{entries}\n\t\t\t);\n"
            f"\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
            f"\t\t}};"
        )
    objects.append("/* End PBXSourcesBuildPhase section */\n")

    # ---- PBXTargetDependency ----
    objects.append("/* Begin PBXTargetDependency section */")
    for dependent, dependency in (
        ("Zenithium", "ZenithiumWidgets"),
        ("Zenithium", "ZenithiumWatch"),
        ("ZenithiumTests", "Zenithium"),
    ):
        objects.append(
            f"\t\t{uid('dependency', dependent, dependency)} /* PBXTargetDependency */ = {{\n"
            f"\t\t\tisa = PBXTargetDependency;\n"
            f"\t\t\ttarget = {uid('target', dependency)} /* {dependency} */;\n"
            f"\t\t\ttargetProxy = {uid('proxy', dependent, dependency)} /* PBXContainerItemProxy */;\n"
            f"\t\t}};"
        )
    objects.append("/* End PBXTargetDependency section */\n")

    # ---- XCBuildConfiguration ----
    shared_base = {
        "CLANG_ENABLE_MODULES": "YES",
        "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
        "GCC_TREAT_WARNINGS_AS_ERRORS": "YES",
        "IPHONEOS_DEPLOYMENT_TARGET": DEPLOYMENT_TARGET,
        "SDKROOT": "iphoneos",
        # §2.1 — Swift 6 language mode with complete strict concurrency, warnings as errors
        # so a concurrency diagnostic cannot be shipped past.
        "SWIFT_STRICT_CONCURRENCY": "complete",
        "SWIFT_TREAT_WARNINGS_AS_ERRORS": "YES",
        "SWIFT_UPCOMING_FEATURE_EXISTENTIAL_ANY": "YES",
        "SWIFT_VERSION": SWIFT_VERSION,
        "CODE_SIGN_STYLE": "Automatic",
    }
    debug_extra = {
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG",
        "SWIFT_OPTIMIZATION_LEVEL": '"-Onone"',
        "ENABLE_TESTABILITY": "YES",
        "ONLY_ACTIVE_ARCH": "YES",
        # ASSUMPTION BUILD-4 (revised): warnings are errors in Release only. Keeping them
        # fatal in Debug too would mean a single unused-variable warning blocks a device
        # build, which turns bring-up into a slog for no safety gain — Release and CI still
        # enforce the §2.1 zero-warning requirement before anything ships.
        "SWIFT_TREAT_WARNINGS_AS_ERRORS": "NO",
        "GCC_TREAT_WARNINGS_AS_ERRORS": "NO",
    }
    release_extra = {
        "SWIFT_COMPILATION_MODE": "wholemodule",
        "SWIFT_OPTIMIZATION_LEVEL": '"-O"',
        "ENABLE_TESTABILITY": "NO",
        "VALIDATE_PRODUCT": "YES",
    }
    target_settings = {
        "Zenithium": {
            "PRODUCT_BUNDLE_IDENTIFIER": f"{BUNDLE_PREFIX}.app",
            "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
            "PRODUCT_NAME": "Zenithium",
            "INFOPLIST_FILE": "Zenithium/Info.plist",
            "CODE_SIGN_ENTITLEMENTS": "Zenithium/Zenithium.entitlements",
            "TARGETED_DEVICE_FAMILY": '"1,2"',
            "GENERATE_INFOPLIST_FILE": "NO",
            "CURRENT_PROJECT_VERSION": "3",
            "MARKETING_VERSION": "1.0",
            "SWIFT_EMIT_LOC_STRINGS": "YES",
        },
        "ZenithiumWidgets": {
            "PRODUCT_BUNDLE_IDENTIFIER": f"{BUNDLE_PREFIX}.app.widgets",
            # No app icon: an app extension does not display one.
            "PRODUCT_NAME": "ZenithiumWidgets",
            "INFOPLIST_FILE": "ZenithiumWidgets/Info.plist",
            "CODE_SIGN_ENTITLEMENTS": "ZenithiumWidgets/ZenithiumWidgets.entitlements",
            "TARGETED_DEVICE_FAMILY": '"1,2"',
            "GENERATE_INFOPLIST_FILE": "NO",
            "SKIP_INSTALL": "YES",
            "CURRENT_PROJECT_VERSION": "3",
            "MARKETING_VERSION": "1.0",
        },
        "ZenithiumWatch": {
            # A single-target watch app's bundle identifier must be the phone app's with a
            # suffix; Xcode rejects anything else at install time.
            "PRODUCT_BUNDLE_IDENTIFIER": f"{BUNDLE_PREFIX}.app.watchkitapp",
            # `AppIconWatch.xcassets`, beside this target's sources, holds the only set by
            # this name the watch compiles — see project.yml.
            "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
            "PRODUCT_NAME": "ZenithiumWatch",
            "INFOPLIST_FILE": "ZenithiumWatch/Info.plist",
            "CODE_SIGN_ENTITLEMENTS": "ZenithiumWatch/ZenithiumWatch.entitlements",
            # The shared base sets an iOS SDK, so the watch target overrides all three of
            # SDK, deployment target and device family — leaving any of them inherited is how
            # a watch target silently builds for iPhone.
            "SDKROOT": "watchos",
            "WATCHOS_DEPLOYMENT_TARGET": WATCH_DEPLOYMENT_TARGET,
            "TARGETED_DEVICE_FAMILY": "4",
            "SUPPORTED_PLATFORMS": '"watchos watchsimulator"',
            "GENERATE_INFOPLIST_FILE": "NO",
            "SKIP_INSTALL": "YES",
            "CURRENT_PROJECT_VERSION": "3",
            "MARKETING_VERSION": "1.0",
        },
        "ZenithiumTests": {
            "PRODUCT_BUNDLE_IDENTIFIER": f"{BUNDLE_PREFIX}.app.tests",
            "PRODUCT_NAME": "ZenithiumTests",
            "GENERATE_INFOPLIST_FILE": "YES",
            "TEST_HOST": '"$(BUILT_PRODUCTS_DIR)/Zenithium.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Zenithium"',
            "BUNDLE_LOADER": '"$(TEST_HOST)"',
        },
    }

    def render_settings(settings: dict[str, str]) -> str:
        return "\n".join(f"\t\t\t\t{key} = {value};" for key, value in sorted(settings.items()))

    objects.append("/* Begin XCBuildConfiguration section */")
    for config, extra in (("Debug", debug_extra), ("Release", release_extra)):
        merged = dict(shared_base)
        merged.update(extra)
        objects.append(
            f"\t\t{uid('config', '__project__', config)} /* {config} */ = {{\n"
            f"\t\t\tisa = XCBuildConfiguration;\n"
            f"\t\t\tbuildSettings = {{\n{render_settings(merged)}\n\t\t\t}};\n"
            f"\t\t\tname = {config};\n"
            f"\t\t}};"
        )
    for target, settings in target_settings.items():
        for config in ("Debug", "Release"):
            objects.append(
                f"\t\t{uid('config', target, config)} /* {config} */ = {{\n"
                f"\t\t\tisa = XCBuildConfiguration;\n"
                f"\t\t\tbuildSettings = {{\n{render_settings(settings)}\n\t\t\t}};\n"
                f"\t\t\tname = {config};\n"
                f"\t\t}};"
            )
    objects.append("/* End XCBuildConfiguration section */\n")

    # ---- XCConfigurationList ----
    objects.append("/* Begin XCConfigurationList section */")
    for scope, label in [("__project__", f'PBXProject "{PROJECT_NAME}"')] + [
        (target, f'PBXNativeTarget "{target}"') for target in target_specs
    ]:
        objects.append(
            f"\t\t{uid('configList', scope)} /* Build configuration list for {label} */ = {{\n"
            f"\t\t\tisa = XCConfigurationList;\n"
            f"\t\t\tbuildConfigurations = (\n"
            f"\t\t\t\t{uid('config', scope, 'Debug')} /* Debug */,\n"
            f"\t\t\t\t{uid('config', scope, 'Release')} /* Release */,\n"
            f"\t\t\t);\n"
            f"\t\t\tdefaultConfigurationIsVisible = 0;\n"
            f"\t\t\tdefaultConfigurationName = Release;\n"
            f"\t\t}};"
        )
    objects.append("/* End XCConfigurationList section */")

    body = "\n".join(objects)
    pbxproj = (
        "// !$*UTF8*$!\n"
        "{\n"
        "\tarchiveVersion = 1;\n"
        "\tclasses = {\n\t};\n"
        "\tobjectVersion = 56;\n"
        "\tobjects = {\n\n"
        f"{body}\n"
        "\t};\n"
        f"\trootObject = {project_id} /* Project object */;\n"
        "}\n"
    )

    out_dir = ROOT / f"{PROJECT_NAME}.xcodeproj"
    out_dir.mkdir(exist_ok=True)
    (out_dir / "project.pbxproj").write_text(pbxproj, encoding="utf-8")

    (out_dir / "project.xcworkspace").mkdir(exist_ok=True)
    (out_dir / "project.xcworkspace" / "contents.xcworkspacedata").write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<Workspace version = "1.0">\n'
        '   <FileRef location = "self:">\n'
        "   </FileRef>\n"
        "</Workspace>\n",
        encoding="utf-8",
    )

    print(
        f"Wrote {out_dir.relative_to(ROOT)}/project.pbxproj — "
        f"{len(app_sources)} app, {len(ext_sources)} extension, "
        f"{len(watch_target_sources)} watch, {len(test_sources)} test sources"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
