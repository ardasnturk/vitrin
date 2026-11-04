import { describe, expect, it } from 'vitest';
import { componentTo255, CROSS_PLATFORM_RULES, expandSetting, parseOpenStepPlist, readPbxproj, scanSource, settingsOf, SIGNAL_RULES, toHex } from '../src/index.js';

const PBX = `// !$*UTF8*$!
{
	archiveVersion = 1;
	objects = {
		P1 /* Project object */ = {
			isa = PBXProject;
			buildConfigurationList = PL /* list */;
			developmentRegion = en;
			knownRegions = ( en, Base, tr, "pt-BR", );
			targets = ( T1 /* App */, T2 /* Widget */, );
		};
		PL = { isa = XCConfigurationList; buildConfigurations = ( PC1 ); };
		PC1 = { isa = XCBuildConfiguration; name = Release; buildSettings = { IPHONEOS_DEPLOYMENT_TARGET = 18.0; SWIFT_VERSION = 6.0; }; };
		T1 = {
			isa = PBXNativeTarget;
			buildConfigurationList = TL1;
			name = Ritim;
			productName = Ritim;
			productType = "com.apple.product-type.application";
			fileSystemSynchronizedGroups = ( G1 );
		};
		G1 = { isa = PBXFileSystemSynchronizedRootGroup; path = Ritim; sourceTree = "<group>"; };
		TL1 = { isa = XCConfigurationList; buildConfigurations = ( C1 ); };
		C1 = { isa = XCBuildConfiguration; name = Release; buildSettings = {
			PRODUCT_BUNDLE_IDENTIFIER = "com.jastech.$(PRODUCT_NAME:rfc1034identifier)";
			TARGETED_DEVICE_FAMILY = "1,2";
			MARKETING_VERSION = 1.2.0;
			INFOPLIST_KEY_CFBundleDisplayName = "Ritim \\"Pro\\"";
			OTHER_FLAGS = ( "-a", "-b" );
		}; };
		T2 = { isa = PBXNativeTarget; buildConfigurationList = TL2; name = RitimWidget; productType = "com.apple.product-type.app-extension"; };
		TL2 = { isa = XCConfigurationList; buildConfigurations = ( ); };
	};
	rootObject = P1 /* Project object */;
}`;

describe('pbxproj parser', () => {
  it('parses quoted strings, arrays and comments', () => {
    const v = parseOpenStepPlist('{ a = "x \\"y\\""; /* c */ b = ( 1, 2, ); // tail\n c = { d = e; }; }') as Record<string, unknown>;
    expect(v).toEqual({ a: 'x "y"', b: ['1', '2'], c: { d: 'e' } });
  });

  it('reads targets, inherited settings and regions', () => {
    const p = readPbxproj(PBX);
    expect(p.developmentRegion).toBe('en');
    expect(p.knownRegions).toEqual(['en', 'Base', 'tr', 'pt-BR']);
    expect(p.targets.map((t) => t.name)).toEqual(['Ritim', 'RitimWidget']);
    const app = settingsOf(p.targets[0]!);
    expect(app.IPHONEOS_DEPLOYMENT_TARGET).toBe('18.0'); // inherited from project
    expect(app.TARGETED_DEVICE_FAMILY).toBe('1,2');
    expect(app.INFOPLIST_KEY_CFBundleDisplayName).toBe('Ritim "Pro"');
    expect(app.OTHER_FLAGS).toBe('-a -b');
    expect(p.targets[0]!.syncedFolders).toEqual(['Ritim']);
    expect(expandSetting(app.PRODUCT_BUNDLE_IDENTIFIER!, app, { PRODUCT_NAME: 'Ritim' })).toBe('com.jastech.Ritim');
  });
});

describe('asset colors', () => {
  it('converts every component notation', () => {
    expect(componentTo255('0.5')).toBe(128);
    expect(componentTo255('0xFF')).toBe(255);
    expect(componentTo255('128')).toBe(128);
    expect(componentTo255(1)).toBe(255);
    expect(toHex({ red: '0.357', green: '0.294', blue: '0.910' })).toBe('#5B4BE8');
  });
});

describe('source signals', () => {
  it('finds a native review prompt in Swift, Flutter and JavaScript sources, and none where there is no prompt', () => {
    const prompt = (file: string, code: string) => [...SIGNAL_RULES, ...CROSS_PLATFORM_RULES].some((rule) => rule.signal === 'ratings.prompt' && scanSource(file, code, [rule]).length > 0);
    expect(prompt('App/Done.swift', '@Environment(\\.requestReview) private var requestReview')).toBe(true);
    expect(prompt('App/Done.swift', 'SKStoreReviewController.requestReview(in: scene)')).toBe(true);
    expect(prompt('lib/done.dart', "import 'package:in_app_review/in_app_review.dart';")).toBe(true);
    expect(prompt('src/done.ts', "import * as StoreReview from 'expo-store-review';")).toBe(true);
    expect(prompt('App/Reviews.swift', 'struct ReviewList: View {}')).toBe(false);
  });

  it('detects frameworks with file:line evidence', () => {
    const hits = scanSource('App/Health.swift', 'import SwiftUI\nimport HealthKit\nlet x = 1\n.accessibilityLabel("a")');
    const health = hits.find((h) => h.rule.id === 'healthkit');
    expect(health?.evidence).toMatchObject({ path: 'App/Health.swift', line: 2 });
    expect(hits.some((h) => h.rule.signal === 'accessibility.voiceover')).toBe(true);
  });
});
