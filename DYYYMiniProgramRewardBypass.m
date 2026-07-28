#import "DYYYMiniProgramRewardBypass.h"

#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <stdatomic.h>
#import <string.h>
#import <substrate.h>

static NSString *const kDYYYMiniProgramRewardEnabledKey = @"DYYYEnableMiniProgramJumpingAds";
static NSString *const kDYYYMiniProgramRewardControllerClassName = @"BDARewardedVideoAdBaseController";
static const NSTimeInterval kDYYYMiniProgramCloseDelay = 0.12;

typedef NS_ENUM(NSUInteger, DYYYMiniProgramRewardSessionState) {
    DYYYMiniProgramRewardSessionStateCreated = 0,
    DYYYMiniProgramRewardSessionStateAppeared,
    DYYYMiniProgramRewardSessionStateCloseScheduled,
    DYYYMiniProgramRewardSessionStateFinished,
};

@interface DYYYMiniProgramRewardSession : NSObject
@property(nonatomic, assign) DYYYMiniProgramRewardSessionState state;
@property(nonatomic, assign) BOOL diagnosticFailureLogged;
@end

@implementation DYYYMiniProgramRewardSession
@end

static char kDYYYMiniProgramRewardSessionKey;

static IMP dyyyOriginalSendReward = NULL;
static IMP dyyyOriginalSendFirstReward = NULL;
static IMP dyyyOriginalDisableHostSendReward = NULL;
static IMP dyyyOriginalSetSendReward = NULL;
static IMP dyyyOriginalSetSendFirstReward = NULL;
static IMP dyyyOriginalSetDisableHostSendReward = NULL;
static IMP dyyyOriginalViewDidAppear = NULL;

static BOOL dyyyMiniProgramRewardHooksInstalled = NO;
static BOOL dyyyMiniProgramRewardRetryScheduled = NO;
static NSUInteger dyyyMiniProgramRewardRetryIndex = 0;
static id dyyyMiniProgramRewardActiveObserver = nil;
static atomic_bool dyyyMiniProgramRewardHooksInstalledAtomic = false;
static atomic_bool dyyyMiniProgramRewardImageRefreshQueued = false;

static BOOL DYYYMiniProgramRewardEnabled(void) {
    return [NSUserDefaults.standardUserDefaults boolForKey:kDYYYMiniProgramRewardEnabledKey];
}

static const char *DYYYMiniProgramUnqualifiedType(const char *type) {
    if (!type) {
        return "";
    }

    while (*type && strchr("rnNoORV", *type)) {
        type++;
    }
    return type;
}

static BOOL DYYYMiniProgramTypeIsInteger(const char *type) {
    const char *unqualifiedType = DYYYMiniProgramUnqualifiedType(type);
    return unqualifiedType[0] != '\0' && strchr("BcCsSiIlLqQ", unqualifiedType[0]) != NULL;
}

static BOOL DYYYMiniProgramTypeIsVoid(const char *type) {
    return DYYYMiniProgramUnqualifiedType(type)[0] == 'v';
}

static NSMethodSignature *DYYYMiniProgramSignatureForMethod(Method method) {
    const char *encoding = method ? method_getTypeEncoding(method) : NULL;
    return encoding ? [NSMethodSignature signatureWithObjCTypes:encoding] : nil;
}

static BOOL DYYYMiniProgramMethodIsIntegerGetter(Method method) {
    NSMethodSignature *signature = DYYYMiniProgramSignatureForMethod(method);
    return signature &&
           signature.numberOfArguments == 2 &&
           DYYYMiniProgramTypeIsInteger(signature.methodReturnType);
}

static BOOL DYYYMiniProgramMethodIsIntegerSetter(Method method) {
    NSMethodSignature *signature = DYYYMiniProgramSignatureForMethod(method);
    return signature &&
           signature.numberOfArguments == 3 &&
           DYYYMiniProgramTypeIsVoid(signature.methodReturnType) &&
           DYYYMiniProgramTypeIsInteger([signature getArgumentTypeAtIndex:2]);
}

