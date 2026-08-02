#import "DYYYSearchKeyboardVoiceHooks.h"

#import "AwemeHeaders.h"

#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#import <objc/runtime.h>
#import <stdatomic.h>
#import <stdlib.h>
#import <string.h>

static NSString *const kDYYYHideKeyboardAIKey = @"DYYYHideKeyboardAI";
static const char *const kDYYYSearchFrameworkImageMarker = "/AWESearchFramework.framework/";
static const char *const kDYYYVoiceSearchManagerClassName = "AWEVoiceSearchManager";
static const char *const kDYYYNewVoiceEntranceClassName = "AWEVoiceSearchNewEntranceView";
static const char *const kDYYYVoiceEntranceClassName = "AWEVoiceSearchEntranceView";
static const char *const kDYYYAISearchElementClassName = "AWESearchKeyboardAISearchElement";

typedef void (*DYYYVoidIMP)(id, SEL);
typedef void (*DYYYVoidObjectIMP)(id, SEL, id);
typedef void (*DYYYVoidBoolIMP)(id, SEL, BOOL);
typedef id (*DYYYObjectGetterIMP)(id, SEL);

static atomic_bool gDYYYNewVoiceEntranceHookLogged = false;
static atomic_bool gDYYYNewVoiceEntranceFirstHitLogged = false;
static atomic_bool gDYYYVoiceSearchManagerHookLogged = false;
static atomic_bool gDYYYVoiceSearchCreatorFirstHitLogged = false;
static atomic_bool gDYYYLegacyVoiceEntranceHookLogged = false;
static atomic_bool gDYYYAISearchElementHookLogged = false;

static IMP gOrigNewVoiceEntranceSetHidden = NULL;
static IMP gOrigNewVoiceEntranceLayout = NULL;
static IMP gOrigNewVoiceEntranceDidMoveToWindow = NULL;
static IMP gOrigVoiceSearchCreateEntrance = NULL;

static IMP gOrigLegacyVoiceEntranceSetHidden = NULL;
static IMP gOrigLegacyVoiceEntranceLayout = NULL;
static IMP gOrigLegacyVoiceEntranceDidMoveToWindow = NULL;

static IMP gOrigAISearchContentView = NULL;
static IMP gOrigAISearchSetContentView = NULL;
static IMP gOrigAISearchSetupUI = NULL;
static IMP gOrigAISearchSetupNewUI = NULL;
static IMP gOrigAISearchElementDidSetup = NULL;
static IMP gOrigAISearchTabbarHidden = NULL;

static BOOL DYYYHideKeyboardAIEnabled(void) {
    return DYYYGetBool(kDYYYHideKeyboardAIKey);
}

static BOOL DYYYClassDefinesInstanceSelector(Class targetClass, SEL selector) {
    unsigned int methodCount = 0;
    Method *methods = class_copyMethodList(targetClass, &methodCount);
    BOOL found = NO;
    for (unsigned int index = 0; index < methodCount; index++) {
        if (method_getName(methods[index]) == selector) {
            found = YES;
            break;
        }
    }
    free(methods);
    return found;
}

static BOOL DYYYInstallExactInstanceHook(Class targetClass,
                                         SEL selector,
                                         const char *expectedTypeEncoding,
                                         IMP replacement,
                                         IMP *originalSlot) {
    if (!targetClass || !selector || !expectedTypeEncoding || !replacement || !originalSlot) {
        return NO;
    }
    if (!DYYYClassDefinesInstanceSelector(targetClass, selector)) {
        return NO;
    }

    Method method = class_getInstanceMethod(targetClass, selector);
    const char *actualTypeEncoding = method ? method_getTypeEncoding(method) : NULL;
    if (!method || !actualTypeEncoding || strcmp(actualTypeEncoding, expectedTypeEncoding) != 0) {
        return NO;
    }

    IMP currentIMP = method_getImplementation(method);
    if (currentIMP == replacement) {
        return YES;
    }
    if (*originalSlot) {
        return NO;
    }

    IMP originalIMP = method_setImplementation(method, replacement);
    if (!originalIMP || originalIMP == replacement) {
        return NO;
    }
    *originalSlot = originalIMP;
    return YES;
}

