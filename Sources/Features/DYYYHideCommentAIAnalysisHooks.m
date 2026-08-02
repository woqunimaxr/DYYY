#import "DYYYHideCommentAIAnalysisHooks.h"

#import "AwemeHeaders.h"

#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <stdatomic.h>

static NSString *const kDYYYHideCommentViewsKey = @"DYYYHideCommentViews";

static NSString *const kDYYYCommentDCFeedAIParseTabComponentClassName =
    @"AWECommentDCFeedSwiftImpl.CommentDCFeedAIParseTabComponent";
static NSString *const kDYYYCommentTemplatePOITabComponentClassName =
    @"AWECommentPOISwiftImpl.CommentTemplatePOITabComponent";
static NSString *const kDYYYCommentEvaluateTabComponentClassName =
    @"AWECommentCommerceSwiftImpl.CommentEvaluateTabComponent";
static NSString *const kDYYYCommentProductCommentTabComponentClassName =
    @"AWECommentCommerceSwiftImpl.CommentProductCommentTabComponent";
static NSString *const kDYYYCommentTabManagerClassName = @"AWECommentPanelTabSwiftImpl.CommentTabManager";
static NSString *const kDYYYCommentTabServiceClassName = @"AWECommentTabService";
static NSString *const kDYYYFeedDoubleColumnAITabUtilClassName = @"AWEFeedDoubleColumnAITabUtil";
static NSString *const kDYYYCommentTabModelClassName = @"AWECommentPanelTabSwiftImpl.CommentTabModel";
static NSString *const kDYYYCommentContainerTabModelClassName =
    @"AWECommentPanelContainerSwiftImpl.CommentTabModel";
static NSString *const kDYYYCommentAIParseViewControllerClassName =
    @"AWEFeedDoubleColumnCommentAIParseViewController";
static NSString *const kDYYYPOIRateListInCommentViewControllerClassName =
    @"AWEPOIUGCRateListInCommentViewController";
static NSString *const kDYYYLocalLifeCommentBizServiceClassName = @"IESLocalLifeCommentBizService";
static NSString *const kDYYYECModuleServiceClassName = @"AWEECModuleService";
static NSString *const kDYYYCommentPanelTabBasicParamsClassName = @"AWECommentPanelTabBasicParams";
static NSString *const kDYYYCommentContainerInnerViewControllerClassName =
    @"AWECommentPanelContainerSwiftImpl.CommentContainerInnerViewController";

typedef BOOL (*DYYYBoolSceneIMP)(id, SEL, id);
typedef BOOL (*DYYYBoolAwemeIMP)(id, SEL, id);
typedef BOOL (*DYYYBoolAwemeEnterFromIMP)(id, SEL, id, id);
typedef BOOL (*DYYYBoolContextTypeIMP)(id, SEL, id, unsigned long long);
typedef BOOL (*DYYYBoolTypeIMP)(id, SEL, unsigned long long);
typedef BOOL (*DYYYBoolNoArgIMP)(id, SEL);
typedef id (*DYYYArrayTypesIMP)(id, SEL, id);
typedef id (*DYYYIdContextIMP)(id, SEL, id);
typedef id (*DYYYViewControllerForTypeIMP)(id, SEL, unsigned long long);
typedef void (*DYYYVoidConfigSegmentedControlIMP)(id, SEL, id);
typedef void (*DYYYSetNeedsUpdateIMP)(id, SEL, BOOL, id);
typedef void (*DYYYSetTitleIMP)(id, SEL, id);
typedef double (*DYYYDoubleNoArgIMP)(id, SEL);

static atomic_bool gDYYYHideCommentAIAnalysisHooksStarted = false;
static NSMutableSet<NSNumber *> *gHiddenCommentTabTypes = nil;
static NSMutableDictionary<NSString *, NSValue *> *gOrigCommentTabSetNeedsUpdateIMPs = nil;

static void DYYYCommentExtraTabSetNeedsUpdate(id self, SEL _cmd, BOOL needsUpdate, id completion);

