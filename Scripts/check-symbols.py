#!/usr/bin/env python3
"""Resolve every type reference in every target against what that target actually compiles.

What this is, and what it is not
--------------------------------
It is not a compiler and it cannot become one. It parses declarations and references with
regular expressions, which means it knows nothing about generics, overloads, type inference
or member lookup. What it *does* know is the one question that has bitten this project
repeatedly and that no test can answer: **does the name this file uses exist in the set of
files this target compiles?**

That question is worth automating because getting it wrong is invisible. A type used by the
watch app but only compiled into the iOS app produces a perfect iOS build and a broken watch
build, and nothing in the iOS build says so. It happened twice with target source lists
(`check-target-sources.py` guards the lists themselves) and it is the failure mode a
four-target project produces on its own.

Checks
------
1. Every referenced type name resolves to a declaration inside the target's own source set,
   or to a known first-party framework symbol.
2. No type is declared twice inside one target.
3. Banned constructs (§2.4) do not appear outside comments.
4. Braces, parentheses and brackets balance in every file.

Exit code is non-zero when anything fails, so it can run before a build.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROJECT_YML = ROOT / "project.yml"

# ---------------------------------------------------------------------------
# Symbols the Apple SDKs provide. Not exhaustive — extended when a scan reports
# a false positive that is genuinely a framework type.
# ---------------------------------------------------------------------------
FRAMEWORK_SYMBOLS = {
    # Swift standard library and Foundation
    "Array", "Bool", "Calendar", "CharacterSet", "Character", "Codable", "CodingKey",
    "Comparable", "Data", "Date", "DateComponents", "DateFormatter", "DateInterval",
    "Decodable", "Decoder", "Dictionary", "Double", "Encodable", "Encoder", "Equatable",
    "Error", "FileManager", "Float", "Hashable", "Identifiable", "Int", "Int64", "JSONDecoder",
    "JSONEncoder", "KeyedDecodingContainer", "LocalizedError", "Locale", "Measurement",
    "NSError", "NSLocalizedString", "NSObject", "NSObjectProtocol", "Notification",
    "NotificationCenter", "NumberFormatter", "Optional", "OptionSet", "Range", "RawRepresentable",
    "Result", "Sendable", "Set", "String", "Substring", "TimeInterval", "TimeZone", "URL",
    "URLComponents", "UUID", "UInt64", "UInt8", "UserDefaults", "XMLParser", "XMLParserDelegate",
    "CaseIterable", "ClosedRange", "Collection", "CustomStringConvertible", "Numeric",
    "AdditiveArithmetic", "BinaryFloatingPoint", "BinaryInteger", "Strideable", "Void",
    "ISO8601DateFormatter", "DateComponentsFormatter", "ByteCountFormatter", "IndexSet",
    "PropertyListDecoder", "PropertyListEncoder", "FileHandle", "Bundle", "ProcessInfo",
    "AnyIterator", "Never", "StaticString", "AnyHashable", "JSONSerialization",
    "Swift", "Foundation",
    # Concurrency
    "Task", "TaskGroup", "ThrowingTaskGroup", "Actor", "MainActor", "AsyncStream",
    "AsyncThrowingStream", "AsyncSequence", "CheckedContinuation", "UnsafeContinuation",
    "TaskPriority", "Duration", "Clock", "ContinuousClock", "AsyncIteratorProtocol",
    "CancellationError", "Sendable",
    # SwiftUI
    "View", "Text", "Image", "VStack", "HStack", "ZStack", "LazyVStack", "LazyHStack",
    "LazyVGrid", "GridItem", "ScrollView", "List", "Section", "NavigationStack",
    "NavigationLink", "NavigationSplitView", "Button", "Toggle", "Picker", "Slider",
    "Stepper", "TextField", "TextEditor", "DatePicker", "Form", "Group", "GroupBox",
    "Spacer", "Divider", "Color", "Font", "Shape", "Path", "Canvas", "GeometryReader",
    "GeometryProxy", "Animation", "Animatable", "AnimatablePair", "EmptyAnimatableData",
    "State", "Binding", "Environment", "EnvironmentObject", "Namespace", "FocusState",
    "ViewModifier", "ViewBuilder", "AnyView", "EdgeInsets", "Alignment", "HorizontalAlignment",
    "VerticalAlignment", "UnitPoint", "Angle", "CGFloat", "CGPoint", "CGSize", "CGRect",
    "CGContext", "CGImage", "CGColorSpace", "CGAffineTransform", "LinearGradient",
    "RadialGradient", "AngularGradient", "Gradient", "Circle", "Ellipse", "Rectangle",
    "RoundedRectangle", "Capsule", "StrokeStyle", "ShapeStyle", "Material", "Label",
    "ProgressView", "Chart", "ChartProxy", "BarMark", "LineMark", "AreaMark", "PointMark",
    "RuleMark", "RectangleMark", "AxisMarks", "AxisValueLabel", "AxisGridLine", "AxisTick",
    "PlottableValue", "ScrollViewReader", "TabView", "Tab", "Menu", "ShareLink", "Table",
    "TableColumn", "ContentUnavailableView", "PreviewProvider", "App", "Scene", "WindowGroup",
    "ScenePhase", "ColorScheme", "DynamicTypeSize", "ScaledMetric", "AccessibilityTraits",
    "AXChartDescriptor", "AXDataSeriesDescriptor", "AXNumericDataAxisDescriptor",
    "AXCategoricalDataAxisDescriptor", "AXDataPoint", "AXChartDescriptorRepresentable",
    "UnitCurve", "KeyframeAnimator", "PhaseAnimator", "SensoryFeedback", "Transaction",
    "FileDocument", "FileDocumentConfiguration", "UTType", "FileWrapper", "ReadConfiguration",
    "WriteConfiguration", "TextAlignment", "ControlSize", "Axis", "Visibility", "Edge",
    "SymbolRenderingMode", "ContentTransition", "AnyShapeStyle", "PreferenceKey",
    "Context",
    # SwiftData
    "Model", "ModelContainer", "ModelContext", "ModelActor", "Schema", "ModelConfiguration",
    "PersistentModel", "VersionedSchema", "SchemaMigrationPlan", "MigrationStage",
    "FetchDescriptor", "SortDescriptor", "Predicate", "PersistentIdentifier", "Query",
    "Attribute", "Relationship", "ModelExecutor", "DefaultSerialModelExecutor",
    # HealthKit
    "HKHealthStore", "HKQuery", "HKSampleQuery", "HKStatisticsQuery", "HKObserverQuery",
    "HKStatisticsCollectionQuery", "HKAnchoredObjectQuery", "HKQuantityType", "HKCategoryType",
    "HKObjectType", "HKSampleType", "HKQuantity", "HKUnit", "HKStatistics", "HKSample",
    "HKQuantitySample", "HKCategorySample", "HKWorkout", "HKWorkoutSession", "HKWorkoutBuilder",
    "HKLiveWorkoutBuilder", "HKLiveWorkoutDataSource", "HKWorkoutConfiguration",
    "HKWorkoutActivityType", "HKWorkoutSessionState", "HKWorkoutSessionDelegate",
    "HKLiveWorkoutBuilderDelegate", "HKQueryAnchor", "HKError", "HKAuthorizationRequestStatus",
    "HKBiologicalSex", "HKBiologicalSexObject", "HKCategoryValueSleepAnalysis",
    "HKStatisticsOptions", "HKQueryOptions", "HKSourceRevision", "HKDevice", "HKObject",
    "HKWorkoutEvent", "HKUpdateFrequency", "HKStatisticsCollection", "HKCharacteristicType",
    "HKSeriesType", "HKMetadataKeyWeatherTemperature", "HKMetadataKeyWeatherHumidity",
    # WidgetKit / ActivityKit / AppIntents / WatchConnectivity
    "Widget", "WidgetBundle", "WidgetConfiguration", "StaticConfiguration", "ControlWidget",
    "ControlWidgetConfiguration", "StaticControlConfiguration", "ControlWidgetButton",
    "TimelineProvider", "TimelineEntry", "Timeline", "TimelineEntryRelevance", "WidgetCenter",
    "WidgetFamily", "WidgetRenderingMode", "AccessoryWidgetBackground", "Activity",
    "ActivityAttributes", "ActivityContent", "ActivityConfiguration", "ActivityAuthorizationInfo",
    "DynamicIsland", "DynamicIslandExpandedRegion", "AppIntent", "AppIntentsPackage",
    "AppShortcut", "AppShortcutsProvider", "IntentResult", "IntentDialog", "AppEntity",
    "EntityQuery", "LiveActivityIntent", "WCSession", "WCSessionDelegate",
    "WCSessionActivationState", "ProvidesAppEntity", "OpenIntent", "IntentParameter",
    "ActivityUIDismissalPolicy",
    # Vision / PDFKit / CoreGraphics / OSLog / BackgroundTasks / UIKit
    "VNRecognizeTextRequest", "VNImageRequestHandler", "VNRecognizedTextObservation",
    "VNRequest", "PDFDocument", "PDFPage", "PDFDisplayBox", "Logger", "OSLog", "OSSignposter",
    "OSSignpostID", "OSSignpostIntervalState", "BGTaskScheduler", "BGTask", "BGAppRefreshTask",
    "BGAppRefreshTaskRequest", "UIApplication", "UIGraphicsPDFRenderer",
    "UIGraphicsPDFRendererFormat", "UIColor", "UIFont", "NSAttributedString",
    "NSMutableParagraphStyle", "NSParagraphStyle", "WKApplication", "WKExtension",
    "WKInterfaceDevice", "LanguageModelSession", "SystemLanguageModel", "Observable",
    "ObservationRegistrar", "Generable", "Guide",
    "EmptyView", "ForEach", "LabeledContent", "ToolbarItem", "ToolbarContent",
    "ToolbarContentBuilder", "ViewThatFits", "TimelineView", "MeshGradient", "SIMD2",
    "DragGesture", "Gesture", "Layout", "ProposedViewSize", "Subviews", "FormatStyle",
    "LocalizedStringResource", "IntentDescription", "ProvidesDialog", "NSKeyedArchiver",
    "NSKeyedUnarchiver", "NSSortDescriptor", "UIActivityViewController",
    "UIViewControllerRepresentable", "CGColorSpaceCreateDeviceGray", "CGImageAlphaInfo",
    "HKObjectQueryNoLimit", "HKSampleSortIdentifierStartDate", "HKCategoryValueVaginalBleeding",
    "HKMetadataKeyMenstrualCycleStart", "HKMetadataKeyTimeZone", "Gauge", "Preview",
    "ContainerBackground", "WidgetAccentedRenderingMode",
    # Swift Testing
    "Test", "Suite", "Issue", "Comment", "SourceLocation", "Tag", "ConfirmationError",
    "CustomTestStringConvertible",
}

# Names that appear capitalised but are not type references.
IGNORED_TOKENS = {
    "MARK", "TODO", "FIXME", "NOTE", "ASSUMPTION", "OK", "HRV", "RHR", "REM", "TRIMP",
    "ACWR", "VO", "PDF", "OCR", "JSON", "URL", "UUID", "API", "UI", "ID", "HTTP",
    "Self", "Type", "Protocol", "Any", "AnyObject", "Optional", "Element", "Value", "Key",
    "Output", "Input", "Success", "Failure", "T", "U", "V", "Content", "Body", "Style",
}

BANNED = [
    (r"\bObservableObject\b", "ObservableObject (§2.4)"),
    (r"@Published\b", "@Published (§2.4)"),
    (r"^\s*import Combine\b", "import Combine (§2.4)"),
    (r"\bDispatchQueue\b", "DispatchQueue (§2.4)"),
    (r"\bNSLock\b", "NSLock (§2.4)"),
    (r"^\s*print\(", "print() (§2.4)"),
    (r"\btry!\s", "try! (§2.4)"),
    (r"\bas!\s", "as! (§2.4)"),
]

# `String(format: "%.Nf")` writes a period whatever the locale, which is wrong in an app
# whose every other string is Turkish. Two files define the substitution that fixes it —
# `ZenithiumFormat.decimal` for everything that draws, and `CorrelationEngine`'s own copy,
# which cannot reach the design system because §2.1's dependency runs the other way. Every
# other use went through those, and this keeps a new one from going straight back to C's
# formatter.
DECIMAL_FORMAT = re.compile(r'String\(format:\s*"[^"]*%\.[^"]*f"')
DECIMAL_FORMAT_ALLOWED = {
    "Zenithium/Views/DesignSystem/ZenithiumFont.swift",
    "Zenithium/Engines/CorrelationEngine.swift",
}


def check_decimal_separator(files: list[Path]) -> list[str]:
    problems = []
    for file in files:
        relative = str(file.relative_to(ROOT))
        if relative in DECIMAL_FORMAT_ALLOWED:
            continue
        source = strip_comments(file.read_text(encoding="utf-8"))
        for match in DECIMAL_FORMAT.finditer(source):
            line = source[: match.start()].count("\n") + 1
            problems.append(
                f"{relative}:{line}: ondalık nokta üretiyor — "
                f"ZenithiumFormat.metric/strain kullan"
            )
    return problems

DECLARATION = re.compile(
    r"^([ \t]*)(?:@\w+(?:\([^)]*\))?\s+)*"
    r"(?P<access>public\s+|internal\s+|private\s+|fileprivate\s+|open\s+)?"
    r"(?:final\s+)?(?:indirect\s+)?"
    r"(enum|struct|class|actor|protocol|typealias)\s+([A-Za-z_]\w*)",
    re.M,
)
# Generic parameters look like type references but are declared inline.
GENERIC_PARAMS = re.compile(
    r"(?:func|struct|enum|class|actor)\s+\w+\s*<([^<>]*(?:<[^<>]*>[^<>]*)*)>"
)
GLOBAL_FUNC = re.compile(r"^(?:public\s+|internal\s+)?func\s+([a-z]\w*)", re.M)
EXTENSION = re.compile(r"^\s*extension\s+([A-Za-z_]\w*)", re.M)


def strip_noise(source: str) -> str:
    """Remove comments and string literals, so their contents are not read as code."""
    source = re.sub(r"/\*.*?\*/", " ", source, flags=re.S)
    source = re.sub(r"//.*?$", " ", source, flags=re.M)
    source = re.sub(r'"""[\s\S]*?"""', '""', source)
    source = re.sub(r'"(?:\\.|[^"\\])*"', '""', source)
    return source


def strip_comments(source: str) -> str:
    """Remove comments but keep string literals.

    `strip_noise` blanks every literal, which is right for reading code and wrong for reading
    copy. The accessibility-language check was written against `strip_noise` and therefore
    scanned a source with no strings in it at all — it reported clean for two runs while a
    dozen English labels sat in the files.
    """
    source = re.sub(r"/\*.*?\*/", " ", source, flags=re.S)
    return re.sub(r"^\s*//.*?$", " ", source, flags=re.M)


def strip_for_references(source: str) -> str:
    """Also drop the things that look like type references but are not.

    Import lines name modules, not types. Attributes name macros. And anything after a dot is
    a member of something already accounted for — `HKError.Code` is one reference, not two.
    """
    source = strip_noise(source)
    source = re.sub(r"^\s*(?:@testable\s+)?import\s+[\w.]+.*$", " ", source, flags=re.M)
    # `#if canImport(ActivityKit)` names a module, not a type.
    source = re.sub(r"canImport\(\s*\w+\s*\)", " ", source)
    source = re.sub(r"@\w+", " ", source)
    return source


def target_sources(target: str) -> list[Path]:
    """The Swift files one target compiles, from project.yml."""
    lines = PROJECT_YML.read_text(encoding="utf-8").splitlines()
    inside = in_sources = False
    paths: list[str] = []
    excludes: list[str] = []
    for line in lines:
        if re.match(rf"^  {re.escape(target)}:\s*$", line):
            inside = True
            continue
        if inside and re.match(r"^  \S", line):
            break
        if inside and re.match(r"^    sources:\s*$", line):
            in_sources = True
            continue
        if in_sources:
            if match := re.match(r"^      - path:\s*(\S+)", line):
                paths.append(match.group(1))
            elif match := re.match(r'^\s+- "([^"]+)"', line):
                excludes.append(match.group(1))
            elif re.match(r"^    \S", line):
                in_sources = False

    files: list[Path] = []
    for path in paths:
        candidate = ROOT / path
        if candidate.is_dir():
            files.extend(sorted(candidate.rglob("*.swift")))
        elif candidate.suffix == ".swift":
            files.append(candidate)
    return [f for f in files if f.name not in excludes]


TOP_LEVEL: dict[str, list[Path]] = {}
GENERIC_NAMES: set[str] = set()


def declared_names(files: list[Path]) -> tuple[dict[str, list[Path]], set[str]]:
    """Type names declared in these files, and global function names."""
    top_level = TOP_LEVEL
    top_level.clear()
    types: dict[str, list[Path]] = {}
    functions: set[str] = set()
    generics = GENERIC_NAMES
    generics.clear()
    for file in files:
        source = strip_noise(file.read_text(encoding="utf-8"))
        for match in DECLARATION.finditer(source):
            name = match.group(4)
            types.setdefault(name, []).append(file)
            # Only a declaration with no indentation is top level. A nested one is scoped to
            # its parent, so two files may both declare a `Content` without colliding.
            access = (match.group("access") or "").strip()
            if match.group(1) == "" and access not in {"private", "fileprivate"}:
                top_level.setdefault(name, []).append(file)
        functions.update(GLOBAL_FUNC.findall(source))
        # Generic parameter names are declarations too, in the scope that introduces them.
        for group in GENERIC_PARAMS.findall(source):
            for part in group.split(","):
                bare = part.split(":")[0].strip()
                if re.fullmatch(r"[A-Z]\w*", bare):
                    generics.add(bare)
    return types, functions


def referenced_names(files: list[Path]) -> dict[str, set[Path]]:
    """Capitalised identifiers used in these files."""
    used: dict[str, set[Path]] = {}
    for file in files:
        source = strip_for_references(file.read_text(encoding="utf-8"))
        # Drop the declaration keywords themselves so a name is not "used" by its own
        # declaration line.
        source = DECLARATION.sub(" ", source)
        # `(?<![.\w])` drops members: `AsyncStream.Continuation` is a use of `AsyncStream`.
        for name in re.findall(r"(?<![.\w])([A-Z][A-Za-z0-9_]*)\b", source):
            used.setdefault(name, set()).add(file)
    return used


def check_balance(files: list[Path]) -> list[str]:
    problems = []
    for file in files:
        source = strip_noise(file.read_text(encoding="utf-8"))
        for open_char, close_char, label in (("{", "}", "brace"), ("(", ")", "paren"), ("[", "]", "bracket")):
            delta = source.count(open_char) - source.count(close_char)
            if delta:
                problems.append(f"{file.relative_to(ROOT)}: {label} dengesiz ({delta:+d})")
    return problems


# Words that only appear in an accessibility string if a translation was skipped.
#
# The app is Turkish. Its visible labels were translated and its spoken ones were not: a whole
# `TrainingLens.accessibilityName` table plus roughly thirty labels and values across the app,
# the widget and the watch shipped in English through to v0.1's release scan. Nothing caught
# it because nothing looks at accessibility copy — the screens read correctly and only a
# Turkish-speaking VoiceOver user would have heard "Heart rate variability" or "out of 100".
#
# The list is English function words and the unit names these strings actually reach for. It
# is deliberately not a full dictionary: the failure is a whole English phrase left in place,
# and no such phrase avoids all of these. Interpolations are stripped before matching, so a
# Swift identifier inside `\(...)` never trips it.
#
# `ZenithiumTests/AccessibilityCopyTests.swift` covers what the test target compiles. This is
# the pass that reaches the two extensions, which it does not.
ACCESSIBILITY_ENGLISH = {
    # function words
    "of", "the", "your", "out", "from", "than", "per", "over", "and", "with", "still",
    # units and quantities
    "percent", "beats", "breaths", "minute", "hours", "milliseconds", "degrees", "nights",
    # vocabulary these strings reached for
    "heart", "rate", "reserve", "resting", "variability", "readiness", "ready", "asleep",
    "night", "day", "baseline", "collected", "calibrating", "confidence", "weighted",
    "slower", "reference", "pace", "penalty", "splits", "round", "session",
    "station", "transition", "running", "muscular", "cardiovascular", "compromised",
    "recovery", "strain", "score", "band", "workload", "posterior", "chain", "grip",
    # Not "total": `Total kolesterol` and `Total testosteron` are how Turkish laboratory
    # reports print those markers, and the catalogue matches what a report says.
    "weekly", "volume", "push", "pull", "balance", "sleep", "consistency", "daylight",
    "walking", "speed", "time", "best", "training", "hour",
}

ACCESSIBILITY_CALL = re.compile(
    r'accessibility(?:Label|Value|Hint|Name)\w*\s*[:(]\s*"((?:[^"\\]|\\.)*)"'
)

# `\(...)` interpolations carry Swift identifiers, not copy.
INTERPOLATION = re.compile(r"\\\([^)]*\)")


# Visible copy, checked the same way and for the same reason.
#
# The accessibility sweep turned up eight whole English sentences on screen — "The curve is
# flattened today because recovery is low", "couldn't be measured last night", "of today had
# no heart data" — in an app whose every other string is Turkish. They survived because they
# are conditional: they only render on a low-recovery day, a night with a missing sensor, a
# day with a gap in heart data. Nobody had been looking at the screen on one of those days.
#
# Two English words in one literal, rather than one, so a Turkish sentence quoting a unit or
# a proper noun does not trip it.
VISIBLE_ENGLISH = ACCESSIBILITY_ENGLISH | {
    "for", "this", "that", "are", "was", "were", "have", "has", "will", "can", "not", "you",
    "muscle", "group", "week", "load", "level", "zone", "last", "next", "first", "average",
    "based", "between", "during", "after", "before", "when", "where", "which", "more",
    "less", "most", "least", "high", "low", "good", "new", "old", "seconds", "minutes",
}

# An SF Symbol name, a bundle identifier or a UserDefaults key is not copy.
SYMBOLIC_LITERAL = re.compile(r"^[a-z0-9._]+$")
STRING_LITERAL = re.compile(r'"((?:[^"\\\n]|\\.){4,})"')


def check_visible_language(files: list[Path]) -> list[str]:
    problems = []
    for file in files:
        if "/Views/" not in str(file) and not str(file).startswith(("ZenithiumWatch", "ZenithiumWidgets")):
            continue
        source = strip_comments(file.read_text(encoding="utf-8"))
        for match in STRING_LITERAL.finditer(source):
            raw = match.group(1)
            if SYMBOLIC_LITERAL.match(raw):
                continue
            literal = INTERPOLATION.sub(" ", raw)
            words = {w.lower() for w in re.findall(r"[A-Za-zçğıöşüÇĞİÖŞÜâîû]+", literal)}
            english = sorted(words & VISIBLE_ENGLISH)
            if len(english) >= 2:
                line = source[: match.start()].count("\n") + 1
                problems.append(
                    f"{file.relative_to(ROOT)}:{line}: görünen metin İngilizce — "
                    f"{', '.join(repr(w) for w in english)}"
                )
    return problems


def check_accessibility_language(files: list[Path]) -> list[str]:
    problems = []
    for file in files:
        source = strip_comments(file.read_text(encoding="utf-8"))
        for match in ACCESSIBILITY_CALL.finditer(source):
            literal = INTERPOLATION.sub(" ", match.group(1))
            # Turkish letters are part of a word. Tokenizing on ASCII alone split `bandı`
            # into `band` and reported the app's own Turkish as English.
            words = {w.lower() for w in re.findall(r"[A-Za-zçğıöşüÇĞİÖŞÜâîû]+", literal)}
            english = sorted(words & ACCESSIBILITY_ENGLISH)
            if english:
                line = source[: match.start()].count("\n") + 1
                problems.append(
                    f"{file.relative_to(ROOT)}:{line}: erişilebilirlik metni İngilizce — "
                    f"{', '.join(repr(w) for w in english)}"
                )
    return problems


def check_banned(files: list[Path]) -> list[str]:
    problems = []
    for file in files:
        source = strip_noise(file.read_text(encoding="utf-8"))
        for pattern, label in BANNED:
            for match in re.finditer(pattern, source, re.M):
                line = source[: match.start()].count("\n") + 1
                problems.append(f"{file.relative_to(ROOT)}:{line}: yasaklı — {label}")
    return problems



# ---------------------------------------------------------------------------
# Argument labels
# ---------------------------------------------------------------------------
#
# The check above answers "does this name exist". This one answers the next question a
# compiler asks and a reader does not: "does this call name arguments the type actually has".
# It is deliberately conservative — it flags a label only when the type has no initialiser
# parameter and no stored property by that name, which is the shape a rename or a guessed API
# produces. Overloads, defaults and ordering are all left alone, because getting those wrong
# needs a type checker and getting *this* wrong only needs a memory.

INIT_SIGNATURE = re.compile(r"\binit\s*(?:\?|!)?\s*\(([^)]*)\)", re.S)
STORED_PROPERTY = re.compile(
    r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*"
    r"(?:public\s+|private\s+|internal\s+|fileprivate\s+)?(?:private\(set\)\s+|internal\(set\)\s+)?"
    r"(?:static\s+|weak\s+|lazy\s+)*(?:let|var)\s+(\w+)\s*[:=]",
    re.M,
)
LABEL = re.compile(r"^\s*(\w+)\s*:")
CALL_HEAD = re.compile(r"(?<![.\w])([A-Z]\w*)\s*\(")


def top_level_arguments(source: str, open_index: int) -> tuple[list[str], int] | None:
    """Split one call's arguments at depth zero.

    A regex cannot do this: `Foo(bar: Baz(qux: 1))` has `qux` nested inside `bar`, and a
    pattern that merely allows one level of parentheses attributes `qux` to `Foo`. That was
    the whole noise floor of the first version of this check — nearly every finding was an
    inner label blamed on an outer type.
    """
    depth = 0
    start = open_index + 1
    parts: list[str] = []
    index = open_index
    while index < len(source):
        character = source[index]
        if character in "([{":
            depth += 1
        elif character in ")]}":
            depth -= 1
            if depth == 0:
                parts.append(source[start:index])
                return parts, index
        elif character == "," and depth == 1:
            parts.append(source[start:index])
            start = index + 1
        index += 1
    return None


LABEL = re.compile(r"^\s*(\w+)\s*:")
CALL_HEAD = re.compile(r"(?<![.\w])([A-Z]\w*)\s*\(")


def top_level_arguments(source: str, open_index: int) -> tuple[list[str], int] | None:
    """Split one call's arguments at depth zero.

    A regex cannot do this: `Foo(bar: Baz(qux: 1))` has `qux` nested inside `bar`, and a
    pattern that merely allows one level of parentheses attributes `qux` to `Foo`. That was
    the entire noise floor of this check's first version — nearly every finding was an inner
    label blamed on an outer type.
    """
    depth = 0
    start = open_index + 1
    parts: list[str] = []
    index = open_index
    while index < len(source):
        character = source[index]
        if character in "([{":
            depth += 1
        elif character in ")]}":
            depth -= 1
            if depth == 0:
                parts.append(source[start:index])
                return parts, index
        elif character == "," and depth == 1:
            parts.append(source[start:index])
            start = index + 1
        index += 1
    return None


def type_bodies(files: list[Path]) -> dict[str, str]:
    """Each project type's source text, keyed by name.

    Brace-counted from the declaration, which is crude but sufficient: these files are
    consistently formatted and the only thing being extracted is a set of names.
    """
    bodies: dict[str, str] = {}
    for file in files:
        source = strip_noise(file.read_text(encoding="utf-8"))
        for match in DECLARATION.finditer(source):
            if match.group(3) not in {"struct", "class", "actor", "enum"}:
                continue
            name = match.group(4)
            start = source.find("{", match.end())
            if start < 0:
                continue
            depth, index = 0, start
            while index < len(source):
                if source[index] == "{":
                    depth += 1
                elif source[index] == "}":
                    depth -= 1
                    if depth == 0:
                        break
                index += 1
            bodies[name] = bodies.get(name, "") + source[start:index]
    return bodies


def known_labels(bodies: dict[str, str]) -> dict[str, set[str]]:
    labels: dict[str, set[str]] = {}
    for name, body in bodies.items():
        names: set[str] = set(STORED_PROPERTY.findall(body))
        for signature in INIT_SIGNATURE.findall(body):
            for parameter in signature.split(","):
                head = parameter.split(":")[0].strip()
                for part in head.split():
                    if re.fullmatch(r"\w+", part) and part != "_":
                        names.add(part)
        # A `RawRepresentable` enum gets `init?(rawValue:)` for free, and no declaration in
        # the body says so. `@ModelActor` likewise synthesises `init(modelContainer:)`.
        names.add("rawValue")
        names.add("modelContainer")
        labels[name] = names
    return labels


def check_labels(files: list[Path], labels: dict[str, set[str]]) -> list[str]:
    problems = []
    for file in files:
        source = strip_for_references(file.read_text(encoding="utf-8"))
        for match in CALL_HEAD.finditer(source):
            name = match.group(1)
            known = labels.get(name)
            if known is None:
                continue
            split = top_level_arguments(source, match.end() - 1)
            if split is None:
                continue
            for part in split[0]:
                label_match = LABEL.match(part)
                if label_match is None:
                    continue
                label = label_match.group(1)
                if label in known:
                    continue
                line = source[: match.start()].count("\n") + 1
                problems.append(
                    f"{file.relative_to(ROOT)}:{line}: {name}(… {label}: …) — böyle bir parametre yok"
                )
    return problems


TARGETS = ["Zenithium", "ZenithiumWidgets", "ZenithiumWatch"]


def main() -> int:
    failures = 0

    # Tests compile against the app target plus their own files.
    app_files = target_sources("Zenithium")
    test_files = sorted((ROOT / "ZenithiumTests").rglob("*.swift"))

    for target in TARGETS + ["ZenithiumTests"]:
        if target == "ZenithiumTests":
            files = app_files + test_files
            own = test_files
        else:
            files = target_sources(target)
            own = files

        types, functions = declared_names(files)
        known = set(types) | FRAMEWORK_SYMBOLS | IGNORED_TOKENS | functions | GENERIC_NAMES

        unresolved: dict[str, set[Path]] = {}
        for name, users in referenced_names(own).items():
            if name in known:
                continue
            unresolved[name] = users

        duplicates = {
            name: paths for name, paths in TOP_LEVEL.items()
            if len({p for p in paths}) > 1
        }

        print(f"\n=== {target} — {len(files)} dosya, {len(types)} tip ===")
        if unresolved:
            failures += len(unresolved)
            for name, users in sorted(unresolved.items()):
                where = ", ".join(sorted(str(p.relative_to(ROOT)) for p in list(users)[:3]))
                print(f"  ÇÖZÜLEMEDİ  {name:<34} {where}")
        else:
            print("  OK   her tip referansı hedefin içinde çözülüyor")

        if duplicates:
            failures += len(duplicates)
            for name, paths in sorted(duplicates.items()):
                where = ", ".join(sorted(str(p.relative_to(ROOT)) for p in paths))
                print(f"  ÇİFT TANIM  {name}: {where}")

    print("\n=== argüman etiketleri ===")
    every_file = sorted(set(app_files) | set(test_files)
                        | set(target_sources("ZenithiumWatch"))
                        | set(target_sources("ZenithiumWidgets")))
    labels = known_labels(type_bodies(every_file))
    label_problems = check_labels(every_file, labels)
    for problem in label_problems:
        failures += 1
        print(f"  {problem}")
    if not label_problems:
        print("  OK   her adlandırılmış argüman tipinde mevcut")

    print("\n=== yasaklı yapılar ve denge ===")
    all_files = sorted(set(app_files) | set(test_files)
                       | set(target_sources("ZenithiumWatch"))
                       | set(target_sources("ZenithiumWidgets")))
    for problem in check_banned(all_files) + check_balance(all_files) + check_decimal_separator(all_files):
        failures += 1
        print(f"  {problem}")
    if failures == 0:
        print("  OK   temiz")

    print("\n=== arayüz metni dili ===")
    language_problems = check_accessibility_language(all_files) + check_visible_language(all_files)
    for problem in language_problems:
        failures += 1
        print(f"  {problem}")
    if not language_problems:
        print("  OK   sesli ve görünen metinlerin hepsi Türkçe")

    print(f"\ntoplam sorun: {failures}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
