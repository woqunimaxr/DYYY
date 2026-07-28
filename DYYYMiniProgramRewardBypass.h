#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 安装小程序激励视频的窄范围运行时适配器。
/// 安装本身与开关状态无关；所有替换函数都会实时读取设置并在关闭时透传原实现。
FOUNDATION_EXPORT void DYYYStartMiniProgramRewardBypassInstaller(void);

NS_ASSUME_NONNULL_END
