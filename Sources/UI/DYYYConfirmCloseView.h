#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/** 带倒计时的自定义确认关闭弹窗。 */
@interface DYYYConfirmCloseView : UIView

@property(nonatomic, strong) UIVisualEffectView *blurView;
@property(nonatomic, strong) UIView *contentView;
@property(nonatomic, strong) UILabel *titleLabel;
@property(nonatomic, strong) UILabel *messageLabel;
@property(nonatomic, strong) UIButton *cancelButton;
@property(nonatomic, strong) UIButton *confirmButton;
@property(nonatomic, strong) UILabel *countdownLabel;
@property(nonatomic, assign) NSInteger countdown;
@property(nonatomic, strong) NSTimer *countdownTimer;

/** 初始化确认关闭弹窗 */
- (instancetype)initWithTitle:(NSString *)title message:(NSString *)message;

/** 显示弹窗 */
- (void)show;

/** 关闭弹窗 */
- (void)dismiss;

@end

NS_ASSUME_NONNULL_END
