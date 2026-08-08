#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 开启最高可用帧率：构造阶段只准备 ProMotion 门闩；App 激活后才检查
/// 屏幕能力，并调用抖音自带 `AWEProMotionFPSBooster` / 降帧控制器。
FOUNDATION_EXPORT void DYYYStartHighFPSHooks(void);

/// 设置页切换或 App 激活后应用；不会在 dylib initializer 中访问 UIKit。
FOUNDATION_EXPORT void DYYYApplyHighFPSSettingChange(BOOL enabled);

NS_ASSUME_NONNULL_END
