#!/usr/bin/env python3
"""Text-first Xcode project for Meine. File-system synchronized (Xcode 16+)."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROJ = ROOT / "Meine.xcodeproj"
SCHEME = PROJ / "xcshareddata" / "xcschemes"

def hid(n):
    return f"M{n:023X}"

PROJECT, TARGET, APP_SYNC, TEST_SYNC, SOURCES, RESOURCES, FRAMEWORKS = (hid(i) for i in range(1, 8))
PRODUCT, TEST_PRODUCT, G_ROOT, G_PROD = (hid(i) for i in range(8, 12))
CL_PROJ, CL_TGT, CL_TEST = hid(12), hid(13), hid(14)
CFG_PD, CFG_PR, CFG_TD, CFG_TR, CFG_TED, CFG_TER = (hid(i) for i in range(15, 21))
TEST_TARGET, TEST_DEP, TEST_PROXY, EXCEPTIONS = hid(21), hid(22), hid(23), hid(24)

APP_EXC = """
				exceptions = (
					{EXCEPTIONS} /* Exceptions for "Meine" folder in "Synchronize Root Group" */,
				);
""".replace("{EXCEPTIONS}", EXCEPTIONS)

pbx = f"""// !$*UTF8*$!
{{
	archiveVersion = 1;
	classes = {{
	}};
	objectVersion = 70;
	objects = {{

/* Begin PBXContainerItemProxy section */
		{TEST_PROXY} /* PBXContainerItemProxy */ = {{
			isa = PBXContainerItemProxy;
			containerPortal = {PROJECT} /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = {TARGET};
			remoteInfo = Meine;
		}};
/* End PBXContainerItemProxy section */

/* Begin PBXFileSystemSynchronizedBuildFileExceptionSet section */
		{EXCEPTIONS} /* Exceptions for "Meine" folder in "Synchronize Root Group" */ = {{
			isa = PBXFileSystemSynchronizedBuildFileExceptionSet;
			membershipExceptions = (
				Info.plist,
				PrivacyInfo.xcprivacy,
			);
			target = {TARGET} /* Meine */;
		}};
/* End PBXFileSystemSynchronizedBuildFileExceptionSet section */

/* Begin PBXFileSystemSynchronizedRootGroup section */
		{APP_SYNC} /* Meine */ = {{
			isa = PBXFileSystemSynchronizedRootGroup;
			exceptions = (
				{EXCEPTIONS} /* Exceptions for "Meine" folder in "Synchronize Root Group" */,
			);
			path = Meine;
			sourceTree = "<group>";
		}};
		{TEST_SYNC} /* MeineTests */ = {{
			isa = PBXFileSystemSynchronizedRootGroup;
			path = MeineTests;
			sourceTree = "<group>";
		}};
/* End PBXFileSystemSynchronizedRootGroup section */

/* Begin PBXFileReference section */
		{PRODUCT} /* Meine.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Meine.app; sourceTree = BUILT_PRODUCTS_DIR; }};
		{TEST_PRODUCT} /* MeineTests.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = MeineTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
		{FRAMEWORKS} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		{G_ROOT} = {{
			isa = PBXGroup;
			children = (
				{APP_SYNC} /* Meine */,
				{TEST_SYNC} /* MeineTests */,
				{G_PROD} /* Products */,
			);
			sourceTree = "<group>";
		}};
		{G_PROD} /* Products */ = {{
			isa = PBXGroup;
			children = (
				{PRODUCT} /* Meine.app */,
				{TEST_PRODUCT} /* MeineTests.xctest */,
			);
			name = Products;
			sourceTree = "<group>";
		}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		{TARGET} /* Meine */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {CL_TGT} /* Build configuration list for PBXNativeTarget "Meine" */;
			buildPhases = (
				{SOURCES} /* Sources */,
				{FRAMEWORKS} /* Frameworks */,
				{RESOURCES} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			fileSystemSynchronizedGroups = (
				{APP_SYNC} /* Meine */,
			);
			name = Meine;
			packageProductDependencies = (
			);
			productName = Meine;
			productReference = {PRODUCT} /* Meine.app */;
			productType = "com.apple.product-type.application";
		}};
		{TEST_TARGET} /* MeineTests */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {CL_TEST} /* Build configuration list for PBXNativeTarget "MeineTests" */;
			buildPhases = (
				{hid(25)} /* Sources */,
				{hid(26)} /* Frameworks */,
				{hid(27)} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
				{TEST_DEP} /* PBXTargetDependency */,
			);
			fileSystemSynchronizedGroups = (
				{TEST_SYNC} /* MeineTests */,
			);
			name = MeineTests;
			packageProductDependencies = (
			);
			productName = MeineTests;
			productReference = {TEST_PRODUCT} /* MeineTests.xctest */;
			productType = "com.apple.product-type.bundle.unit-test";
		}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		{PROJECT} /* Project object */ = {{
			isa = PBXProject;
			attributes = {{
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 1600;
				LastUpgradeCheck = 1600;
				TargetAttributes = {{
					{TARGET} = {{
						CreatedOnToolsVersion = 16.0;
					}};
					{TEST_TARGET} = {{
						CreatedOnToolsVersion = 16.0;
						TestTargetID = {TARGET};
					}};
				}};
			}};
			buildConfigurationList = {CL_PROJ} /* Build configuration list for PBXProject "Meine" */;
			compatibilityVersion = "Xcode 14.0";
			developmentRegion = vi;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
				vi,
			);
			mainGroup = {G_ROOT};
			productRefGroup = {G_PROD} /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				{TARGET} /* Meine */,
				{TEST_TARGET} /* MeineTests */,
			);
		}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		{RESOURCES} /* Resources */ = {{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{hid(27)} /* Resources */ = {{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		{SOURCES} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{hid(25)} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXSourcesBuildPhase section */

/* Begin PBXTargetDependency section */
		{TEST_DEP} /* PBXTargetDependency */ = {{
			isa = PBXTargetDependency;
			target = {TARGET} /* Meine */;
			targetProxy = {TEST_PROXY} /* PBXContainerItemProxy */;
		}};
/* End PBXTargetDependency section */

/* Begin PBXFrameworksBuildPhase test */
		{hid(26)} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End extra */

/* Begin XCBuildConfiguration section */
		{CFG_PD} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_TESTABILITY = YES;
				ENABLE_USER_SCRIPT_SANDBOXING = NO;
				GCC_DYNAMIC_NO_PIC = NO;
				GCC_OPTIMIZATION_LEVEL = 0;
				IPHONEOS_DEPLOYMENT_TARGET = 18.0;
				ONLY_ACTIVE_ARCH = YES;
				SDKROOT = iphoneos;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
				SWIFT_VERSION = 5.0;
			}};
			name = Debug;
		}};
		{CFG_PR} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
				ENABLE_USER_SCRIPT_SANDBOXING = NO;
				IPHONEOS_DEPLOYMENT_TARGET = 18.0;
				SDKROOT = iphoneos;
				SWIFT_COMPILATION_MODE = wholemodule;
				SWIFT_VERSION = 5.0;
				VALIDATE_PRODUCT = YES;
			}};
			name = Release;
		}};
		{CFG_TD} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = NO;
				ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOLS = NO;
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				CODE_SIGNING_ALLOWED = NO;
				CODE_SIGNING_REQUIRED = NO;
				CODE_SIGN_IDENTITY = "";
				CODE_SIGN_STYLE = Manual;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_TEAM = "";
				ENABLE_PREVIEWS = NO;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = Meine/Info.plist;
				INFOPLIST_KEY_CFBundleDisplayName = Meine;
				INFOPLIST_KEY_LSSupportsOpeningDocumentsInPlace = YES;
				INFOPLIST_KEY_NSCameraUsageDescription = "Meine dùng camera để đọc mã QR nguồn do bạn đưa.";
				INFOPLIST_KEY_NSFaceIDUsageDescription = "Meine dùng Face ID để mở nguồn đã khóa trên máy này.";
				INFOPLIST_KEY_NSLocalNetworkUsageDescription = "Meine kết nối máy TTS trong mạng cục bộ khi bạn tự nhập địa chỉ.";
				INFOPLIST_KEY_NSPhotoLibraryAddUsageDescription = "Meine lưu thẻ lời bài hát vào Ảnh khi bạn chia sẻ.";
				INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
				INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;
				INFOPLIST_KEY_UIBackgroundModes = "audio";
				INFOPLIST_KEY_UILaunchScreen_Generation = YES;
				INFOPLIST_KEY_UISupportedInterfaceOrientations = "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
				INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = app.meine.ios;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
				SUPPORTS_MACCATALYST = NO;
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
			}};
			name = Debug;
		}};
		{CFG_TR} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = NO;
				ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOLS = NO;
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				CODE_SIGNING_ALLOWED = NO;
				CODE_SIGNING_REQUIRED = NO;
				CODE_SIGN_IDENTITY = "";
				CODE_SIGN_STYLE = Manual;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_TEAM = "";
				ENABLE_PREVIEWS = NO;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = Meine/Info.plist;
				INFOPLIST_KEY_CFBundleDisplayName = Meine;
				INFOPLIST_KEY_LSSupportsOpeningDocumentsInPlace = YES;
				INFOPLIST_KEY_NSCameraUsageDescription = "Meine dùng camera để đọc mã QR nguồn do bạn đưa.";
				INFOPLIST_KEY_NSFaceIDUsageDescription = "Meine dùng Face ID để mở nguồn đã khóa trên máy này.";
				INFOPLIST_KEY_NSLocalNetworkUsageDescription = "Meine kết nối máy TTS trong mạng cục bộ khi bạn tự nhập địa chỉ.";
				INFOPLIST_KEY_NSPhotoLibraryAddUsageDescription = "Meine lưu thẻ lời bài hát vào Ảnh khi bạn chia sẻ.";
				INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
				INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;
				INFOPLIST_KEY_UIBackgroundModes = "audio";
				INFOPLIST_KEY_UILaunchScreen_Generation = YES;
				INFOPLIST_KEY_UISupportedInterfaceOrientations = "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
				INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = app.meine.ios;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
				SUPPORTS_MACCATALYST = NO;
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
			}};
			name = Release;
		}};
		{CFG_TED} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				BUNDLE_LOADER = "$(TEST_HOST)";
				CODE_SIGNING_ALLOWED = NO;
				CODE_SIGNING_REQUIRED = NO;
				CODE_SIGN_STYLE = Manual;
				DEVELOPMENT_TEAM = "";
				GENERATE_INFOPLIST_FILE = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 18.0;
				PRODUCT_BUNDLE_IDENTIFIER = app.meine.ios.tests;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SDKROOT = iphoneos;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
				TEST_HOST = "$(BUILT_PRODUCTS_DIR)/Meine.app/Meine";
			}};
			name = Debug;
		}};
		{CFG_TER} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				BUNDLE_LOADER = "$(TEST_HOST)";
				CODE_SIGNING_ALLOWED = NO;
				CODE_SIGNING_REQUIRED = NO;
				CODE_SIGN_STYLE = Manual;
				DEVELOPMENT_TEAM = "";
				GENERATE_INFOPLIST_FILE = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 18.0;
				PRODUCT_BUNDLE_IDENTIFIER = app.meine.ios.tests;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SDKROOT = iphoneos;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
				TEST_HOST = "$(BUILT_PRODUCTS_DIR)/Meine.app/Meine";
			}};
			name = Release;
		}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		{CL_PROJ} /* Build configuration list for PBXProject "Meine" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{CFG_PD} /* Debug */,
				{CFG_PR} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		{CL_TGT} /* Build configuration list for PBXNativeTarget "Meine" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{CFG_TD} /* Debug */,
				{CFG_TR} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		{CL_TEST} /* Build configuration list for PBXNativeTarget "MeineTests" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{CFG_TED} /* Debug */,
				{CFG_TER} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
/* End XCConfigurationList section */
	}};
	rootObject = {PROJECT} /* Project object */;
}}
"""

PROJ.mkdir(parents=True, exist_ok=True)
(PROJ / "project.pbxproj").write_text(pbx)
SCHEME.mkdir(parents=True, exist_ok=True)
(SCHEME / "Meine.xcscheme").write_text(f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1600"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{TARGET}"
               BuildableName = "Meine.app"
               BlueprintName = "Meine"
               ReferencedContainer = "container:Meine.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
         <TestableReference
            skipped = "NO"
            parallelizable = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{TEST_TARGET}"
               BuildableName = "MeineTests.xctest"
               BlueprintName = "MeineTests"
               ReferencedContainer = "container:Meine.xcodeproj">
            </BuildableReference>
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{TARGET}"
            BuildableName = "Meine.app"
            BlueprintName = "Meine"
            ReferencedContainer = "container:Meine.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{TARGET}"
            BuildableName = "Meine.app"
            BlueprintName = "Meine"
            ReferencedContainer = "container:Meine.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
""")
print("wrote", PROJ / "project.pbxproj")
print("TARGET", TARGET)
print("TEST", TEST_TARGET)
