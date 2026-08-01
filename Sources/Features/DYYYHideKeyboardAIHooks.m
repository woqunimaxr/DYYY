#import "DYYYHideKeyboardAIHooks.h"

#import "AwemeHeaders.h"

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <stdatomic.h>

static NSString *const kDYYYHideKeyboardAIKey = @"DYYYHideKeyboardAI";
static NSString *const kDYYYLegacyVoiceSearchClassName = @"AWESearchKeyboardVoiceSearchEntranceView";

static const CGFloat kDYYYMaxToolbarHeight = 120.0;
static const CGFloat kDYYYMaxToolbarWidthRatio = 0.98;

typedef void (*DYYYVoidIMP)(id, SEL);
typedef void (*DYYYSetHiddenIMP)(id, SEL, BOOL);
typedef void (*DYYYSetTextIMP)(id, SEL, id);
typedef void (*DYYYSetTitleForStateIMP)(id, SEL, id, NSUInteger);

static atomic_bool gDYYYHideKeyboardAIHooksStarted = false;

static DYYYVoidIMP gOrigLegacyLayout = NULL;
static DYYYSetHiddenIMP gOrigLegacySetHidden = NULL;
static DYYYVoidIMP gOrigLegacyDidMoveToWindow = NULL;

static Class gDiscoveredPillClass = Nil;
static DYYYVoidIMP gOrigPillLayout = NULL;
static DYYYSetHiddenIMP gOrigPillSetHidden = NULL;
static DYYYVoidIMP gOrigPillDidMoveToWindow = NULL;

static DYYYSetTextIMP gOrigLabelSetText = NULL;
static DYYYSetTextIMP gOrigLabelSetAttributedText = NULL;
static DYYYSetTitleForStateIMP gOrigButtonSetTitleForState = NULL;
static DYYYSetTextIMP gOrigSetAccessibilityLabel = NULL;

static BOOL DYYYHideKeyboardAIEnabled(void) {
    return DYYYGetBool(kDYYYHideKeyboardAIKey);
}

static BOOL DYYYStringLooksLikeVoiceSearch(NSString *text) {
    return text.length >= 4 && [text containsString:@"语音搜索"];
}

static BOOL DYYYViewHasKnownCompactToolbarSize(UIView *view) {
    if (![view isKindOfClass:[UIView class]]) {
        return NO;
    }
    CGSize size = view.bounds.size;
    if (size.width < 1.0 || size.height < 1.0) {
        return NO;
    }
    if (size.height > kDYYYMaxToolbarHeight) {
        return NO;
    }
    CGFloat screenWidth = UIScreen.mainScreen.bounds.size.width;
    if (screenWidth > 0.0 && size.width > screenWidth * kDYYYMaxToolbarWidthRatio && size.height > 64.0) {
        return NO;
    }
    return YES;
}

static void DYYYHideChromeView(UIView *view) {
    if (![view isKindOfClass:[UIView class]]) {
        return;
    }
    // 直接改 ivar 路径不可靠；走 setHidden:（若已 Hook 会强制保持隐藏）
    view.hidden = YES;
    view.userInteractionEnabled = NO;
}

/// 旧版：隐藏语音入口；仅当曾祖父仍是紧凑工具条时同层藏 AI。
static void DYYYApplyLegacyVoiceSearchHide(UIView *voiceEntrance) {
    if (!voiceEntrance) {
        return;
    }
    DYYYHideChromeView(voiceEntrance);

    UIView *parentView = voiceEntrance.superview;
    UIView *grandParentView = parentView.superview;
    UIView *greatGrandParentView = grandParentView.superview;
    if (!greatGrandParentView || !DYYYViewHasKnownCompactToolbarSize(greatGrandParentView)) {
        if (parentView && DYYYViewHasKnownCompactToolbarSize(parentView)) {
            DYYYHideChromeView(parentView);
        }
        return;
    }
    for (UIView *subview in greatGrandParentView.subviews) {
        if (DYYYViewHasKnownCompactToolbarSize(subview)) {
            DYYYHideChromeView(subview);
        }
    }
}

static BOOL DYYYClassNameIsSystemUIKit(NSString *className) {
    if (className.length == 0) {
        return YES;
    }
    return [className hasPrefix:@"UI"] || [className hasPrefix:@"_UI"] || [className hasPrefix:@"NS"];
}

/// 从「语音搜索」文字节点向上找最深的自定义紧凑容器，作为 Hook 目标。
static UIView *DYYYNearestHookablePillView(UIView *anchor) {
    UIView *current = anchor;
    for (NSInteger depth = 0; depth < 6 && current; depth++) {
        NSString *className = NSStringFromClass(object_getClass(current));
        if (!DYYYClassNameIsSystemUIKit(className)) {
            CGSize size = current.bounds.size;
            BOOL sizeUnknown = (size.width < 1.0 || size.height < 1.0);
            BOOL compact = sizeUnknown || (size.height <= 64.0 && size.width <= 280.0);
            if (compact) {
                return current;
            }
        }
        current = current.superview;
    }
    return nil;
}

