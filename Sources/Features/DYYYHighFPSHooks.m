#import "DYYYHighFPSHooks.h"

#import "AwemeHeaders.h"
#import "DYYYConstants.h"

#import <CoreFoundation/CoreFoundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <stdatomic.h>
#import <substrate.h>

/*
 * 基于对 Aweme 39.8 解包的静态证据（.ipa_extract_3980）：
 * 1) Info.plist 无 CADisableMinimumFrameDurationOnPhone → CADisplayLink 会被系统钳在 60Hz
 * 2) AwemeCore 存在 AWEProMotionFPSBooster（boostFPSForScrolling/Appearance/... / degradeFPS）
 * 3) AwemeCore 存在 AWEDisplayLinkDegradeManager（disableDegradeOperation / degradeFPS）
 *
 * 开启最高帧率后默认：热状态偏高或低电量模式时自动降档（无独立设置项）。
 */

static NSString *const kDYYYCADisableMinimumFrameDurationOnPhoneKey = @"CADisableMinimumFrameDurationOnPhone";

static atomic_bool gDYYYHighFPSStarted = false;
static atomic_bool gDYYYCFBundleHookInstalled = false;
static atomic_bool gDYYYDegradeHookInstalled = false;
static atomic_bool gDYYYLoadObserversInstalled = false;

static BOOL gDYYYHighFPSThrottled = NO;
static BOOL gDYYYUnsupportedDisplayLogged = NO;

static id gDYYYThermalObserver = nil;
static id gDYYYPowerObserver = nil;

static IMP gOrigSetDisableDegradeOperation = NULL;
typedef void (*DYYYVoidBoolIMP)(id, SEL, BOOL);
typedef id (*DYYYObjectGetterIMP)(id, SEL);

static CFTypeRef (*gOrigCFBundleGetValueForInfoDictionaryKey)(CFBundleRef, CFStringRef) = NULL;

static BOOL DYYYHighFPSEnabled(void) {
    return DYYYGetBoolCached(DYYY_ENABLE_HIGH_FPS_KEY);
}

/// 负载过重：热状态 ≥ Fair，或系统低电量模式。
static BOOL DYYYHighFPSLoadRequiresThrottle(void) {
    NSProcessInfo *info = [NSProcessInfo processInfo];
    if (info.isLowPowerModeEnabled) {
        return YES;
    }
    return info.thermalState >= NSProcessInfoThermalStateFair;
}

/// 高帧率生效且当前不在降档：才强制 boost / 禁止宿主降帧。
static BOOL DYYYHighFPSShouldBoost(void) {
    return DYYYHighFPSEnabled() && !gDYYYHighFPSThrottled;
}

#pragma mark - Helpers

static id DYYYCallSharedIfPossible(Class cls) {
    if (!cls) {
        return nil;
    }
    static const char *kSharedSels[] = {
        "sharedInstance",
        "sharedManager",
        "p_sharedInstance",
        "defaultManager",
        "manager",
    };
    for (size_t i = 0; i < sizeof(kSharedSels) / sizeof(kSharedSels[0]); i++) {
        SEL sel = sel_registerName(kSharedSels[i]);
        if (![cls respondsToSelector:sel]) {
            continue;
        }
        id obj = ((DYYYObjectGetterIMP)objc_msgSend)(cls, sel);
        if (obj) {
            return obj;
        }
    }
    return nil;
}

static BOOL DYYYPerformVoidOnTarget(id target, const char *selName) {
    if (!target || !selName) {
        return NO;
    }
    SEL sel = sel_registerName(selName);
    if (![target respondsToSelector:sel]) {
        return NO;
    }
    ((void (*)(id, SEL))objc_msgSend)(target, sel);
    return YES;
}

static id DYYYProMotionBoosterTarget(Class *outClass) {
    Class cls = NSClassFromString(@"AWEProMotionFPSBooster");
    if (outClass) {
        *outClass = cls;
    }
    if (!cls) {
        return nil;
    }
    id booster = DYYYCallSharedIfPossible(cls);
    return booster ?: (id)cls;
}

#pragma mark - ProMotion Info.plist unlock