static BOOL DYYYInstallSubclassOverride(Class targetClass,
                                        SEL selector,
                                        const char *expectedTypeEncoding,
                                        IMP replacement,
                                        IMP *originalSlot) {
    if (!targetClass || !selector || !expectedTypeEncoding || !replacement || !originalSlot) {
        return NO;
    }

    Method method = class_getInstanceMethod(targetClass, selector);
    const char *actualTypeEncoding = method ? method_getTypeEncoding(method) : NULL;
    if (!method || !actualTypeEncoding || strcmp(actualTypeEncoding, expectedTypeEncoding) != 0) {
        return NO;
    }

    IMP currentIMP = method_getImplementation(method);
    if (currentIMP == replacement) {
        return YES;
    }
    if (*originalSlot) {
        return NO;
    }

    if (DYYYClassDefinesInstanceSelector(targetClass, selector)) {
        IMP originalIMP = method_setImplementation(method, replacement);
        if (!originalIMP || originalIMP == replacement) {
            return NO;
        }
        *originalSlot = originalIMP;
        return YES;
    }

    // 继承方法仅在指定的抖音私有子类上增加覆盖，不修改 UIView 或搜索框架基类。
    if (!class_addMethod(targetClass, selector, replacement, actualTypeEncoding)) {
        return NO;
    }
    *originalSlot = currentIMP;
    return YES;
}

static void DYYYLogNewVoiceEntranceFirstHit(void) {
    bool expected = false;
    if (atomic_compare_exchange_strong(&gDYYYNewVoiceEntranceFirstHitLogged, &expected, true)) {
        NSLog(@"[DYYY][RuntimeHook][HideKeyboardAI] 已命中 AWEVoiceSearchNewEntranceView 并强制隐藏");
    }
}

#pragma mark - 39.8.0 manager-owned 语音搜索入口

static void DYYYForceHideNewVoiceEntranceIfNeeded(id entranceView) {
    if (!DYYYHideKeyboardAIEnabled() || !entranceView || !gOrigNewVoiceEntranceSetHidden) {
        return;
    }

    ((DYYYVoidBoolIMP)gOrigNewVoiceEntranceSetHidden)(entranceView, @selector(setHidden:), YES);
    DYYYLogNewVoiceEntranceFirstHit();
}

static void DYYYNewVoiceEntranceSetHidden(id self, SEL _cmd, BOOL hidden) {
    BOOL effectiveHidden = hidden || DYYYHideKeyboardAIEnabled();
    ((DYYYVoidBoolIMP)gOrigNewVoiceEntranceSetHidden)(self, _cmd, effectiveHidden);
    if (effectiveHidden && DYYYHideKeyboardAIEnabled()) {
        DYYYLogNewVoiceEntranceFirstHit();
    }
}

static void DYYYNewVoiceEntranceLayout(id self, SEL _cmd) {
    ((DYYYVoidIMP)gOrigNewVoiceEntranceLayout)(self, _cmd);
    DYYYForceHideNewVoiceEntranceIfNeeded(self);
}

static void DYYYNewVoiceEntranceDidMoveToWindow(id self, SEL _cmd) {
    ((DYYYVoidIMP)gOrigNewVoiceEntranceDidMoveToWindow)(self, _cmd);
    if (((UIView *)self).window) {
        DYYYForceHideNewVoiceEntranceIfNeeded(self);
    }
}

