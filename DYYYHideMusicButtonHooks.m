#import "DYYYHideMusicButtonHooks.h"

#import "AwemeHeaders.h"

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <stdatomic.h>

static NSString *const kDYYYHideMusicButtonKey = @"DYYYHideMusicButton";
static NSString *const kDYYYHideCancelMuteKey = @"DYYYHideCancelMute";

typedef void (*DYYYVoidLayoutIMP)(id, SEL);

typedef struct {
    const char *className;
    DYYYVoidLayoutIMP *originalSlot;
    DYYYVoidLayoutIMP replacement;
    BOOL required;
} DYYYHideMusicLayoutHookSpec;

static atomic_bool gDYYYHideMusicButtonHooksStarted = false;

static DYYYVoidLayoutIMP gOrigMusicCoverButtonLayout = NULL;
static DYYYVoidLayoutIMP gOrigListenFeedViewLayout = NULL;
static DYYYVoidLayoutIMP gOrigClassicMusicViewLayout = NULL;
static DYYYVoidLayoutIMP gOrigStyleOneMusicViewLayout = NULL;
static DYYYVoidLayoutIMP gOrigStyleTwoMusicViewLayout = NULL;
static DYYYVoidLayoutIMP gOrigCancelMuteAwemeViewLayout = NULL;
static DYYYVoidLayoutIMP gOrigLiveCancelMuteAwemeViewLayout = NULL;

static BOOL DYYYHideMusicButtonEnabled(void) {
    return DYYYGetBool(kDYYYHideMusicButtonKey);
}

static BOOL DYYYShouldHideCancelMuteChrome(void) {
    // 隐藏音乐按钮时，默认静音场景下占同一右下角位的「取消静音」也应一并收掉。
    return DYYYHideMusicButtonEnabled() || DYYYGetBool(kDYYYHideCancelMuteKey);
}

static void DYYYRemoveMusicChromeView(UIView *view) {
    if (![view isKindOfClass:[UIView class]]) {
        return;
    }
    view.hidden = YES;
    [view removeFromSuperview];
}

static BOOL DYYYClassNameMatchesMusicContainer(NSString *className) {
    if (className.length == 0) {
        return NO;
    }
    return [className isEqualToString:@"AWEPlayInteractionMusicView"] ||
           [className isEqualToString:@"AWEPlayInteractionStyleOneMusicView"] ||
           [className isEqualToString:@"AWEPlayInteractionStyleTwoMusicView"] ||
           [className isEqualToString:@"AWEPlayInteractionListenFeedView"];
}

static UIView *DYYYNearestMusicContainerView(UIView *view) {
    UIView *current = view;
    while (current) {
        NSString *className = NSStringFromClass(object_getClass(current));
        if (DYYYClassNameMatchesMusicContainer(className)) {
            return current;
        }
        current = current.superview;
    }
    return nil;
}

static BOOL DYYYMusicCoverAccessibilityShouldHide(NSString *accessibilityLabel) {
    if (accessibilityLabel.length == 0) {
        return NO;
    }
    if ([accessibilityLabel isEqualToString:@"音乐详情"]) {
        return YES;
    }
    // 跟拍/模板视频会把右下角音乐位改成「拍同款」文案
    if ([accessibilityLabel isEqualToString:@"拍同款"] || [accessibilityLabel containsString:@"拍同款"]) {
        return YES;
    }
    return NO;
}

static void DYYYHideMusicCoverButtonIfNeeded(UIView *button) {
    if (!DYYYHideMusicButtonEnabled() || ![button isKindOfClass:[UIView class]]) {
        return;
    }

    UIView *container = DYYYNearestMusicContainerView(button);
    if (container) {
        DYYYRemoveMusicChromeView(container);
        return;
    }

    NSString *accessibilityLabel = nil;
    if ([button respondsToSelector:@selector(accessibilityLabel)]) {
        accessibilityLabel = button.accessibilityLabel;
    }
    if (!DYYYMusicCoverAccessibilityShouldHide(accessibilityLabel)) {
        return;
    }

    UIView *parent = button.superview;
    if (parent) {
        DYYYRemoveMusicChromeView(parent);
    } else {
        DYYYRemoveMusicChromeView(button);
    }
}

static void DYYYHideMusicContainerIfNeeded(UIView *view) {
    if (!DYYYHideMusicButtonEnabled()) {
        return;
    }
    DYYYRemoveMusicChromeView(view);
}

static void DYYYHideCancelMuteViewIfNeeded(UIView *view) {
    if (!DYYYShouldHideCancelMuteChrome()) {
        return;
    }
    DYYYRemoveMusicChromeView(view);
}

#pragma mark - Replacements

static void DYYYMusicCoverButtonLayoutSubviews(id self, SEL _cmd) {
    if (gOrigMusicCoverButtonLayout) {
        gOrigMusicCoverButtonLayout(self, _cmd);
    }
    DYYYHideMusicCoverButtonIfNeeded((UIView *)self);
}

static void DYYYListenFeedViewLayoutSubviews(id self, SEL _cmd) {
    if (gOrigListenFeedViewLayout) {
        gOrigListenFeedViewLayout(self, _cmd);
    }
    DYYYHideMusicContainerIfNeeded((UIView *)self);
}

static void DYYYClassicMusicViewLayoutSubviews(id self, SEL _cmd) {
    if (gOrigClassicMusicViewLayout) {
        gOrigClassicMusicViewLayout(self, _cmd);
    }
    DYYYHideMusicContainerIfNeeded((UIView *)self);
}

static void DYYYStyleOneMusicViewLayoutSubviews(id self, SEL _cmd) {
    if (gOrigStyleOneMusicViewLayout) {
        gOrigStyleOneMusicViewLayout(self, _cmd);
    }
    DYYYHideMusicContainerIfNeeded((UIView *)self);
}

