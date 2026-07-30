#import "DYYYLoginBypassManager.h"

#import "AwemeHeaders.h"
#import "DYYYUtils.h"
#import <objc/message.h>

static NSString *const kDYYYLoginBypassManagerEnabledKey = @"DYYYEnableLoginBypass";
static NSString *const kDYYYLoginBypassDisabledToast = @"检测账号登录，绕登录设置关闭";
static NSString *const kDYYYLoginBypassManualCloseToast = @"检测登录态失败，请手动关闭绕登录设置";

typedef NS_ENUM(NSUInteger, DYYYOfficialAccountLoginState) {
    DYYYOfficialAccountLoginStateUnknown,
    DYYYOfficialAccountLoginStateLoggedOut,
    DYYYOfficialAccountLoginStateLoggedIn,
};

static NSString *dyyyLoginBypassDefaultsDomainName = nil;
static BOOL dyyyLoginBypassInitialConfigurationPending = NO;
static BOOL dyyyLoginBypassDisableInFlight = NO;
static NSString *dyyyLoginBypassLastHandledUserID = nil;
static CFAbsoluteTime dyyyLoginBypassLastHandledAt = 0;

@implementation DYYYLoginBypassManager

#pragma mark - Official account helpers

+ (DYYYOfficialAccountLoginState)officialAccountLoginState {
    Class serviceClass = NSClassFromString(@"AWEUserService");
    if (!serviceClass || ![serviceClass respondsToSelector:@selector(sharedService)]) {
        return DYYYOfficialAccountLoginStateUnknown;
    }

    @try {
        AWEUserService *service = ((id (*)(id, SEL))objc_msgSend)(serviceClass, @selector(sharedService));
        if (!service || ![service respondsToSelector:@selector(isLogin)]) {
            return DYYYOfficialAccountLoginStateUnknown;
        }

        return [service isLogin] ? DYYYOfficialAccountLoginStateLoggedIn : DYYYOfficialAccountLoginStateLoggedOut;
    } @catch (NSException *exception) {
        NSLog(@"[DYYY][绕登录] 账号登录态检测异常：%@", exception.reason);
        return DYYYOfficialAccountLoginStateUnknown;
    }
}