// `UIScreen` 首次初始化会加载 UIKit 的 application initialization context。
// DYYYStartHighFPSHooks 在 dylib initializer 中调用，因此那里不能访问它；
// 仅在设置页或 UIApplicationDidBecomeActive 后调用本函数。
static NSInteger DYYYMaximumSupportedFramesPerSecond(void) {
    return UIScreen.mainScreen.maximumFramesPerSecond;
}

static BOOL DYYYCurrentDisplaySupportsHighFPS(void) {
    return DYYYMaximumSupportedFramesPerSecond() > 60;
}

static CFTypeRef DYYYCFBundleGetValueForInfoDictionaryKey(CFBundleRef bundle, CFStringRef key) {
    // 门闩保持解锁，便于负载恢复后快速回到高刷；降档走宿主 degrade，不反复改写 plist。
    if (DYYYHighFPSEnabled() && key &&
        CFStringCompare(key, CFSTR("CADisableMinimumFrameDurationOnPhone"), 0) == kCFCompareEqualTo) {
        return kCFBooleanTrue;
    }
    if (gOrigCFBundleGetValueForInfoDictionaryKey) {
        return gOrigCFBundleGetValueForInfoDictionaryKey(bundle, key);
    }
    return NULL;
}

static void DYYYInstallCFBundleProMotionHookIfNeeded(void) {
    bool expected = false;
    if (!atomic_compare_exchange_strong(&gDYYYCFBundleHookInstalled, &expected, true)) {
        return;
    }
    MSHookFunction((void *)CFBundleGetValueForInfoDictionaryKey,
                   (void *)DYYYCFBundleGetValueForInfoDictionaryKey,
                   (void **)&gOrigCFBundleGetValueForInfoDictionaryKey);
}

#pragma mark - AWEDisplayLinkDegradeManager

static void DYYYSetDisableDegradeOperation(id self, SEL _cmd, BOOL disable) {
    if (DYYYHighFPSShouldBoost()) {
        disable = YES;
    }
    if (gOrigSetDisableDegradeOperation) {
        ((DYYYVoidBoolIMP)gOrigSetDisableDegradeOperation)(self, _cmd, disable);
    }
}

static void DYYYApplyDisplayLinkDegradePolicy(BOOL forceDisableDegrade) {
    Class cls = NSClassFromString(@"AWEDisplayLinkDegradeManager");
    id mgr = DYYYCallSharedIfPossible(cls);
    if (!mgr) {
        mgr = cls;
    }
    if (!mgr) {
        NSLog(@"[DYYY][RuntimeHook][HighFPS] AWEDisplayLinkDegradeManager 未找到");
        return;
    }

    SEL setDisableSel = @selector(setDisableDegradeOperation:);
    if ([mgr respondsToSelector:setDisableSel]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(mgr, setDisableSel, forceDisableDegrade);
        NSLog(@"[DYYY][RuntimeHook][HighFPS] setDisableDegradeOperation:%d", forceDisableDegrade);
    }

    bool expected = false;
    if (cls && atomic_compare_exchange_strong(&gDYYYDegradeHookInstalled, &expected, true)) {
        Method instanceMethod = class_getInstanceMethod(cls, setDisableSel);
        if (instanceMethod) {
            IMP previous = method_setImplementation(instanceMethod, (IMP)DYYYSetDisableDegradeOperation);
            if (previous && previous != (IMP)DYYYSetDisableDegradeOperation) {
                gOrigSetDisableDegradeOperation = previous;
                NSLog(@"[DYYY][RuntimeHook][HighFPS] 已 Hook setDisableDegradeOperation:");
            }
        } else {
            NSLog(@"[DYYY][RuntimeHook][HighFPS] setDisableDegradeOperation: 实例方法未找到");
        }
    }
}

#pragma mark - AWEProMotionFPSBooster