static DYYYBoolSceneIMP gOrigShouldShowDCFeedAITabWithScene = NULL;
static DYYYBoolAwemeEnterFromIMP gOrigCurrentVideoShouldShowAITab = NULL;
static DYYYBoolSceneIMP gOrigCommentTabServiceMultiTabs = NULL;
static DYYYBoolContextTypeIMP gOrigCommentTabServiceContainsTab = NULL;
static DYYYBoolTypeIMP gOrigCommentTabManagerContainsTab = NULL;
static DYYYArrayTypesIMP gOrigCommentTabManagerComponentTypes = NULL;
static DYYYViewControllerForTypeIMP gOrigCommentTabManagerViewControllerForType = NULL;
static DYYYVoidConfigSegmentedControlIMP gOrigCommentTabManagerConfigSegmentedControl = NULL;
static DYYYIdContextIMP gOrigCommentPanelTabBasicParamsInit = NULL;
static DYYYBoolNoArgIMP gOrigCommentPanelTabBasicParamsNoTabScene = NULL;
static DYYYDoubleNoArgIMP gOrigCommentContainerHeightForSegmentedControl = NULL;
static DYYYSetTitleIMP gOrigCommentTabModelSetTitle = NULL;
static DYYYSetTitleIMP gOrigCommentContainerTabModelSetTitle = NULL;
static DYYYBoolAwemeIMP gOrigShouldShowRateTabInCommentWithAweme = NULL;
static DYYYBoolAwemeIMP gOrigShouldShowProductCommentWithAwemeModel = NULL;

static BOOL DYYYHideCommentViewsEnabled(void) {
    return DYYYGetBool(kDYYYHideCommentViewsKey);
}

static NSValue *DYYYOriginalIMPValueForObject(NSDictionary<NSString *, NSValue *> *storage, id object) {
    for (Class cls = object_getClass(object); cls; cls = class_getSuperclass(cls)) {
        NSValue *value = storage[NSStringFromClass(cls)];
        if (value) {
            return value;
        }
    }
    return nil;
}

static NSString *DYYYNormalizedCommentTabTitle(NSString *text) {
    if (text.length == 0) {
        return @"";
    }
    return [[text stringByReplacingOccurrencesOfString:@" " withString:@""] lowercaseString];
}

static BOOL DYYYStringLooksLikePrimaryCommentTab(NSString *text) {
    if (text.length == 0) {
        return NO;
    }
    NSString *normalized = DYYYNormalizedCommentTabTitle(text);
    if ([normalized containsString:@"条评论"]) {
        return YES;
    }
    return [normalized isEqualToString:@"评论"];
}

static BOOL DYYYStringLooksLikeExtraCommentTab(NSString *text) {
    if (text.length == 0 || text.length > 16) {
        return NO;
    }
    if (DYYYStringLooksLikePrimaryCommentTab(text)) {
        return NO;
    }

    NSString *normalized = DYYYNormalizedCommentTabTitle(text);
    static NSArray<NSString *> *hiddenPatterns = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      hiddenPatterns = @[
          @"ai解析",
          @"门店评价",
          @"商品评价",
          @"种草评价",
          @"评价",
          @"看过",
          @"赞过",
          @"收藏",
          @"火焰",
          @"金币",
          @"游戏",
          @"娱乐",
      ];
    });

    for (NSString *pattern in hiddenPatterns) {
        if ([normalized containsString:pattern]) {
            return YES;
        }
    }
    return NO;
}

static void DYYYCacheHiddenCommentTabTypeIfNeeded(unsigned long long tabType, NSString *title) {
    if (tabType == 0 || title.length == 0) {
        return;
    }
    if (!DYYYStringLooksLikeExtraCommentTab(title)) {
        return;
    }
    if (!gHiddenCommentTabTypes) {
        gHiddenCommentTabTypes = [NSMutableSet set];
    }
    [gHiddenCommentTabTypes addObject:@(tabType)];
}

static BOOL DYYYIsHiddenCommentTabType(unsigned long long tabType) {
    return tabType != 0 && [gHiddenCommentTabTypes containsObject:@(tabType)];
}