+ (nullable NSString *)normalizedUserID:(id)value {
    NSString *userID = nil;
    if ([value isKindOfClass:NSString.class]) {
        userID = value;
    } else if ([value respondsToSelector:@selector(stringValue)]) {
        userID = [value stringValue];
    }

    userID = [userID stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (userID.length == 0 ||
        [userID rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location != NSNotFound) {
        return nil;
    }

    NSCharacterSet *nonZeroDigits = [NSCharacterSet characterSetWithCharactersInString:@"123456789"];
    return [userID rangeOfCharacterFromSet:nonZeroDigits].location == NSNotFound ? nil : userID;
}

+ (nullable NSString *)userIDFromLoginPayload:(id)userIDOrAccount {
    NSString *direct = [self normalizedUserID:userIDOrAccount];
    if (direct.length > 0) {
        return direct;
    }
    if (!userIDOrAccount) {
        return nil;
    }

    @try {
        if ([userIDOrAccount respondsToSelector:@selector(userID)]) {
            return [self normalizedUserID:[userIDOrAccount userID]];
        }
    } @catch (NSException *exception) {
        NSLog(@"[DYYY][绕登录] 解析登录载荷 UID 异常：%@", exception.reason);
    }
    return nil;
}

+ (nullable NSString *)currentOfficialUserID {
    Class serviceClass = NSClassFromString(@"AWEUserService");
    if (!serviceClass || ![serviceClass respondsToSelector:@selector(sharedService)]) {
        return nil;
    }

    @try {
        AWEUserService *service = ((id (*)(id, SEL))objc_msgSend)(serviceClass, @selector(sharedService));
        if (!service) {
            return nil;
        }

        if ([service respondsToSelector:@selector(userID)]) {
            NSString *serviceUserID = [self normalizedUserID:[service userID]];
            if (serviceUserID.length > 0) {
                return serviceUserID;
            }
        }

        if ([service respondsToSelector:@selector(currentLoginUser)]) {
            AWEUserModel *currentUser = [service currentLoginUser];
            if ([currentUser respondsToSelector:@selector(userID)]) {
                return [self normalizedUserID:[currentUser userID]];
            }
        }
    } @catch (NSException *exception) {
        NSLog(@"[DYYY][绕登录] 读取官方 UID 异常：%@", exception.reason);
    }
    return nil;
}

+ (BOOL)officialUserServiceConfirmsLoginWithUserID:(NSString *)callbackUserID {
    Class serviceClass = NSClassFromString(@"AWEUserService");
    if (!serviceClass || ![serviceClass respondsToSelector:@selector(sharedService)]) {
        return NO;
    }

    @try {
        AWEUserService *service = ((id (*)(id, SEL))objc_msgSend)(serviceClass, @selector(sharedService));
        if (!service ||
            ![service respondsToSelector:@selector(isLogin)] ||
            ![service respondsToSelector:@selector(userID)] ||
            ![service isLogin]) {
            return NO;
        }

        NSString *serviceUserID = [self normalizedUserID:[service userID]];
        NSString *modelUserID = nil;
        if ([service respondsToSelector:@selector(currentLoginUser)]) {
            AWEUserModel *currentUser = [service currentLoginUser];
            if ([currentUser respondsToSelector:@selector(userID)]) {
                modelUserID = [self normalizedUserID:[currentUser userID]];
            }
        }

        return (serviceUserID.length > 0 && [serviceUserID isEqualToString:callbackUserID]) ||
               (modelUserID.length > 0 && [modelUserID isEqualToString:callbackUserID]);
    } @catch (NSException *exception) {
        NSLog(@"[DYYY][绕登录] 官方账号服务状态校验异常：%@", exception.reason);
        return NO;
    }
}

+ (BOOL)officialUserServiceConfirmsLoginWeakly {
    if ([self officialAccountLoginState] != DYYYOfficialAccountLoginStateLoggedIn) {
        return NO;
    }
    return [self currentOfficialUserID].length > 0;
}

#pragma mark - Defaults / initial configuration

+ (BOOL)hasPersistentLoginBypassSetting {
    if (dyyyLoginBypassDefaultsDomainName.length == 0) {
        return YES;
    }

    @try {
        NSDictionary *persistentDomain =
            [NSUserDefaults.standardUserDefaults persistentDomainForName:dyyyLoginBypassDefaultsDomainName];
        return persistentDomain[kDYYYLoginBypassManagerEnabledKey] != nil;
    } @catch (NSException *exception) {
        NSLog(@"[DYYY][绕登录] 读取首次配置状态异常：%@", exception.reason);
        return YES;
    }
}

+ (void)persistLoginBypassEnabled:(BOOL)enabled {
    [NSUserDefaults.standardUserDefaults setBool:enabled forKey:kDYYYLoginBypassManagerEnabledKey];
    dyyyLoginBypassInitialConfigurationPending = NO;
}

+ (BOOL)finalizeInitialConfigurationIfPossible {
    if (!dyyyLoginBypassInitialConfigurationPending || [self hasPersistentLoginBypassSetting]) {
        dyyyLoginBypassInitialConfigurationPending = NO;
        return YES;
    }

    DYYYOfficialAccountLoginState loginState = [self officialAccountLoginState];
    if (loginState == DYYYOfficialAccountLoginStateUnknown) {
        return NO;
    }

    BOOL shouldEnable = loginState == DYYYOfficialAccountLoginStateLoggedOut;
    [self persistLoginBypassEnabled:shouldEnable];
    NSLog(@"[DYYY][绕登录] 首次配置已完成，当前账号%@登录，绕登录已%@",
          shouldEnable ? @"未" : @"已",
          shouldEnable ? @"开启" : @"关闭");
    return YES;
}

+ (void)attemptInitialConfigurationWithRetryIndex:(NSUInteger)retryIndex {
    if ([self finalizeInitialConfigurationIfPossible]) {
        return;
    }

    static NSArray<NSNumber *> *retryDelays = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      retryDelays = @[ @0.2, @0.8, @2.0 ];
    });
    if (retryIndex >= retryDelays.count) {
        NSLog(@"[DYYY][绕登录] 首次配置登录态仍未知，保持运行时默认开启");
        return;
    }

    NSTimeInterval delay = retryDelays[retryIndex].doubleValue;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      [self attemptInitialConfigurationWithRetryIndex:retryIndex + 1];
    });
}

+ (void)configureInitialStateIfNeeded {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      @try {
          dyyyLoginBypassDefaultsDomainName = NSBundle.mainBundle.bundleIdentifier.copy;
      } @catch (NSException *exception) {
          NSLog(@"[DYYY][绕登录] 获取首次配置持久化域异常：%@", exception.reason);
          return;
      }
      if (dyyyLoginBypassDefaultsDomainName.length == 0) {
          return;
      }
      if ([self hasPersistentLoginBypassSetting]) {
          return;
      }

      // 同步探测：已登录场景尽早写 NO，避免 registerDefaults=YES 造成短暂误开。
      DYYYOfficialAccountLoginState loginState = [self officialAccountLoginState];
      if (loginState == DYYYOfficialAccountLoginStateLoggedIn) {
          [self persistLoginBypassEnabled:NO];
          NSLog(@"[DYYY][绕登录] 首次同步配置：已登录，绕登录已关闭");
          return;
      }
      if (loginState == DYYYOfficialAccountLoginStateLoggedOut) {
          [self persistLoginBypassEnabled:YES];
          NSLog(@"[DYYY][绕登录] 首次同步配置：未登录，绕登录已开启");
          return;
      }

      dyyyLoginBypassInitialConfigurationPending = YES;
      dispatch_async(dispatch_get_main_queue(), ^{
        [self attemptInitialConfigurationWithRetryIndex:0];
      });
    });
}

