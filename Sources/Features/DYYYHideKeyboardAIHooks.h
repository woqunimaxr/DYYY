#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 安装「隐藏键盘 AI / 语音搜索」Runtime Hook。
/// - 旧版：Hook `AWESearchKeyboardVoiceSearchEntranceView` 的 layout / setHidden / didMoveToWindow。
/// - 新版：通过 UILabel/UIButton 文案「语音搜索」定位胶囊宿主类，并 Hook 其 layout / setHidden / didMoveToWindow，
///   避免仅依赖键盘通知临时扫描或单次 layout。
/// 安装与开关无关；替换函数实时读取 `DYYYHideKeyboardAI`。
FOUNDATION_EXPORT void DYYYStartHideKeyboardAIHooks(void);

/// 预留停止接口（当前无通知观察者）。
FOUNDATION_EXPORT void DYYYStopHideKeyboardAIHooks(void);

NS_ASSUME_NONNULL_END
