#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// 定义警告框操作回调类型
typedef void (^DYYYAlertActionHandler)(void);

@interface DYYYBottomAlertView : UIView

/** 标记并识别由 DYYY 创建的原生半屏弹窗，避免自定义配色影响抖音官方实例。 */
+ (void)markManagedHalfScreenViewController:(UIViewController *)viewController;
+ (BOOL)isManagedHalfScreenViewController:(UIViewController *)viewController;

/**
 * 显示带头像的警告框，支持自定义按钮文本；返回控制器实例可用于视图管理。
 * @param avatarURL 为空时不显示头像
 * @param cancelButtonText 、confirmButtonText 为空时使用默认文本
 * @param closeAction 点击关闭按钮、下滑或点击外部区域关闭时回调，为空时用 cancelAction
 */
+ (UIViewController *)showAlertWithTitle:(nullable NSString *)title
                                 message:(nullable NSString *)message
                               avatarURL:(nullable NSString *)avatarURL
                        cancelButtonText:(nullable NSString *)cancelButtonText
                       confirmButtonText:(nullable NSString *)confirmButtonText
                            cancelAction:(nullable DYYYAlertActionHandler)cancelAction
                             closeAction:(nullable DYYYAlertActionHandler)closeAction
                           confirmAction:(nullable DYYYAlertActionHandler)confirmAction;

/** 关闭警告框 */
- (void)dismiss;

@end

NS_ASSUME_NONNULL_END