static BOOL DYYYMiniProgramMethodIsViewDidAppear(Method method) {
    NSMethodSignature *signature = DYYYMiniProgramSignatureForMethod(method);
    return signature &&
           signature.numberOfArguments == 3 &&
           DYYYMiniProgramTypeIsVoid(signature.methodReturnType) &&
           DYYYMiniProgramTypeIsInteger([signature getArgumentTypeAtIndex:2]);
}

static BOOL DYYYMiniProgramMethodIsVoidWithoutArguments(Method method) {
    NSMethodSignature *signature = DYYYMiniProgramSignatureForMethod(method);
    return signature &&
           signature.numberOfArguments == 2 &&
           DYYYMiniProgramTypeIsVoid(signature.methodReturnType);
}

static BOOL DYYYMiniProgramClassIsSubclassOfClass(Class cls, Class expectedSuperclass) {
    if (!cls || !expectedSuperclass) {
        return NO;
    }

    for (Class currentClass = cls; currentClass; currentClass = class_getSuperclass(currentClass)) {
        if (currentClass == expectedSuperclass) {
            return YES;
        }
    }
    return NO;
}

static DYYYMiniProgramRewardSession *DYYYMiniProgramSessionForController(id controller, BOOL createIfNeeded) {
    if (!controller) {
        return nil;
    }

    DYYYMiniProgramRewardSession *session = objc_getAssociatedObject(controller, &kDYYYMiniProgramRewardSessionKey);
    if (!session && createIfNeeded) {
        session = [DYYYMiniProgramRewardSession new];
        session.state = DYYYMiniProgramRewardSessionStateCreated;
        objc_setAssociatedObject(controller,
                                 &kDYYYMiniProgramRewardSessionKey,
                                 session,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return session;
}

static BOOL DYYYMiniProgramReadIntegerGetter(id object, SEL selector, NSInteger *value) {
    if (!object || !selector || ![object respondsToSelector:selector]) {
        return NO;
    }

    Method method = class_getInstanceMethod(object_getClass(object), selector);
    if (!DYYYMiniProgramMethodIsIntegerGetter(method)) {
        return NO;
    }

    if (value) {
        *value = ((NSInteger (*)(id, SEL))objc_msgSend)(object, selector);
    }
    return YES;
}

static BOOL DYYYMiniProgramWriteIntegerSetter(id object, SEL selector, NSInteger value) {
    if (!object || !selector || ![object respondsToSelector:selector]) {
        return NO;
    }

    Method method = class_getInstanceMethod(object_getClass(object), selector);
    if (!DYYYMiniProgramMethodIsIntegerSetter(method)) {
        return NO;
    }

    ((void (*)(id, SEL, NSInteger))objc_msgSend)(object, selector, value);
    return YES;
}

static BOOL DYYYMiniProgramPrepareLocalRewardState(id controller) {
    @try {
        DYYYMiniProgramWriteIntegerSetter(controller, NSSelectorFromString(@"setDisableHostSendReward:"), 0);
        DYYYMiniProgramWriteIntegerSetter(controller, NSSelectorFromString(@"setSendReward:"), 1);
        DYYYMiniProgramWriteIntegerSetter(controller, NSSelectorFromString(@"setSendFirstReward:"), 1);

        NSInteger sendReward = 0;
        NSInteger sendFirstReward = 0;
        if (!DYYYMiniProgramReadIntegerGetter(controller, NSSelectorFromString(@"sendReward"), &sendReward) ||
            !DYYYMiniProgramReadIntegerGetter(controller, NSSelectorFromString(@"sendFirstReward"), &sendFirstReward)) {
            return NO;
        }

        NSInteger disableHostSendReward = 0;
        BOOL hasDisableHostSendReward =
            DYYYMiniProgramReadIntegerGetter(controller,
                                             NSSelectorFromString(@"disableHostSendReward"),
                                             &disableHostSendReward);
        return sendReward != 0 &&
               sendFirstReward != 0 &&
               (!hasDisableHostSendReward || disableHostSendReward == 0);
    } @catch (NSException *exception) {
        NSLog(@"[DYYY][小程序跳广告] 奖励状态校验异常：%@", exception.reason);
        return NO;
    }
}

static BOOL DYYYMiniProgramControllerIsVisible(id controller) {
    if (![controller isKindOfClass:UIViewController.class]) {
        return NO;
    }

    UIViewController *viewController = controller;
    return viewController.isViewLoaded && viewController.view.window != nil;
}

static BOOL DYYYMiniProgramCloseController(id controller) {
    SEL closeSelector = NSSelectorFromString(@"close");
    if (!controller || ![controller respondsToSelector:closeSelector]) {
        return NO;
    }

    Method closeMethod = class_getInstanceMethod(object_getClass(controller), closeSelector);
    if (!DYYYMiniProgramMethodIsVoidWithoutArguments(closeMethod)) {
        return NO;
    }

    @try {
        ((void (*)(id, SEL))objc_msgSend)(controller, closeSelector);
        return YES;
    } @catch (NSException *exception) {
        NSLog(@"[DYYY][小程序跳广告] 关闭广告控制器异常：%@", exception.reason);
        return NO;
    }
}

static void DYYYMiniProgramScheduleClose(id controller) {
    if (!controller || !DYYYMiniProgramRewardEnabled()) {
        return;
    }

    DYYYMiniProgramRewardSession *session = DYYYMiniProgramSessionForController(controller, YES);
    @synchronized(session) {
        if (session.state == DYYYMiniProgramRewardSessionStateCloseScheduled ||
            session.state == DYYYMiniProgramRewardSessionStateFinished) {
            return;
        }
        session.state = DYYYMiniProgramRewardSessionStateAppeared;
    }

    if (!DYYYMiniProgramPrepareLocalRewardState(controller)) {
        @synchronized(session) {
            if (!session.diagnosticFailureLogged) {
                session.diagnosticFailureLogged = YES;
                NSLog(@"[DYYY][小程序跳广告] 本地奖励状态未确认，保留原广告流程：%@",
                      NSStringFromClass([controller class]));
            }
        }
        return;
    }

    @synchronized(session) {
        if (session.state == DYYYMiniProgramRewardSessionStateFinished) {
            return;
        }
        session.state = DYYYMiniProgramRewardSessionStateCloseScheduled;
    }

    __weak id weakController = controller;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                 (int64_t)(kDYYYMiniProgramCloseDelay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
      id strongController = weakController;
      if (!strongController) {
          return;
      }

      DYYYMiniProgramRewardSession *strongSession =
          DYYYMiniProgramSessionForController(strongController, NO);
      if (!strongSession) {
          return;
      }

      @synchronized(strongSession) {
          if (strongSession.state != DYYYMiniProgramRewardSessionStateCloseScheduled) {
              return;
          }
          if (!DYYYMiniProgramRewardEnabled()) {
              strongSession.state = DYYYMiniProgramRewardSessionStateAppeared;
              return;
          }
      }

      if (!DYYYMiniProgramControllerIsVisible(strongController) ||
          !DYYYMiniProgramPrepareLocalRewardState(strongController)) {
          @synchronized(strongSession) {
              strongSession.state = DYYYMiniProgramRewardSessionStateAppeared;
          }
          return;
      }

      BOOL closed = DYYYMiniProgramCloseController(strongController);
      @synchronized(strongSession) {
          strongSession.state = closed
                                    ? DYYYMiniProgramRewardSessionStateFinished
                                    : DYYYMiniProgramRewardSessionStateAppeared;
      }
      if (closed) {
          NSLog(@"[DYYY][小程序跳广告] 已确认本地奖励状态并关闭广告控制器：%@",
                NSStringFromClass([strongController class]));
      }
    });
}

static NSInteger DYYYMiniProgramSendReward(id self, SEL _cmd) {
    if (DYYYMiniProgramRewardEnabled()) {
        return 1;
    }
    return dyyyOriginalSendReward
               ? ((NSInteger (*)(id, SEL))dyyyOriginalSendReward)(self, _cmd)
               : 0;
}

static NSInteger DYYYMiniProgramSendFirstReward(id self, SEL _cmd) {
    if (DYYYMiniProgramRewardEnabled()) {
        return 1;
    }
    return dyyyOriginalSendFirstReward
               ? ((NSInteger (*)(id, SEL))dyyyOriginalSendFirstReward)(self, _cmd)
               : 0;
}

static NSInteger DYYYMiniProgramDisableHostSendReward(id self, SEL _cmd) {
    if (DYYYMiniProgramRewardEnabled()) {
        return 0;
    }
    return dyyyOriginalDisableHostSendReward
               ? ((NSInteger (*)(id, SEL))dyyyOriginalDisableHostSendReward)(self, _cmd)
               : 0;
}

static void DYYYMiniProgramSetSendReward(id self, SEL _cmd, NSInteger value) {
    if (DYYYMiniProgramRewardEnabled()) {
        value = 1;
    }
    if (dyyyOriginalSetSendReward) {
        ((void (*)(id, SEL, NSInteger))dyyyOriginalSetSendReward)(self, _cmd, value);
    }
}

static void DYYYMiniProgramSetSendFirstReward(id self, SEL _cmd, NSInteger value) {
    if (DYYYMiniProgramRewardEnabled()) {
        value = 1;
    }
    if (dyyyOriginalSetSendFirstReward) {
        ((void (*)(id, SEL, NSInteger))dyyyOriginalSetSendFirstReward)(self, _cmd, value);
    }
}

static void DYYYMiniProgramSetDisableHostSendReward(id self, SEL _cmd, NSInteger value) {
    if (DYYYMiniProgramRewardEnabled()) {
        value = 0;
    }
    if (dyyyOriginalSetDisableHostSendReward) {
        ((void (*)(id, SEL, NSInteger))dyyyOriginalSetDisableHostSendReward)(self, _cmd, value);
    }
}

static void DYYYMiniProgramViewDidAppear(id self, SEL _cmd, BOOL animated) {
    if (dyyyOriginalViewDidAppear) {
        ((void (*)(id, SEL, BOOL))dyyyOriginalViewDidAppear)(self, _cmd, animated);
    }

    if (!DYYYMiniProgramRewardEnabled()) {
        return;
    }

    @try {
        DYYYMiniProgramScheduleClose(self);
    } @catch (NSException *exception) {
        NSLog(@"[DYYY][小程序跳广告] 广告生命周期处理异常：%@", exception.reason);
    }
}

typedef BOOL (*DYYYMiniProgramMethodValidator)(Method method);

static BOOL DYYYMiniProgramInstallHook(Class cls,
                                       SEL selector,
                                       IMP replacement,
                                       IMP *original,
                                       DYYYMiniProgramMethodValidator validator,
                                       BOOL required) {
    Method method = cls && selector ? class_getInstanceMethod(cls, selector) : NULL;
    if (!method) {
        if (required) {
            NSLog(@"[DYYY][小程序跳广告] 缺少必要方法：%@ %@",
                  NSStringFromClass(cls),
                  NSStringFromSelector(selector));
        }
        return NO;
    }

    if (!validator(method)) {
        NSLog(@"[DYYY][小程序跳广告] 方法签名不兼容，跳过 Hook：%@ %@ (%s)",
              NSStringFromClass(cls),
              NSStringFromSelector(selector),
              method_getTypeEncoding(method));
        return NO;
    }

    IMP currentImplementation = method_getImplementation(method);
    if (currentImplementation == replacement) {
        return original && *original != NULL;
    }

    IMP previousImplementation = NULL;
    MSHookMessageEx(cls, selector, replacement, &previousImplementation);
    if (!previousImplementation || previousImplementation == replacement) {
        NSLog(@"[DYYY][小程序跳广告] 无法保存原 IMP，停止使用：%@ %@",
              NSStringFromClass(cls),
              NSStringFromSelector(selector));
        return NO;
    }

    *original = previousImplementation;
    return YES;
}

static BOOL DYYYMiniProgramValidateControllerClass(Class cls) {
    if (!DYYYMiniProgramClassIsSubclassOfClass(cls, UIViewController.class)) {
        NSLog(@"[DYYY][小程序跳广告] 目标类不是 UIViewController 子类：%@",
              NSStringFromClass(cls));
        return NO;
    }

    Method sendRewardMethod = class_getInstanceMethod(cls, NSSelectorFromString(@"sendReward"));
    Method sendFirstRewardMethod = class_getInstanceMethod(cls, NSSelectorFromString(@"sendFirstReward"));
    Method viewDidAppearMethod = class_getInstanceMethod(cls, @selector(viewDidAppear:));
    Method closeMethod = class_getInstanceMethod(cls, NSSelectorFromString(@"close"));
    return DYYYMiniProgramMethodIsIntegerGetter(sendRewardMethod) &&
           DYYYMiniProgramMethodIsIntegerGetter(sendFirstRewardMethod) &&
           DYYYMiniProgramMethodIsViewDidAppear(viewDidAppearMethod) &&
           DYYYMiniProgramMethodIsVoidWithoutArguments(closeMethod);
}

static BOOL DYYYMiniProgramInstallControllerHooks(Class cls) {
    if (!DYYYMiniProgramValidateControllerClass(cls)) {
        NSLog(@"[DYYY][小程序跳广告] 核心方法不完整或签名不匹配，保持原流程：%@",
              NSStringFromClass(cls));
        return NO;
    }

    BOOL sendRewardInstalled =
        DYYYMiniProgramInstallHook(cls,
                                   NSSelectorFromString(@"sendReward"),
                                   (IMP)DYYYMiniProgramSendReward,
                                   &dyyyOriginalSendReward,
                                   DYYYMiniProgramMethodIsIntegerGetter,
                                   YES);
    BOOL sendFirstRewardInstalled =
        DYYYMiniProgramInstallHook(cls,
                                   NSSelectorFromString(@"sendFirstReward"),
                                   (IMP)DYYYMiniProgramSendFirstReward,
                                   &dyyyOriginalSendFirstReward,
                                   DYYYMiniProgramMethodIsIntegerGetter,
                                   YES);
    BOOL viewDidAppearInstalled =
        DYYYMiniProgramInstallHook(cls,
                                   @selector(viewDidAppear:),
                                   (IMP)DYYYMiniProgramViewDidAppear,
                                   &dyyyOriginalViewDidAppear,
                                   DYYYMiniProgramMethodIsViewDidAppear,
                                   YES);
    if (!sendRewardInstalled || !sendFirstRewardInstalled || !viewDidAppearInstalled) {
        return NO;
    }

    DYYYMiniProgramInstallHook(cls,
                               NSSelectorFromString(@"disableHostSendReward"),
                               (IMP)DYYYMiniProgramDisableHostSendReward,
                               &dyyyOriginalDisableHostSendReward,
                               DYYYMiniProgramMethodIsIntegerGetter,
                               NO);
    DYYYMiniProgramInstallHook(cls,
                               NSSelectorFromString(@"setSendReward:"),
                               (IMP)DYYYMiniProgramSetSendReward,
                               &dyyyOriginalSetSendReward,
                               DYYYMiniProgramMethodIsIntegerSetter,
                               NO);
    DYYYMiniProgramInstallHook(cls,
                               NSSelectorFromString(@"setSendFirstReward:"),
                               (IMP)DYYYMiniProgramSetSendFirstReward,
                               &dyyyOriginalSetSendFirstReward,
                               DYYYMiniProgramMethodIsIntegerSetter,
                               NO);
    DYYYMiniProgramInstallHook(cls,
                               NSSelectorFromString(@"setDisableHostSendReward:"),
                               (IMP)DYYYMiniProgramSetDisableHostSendReward,
                               &dyyyOriginalSetDisableHostSendReward,
                               DYYYMiniProgramMethodIsIntegerSetter,
                               NO);

    NSLog(@"[DYYY][小程序跳广告] 已安装窄核心：%@", NSStringFromClass(cls));
    return YES;
}

static NSArray<NSNumber *> *DYYYMiniProgramRewardRetryDelays(void) {
    static NSArray<NSNumber *> *delays = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      delays = @[ @0.5, @1.0, @2.0, @4.0, @8.0, @15.0 ];
    });
    return delays;
}

