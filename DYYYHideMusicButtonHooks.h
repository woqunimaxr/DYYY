#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 安装「隐藏音乐按钮」Runtime Hook。
/// 覆盖经典音乐封面、ListenFeed、StyleOne/StyleTwo「拍同款」音乐位，
/// 以及默认静音场景下的「取消静音」锚点（`AFDCancelMuteAwemeView`）。
/// 安装与开关无关；替换函数实时读取设置，关闭时透传原实现。
FOUNDATION_EXPORT void DYYYStartHideMusicButtonHooks(void);

NS_ASSUME_NONNULL_END