static void DYYYInvokeProMotionFPSBooster(void) {
    Class cls = nil;
    id primary = DYYYProMotionBoosterTarget(&cls);
    if (!cls) {
        NSLog(@"[DYYY][RuntimeHook][HighFPS] AWEProMotionFPSBooster 类未加载");
        return;
    }

    NSUInteger hit = 0;
    id targets[] = {primary, cls};
    static const char *kBoostSels[] = {
        "boostFPSForScrolling",
        "boostFPSForAppearance",
        "boostFPSForVCAppearance",
        "SetHighRefreshRate",
        "setHighRefreshRate",
    };

    for (size_t t = 0; t < sizeof(targets) / sizeof(targets[0]); t++) {
        id target = targets[t];
        if (!target) {
            continue;
        }
        for (size_t i = 0; i < sizeof(kBoostSels) / sizeof(kBoostSels[0]); i++) {
            if (DYYYPerformVoidOnTarget(target, kBoostSels[i])) {
                hit += 1;
            }
        }
        SEL setHigh = @selector(setHighRefreshRate:);
        if ([target respondsToSelector:setHigh]) {
            NSMethodSignature *sig = [target methodSignatureForSelector:setHigh];
            if (sig.numberOfArguments == 3) {
                const char *type = [sig getArgumentTypeAtIndex:2];
                if (type && (type[0] == 'B' || type[0] == 'c' || type[0] == 'C')) {
                    ((void (*)(id, SEL, BOOL))objc_msgSend)(target, setHigh, YES);
                    hit += 1;
                } else if (type && (type[0] == 'q' || type[0] == 'Q' || type[0] == 'i' || type[0] == 'I' || type[0] == 'l' || type[0] == 'L')) {
                    NSInteger maxFPS = UIScreen.mainScreen.maximumFramesPerSecond;
                    if (maxFPS <= 0) {
                        maxFPS = 120;
                    }
                    ((void (*)(id, SEL, NSInteger))objc_msgSend)(target, setHigh, maxFPS);
                    hit += 1;
                }
            }
        }
    }

    NSLog(@"[DYYY][RuntimeHook][HighFPS] ProMotion booster 命中 %lu 个入口", (unsigned long)hit);
}

static void DYYYInvokeProMotionFPSDegrade(void) {
    Class cls = nil;
    id primary = DYYYProMotionBoosterTarget(&cls);
    if (!cls) {
        return;
    }

    NSUInteger hit = 0;
    id targets[] = {primary, cls};
    static const char *kDegradeSels[] = {
        "degradeFPS",
        "boostFPSForVCDisAppearance",
    };
    for (size_t t = 0; t < sizeof(targets) / sizeof(targets[0]); t++) {
        id target = targets[t];
        if (!target) {
            continue;
        }
        for (size_t i = 0; i < sizeof(kDegradeSels) / sizeof(kDegradeSels[0]); i++) {
            if (DYYYPerformVoidOnTarget(target, kDegradeSels[i])) {
                hit += 1;
            }
        }
    }
    NSLog(@"[DYYY][RuntimeHook][HighFPS] ProMotion degrade 命中 %lu 个入口", (unsigned long)hit);
}

#pragma mark - Auto throttle (built-in)

static void DYYYHighFPSEnterThrottle(void) {
    if (gDYYYHighFPSThrottled) {
        return;
    }
    gDYYYHighFPSThrottled = YES;
    NSProcessInfo *info = [NSProcessInfo processInfo];
    NSLog(@"[DYYY][RuntimeHook][HighFPS] 自动降档 thermal=%ld lowPower=%d",
          (long)info.thermalState,
          info.isLowPowerModeEnabled);
    DYYYInvokeProMotionFPSDegrade();
    // 允许宿主 DisplayLink 降帧；Hook 在 ShouldBoost=NO 时不再强制 YES。
    DYYYApplyDisplayLinkDegradePolicy(NO);
}

static void DYYYHighFPSExitThrottle(void) {
    if (!gDYYYHighFPSThrottled) {
        return;
    }
    gDYYYHighFPSThrottled = NO;
    NSLog(@"[DYYY][RuntimeHook][HighFPS] 负载恢复，重新拉高帧率");
    DYYYApplyDisplayLinkDegradePolicy(YES);
    DYYYInvokeProMotionFPSBooster();
}