static void DYYYMiniProgramAttemptInstall(void);

static void DYYYMiniProgramScheduleRetryIfNeeded(void) {
    if (dyyyMiniProgramRewardHooksInstalled || dyyyMiniProgramRewardRetryScheduled) {
        return;
    }

    NSArray<NSNumber *> *delays = DYYYMiniProgramRewardRetryDelays();
    if (dyyyMiniProgramRewardRetryIndex >= delays.count) {
        return;
    }

    NSTimeInterval delay = delays[dyyyMiniProgramRewardRetryIndex++].doubleValue;
    dyyyMiniProgramRewardRetryScheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
      dyyyMiniProgramRewardRetryScheduled = NO;
      DYYYMiniProgramAttemptInstall();
    });
}

static void DYYYMiniProgramAttemptInstall(void) {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
          DYYYMiniProgramAttemptInstall();
        });
        return;
    }
    if (dyyyMiniProgramRewardHooksInstalled) {
        return;
    }

    Class controllerClass = NSClassFromString(kDYYYMiniProgramRewardControllerClassName);
    if (controllerClass) {
        dyyyMiniProgramRewardHooksInstalled =
            DYYYMiniProgramInstallControllerHooks(controllerClass);
        if (dyyyMiniProgramRewardHooksInstalled) {
            atomic_store_explicit(&dyyyMiniProgramRewardHooksInstalledAtomic,
                                  true,
                                  memory_order_release);
        }
    }
    if (!dyyyMiniProgramRewardHooksInstalled) {
        DYYYMiniProgramScheduleRetryIfNeeded();
    }
}