#pragma mark - Generic installer

static BOOL DYYYInstallInstanceHook(Class cls, SEL selector, IMP replacement, void *originalSlot, BOOL requireVoidReturn) {
    if (!cls || !selector || !replacement || !originalSlot) {
        return NO;
    }
    if (*(IMP *)originalSlot != NULL) {
        return YES;
    }

    Method existing = class_getInstanceMethod(cls, selector);
    if (!existing) {
        return NO;
    }
    const char *typeEncoding = method_getTypeEncoding(existing);
    if (!typeEncoding) {
        return NO;
    }
    if (requireVoidReturn && typeEncoding[0] != 'v') {
        return NO;
    }

    IMP existingIMP = method_getImplementation(existing);
    if (existingIMP == replacement) {
        return YES;
    }

    BOOL methodDefinedOnClass = NO;
    unsigned int methodCount = 0;
    Method *methods = class_copyMethodList(cls, &methodCount);
    for (unsigned int index = 0; index < methodCount; index++) {
        if (method_getName(methods[index]) == selector) {
            methodDefinedOnClass = YES;
            break;
        }
    }
    free(methods);

    if (!methodDefinedOnClass) {
        if (!class_addMethod(cls, selector, replacement, typeEncoding)) {
            return NO;
        }
        *(IMP *)originalSlot = existingIMP;
        return YES;
    }

    IMP previous = method_setImplementation(existing, replacement);
    if (!previous || previous == replacement) {
        return NO;
    }
    *(IMP *)originalSlot = previous;
    return YES;
}

#pragma mark - Legacy class hooks

static void DYYYLegacyLayoutSubviews(id self, SEL _cmd) {
    if (gOrigLegacyLayout) {
        gOrigLegacyLayout(self, _cmd);
    }
    if (DYYYHideKeyboardAIEnabled()) {
        DYYYApplyLegacyVoiceSearchHide((UIView *)self);
    }
}

static void DYYYLegacySetHidden(id self, SEL _cmd, BOOL hidden) {
    if (DYYYHideKeyboardAIEnabled()) {
        if (gOrigLegacySetHidden) {
            gOrigLegacySetHidden(self, _cmd, YES);
        }
        return;
    }
    if (gOrigLegacySetHidden) {
        gOrigLegacySetHidden(self, _cmd, hidden);
    }
}

static void DYYYLegacyDidMoveToWindow(id self, SEL _cmd) {
    if (gOrigLegacyDidMoveToWindow) {
        gOrigLegacyDidMoveToWindow(self, _cmd);
    }
    if (DYYYHideKeyboardAIEnabled() && ((UIView *)self).window) {
        DYYYApplyLegacyVoiceSearchHide((UIView *)self);
    }
}

static BOOL DYYYInstallLegacyVoiceSearchHooks(void) {
    Class cls = NSClassFromString(kDYYYLegacyVoiceSearchClassName);
    if (!cls) {
        return NO;
    }
    BOOL layoutOK = DYYYInstallInstanceHook(cls, @selector(layoutSubviews), (IMP)DYYYLegacyLayoutSubviews, &gOrigLegacyLayout, YES);
    BOOL hiddenOK = DYYYInstallInstanceHook(cls, @selector(setHidden:), (IMP)DYYYLegacySetHidden, &gOrigLegacySetHidden, YES);
    BOOL windowOK = DYYYInstallInstanceHook(cls, @selector(didMoveToWindow), (IMP)DYYYLegacyDidMoveToWindow, &gOrigLegacyDidMoveToWindow, YES);
    return layoutOK || hiddenOK || windowOK;
}

#pragma mark - Discovered pill class hooks

static void DYYYPillLayoutSubviews(id self, SEL _cmd) {
    if (gOrigPillLayout) {
        gOrigPillLayout(self, _cmd);
    }
    if (DYYYHideKeyboardAIEnabled()) {
        DYYYHideChromeView((UIView *)self);
    }
}

static void DYYYPillSetHidden(id self, SEL _cmd, BOOL hidden) {
    if (DYYYHideKeyboardAIEnabled()) {
        if (gOrigPillSetHidden) {
            gOrigPillSetHidden(self, _cmd, YES);
        }
        return;
    }
    if (gOrigPillSetHidden) {
        gOrigPillSetHidden(self, _cmd, hidden);
    }
}

static void DYYYPillDidMoveToWindow(id self, SEL _cmd) {
    if (gOrigPillDidMoveToWindow) {
        gOrigPillDidMoveToWindow(self, _cmd);
    }
    if (DYYYHideKeyboardAIEnabled() && ((UIView *)self).window) {
        DYYYHideChromeView((UIView *)self);
    }
}