+ (BOOL)isLoginBypassEnabled {
    if (dyyyLoginBypassInitialConfigurationPending) {
        // pending 期间每次门控复查官方态：已登录立即落盘关闭，避免伪装误开。
        if ([self finalizeInitialConfigurationIfPossible]) {
            return [NSUserDefaults.standardUserDefaults boolForKey:kDYYYLoginBypassManagerEnabledKey];
        }
        // 登录态仍未知：允许开启，保证未登录首次注入可绕过风险提示。
        return YES;
    }

    id storedValue = [NSUserDefaults.standardUserDefaults objectForKey:kDYYYLoginBypassManagerEnabledKey];
    return storedValue == nil ? YES : [storedValue boolValue];
}

#pragma mark - Toast / disable pipeline

+ (void)showToastOnMainQueue:(NSString *)text {
    if (text.length == 0) {
        return;
    }
    dispatch_block_t showBlock = ^{
      [DYYYUtils showToast:text];
    };
    if ([NSThread isMainThread]) {
        showBlock();
    } else {
        dispatch_async(dispatch_get_main_queue(), showBlock);
    }
}

+ (void)markDisablePipelineFinishedWithUserID:(nullable NSString *)userID {
    dyyyLoginBypassDisableInFlight = NO;
    dyyyLoginBypassLastHandledAt = CFAbsoluteTimeGetCurrent();
    if (userID.length > 0) {
        dyyyLoginBypassLastHandledUserID = [userID copy];
    }
}

+ (BOOL)shouldStartDisablePipelineForUserID:(nullable NSString *)userID {
    (void)userID;
    if (![self isLoginBypassEnabled]) {
        return NO;
    }

    // 双通道几乎同时回调时只启动一轮；失败后允许再次登录重试。
    if (dyyyLoginBypassDisableInFlight || (CFAbsoluteTimeGetCurrent() - dyyyLoginBypassLastHandledAt) < 2.0) {
        return NO;
    }

    dyyyLoginBypassDisableInFlight = YES;
    return YES;
}

+ (BOOL)disableIfOfficialLoginIsConfirmedWithUserID:(nullable NSString *)userID allowWeakMatch:(BOOL)allowWeakMatch {
    if (![self isLoginBypassEnabled]) {
        [self markDisablePipelineFinishedWithUserID:userID];
        return YES;
    }

    NSString *resolvedUserID = userID.length > 0 ? userID : [self currentOfficialUserID];
    BOOL confirmed = NO;
    if (resolvedUserID.length > 0) {
        confirmed = [self officialUserServiceConfirmsLoginWithUserID:resolvedUserID];
    }
    if (!confirmed && allowWeakMatch) {
        confirmed = [self officialUserServiceConfirmsLoginWeakly];
        if (confirmed && resolvedUserID.length == 0) {
            resolvedUserID = [self currentOfficialUserID];
        }
    }
    if (!confirmed) {
        return NO;
    }

    [self persistLoginBypassEnabled:NO];
    NSLog(@"[DYYY][绕登录] 已通过官方账号服务确认登录(uid=%@)，自动关闭绕登录开关", resolvedUserID ?: @"unknown");
    [self showToastOnMainQueue:kDYYYLoginBypassDisabledToast];
    [self markDisablePipelineFinishedWithUserID:resolvedUserID];
    return YES;
}

+ (void)attemptDisableWithUserID:(nullable NSString *)userID retryIndex:(NSUInteger)retryIndex {
    static NSArray<NSNumber *> *retryDelays = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      retryDelays = @[ @0.2, @0.8, @2.0 ];
    });

    BOOL isLastAttempt = retryIndex >= retryDelays.count;
    if ([self disableIfOfficialLoginIsConfirmedWithUserID:userID allowWeakMatch:isLastAttempt]) {
        return;
    }

    if (isLastAttempt) {
        NSLog(@"[DYYY][绕登录] 登录态校验失败，请手动关闭绕登录开关");
        [self showToastOnMainQueue:kDYYYLoginBypassManualCloseToast];
        [self markDisablePipelineFinishedWithUserID:userID];
        return;
    }

    NSTimeInterval delay = retryDelays[retryIndex].doubleValue;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      [self attemptDisableWithUserID:userID retryIndex:retryIndex + 1];
    });
}

+ (void)handleOfficialLoginCompletionWithUserID:(nullable id)userIDOrAccount {
    NSString *normalizedUserID = [self userIDFromLoginPayload:userIDOrAccount];
    if (normalizedUserID.length == 0) {
        normalizedUserID = [self currentOfficialUserID];
    }

    if (![self shouldStartDisablePipelineForUserID:normalizedUserID]) {
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
      [self attemptDisableWithUserID:normalizedUserID retryIndex:0];
    });
}

@end