static id DYYYVoiceSearchCreateEntrance(id self, SEL _cmd) {
    id entranceView = ((DYYYObjectGetterIMP)gOrigVoiceSearchCreateEntrance)(self, _cmd);
    Class newEntranceClass = objc_lookUpClass(kDYYYNewVoiceEntranceClassName);
    Class voiceEntranceClass = objc_lookUpClass(kDYYYVoiceEntranceClassName);
    BOOL isKnownSearchVoiceEntrance =
        (newEntranceClass && [entranceView isKindOfClass:newEntranceClass]) ||
        (voiceEntranceClass && [entranceView isKindOfClass:voiceEntranceClass]);
    if (DYYYHideKeyboardAIEnabled() && isKnownSearchVoiceEntrance &&
        [entranceView isKindOfClass:[UIView class]]) {
        ((UIView *)entranceView).hidden = YES;

        bool expected = false;
        if (atomic_compare_exchange_strong(&gDYYYVoiceSearchCreatorFirstHitLogged, &expected, true)) {
            NSLog(@"[DYYY][RuntimeHook][HideKeyboardAI] createVoiceSearchEntranceView 返回 %@，已隐藏",
                  NSStringFromClass([entranceView class]));
        }
    }
    return entranceView;
}

#pragma mark - 旧样式搜索语音入口（含键盘子类）

static void DYYYForceHideLegacyVoiceEntranceIfNeeded(id entranceView) {
    if (!DYYYHideKeyboardAIEnabled() || !entranceView || !gOrigLegacyVoiceEntranceSetHidden) {
        return;
    }
    ((DYYYVoidBoolIMP)gOrigLegacyVoiceEntranceSetHidden)(entranceView, @selector(setHidden:), YES);
}

static void DYYYLegacyVoiceEntranceSetHidden(id self, SEL _cmd, BOOL hidden) {
    BOOL effectiveHidden = hidden || DYYYHideKeyboardAIEnabled();
    ((DYYYVoidBoolIMP)gOrigLegacyVoiceEntranceSetHidden)(self, _cmd, effectiveHidden);
}

static void DYYYLegacyVoiceEntranceLayout(id self, SEL _cmd) {
    ((DYYYVoidIMP)gOrigLegacyVoiceEntranceLayout)(self, _cmd);
    DYYYForceHideLegacyVoiceEntranceIfNeeded(self);
}

static void DYYYLegacyVoiceEntranceDidMoveToWindow(id self, SEL _cmd) {
    ((DYYYVoidIMP)gOrigLegacyVoiceEntranceDidMoveToWindow)(self, _cmd);
    if (((UIView *)self).window) {
        DYYYForceHideLegacyVoiceEntranceIfNeeded(self);
    }
}

#pragma mark - 旧版本右下角 AI 搜索入口

static void DYYYHideAISearchElementIfNeeded(id element) {
    if (!DYYYHideKeyboardAIEnabled() || !element || !gOrigAISearchContentView) {
        return;
    }

    id contentView = ((DYYYObjectGetterIMP)gOrigAISearchContentView)(element, NSSelectorFromString(@"contentView"));
    if ([contentView isKindOfClass:[UIView class]]) {
        ((UIView *)contentView).hidden = YES;
        ((UIView *)contentView).userInteractionEnabled = NO;
    }
}

static id DYYYAISearchContentView(id self, SEL _cmd) {
    id contentView = ((DYYYObjectGetterIMP)gOrigAISearchContentView)(self, _cmd);
    if (DYYYHideKeyboardAIEnabled() && [contentView isKindOfClass:[UIView class]]) {
        ((UIView *)contentView).hidden = YES;
        ((UIView *)contentView).userInteractionEnabled = NO;
    }
    return contentView;
}

static void DYYYAISearchSetContentView(id self, SEL _cmd, id contentView) {
    ((DYYYVoidObjectIMP)gOrigAISearchSetContentView)(self, _cmd, contentView);
    if (DYYYHideKeyboardAIEnabled() && [contentView isKindOfClass:[UIView class]]) {
        ((UIView *)contentView).hidden = YES;
        ((UIView *)contentView).userInteractionEnabled = NO;
    }
}

static void DYYYAISearchSetupUI(id self, SEL _cmd) {
    ((DYYYVoidIMP)gOrigAISearchSetupUI)(self, _cmd);
    DYYYHideAISearchElementIfNeeded(self);
}

static void DYYYAISearchSetupNewUI(id self, SEL _cmd) {
    ((DYYYVoidIMP)gOrigAISearchSetupNewUI)(self, _cmd);
    DYYYHideAISearchElementIfNeeded(self);
}

