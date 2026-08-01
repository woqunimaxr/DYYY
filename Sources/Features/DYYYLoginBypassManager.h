#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface DYYYLoginBypassManager : NSObject

/// 首次注入时按官方登录态写入默认开关；未登录默认开，已登录默认关。
+ (void)configureInitialStateIfNeeded;

/// 运行时门控：含首次配置 pending 时对已登录态的即时抑制，避免短暂误开。
+ (BOOL)isLoginBypassEnabled;

/// 官方登录完成双通道入口（AWEUserServiceListener / TTAccountMulticast）。
+ (void)handleOfficialLoginCompletionWithUserID:(nullable id)userIDOrAccount;

@end

NS_ASSUME_NONNULL_END