static BOOL DYYYShouldHideExtraCommentTabTypeString(NSString *typeString) {
    if (typeString.length == 0) {
        return NO;
    }
    if ([typeString isEqualToString:@"Comment"] || [typeString isEqualToString:@"CommentLike"]) {
        return NO;
    }

    static NSArray<NSString *> *hiddenTypePatterns = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      hiddenTypePatterns = @[
          @"CommentAIParse",
          @"CommentDCFeedAIParse",
          @"CommentTemplatePOI",
          @"CommentEvaluate",
          @"CommentProductComment",
          @"CommentViewer",
          @"CommentFavorite",
          @"CommentGoldLike",
          @"CommentHTSFlame",
          @"CommentSendGoldCollect",
          @"CommentADComment",
          @"CommentGameCP",
          @"CommentTemplateEntertainment",
          @"CommentTemplateGameCP",
      ];
    });

    for (NSString *pattern in hiddenTypePatterns) {
        if ([typeString containsString:pattern]) {
            return YES;
        }
    }
    return NO;
}

static BOOL DYYYObjectIsCommentAIParseViewController(id object) {
    if (!object) {
        return NO;
    }
    Class aiParseVCClass = NSClassFromString(kDYYYCommentAIParseViewControllerClassName);
    return aiParseVCClass && [object isKindOfClass:aiParseVCClass];
}

static BOOL DYYYObjectIsExtraCommentTabViewController(id object) {
    if (!object) {
        return NO;
    }
    if (DYYYObjectIsCommentAIParseViewController(object)) {
        return YES;
    }

    Class rateVCClass = NSClassFromString(kDYYYPOIRateListInCommentViewControllerClassName);
    if (rateVCClass && [object isKindOfClass:rateVCClass]) {
        return YES;
    }

    NSString *className = NSStringFromClass([object class]);
    if ([className containsString:@"ProductEvaluation"] || [className containsString:@"RateListInComment"] ||
        [className containsString:@"CommentAIParse"]) {
        return YES;
    }
    return NO;
}

static BOOL DYYYShouldHideCommentTab(unsigned long long tabType, id viewController, NSString *title) {
    if (!DYYYHideCommentViewsEnabled()) {
        return NO;
    }
    if (DYYYIsHiddenCommentTabType(tabType)) {
        return YES;
    }
    if (DYYYObjectIsExtraCommentTabViewController(viewController)) {
        if (tabType != 0) {
            if (!gHiddenCommentTabTypes) {
                gHiddenCommentTabTypes = [NSMutableSet set];
            }
            [gHiddenCommentTabTypes addObject:@(tabType)];
        }
        return YES;
    }
    if (title.length > 0 && DYYYStringLooksLikeExtraCommentTab(title)) {
        if (tabType != 0) {
            DYYYCacheHiddenCommentTabTypeIfNeeded(tabType, title);
        }
        return YES;
    }
    return NO;
}

static void DYYYHideCommentPanelSegmentedControlView(UIView *segmentedControl) {
    if (!segmentedControl || ![segmentedControl isKindOfClass:[UIView class]]) {
        return;
    }
    segmentedControl.hidden = YES;
    segmentedControl.alpha = 0.0;
    segmentedControl.userInteractionEnabled = NO;
}

static NSArray *DYYYFilterExtraCommentTabTypes(NSArray *types) {
    if (!DYYYHideCommentViewsEnabled() || types.count == 0) {
        return types;
    }

    NSMutableArray *filtered = [NSMutableArray arrayWithCapacity:types.count];
    for (id item in types) {
        if ([item isKindOfClass:[NSNumber class]]) {
            unsigned long long value = [(NSNumber *)item unsignedLongLongValue];
            if (DYYYIsHiddenCommentTabType(value)) {
                continue;
            }
        } else if ([item isKindOfClass:[NSString class]]) {
            if (DYYYShouldHideExtraCommentTabTypeString((NSString *)item)) {
                continue;
            }
        }
        [filtered addObject:item];
    }
    return filtered.count == types.count ? types : [filtered copy];
}

#pragma mark - Generic installer

