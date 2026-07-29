#import "DYYYLoginBypassManager.h"

#import "AwemeHeaders.h"
#import <objc/message.h>

static NSString *const kDYYYLoginBypassManagerEnabledKey = @"DYYYEnableLoginBypass";

typedef NS_ENUM(NSUInteger, DYYYOfficialAccountLoginState) {
    DYYYOfficialAccountLoginStateUnknown,
    DYYYOfficialAccountLoginStateLoggedOut,
    DYYYOfficialAccountLoginStateLoggedIn,
};

static NSString *dyyyLoginBypassDefaultsDomainName = nil;
static BOOL dyyyLoginBypassInitialConfigurationPending = NO;

@implementation DYYYLoginBypassManager

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
        NSLog(@"[DYYY][绕登录] 首次配置账号登录态检测异常：%@", exception.reason);
        return DYYYOfficialAccountLoginStateUnknown;
    }
}

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

+ (void)attemptInitialConfigurationWithRetryIndex:(NSUInteger)retryIndex {
    if (!dyyyLoginBypassInitialConfigurationPending || [self hasPersistentLoginBypassSetting]) {
        dyyyLoginBypassInitialConfigurationPending = NO;
        return;
    }

    DYYYOfficialAccountLoginState loginState = [self officialAccountLoginState];
    if (loginState != DYYYOfficialAccountLoginStateUnknown) {
        BOOL shouldEnable = loginState == DYYYOfficialAccountLoginStateLoggedOut;
        [NSUserDefaults.standardUserDefaults setBool:shouldEnable forKey:kDYYYLoginBypassManagerEnabledKey];
        dyyyLoginBypassInitialConfigurationPending = NO;
        NSLog(@"[DYYY][绕登录] 首次配置已完成，当前账号%@登录，绕登录已%@",
              shouldEnable ? @"未" : @"已",
              shouldEnable ? @"开启" : @"关闭");
        return;
    }

    static NSArray<NSNumber *> *retryDelays = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      retryDelays = @[ @0.2, @0.8, @2.0 ];
    });
    if (retryIndex >= retryDelays.count) {
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

      dyyyLoginBypassInitialConfigurationPending = YES;
      dispatch_async(dispatch_get_main_queue(), ^{
        [self attemptInitialConfigurationWithRetryIndex:0];
      });
    });
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

+ (BOOL)disableIfOfficialLoginIsConfirmedWithUserID:(NSString *)userID {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if (![defaults boolForKey:kDYYYLoginBypassManagerEnabledKey]) {
        return YES;
    }
    if (![self officialUserServiceConfirmsLoginWithUserID:userID]) {
        return NO;
    }

    [defaults setBool:NO forKey:kDYYYLoginBypassManagerEnabledKey];
    NSLog(@"[DYYY][绕登录] 已通过官方账号服务确认登录，自动关闭绕登录开关");
    return YES;
}

+ (void)attemptDisableWithUserID:(NSString *)userID retryIndex:(NSUInteger)retryIndex {
    if ([self disableIfOfficialLoginIsConfirmedWithUserID:userID]) {
        return;
    }

    static NSArray<NSNumber *> *retryDelays = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      retryDelays = @[ @0.2, @0.8, @2.0 ];
    });
    if (retryIndex >= retryDelays.count) {
        return;
    }

    NSTimeInterval delay = retryDelays[retryIndex].doubleValue;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      [self attemptDisableWithUserID:userID retryIndex:retryIndex + 1];
    });
}

+ (void)handleOfficialLoginCompletionWithUserID:(nullable NSString *)userID {
    if (![NSUserDefaults.standardUserDefaults boolForKey:kDYYYLoginBypassManagerEnabledKey]) {
        return;
    }

    NSString *normalizedUserID = [self normalizedUserID:userID];
    if (normalizedUserID.length == 0) {
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
      [self attemptDisableWithUserID:normalizedUserID retryIndex:0];
    });
}

@end