static void DYYYStyleTwoMusicViewLayoutSubviews(id self, SEL _cmd) {
    if (gOrigStyleTwoMusicViewLayout) {
        gOrigStyleTwoMusicViewLayout(self, _cmd);
    }
    DYYYHideMusicContainerIfNeeded((UIView *)self);
}

static void DYYYCancelMuteAwemeViewLayoutSubviews(id self, SEL _cmd) {
    if (gOrigCancelMuteAwemeViewLayout) {
        gOrigCancelMuteAwemeViewLayout(self, _cmd);
    }
    DYYYHideCancelMuteViewIfNeeded((UIView *)self);
}

static void DYYYLiveCancelMuteAwemeViewLayoutSubviews(id self, SEL _cmd) {
    if (gOrigLiveCancelMuteAwemeViewLayout) {
        gOrigLiveCancelMuteAwemeViewLayout(self, _cmd);
    }
    DYYYHideCancelMuteViewIfNeeded((UIView *)self);
}

#pragma mark - Install

static BOOL DYYYMethodLooksLikeVoidLayoutSubviews(Method method) {
    if (!method) {
        return NO;
    }
    const char *typeEncoding = method_getTypeEncoding(method);
    if (!typeEncoding) {
        return NO;
    }
    // layoutSubviews -> v16@0:8
    return typeEncoding[0] == 'v';
}

static BOOL DYYYInstallLayoutSubviewsHook(Class cls, DYYYVoidLayoutIMP replacement, DYYYVoidLayoutIMP *originalSlot, BOOL required) {
    if (!cls || !replacement || !originalSlot) {
        return NO;
    }

    SEL selector = @selector(layoutSubviews);
    Method existing = class_getInstanceMethod(cls, selector);
    if (!existing || !DYYYMethodLooksLikeVoidLayoutSubviews(existing)) {
        if (required) {
            NSLog(@"[DYYY][RuntimeHook][HideMusicButton] 缺少 layoutSubviews：%@", NSStringFromClass(cls));
        }
        return NO;
    }

    const char *typeEncoding = method_getTypeEncoding(existing);
    IMP existingIMP = method_getImplementation(existing);
    if (existingIMP == (IMP)replacement) {
        return *originalSlot != NULL;
    }

    // class_getInstanceMethod 会沿继承链查找；用 class_copyMethodList 判断本类是否已有实现。
    BOOL methodDefinedOnClass = NO;
    unsigned int methodCount = 0;
    Method *methods = class_copyMethodList(cls, &methodCount);
    for (unsigned int i = 0; i < methodCount; i++) {
        if (method_getName(methods[i]) == selector) {
            methodDefinedOnClass = YES;
            break;
        }
    }
    free(methods);

    if (!methodDefinedOnClass) {
        IMP superIMP = existingIMP;
        if (!class_addMethod(cls, selector, (IMP)replacement, typeEncoding)) {
            if (required) {
                NSLog(@"[DYYY][RuntimeHook][HideMusicButton] class_addMethod 失败：%@", NSStringFromClass(cls));
            }
            return NO;
        }
        *originalSlot = (DYYYVoidLayoutIMP)superIMP;
        return YES;
    }

    IMP previous = method_setImplementation(existing, (IMP)replacement);
    if (!previous || previous == (IMP)replacement) {
        NSLog(@"[DYYY][RuntimeHook][HideMusicButton] 无法保存原 IMP：%@", NSStringFromClass(cls));
        return NO;
    }
    *originalSlot = (DYYYVoidLayoutIMP)previous;
    return YES;
}

void DYYYStartHideMusicButtonHooks(void) {
    bool expected = false;
    if (!atomic_compare_exchange_strong(&gDYYYHideMusicButtonHooksStarted, &expected, true)) {
        return;
    }

    DYYYHideMusicLayoutHookSpec specs[] = {
        {"AWEMusicCoverButton", &gOrigMusicCoverButtonLayout, DYYYMusicCoverButtonLayoutSubviews, YES},
        {"AWEPlayInteractionListenFeedView", &gOrigListenFeedViewLayout, DYYYListenFeedViewLayoutSubviews, YES},
        {"AWEPlayInteractionMusicView", &gOrigClassicMusicViewLayout, DYYYClassicMusicViewLayoutSubviews, NO},
        {"AWEPlayInteractionStyleOneMusicView", &gOrigStyleOneMusicViewLayout, DYYYStyleOneMusicViewLayoutSubviews, NO},
        {"AWEPlayInteractionStyleTwoMusicView", &gOrigStyleTwoMusicViewLayout, DYYYStyleTwoMusicViewLayoutSubviews, NO},
        {"AFDCancelMuteAwemeView", &gOrigCancelMuteAwemeViewLayout, DYYYCancelMuteAwemeViewLayoutSubviews, YES},
        {"AWELiveCancelMuteAwemeView", &gOrigLiveCancelMuteAwemeViewLayout, DYYYLiveCancelMuteAwemeViewLayoutSubviews, NO},
    };

    NSUInteger installed = 0;
    for (size_t i = 0; i < sizeof(specs) / sizeof(specs[0]); i++) {
        Class cls = objc_getClass(specs[i].className);
        if (!cls) {
            if (specs[i].required) {
                NSLog(@"[DYYY][RuntimeHook][HideMusicButton] 类未加载：%s", specs[i].className);
            }
            continue;
        }
        if (DYYYInstallLayoutSubviewsHook(cls, specs[i].replacement, specs[i].originalSlot, specs[i].required)) {
            installed += 1;
        }
    }

    NSLog(@"[DYYY][RuntimeHook][HideMusicButton] 安装完成，成功 %lu 个目标", (unsigned long)installed);
}