static BOOL DYYYInstallClassHook(Class cls,
                                 SEL selector,
                                 IMP replacement,
                                 IMP *originalSlot,
                                 BOOL isClassMethod,
                                 BOOL requireBoolReturn) {
    if (!cls || !selector || !replacement || !originalSlot) {
        return NO;
    }
    if (*originalSlot != NULL) {
        return YES;
    }

    Method existing = isClassMethod ? class_getClassMethod(cls, selector) : class_getInstanceMethod(cls, selector);
    if (!existing) {
        return NO;
    }

    const char *typeEncoding = method_getTypeEncoding(existing);
    if (!typeEncoding) {
        return NO;
    }
    if (requireBoolReturn && typeEncoding[0] != 'B' && typeEncoding[0] != 'c') {
        return NO;
    }

    IMP existingIMP = method_getImplementation(existing);
    if (existingIMP == replacement) {
        return YES;
    }

    if (isClassMethod) {
        if (!class_addMethod(object_getClass(cls), selector, replacement, typeEncoding)) {
            IMP previous = method_setImplementation(existing, replacement);
            if (!previous || previous == replacement) {
                return NO;
            }
            *originalSlot = previous;
            return YES;
        }
        *originalSlot = existingIMP;
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
        *originalSlot = existingIMP;
        return YES;
    }

    IMP previous = method_setImplementation(existing, replacement);
    if (!previous || previous == replacement) {
        return NO;
    }
    *originalSlot = previous;
    return YES;
}