static void DYYYAISearchElementDidSetup(id self, SEL _cmd) {
    ((DYYYVoidIMP)gOrigAISearchElementDidSetup)(self, _cmd);
    DYYYHideAISearchElementIfNeeded(self);
}

static void DYYYAISearchTabbarHidden(id self, SEL _cmd, BOOL hidden) {
    BOOL effectiveHidden = hidden || DYYYHideKeyboardAIEnabled();
    ((DYYYVoidBoolIMP)gOrigAISearchTabbarHidden)(self, _cmd, effectiveHidden);
    DYYYHideAISearchElementIfNeeded(self);
}

#pragma mark - 安装与框架延迟加载

static void DYYYInstallNewVoiceEntranceHooks(void) {
    Class targetClass = objc_lookUpClass(kDYYYNewVoiceEntranceClassName);
    if (!targetClass) {
        return;
    }

    BOOL installed =
        DYYYInstallSubclassOverride(targetClass,
                                    @selector(setHidden:),
                                    "v20@0:8B16",
                                    (IMP)DYYYNewVoiceEntranceSetHidden,
                                    &gOrigNewVoiceEntranceSetHidden) &&
        DYYYInstallExactInstanceHook(targetClass,
                                     @selector(layoutSubviews),
                                     "v16@0:8",
                                     (IMP)DYYYNewVoiceEntranceLayout,
                                     &gOrigNewVoiceEntranceLayout) &&
        DYYYInstallSubclassOverride(targetClass,
                                    @selector(didMoveToWindow),
                                    "v16@0:8",
                                    (IMP)DYYYNewVoiceEntranceDidMoveToWindow,
                                    &gOrigNewVoiceEntranceDidMoveToWindow);

    if (installed) {
        bool expected = false;
        if (atomic_compare_exchange_strong(&gDYYYNewVoiceEntranceHookLogged, &expected, true)) {
            NSLog(@"[DYYY][RuntimeHook][HideKeyboardAI] AWEVoiceSearchNewEntranceView Hook 已安装");
        }
    }
}

static void DYYYInstallVoiceSearchManagerHooks(void) {
    Class targetClass = objc_lookUpClass(kDYYYVoiceSearchManagerClassName);
    if (!targetClass) {
        return;
    }

    BOOL installed = DYYYInstallExactInstanceHook(targetClass,
                                                   NSSelectorFromString(@"createVoiceSearchEntranceView"),
                                                   "@16@0:8",
                                                   (IMP)DYYYVoiceSearchCreateEntrance,
                                                   &gOrigVoiceSearchCreateEntrance);
    if (installed) {
        bool expected = false;
        if (atomic_compare_exchange_strong(&gDYYYVoiceSearchManagerHookLogged, &expected, true)) {
            NSLog(@"[DYYY][RuntimeHook][HideKeyboardAI] AWEVoiceSearchManager.createVoiceSearchEntranceView Hook 已安装");
        }
    }
}

static void DYYYInstallLegacyVoiceEntranceHooks(void) {
    Class targetClass = objc_lookUpClass(kDYYYVoiceEntranceClassName);
    if (!targetClass) {
        return;
    }

    BOOL installed =
        DYYYInstallSubclassOverride(targetClass,
                                    @selector(setHidden:),
                                    "v20@0:8B16",
                                    (IMP)DYYYLegacyVoiceEntranceSetHidden,
                                    &gOrigLegacyVoiceEntranceSetHidden) &&
        DYYYInstallSubclassOverride(targetClass,
                                    @selector(layoutSubviews),
                                    "v16@0:8",
                                    (IMP)DYYYLegacyVoiceEntranceLayout,
                                    &gOrigLegacyVoiceEntranceLayout) &&
        DYYYInstallSubclassOverride(targetClass,
                                    @selector(didMoveToWindow),
                                    "v16@0:8",
                                    (IMP)DYYYLegacyVoiceEntranceDidMoveToWindow,
                                    &gOrigLegacyVoiceEntranceDidMoveToWindow);

    if (installed) {
        bool expected = false;
        if (atomic_compare_exchange_strong(&gDYYYLegacyVoiceEntranceHookLogged, &expected, true)) {
            NSLog(@"[DYYY][RuntimeHook][HideKeyboardAI] AWEVoiceSearchEntranceView Hook 已安装（含旧版键盘子类）");
        }
    }
}

