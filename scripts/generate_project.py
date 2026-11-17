#!/usr/bin/env python3
"""Regenerate the dependency-free Xcode project using only Python's standard library."""
from pathlib import Path
import hashlib
import plistlib

ROOT = Path(__file__).resolve().parents[1]

def uid(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()

def write_plist(path, data):
    with (ROOT / path).open("wb") as handle:
        plistlib.dump(data, handle)

common_info = {
    "CFBundleDevelopmentRegion": "en",
    "CFBundleExecutable": "$(EXECUTABLE_NAME)",
    "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
    "CFBundleInfoDictionaryVersion": "6.0",
    "CFBundleName": "$(PRODUCT_NAME)",
    "CFBundleDisplayName": "ShotSkiff",
    "CFBundlePackageType": "APPL",
    "CFBundleShortVersionString": "$(MARKETING_VERSION)",
    "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
    "NSLocalNetworkUsageDescription": "ShotSkiff connects to your saved device and transfers the photos you take directly to your Mac.",
    "NSBonjourServices": ["_snapbridge-v1._tcp", "_snapbridge-v1._udp"],
}
write_plist("Resources/Mac-Info.plist", dict(common_info, **{
    "LSUIElement": True,
    "LSMinimumSystemVersion": "$(MACOSX_DEPLOYMENT_TARGET)",
    "LSApplicationCategoryType": "public.app-category.photography",
    "NSPrincipalClass": "NSApplication",
    "CFBundleIconFile": "SnapBridgeIcon",
    "NSHighResolutionCapable": True,
}))
write_plist("Resources/iPhone-Info.plist", dict(common_info, **{
    "LSRequiresIPhoneOS": True,
    "NSCameraUsageDescription": "Take a photo and send it straight to your paired Mac, ready to paste into a chat.",
    "NSPhotoLibraryUsageDescription": "ShotSkiff reads the latest screenshot only when its screenshot automation runs, then sends it to your paired Mac.",
    "UILaunchScreen": {},
    "UISupportedInterfaceOrientations": ["UIInterfaceOrientationPortrait", "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"],
    "UIApplicationSceneManifest": {"UIApplicationSupportsMultipleScenes": False},
}))

objects = []
def obj(key, value):
    objects.append(f"\t\t{uid(key)} = {{ {value} }};")
    return uid(key)

shared = ["Shared/WireProtocol.swift", "Shared/KeychainStore.swift", "Shared/NearbyTransport.swift", "Shared/PhotoProcessing.swift", "Shared/PerformanceTrace.swift", "Shared/FastPhotoChannel.swift"]
mac = ["Mac/SnapBridgeMac.swift", "Mac/PhoneScreenshots.swift", "Mac/ScreenshotImportSetup.swift", "Shared/PhotoStore.swift", "Mac/PhotoClipboard.swift", "Shared/PhotoBatch.swift"]
phone = ["iPhone/SnapBridgePhone.swift", "iPhone/CameraController.swift", "iPhone/PhoneModel.swift", "iPhone/ScreenshotShortcut.swift"]
files = shared + mac + phone + ["Resources/Mac-Info.plist", "Resources/iPhone-Info.plist",
                               "Resources/SnapBridgeIcon.icns", "Resources/Assets.xcassets", "Resources/Signing.xcconfig", "scripts/watch_screenshots.py"]
for path in files:
    kind = "sourcecode.swift" if path.endswith(".swift") else "text.script.python" if path.endswith(".py") else "text.plist.xml" if path.endswith(".plist") else "folder.assetcatalog" if path.endswith(".xcassets") else "text.xcconfig" if path.endswith(".xcconfig") else "image.icns"
    obj(path, f'isa = PBXFileReference; lastKnownFileType = {kind}; path = "{path}"; sourceTree = "<group>";')

targets = [("SnapBridgeMac", "SnapBridge", shared + mac, ["Resources/SnapBridgeIcon.icns", "scripts/watch_screenshots.py"], "macosx"),
           ("SnapBridgePhone", "SnapBridgeCamera", shared + phone, ["Resources/Assets.xcassets"], "iphoneos")]
for target, product, sources, resources, sdk in targets:
    obj(target + "Product", f'isa = PBXFileReference; explicitFileType = wrapper.application; path = "{product}.app"; sourceTree = BUILT_PRODUCTS_DIR;')
    for path in sources + resources:
        obj(target + path, f"isa = PBXBuildFile; fileRef = {uid(path)};")
    obj(target + "Sources", "isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (" + ",".join(uid(target + p) for p in sources) + "); runOnlyForDeploymentPostprocessing = 0;")
    obj(target + "Resources", "isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (" + ",".join(uid(target + p) for p in resources) + "); runOnlyForDeploymentPostprocessing = 0;")
    obj(target + "Frameworks", "isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;")
    for config in ["Debug", "Release"]:
        settings = {
            "PRODUCT_NAME": product,
            "PRODUCT_BUNDLE_IDENTIFIER": "$(SNAPBRIDGE_BUNDLE_PREFIX).snapbridge.mac" if sdk == "macosx" else "$(SNAPBRIDGE_BUNDLE_PREFIX).snapbridge.camera",
            "INFOPLIST_FILE": "Resources/Mac-Info.plist" if sdk == "macosx" else "Resources/iPhone-Info.plist",
            "SDKROOT": sdk,
            "SUPPORTED_PLATFORMS": "macosx" if sdk == "macosx" else "iphoneos iphonesimulator",
            "CODE_SIGN_STYLE": "Automatic",
            "SWIFT_VERSION": "5.0",
            "SWIFT_STRICT_CONCURRENCY": "minimal",
            "CURRENT_PROJECT_VERSION": "8" if sdk == "macosx" else "7",
            "MARKETING_VERSION": "0.1.0",
            "ENABLE_APP_SANDBOX": "NO",
            "ENABLE_HARDENED_RUNTIME": "YES" if sdk == "macosx" else "NO",
            "SWIFT_OPTIMIZATION_LEVEL": "-Onone" if config == "Debug" else "-O",
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG" if config == "Debug" else "",
        }
        if sdk == "macosx":
            settings.update({"MACOSX_DEPLOYMENT_TARGET": "14.0", "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/../Frameworks"})
        else:
            settings.update({"IPHONEOS_DEPLOYMENT_TARGET": "17.0", "TARGETED_DEVICE_FAMILY": "1", "SUPPORTS_MACCATALYST": "NO", "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon", "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks"})
        values = " ".join(f'{k} = "{v}";' for k, v in settings.items())
        obj(target + config, f'isa = XCBuildConfiguration; baseConfigurationReference = {uid("Resources/Signing.xcconfig")}; buildSettings = {{ {values} }}; name = {config};')
    obj(target + "Config", f'isa = XCConfigurationList; buildConfigurations = ({uid(target + "Debug")},{uid(target + "Release")}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
    obj(target, f'isa = PBXNativeTarget; buildConfigurationList = {uid(target + "Config")}; buildPhases = ({uid(target + "Sources")},{uid(target + "Frameworks")},{uid(target + "Resources")}); buildRules = (); dependencies = (); name = {target}; productName = {product}; productReference = {uid(target + "Product")}; productType = "com.apple.product-type.application";')

obj("Products", "isa = PBXGroup; children = (" + ",".join(uid(t[0] + "Product") for t in targets) + '); name = Products; sourceTree = "<group>";')
obj("Root", "isa = PBXGroup; children = (" + ",".join(uid(p) for p in files) + f',{uid("Products")}); sourceTree = "<group>";')
for config in ["Debug", "Release"]:
    obj("Project" + config, f'isa = XCBuildConfiguration; buildSettings = {{ CLANG_ENABLE_MODULES = YES; CLANG_ENABLE_OBJC_ARC = YES; ENABLE_USER_SCRIPT_SANDBOXING = YES; }}; name = {config};')
obj("ProjectConfig", f'isa = XCConfigurationList; buildConfigurations = ({uid("ProjectDebug")},{uid("ProjectRelease")}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
obj("Project", f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 1600; }}; buildConfigurationList = {uid("ProjectConfig")}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); mainGroup = {uid("Root")}; productRefGroup = {uid("Products")}; projectDirPath = ""; projectRoot = ""; targets = ({",".join(uid(t[0]) for t in targets)});')
(ROOT / "SnapBridge.xcodeproj/project.pbxproj").write_text("// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n" + "\n".join(objects) + f'\n}}; rootObject = {uid("Project")}; }}\n')

for target, product, *_ in targets:
    (ROOT / f"SnapBridge.xcodeproj/xcshareddata/xcschemes/{target}.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid(target)}" BuildableName="{product}.app" BlueprintName="{target}" ReferencedContainer="container:SnapBridge.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
 <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"/>
 <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid(target)}" BuildableName="{product}.app" BlueprintName="{target}" ReferencedContainer="container:SnapBridge.xcodeproj"/></BuildableProductRunnable></LaunchAction>
 <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid(target)}" BuildableName="{product}.app" BlueprintName="{target}" ReferencedContainer="container:SnapBridge.xcodeproj"/></BuildableProductRunnable></ProfileAction>
 <AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')
print("Generated Mac and iPhone targets.")