static BOOL DYYYInstallSetNeedsUpdateHookForClassName(NSString *className, NSString *mangledClassName) {
    Class cls = NSClassFromString(className);
    if (!cls && mangledClassName.length > 0) {
        cls = objc_getClass(mangledClassName.UTF8String);
    }
    if (!cls) {
        return NO;
    }

    SEL selector = @selector(setNeedsUpdate:completion:);
    Method existing = class_getInstanceMethod(cls, selector);
    if (!existing) {
        return NO;
    }

    NSString *key = NSStringFromClass(cls);
    if (gOrigCommentTabSetNeedsUpdateIMPs[key]) {
        return YES;
    }

    const char *typeEncoding = method_getTypeEncoding(existing);
    if (!typeEncoding) {
        return NO;
    }

    IMP existingIMP = method_getImplementation(existing);
    IMP replacement = (IMP)DYYYCommentExtraTabSetNeedsUpdate;
    if (existingIMP == replacement) {
        return NO;
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

    IMP original = existingIMP;
    if (!methodDefinedOnClass) {
        // class_getInstanceMethod 会返回继承自父类的 Method。必须在 POI 子类上新增覆盖，
        // 不能直接替换共享的父类 IMP，否则会连带拦截原生评论数组件。
        if (!class_addMethod(cls, selector, replacement, typeEncoding)) {
            return NO;
        }
    } else {
        original = method_setImplementation(existing, replacement);
        if (!original || original == replacement) {
            return NO;
        }
    }

    if (!gOrigCommentTabSetNeedsUpdateIMPs) {
        gOrigCommentTabSetNeedsUpdateIMPs = [NSMutableDictionary dictionary];
    }
    gOrigCommentTabSetNeedsUpdateIMPs[key] = [NSValue valueWithPointer:original];
    return YES;
}

#pragma mark - AWEFeedDoubleColumnAITabUtil

static BOOL DYYYShouldShowDCFeedAITabWithScene(id self, SEL _cmd, id scene) {
    if (DYYYHideCommentViewsEnabled()) {
        return NO;
    }
    if (gOrigShouldShowDCFeedAITabWithScene) {
        return gOrigShouldShowDCFeedAITabWithScene(self, _cmd, scene);
    }
    return YES;
}

static BOOL DYYYCurrentVideoShouldShowAITab(id self, SEL _cmd, id aweme, id enterFrom) {
    if (DYYYHideCommentViewsEnabled()) {
        return NO;
    }
    if (gOrigCurrentVideoShouldShowAITab) {
        return gOrigCurrentVideoShouldShowAITab(self, _cmd, aweme, enterFrom);
    }
    return YES;
}

static BOOL DYYYInstallFeedDoubleColumnAITabUtilHooks(void) {
    Class cls = NSClassFromString(kDYYYFeedDoubleColumnAITabUtilClassName);
    if (!cls) {
        return NO;
    }

    BOOL sceneOK = DYYYInstallClassHook(cls,
                                        @selector(shouldShowDCFeedAITabWithScene:),
                                        (IMP)DYYYShouldShowDCFeedAITabWithScene,
                                        (IMP *)&gOrigShouldShowDCFeedAITabWithScene,
                                        YES,
                                        YES);
    BOOL videoOK = DYYYInstallClassHook(cls,
                                        @selector(currentVideoShouldShowAITab:enterFrom:),
                                        (IMP)DYYYCurrentVideoShouldShowAITab,
                                        (IMP *)&gOrigCurrentVideoShouldShowAITab,
                                        YES,
                                        YES);
    return sceneOK || videoOK;
}

#pragma mark - POI / Commerce tab visibility

static BOOL DYYYShouldShowRateTabInCommentWithAweme(id self, SEL _cmd, id aweme) {
    if (DYYYHideCommentViewsEnabled()) {
        return NO;
    }
    if (gOrigShouldShowRateTabInCommentWithAweme) {
        return gOrigShouldShowRateTabInCommentWithAweme(self, _cmd, aweme);
    }
    return YES;
}

static BOOL DYYYShouldShowProductCommentWithAwemeModel(id self, SEL _cmd, id aweme) {
    if (DYYYHideCommentViewsEnabled()) {
        return NO;
    }
    if (gOrigShouldShowProductCommentWithAwemeModel) {
        return gOrigShouldShowProductCommentWithAwemeModel(self, _cmd, aweme);
    }
    return YES;
}

static BOOL DYYYInstallLocalLifeCommentBizServiceHooks(void) {
    Class cls = NSClassFromString(kDYYYLocalLifeCommentBizServiceClassName);
    if (!cls) {
        return NO;
    }
    return DYYYInstallClassHook(cls,
                                @selector(shouldShowRateTabInCommentWithAweme:),
                                (IMP)DYYYShouldShowRateTabInCommentWithAweme,
                                (IMP *)&gOrigShouldShowRateTabInCommentWithAweme,
                                NO,
                                YES);
}

static BOOL DYYYInstallECModuleServiceHooks(void) {
    Class cls = NSClassFromString(kDYYYECModuleServiceClassName);
    if (!cls) {
        return NO;
    }
    return DYYYInstallClassHook(cls,
                                @selector(shouldShowProductCommentWithAwemeModel:),
                                (IMP)DYYYShouldShowProductCommentWithAwemeModel,
                                (IMP *)&gOrigShouldShowProductCommentWithAwemeModel,
                                NO,
                                YES);
}

#pragma mark - AWECommentTabService / CommentTabManager

static BOOL DYYYCommentTabServiceMultiTabs(id self, SEL _cmd, id context) {
    if (DYYYHideCommentViewsEnabled()) {
        return NO;
    }
    if (gOrigCommentTabServiceMultiTabs) {
        return gOrigCommentTabServiceMultiTabs(self, _cmd, context);
    }
    return YES;
}

static BOOL DYYYCommentTabServiceContainsTab(id self, SEL _cmd, id context, unsigned long long type) {
    if (DYYYShouldHideCommentTab(type, nil, nil)) {
        return NO;
    }
    if (gOrigCommentTabServiceContainsTab) {
        return gOrigCommentTabServiceContainsTab(self, _cmd, context, type);
    }
    return YES;
}

static id DYYYCommentTabManagerViewControllerForType(id self, SEL _cmd, unsigned long long type) {
    if (DYYYShouldHideCommentTab(type, nil, nil)) {
        return nil;
    }
    id viewController = nil;
    if (gOrigCommentTabManagerViewControllerForType) {
        viewController = gOrigCommentTabManagerViewControllerForType(self, _cmd, type);
    }
    if (DYYYShouldHideCommentTab(type, viewController, nil)) {
        return nil;
    }
    return viewController;
}

static BOOL DYYYCommentTabManagerContainsTab(id self, SEL _cmd, unsigned long long type) {
    if (DYYYShouldHideCommentTab(type, nil, nil)) {
        return NO;
    }
    if (gOrigCommentTabManagerViewControllerForType) {
        id viewController = gOrigCommentTabManagerViewControllerForType(self, @selector(viewControllerForType:), type);
        if (DYYYShouldHideCommentTab(type, viewController, nil)) {
            return NO;
        }
    }
    if (gOrigCommentTabManagerContainsTab) {
        return gOrigCommentTabManagerContainsTab(self, _cmd, type);
    }
    return YES;
}

static NSArray *DYYYCommentTabManagerComponentTypes(id self, SEL _cmd, NSArray *types) {
    NSArray *originalTypes = types;
    if (gOrigCommentTabManagerComponentTypes) {
        originalTypes = gOrigCommentTabManagerComponentTypes(self, _cmd, types);
    }
    return DYYYFilterExtraCommentTabTypes(originalTypes);
}

static void DYYYCommentTabManagerConfigSegmentedControl(id self, SEL _cmd, id segmentedControl) {
    if (gOrigCommentTabManagerConfigSegmentedControl) {
        gOrigCommentTabManagerConfigSegmentedControl(self, _cmd, segmentedControl);
    }
    if (DYYYHideCommentViewsEnabled()) {
        DYYYHideCommentPanelSegmentedControlView((UIView *)segmentedControl);
    }
}

static BOOL DYYYInstallCommentTabServiceHooks(void) {
    Class cls = NSClassFromString(kDYYYCommentTabServiceClassName);
    if (!cls) {
        return NO;
    }

    BOOL multiTabsOK = DYYYInstallClassHook(cls,
                                            @selector(multiTabs:),
                                            (IMP)DYYYCommentTabServiceMultiTabs,
                                            (IMP *)&gOrigCommentTabServiceMultiTabs,
                                            NO,
                                            YES);
    BOOL containsOK = DYYYInstallClassHook(cls,
                                           @selector(containsTab:type:),
                                           (IMP)DYYYCommentTabServiceContainsTab,
                                           (IMP *)&gOrigCommentTabServiceContainsTab,
                                           NO,
                                           YES);
    return multiTabsOK || containsOK;
}

static BOOL DYYYInstallCommentTabManagerHooks(void) {
    Class cls = NSClassFromString(kDYYYCommentTabManagerClassName);
    if (!cls) {
        cls = objc_getClass("_TtC27AWECommentPanelTabSwiftImpl17CommentTabManager");
    }
    if (!cls) {
        return NO;
    }

    BOOL containsOK = DYYYInstallClassHook(cls,
                                           @selector(containsTab:),
                                           (IMP)DYYYCommentTabManagerContainsTab,
                                           (IMP *)&gOrigCommentTabManagerContainsTab,
                                           NO,
                                           YES);
    BOOL typesOK = DYYYInstallClassHook(cls,
                                        @selector(componentTypes:),
                                        (IMP)DYYYCommentTabManagerComponentTypes,
                                        (IMP *)&gOrigCommentTabManagerComponentTypes,
                                        NO,
                                        NO);
    BOOL viewControllerOK = DYYYInstallClassHook(cls,
                                                 @selector(viewControllerForType:),
                                                 (IMP)DYYYCommentTabManagerViewControllerForType,
                                                 (IMP *)&gOrigCommentTabManagerViewControllerForType,
                                                 NO,
                                                 NO);
    BOOL segmentedOK = DYYYInstallClassHook(cls,
                                            @selector(configSegmentedControl:),
                                            (IMP)DYYYCommentTabManagerConfigSegmentedControl,
                                            (IMP *)&gOrigCommentTabManagerConfigSegmentedControl,
                                            NO,
                                            NO);
    return containsOK || typesOK || viewControllerOK || segmentedOK;
}

#pragma mark - AWECommentPanelTabBasicParams / CommentContainerInner

static id DYYYCommentPanelTabBasicParamsInit(id self, SEL _cmd, id preNode) {
    id params = nil;
    if (gOrigCommentPanelTabBasicParamsInit) {
        params = gOrigCommentPanelTabBasicParamsInit(self, _cmd, preNode);
    }
    if (DYYYHideCommentViewsEnabled() && params) {
        [params setValue:@YES forKey:@"noTabScene"];
    }
    return params;
}

static BOOL DYYYCommentPanelTabBasicParamsNoTabScene(id self, SEL _cmd) {
    if (DYYYHideCommentViewsEnabled()) {
        return YES;
    }
    if (gOrigCommentPanelTabBasicParamsNoTabScene) {
        return gOrigCommentPanelTabBasicParamsNoTabScene(self, _cmd);
    }
    return NO;
}

static double DYYYCommentContainerHeightForSegmentedControl(id self, SEL _cmd) {
    if (DYYYHideCommentViewsEnabled()) {
        return 0.0;
    }
    if (gOrigCommentContainerHeightForSegmentedControl) {
        return gOrigCommentContainerHeightForSegmentedControl(self, _cmd);
    }
    return 0.0;
}

static BOOL DYYYInstallCommentPanelTabBasicParamsHooks(void) {
    Class cls = NSClassFromString(kDYYYCommentPanelTabBasicParamsClassName);
    if (!cls) {
        return NO;
    }

    BOOL initOK = DYYYInstallClassHook(cls,
                                       @selector(initWithPreNode:),
                                       (IMP)DYYYCommentPanelTabBasicParamsInit,
                                       (IMP *)&gOrigCommentPanelTabBasicParamsInit,
                                       NO,
                                       NO);
    BOOL sceneOK = DYYYInstallClassHook(cls,
                                        @selector(noTabScene),
                                        (IMP)DYYYCommentPanelTabBasicParamsNoTabScene,
                                        (IMP *)&gOrigCommentPanelTabBasicParamsNoTabScene,
                                        NO,
                                        YES);
    return initOK || sceneOK;
}

static BOOL DYYYInstallCommentContainerInnerHooks(void) {
    BOOL installed = NO;

    Class viewControllerClass = NSClassFromString(kDYYYCommentContainerInnerViewControllerClassName);
    if (!viewControllerClass) {
        viewControllerClass = objc_getClass("_TtC33AWECommentPanelContainerSwiftImpl35CommentContainerInnerViewController");
    }
    if (viewControllerClass) {
        installed |= DYYYInstallClassHook(viewControllerClass,
                                          @selector(heightForSegmentedControl),
                                          (IMP)DYYYCommentContainerHeightForSegmentedControl,
                                          (IMP *)&gOrigCommentContainerHeightForSegmentedControl,
                                          NO,
                                          NO);
    }

    return installed;
}

#pragma mark - Extra comment tab components

static void DYYYCommentExtraTabSetNeedsUpdate(id self, SEL _cmd, BOOL needsUpdate, id completion) {
    if (DYYYHideCommentViewsEnabled()) {
        if (completion) {
            ((void (^)(void))completion)();
        }
        return;
    }

    NSValue *origValue = DYYYOriginalIMPValueForObject(gOrigCommentTabSetNeedsUpdateIMPs, self);
    DYYYSetNeedsUpdateIMP orig = origValue ? (DYYYSetNeedsUpdateIMP)origValue.pointerValue : NULL;
    if (orig) {
        orig(self, _cmd, needsUpdate, completion);
    }
}

static BOOL DYYYInstallExtraCommentTabComponentHooks(void) {
    BOOL installed = NO;
    installed |= DYYYInstallSetNeedsUpdateHookForClassName(kDYYYCommentDCFeedAIParseTabComponentClassName,
                                                           @"_TtC25AWECommentDCFeedSwiftImpl32CommentDCFeedAIParseTabComponent");
    installed |= DYYYInstallSetNeedsUpdateHookForClassName(kDYYYCommentTemplatePOITabComponentClassName,
                                                           @"_TtC22AWECommentPOISwiftImpl30CommentTemplatePOITabComponent");
    installed |= DYYYInstallSetNeedsUpdateHookForClassName(kDYYYCommentEvaluateTabComponentClassName,
                                                           @"_TtC27AWECommentCommerceSwiftImpl27CommentEvaluateTabComponent");
    installed |= DYYYInstallSetNeedsUpdateHookForClassName(kDYYYCommentProductCommentTabComponentClassName,
                                                           @"_TtC27AWECommentCommerceSwiftImpl33CommentProductCommentTabComponent");
    return installed;
}

#pragma mark - CommentTabModel title cache

static void DYYYCommentTabModelSetTitle(id self, SEL _cmd, NSString *title) {
    if (gOrigCommentTabModelSetTitle) {
        gOrigCommentTabModelSetTitle(self, _cmd, title);
    }
    if (!DYYYStringLooksLikeExtraCommentTab(title)) {
        return;
    }
    if ([self respondsToSelector:@selector(tab)]) {
        unsigned long long tabType = ((unsigned long long (*)(id, SEL))objc_msgSend)(self, @selector(tab));
        DYYYCacheHiddenCommentTabTypeIfNeeded(tabType, title);
    }
}

static void DYYYCommentContainerTabModelSetTitle(id self, SEL _cmd, NSString *title) {
    if (gOrigCommentContainerTabModelSetTitle) {
        gOrigCommentContainerTabModelSetTitle(self, _cmd, title);
    }
    if (!DYYYStringLooksLikeExtraCommentTab(title)) {
        return;
    }
    if ([self respondsToSelector:@selector(tab)]) {
        unsigned long long tabType = ((unsigned long long (*)(id, SEL))objc_msgSend)(self, @selector(tab));
        DYYYCacheHiddenCommentTabTypeIfNeeded(tabType, title);
    }
}

static BOOL DYYYInstallCommentTabModelHooks(void) {
    BOOL installed = NO;

    Class tabModelClass = NSClassFromString(kDYYYCommentTabModelClassName);
    if (!tabModelClass) {
        tabModelClass = objc_getClass("_TtC27AWECommentPanelTabSwiftImplP33_63C657C2E18159D394914B02AA302F2B15CommentTabModel");
    }
    if (tabModelClass) {
        installed |= DYYYInstallClassHook(tabModelClass,
                                          @selector(setTitle:),
                                          (IMP)DYYYCommentTabModelSetTitle,
                                          (IMP *)&gOrigCommentTabModelSetTitle,
                                          NO,
                                          NO);
    }

    Class containerTabModelClass = NSClassFromString(kDYYYCommentContainerTabModelClassName);
    if (!containerTabModelClass) {
        containerTabModelClass = objc_getClass("_TtC33AWECommentPanelContainerSwiftImpl15CommentTabModel");
    }
    if (containerTabModelClass) {
        installed |= DYYYInstallClassHook(containerTabModelClass,
                                          @selector(setTitle:),
                                          (IMP)DYYYCommentContainerTabModelSetTitle,
                                          (IMP *)&gOrigCommentContainerTabModelSetTitle,
                                          NO,
                                          NO);
    }

    return installed;
}

void DYYYStartHideCommentAIAnalysisHooks(void) {
    bool expected = false;
    if (!atomic_compare_exchange_strong(&gDYYYHideCommentAIAnalysisHooksStarted, &expected, true)) {
        return;
    }

    BOOL utilHooked = DYYYInstallFeedDoubleColumnAITabUtilHooks();
    BOOL localLifeHooked = DYYYInstallLocalLifeCommentBizServiceHooks();
    BOOL ecomHooked = DYYYInstallECModuleServiceHooks();
    BOOL basicParamsHooked = DYYYInstallCommentPanelTabBasicParamsHooks();
    BOOL containerHooked = DYYYInstallCommentContainerInnerHooks();
    BOOL serviceHooked = DYYYInstallCommentTabServiceHooks();
    BOOL managerHooked = DYYYInstallCommentTabManagerHooks();
    BOOL componentHooked = DYYYInstallExtraCommentTabComponentHooks();
    BOOL modelHooked = DYYYInstallCommentTabModelHooks();

    NSLog(@"[DYYY][RuntimeHook][HideCommentExtraTabs] 安装完成 util=%@ localLife=%@ ecom=%@ basicParams=%@ container=%@ service=%@ manager=%@ component=%@ model=%@",
          utilHooked ? @"YES" : @"NO",
          localLifeHooked ? @"YES" : @"NO",
          ecomHooked ? @"YES" : @"NO",
          basicParamsHooked ? @"YES" : @"NO",
          containerHooked ? @"YES" : @"NO",
          serviceHooked ? @"YES" : @"NO",
          managerHooked ? @"YES" : @"NO",
          componentHooked ? @"YES" : @"NO",
          modelHooked ? @"YES" : @"NO");
}