static void DYYYInstallAISearchElementHooks(void) {
    Class targetClass = objc_lookUpClass(kDYYYAISearchElementClassName);
    if (!targetClass) {
        return;
    }

    BOOL contentViewInstalled =
        DYYYInstallSubclassOverride(targetClass,
                                    NSSelectorFromString(@"contentView"),
                                    "@16@0:8",
                                    (IMP)DYYYAISearchContentView,
                                    &gOrigAISearchContentView) &&
        DYYYInstallSubclassOverride(targetClass,
                                    NSSelectorFromString(@"setContentView:"),
                                    "v24@0:8@16",
                                    (IMP)DYYYAISearchSetContentView,
                                    &gOrigAISearchSetContentView);

    DYYYInstallExactInstanceHook(targetClass,
                                 NSSelectorFromString(@"setupUI"),
                                 "v16@0:8",
                                 (IMP)DYYYAISearchSetupUI,
                                 &gOrigAISearchSetupUI);
    DYYYInstallExactInstanceHook(targetClass,
                                 NSSelectorFromString(@"setupNewUI"),
                                 "v16@0:8",
                                 (IMP)DYYYAISearchSetupNewUI,
                                 &gOrigAISearchSetupNewUI);
    DYYYInstallExactInstanceHook(targetClass,
                                 NSSelectorFromString(@"host_elementViewDidSetup"),
                                 "v16@0:8",
                                 (IMP)DYYYAISearchElementDidSetup,
                                 &gOrigAISearchElementDidSetup);
    DYYYInstallExactInstanceHook(targetClass,
                                 NSSelectorFromString(@"host_tabbarHidden:"),
                                 "v20@0:8B16",
                                 (IMP)DYYYAISearchTabbarHidden,
                                 &gOrigAISearchTabbarHidden);

    if (contentViewInstalled) {
        bool expected = false;
        if (atomic_compare_exchange_strong(&gDYYYAISearchElementHookLogged, &expected, true)) {
            NSLog(@"[DYYY][RuntimeHook][HideKeyboardAI] 旧版搜索键盘 AI 元素 Hook 已安装");
        }
    }
}

static void DYYYInstallSearchKeyboardHooks(void) {
    DYYYInstallNewVoiceEntranceHooks();
    DYYYInstallVoiceSearchManagerHooks();
    DYYYInstallLegacyVoiceEntranceHooks();
    DYYYInstallAISearchElementHooks();
}

static BOOL DYYYIsSearchFrameworkImage(const struct mach_header *header) {
    uint32_t imageCount = _dyld_image_count();
    for (uint32_t index = 0; index < imageCount; index++) {
        if (_dyld_get_image_header(index) != header) {
            continue;
        }
        const char *imageName = _dyld_get_image_name(index);
        return imageName && strstr(imageName, kDYYYSearchFrameworkImageMarker) != NULL;
    }
    return NO;
}

static void DYYYSearchFrameworkImageAdded(const struct mach_header *header, intptr_t slide) {
    (void)slide;
    if (!DYYYIsSearchFrameworkImage(header)) {
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
      DYYYInstallSearchKeyboardHooks();
    });
}

void DYYYStartSearchKeyboardVoiceHooks(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      _dyld_register_func_for_add_image(DYYYSearchFrameworkImageAdded);

      for (NSNumber *delayNumber in @[@0.0, @0.2, @0.8, @2.0]) {
          NSTimeInterval delay = delayNumber.doubleValue;
          dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                         dispatch_get_main_queue(), ^{
                           DYYYInstallSearchKeyboardHooks();
                         });
      }
    });
}