static BOOL DYYYInstallPillClassHooks(Class cls) {
    if (!cls) {
        return NO;
    }
    if (cls == NSClassFromString(kDYYYLegacyVoiceSearchClassName)) {
        // 旧类由专用路径处理
        return DYYYInstallLegacyVoiceSearchHooks();
    }
    if (gDiscoveredPillClass == cls && gOrigPillSetHidden != NULL) {
        return YES;
    }

    BOOL layoutOK = DYYYInstallInstanceHook(cls, @selector(layoutSubviews), (IMP)DYYYPillLayoutSubviews, &gOrigPillLayout, YES);
    BOOL hiddenOK = DYYYInstallInstanceHook(cls, @selector(setHidden:), (IMP)DYYYPillSetHidden, &gOrigPillSetHidden, YES);
    BOOL windowOK = DYYYInstallInstanceHook(cls, @selector(didMoveToWindow), (IMP)DYYYPillDidMoveToWindow, &gOrigPillDidMoveToWindow, YES);
    if (!(layoutOK || hiddenOK || windowOK)) {
        return NO;
    }
    gDiscoveredPillClass = cls;
    NSLog(@"[DYYY][RuntimeHook][HideKeyboardAI] 已 Hook 胶囊类：%@ (layout=%@ setHidden=%@ window=%@)",
          NSStringFromClass(cls),
          layoutOK ? @"YES" : @"NO",
          hiddenOK ? @"YES" : @"NO",
          windowOK ? @"YES" : @"NO");
    return YES;
}

static void DYYYHandleVoiceSearchTextAnchor(UIView *anchor) {
    if (!anchor || !DYYYHideKeyboardAIEnabled()) {
        return;
    }

    UIView *pill = DYYYNearestHookablePillView(anchor);
    if (pill) {
        DYYYInstallPillClassHooks(object_getClass(pill));
        DYYYHideChromeView(pill);
        return;
    }

    // 找不到自定义类时，至少藏紧凑父视图，避免只藏文字留下空胶囊
    UIView *parent = anchor.superview;
    if (parent && DYYYViewHasKnownCompactToolbarSize(parent)) {
        DYYYHideChromeView(parent);
    } else {
        DYYYHideChromeView(anchor);
    }
}

#pragma mark - UILabel / UIButton content hooks（文案出现即绑定类并隐藏，解决复用后不再 layout 的问题）

static void DYYYLabelSetText(id self, SEL _cmd, NSString *text) {
    if (gOrigLabelSetText) {
        gOrigLabelSetText(self, _cmd, text);
    }
    if (!DYYYStringLooksLikeVoiceSearch(text)) {
        return;
    }
    DYYYHandleVoiceSearchTextAnchor((UIView *)self);
}

static void DYYYLabelSetAttributedText(id self, SEL _cmd, NSAttributedString *text) {
    if (gOrigLabelSetAttributedText) {
        gOrigLabelSetAttributedText(self, _cmd, text);
    }
    if (!DYYYStringLooksLikeVoiceSearch(text.string)) {
        return;
    }
    DYYYHandleVoiceSearchTextAnchor((UIView *)self);
}

static void DYYYButtonSetTitleForState(id self, SEL _cmd, NSString *title, NSUInteger state) {
    if (gOrigButtonSetTitleForState) {
        gOrigButtonSetTitleForState(self, _cmd, title, state);
    }
    if (!DYYYStringLooksLikeVoiceSearch(title)) {
        return;
    }
    DYYYHandleVoiceSearchTextAnchor((UIView *)self);
}

static void DYYYViewSetAccessibilityLabel(id self, SEL _cmd, NSString *label) {
    if (gOrigSetAccessibilityLabel) {
        gOrigSetAccessibilityLabel(self, _cmd, label);
    }
    if (!DYYYStringLooksLikeVoiceSearch(label)) {
        return;
    }
    DYYYHandleVoiceSearchTextAnchor((UIView *)self);
}

static void DYYYInstallTextDiscoveryHooks(void) {
    DYYYInstallInstanceHook([UILabel class], @selector(setText:), (IMP)DYYYLabelSetText, &gOrigLabelSetText, YES);
    DYYYInstallInstanceHook([UILabel class], @selector(setAttributedText:), (IMP)DYYYLabelSetAttributedText, &gOrigLabelSetAttributedText, YES);
    DYYYInstallInstanceHook([UIButton class], @selector(setTitle:forState:), (IMP)DYYYButtonSetTitleForState, &gOrigButtonSetTitleForState, YES);
    DYYYInstallInstanceHook([UIView class], @selector(setAccessibilityLabel:), (IMP)DYYYViewSetAccessibilityLabel, &gOrigSetAccessibilityLabel, YES);
}

void DYYYStopHideKeyboardAIHooks(void) {
    // 当前实现无通知观察者；保留接口供 AppDelegate 对称调用。
}

void DYYYStartHideKeyboardAIHooks(void) {
    bool expected = false;
    if (!atomic_compare_exchange_strong(&gDYYYHideKeyboardAIHooksStarted, &expected, true)) {
        return;
    }

    BOOL legacyHooked = DYYYInstallLegacyVoiceSearchHooks();
    DYYYInstallTextDiscoveryHooks();

    NSLog(@"[DYYY][RuntimeHook][HideKeyboardAI] 安装完成，legacy=%@，已启用 Label/Button 文案绑定",
          legacyHooked ? @"YES" : @"NO");
}