static void DYYYMiniProgramPerformDeferredImageRefresh(__unused void *context) {
    atomic_store_explicit(&dyyyMiniProgramRewardImageRefreshQueued, false, memory_order_release);
    DYYYMiniProgramAttemptInstall();
}

static void DYYYMiniProgramImageAdded(__unused const struct mach_header *header,
                                      __unused intptr_t slide) {
    if (atomic_load_explicit(&dyyyMiniProgramRewardHooksInstalledAtomic,
                             memory_order_acquire)) {
        return;
    }

    if (!atomic_exchange_explicit(&dyyyMiniProgramRewardImageRefreshQueued,
                                  true,
                                  memory_order_acq_rel)) {
        // dyld 回调中不访问 Objective-C Runtime，也不等待主线程。
        dispatch_async_f(dispatch_get_main_queue(), NULL, DYYYMiniProgramPerformDeferredImageRefresh);
    }
}

void DYYYStartMiniProgramRewardBypassInstaller(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      void (^startInstaller)(void) = ^{
        DYYYMiniProgramAttemptInstall();
        dyyyMiniProgramRewardActiveObserver =
            [NSNotificationCenter.defaultCenter
                addObserverForName:UIApplicationDidBecomeActiveNotification
                            object:nil
                             queue:NSOperationQueue.mainQueue
                        usingBlock:^(__unused NSNotification *notification) {
                          dyyyMiniProgramRewardRetryIndex = 0;
                          DYYYMiniProgramAttemptInstall();
                        }];

        // 避开启动关键路径：只有目标类尚未出现时，才在后台延迟注册 dyld
        // 回调。回调本身只做原子合并和无等待的主队列投递。
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                       dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
          if (!atomic_load_explicit(&dyyyMiniProgramRewardHooksInstalledAtomic,
                                    memory_order_acquire)) {
              _dyld_register_func_for_add_image(DYYYMiniProgramImageAdded);
          }
        });
      };

      if (NSThread.isMainThread) {
          startInstaller();
      } else {
          dispatch_async(dispatch_get_main_queue(), startInstaller);
      }
    });
}
