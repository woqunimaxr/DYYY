#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 安装搜索页键盘 AI / 语音搜索入口的 Runtime Hook。
/// 39.8 语音仅作用于 manager 可能创建的两种搜索入口 View；
/// AI 仅作用于 `AWESearchKeyboardAISearchElement`，并保留旧版入口兼容。
/// 不扫描 UIKit 文案，也不会影响设置页、系统键盘或搜索框架外页面。
FOUNDATION_EXPORT void DYYYStartSearchKeyboardVoiceHooks(void);

NS_ASSUME_NONNULL_END