static void DYYYHighFPSReevaluateLoad(void) {
    if (!DYYYHighFPSEnabled()) {
        gDYYYHighFPSThrottled = NO;
        return;
    }
    if (DYYYHighFPSLoadRequiresThrottle()) {
        DYYYHighFPSEnterThrottle();
    } else {
        DYYYHighFPSExitThrottle();
    }
}

static void DYYYInstallLoadObserversIfNeeded(void) {
    bool expected = false;
    if (!atomic_compare_exchange_strong(&gDYYYLoadObserversInstalled, &expected, true)) {
        return;
    }

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    gDYYYThermalObserver =
        [center addObserverForName:NSProcessInfoThermalStateDidChangeNotification
                            object:nil
                             queue:[NSOperationQueue mainQueue]
                        usingBlock:^(__unused NSNotification *note) {
                          DYYYHighFPSReevaluateLoad();
                        }];
    gDYYYPowerObserver =
        [center addObserverForName:NSProcessInfoPowerStateDidChangeNotification
                            object:nil
                             queue:[NSOperationQueue mainQueue]
                        usingBlock:^(__unused NSNotification *note) {
                          DYYYHighFPSReevaluateLoad();
                        }];
}

#pragma mark - Apply / Start

static void DYYYApplyProMotionUnlock(void) {
    DYYYInstallCFBundleProMotionHookIfNeeded();
    id runtimeValue = [[NSBundle mainBundle] objectForInfoDictionaryKey:kDYYYCADisableMinimumFrameDurationOnPhoneKey];
    NSLog(@"[DYYY][RuntimeHook][HighFPS] ProMotion门闩已启用（未修改 Aweme Info.plist） runtime=%@ maxFPS=%ld",
          runtimeValue,
          (long)DYYYMaximumSupportedFramesPerSecond());
}

static void DYYYApplyHighFPSSettingChangeOnMain(BOOL enabled) {
    if (!enabled) {
        gDYYYHighFPSThrottled = NO;
        return;
    }

    if (!DYYYCurrentDisplaySupportsHighFPS()) {
        gDYYYHighFPSThrottled = NO;
        if (!gDYYYUnsupportedDisplayLogged) {
            gDYYYUnsupportedDisplayLogged = YES;
            NSLog(@"[DYYY][RuntimeHook][HighFPS] 当前设备最高仅 %ldHz，跳过高帧率宿主调用",
                  (long)DYYYMaximumSupportedFramesPerSecond());
        }
        return;
    }

    DYYYInstallLoadObserversIfNeeded();
    DYYYApplyProMotionUnlock();
    // 先按当前负载决定 boost 或降档。
    gDYYYHighFPSThrottled = NO;
    if (DYYYHighFPSLoadRequiresThrottle()) {
        DYYYHighFPSEnterThrottle();
    } else {
        DYYYApplyDisplayLinkDegradePolicy(YES);
        DYYYInvokeProMotionFPSBooster();
    }
}

static void DYYYScheduleHighFPSSettingChange(BOOL enabled) {
    dispatch_async(dispatch_get_main_queue(), ^{
      DYYYApplyHighFPSSettingChangeOnMain(enabled);
    });
}

void DYYYApplyHighFPSSettingChange(BOOL enabled) {
    if ([NSThread isMainThread]) {
        DYYYApplyHighFPSSettingChangeOnMain(enabled);
    } else {
        DYYYScheduleHighFPSSettingChange(enabled);
    }
}

void DYYYStartHighFPSHooks(void) {
    bool expected = false;
    if (!atomic_compare_exchange_strong(&gDYYYHighFPSStarted, &expected, true)) {
        return;
    }

    DYYYInstallCFBundleProMotionHookIfNeeded();

    // 不能在 dylib initializer 中访问 UIKit。XR 上的真实崩溃表明这会与
    // +[UIScreen initialize] 相互等待，最终触发启动 watchdog。
    NSLog(@"[DYYY][RuntimeHook][HighFPS] 已就绪；将于 App 激活后检查显示能力");

    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                      object:nil
                                                      queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(__unused NSNotification *note) {
                                                    if (!DYYYHighFPSEnabled()) {
                                                        return;
                                                    }
                                                    DYYYScheduleHighFPSSettingChange(YES);
                                                  }];
}
