#import "DYYYGlassConfirmView.h"
#import "DYYYUtils.h"

@interface DYYYGlassConfirmView ()
@property(nonatomic, strong) UIView *backdropDimView;
@property(nonatomic, strong) UIView *contentView;
@property(nonatomic, strong) UIView *cardBackgroundView;
@property(nonatomic, strong) UIView *cardTopHighlightView;
@property(nonatomic, strong) UIView *cardBorderView;
@property(nonatomic, strong) UILabel *titleLabel;
@property(nonatomic, strong) UILabel *messageLabel;
@property(nonatomic, strong) UIButton *cancelButton;
@property(nonatomic, strong) UIButton *confirmButton;
@end

@implementation DYYYGlassConfirmView

+ (void)showWithTitle:(NSString *)title
              message:(NSString *)message
     cancelButtonText:(NSString *)cancelButtonText
    confirmButtonText:(NSString *)confirmButtonText
          cancelAction:(void (^)(void))cancelAction
         confirmAction:(void (^)(void))confirmAction {
    DYYYGlassConfirmView *dialog = [[DYYYGlassConfirmView alloc] initWithTitle:title
                                                                       message:message
                                                              cancelButtonText:cancelButtonText
                                                             confirmButtonText:confirmButtonText];
    dialog.onCancel = cancelAction;
    dialog.onConfirm = confirmAction;
    [dialog show];
}

- (UIButton *)dyyy_makePillButtonWithTitle:(NSString *)title
                                     frame:(CGRect)frame
                                  darkMode:(BOOL)isDarkMode
                                 emphasized:(BOOL)emphasized
                                    action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.frame = frame;
    button.layer.cornerRadius = CGRectGetHeight(frame) / 2.0;
    button.layer.masksToBounds = YES;
    button.layer.borderWidth = 0.5;
    button.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:isDarkMode ? 0.08 : 0.14].CGColor;
    // 参考图按钮偏深色实感，左右样式一致
    button.backgroundColor = isDarkMode ? [UIColor colorWithWhite:0 alpha:0.34]
                                        : [UIColor colorWithWhite:0 alpha:0.08];
    [button setTitle:title forState:UIControlStateNormal];
    UIColor *titleColor = isDarkMode ? [UIColor colorWithWhite:1.0 alpha:0.95] : [UIColor colorWithRed:28 / 255.0 green:28 / 255.0 blue:30 / 255.0 alpha:1.0];
    [button setTitleColor:titleColor forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    (void)emphasized;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (instancetype)initWithTitle:(NSString *)title
                      message:(NSString *)message
             cancelButtonText:(NSString *)cancelButtonText
            confirmButtonText:(NSString *)confirmButtonText {
    if (self = [super initWithFrame:UIScreen.mainScreen.bounds]) {
        BOOL isDarkMode = [DYYYUtils isDarkMode];
        self.backgroundColor = UIColor.clearColor;

        // 参考图：背景仅轻压暗，不做全屏模糊；实感主要来自卡片本体
        self.backdropDimView = [[UIView alloc] initWithFrame:self.bounds];
        self.backdropDimView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.backdropDimView.backgroundColor = [UIColor colorWithWhite:0 alpha:isDarkMode ? 0.22 : 0.14];
        self.backdropDimView.userInteractionEnabled = NO;
        [self addSubview:self.backdropDimView];

        CGFloat contentWidth = MIN(300.0, CGRectGetWidth(self.bounds) - 60.0);
        CGFloat horizontalPadding = 20.0;
        CGFloat textWidth = contentWidth - horizontalPadding * 2.0;
        UIFont *titleFont = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
        UIFont *messageFont = [UIFont systemFontOfSize:14 weight:UIFontWeightRegular];

        NSMutableParagraphStyle *messageStyle = [[NSMutableParagraphStyle alloc] init];
        messageStyle.lineSpacing = 4.0;
        messageStyle.alignment = NSTextAlignmentLeft;
        NSDictionary *messageAttributes = @{NSFontAttributeName : messageFont, NSParagraphStyleAttributeName : messageStyle};
        CGRect titleRect = [title boundingRectWithSize:CGSizeMake(textWidth, CGFLOAT_MAX)
                                               options:NSStringDrawingUsesLineFragmentOrigin
                                            attributes:@{NSFontAttributeName : titleFont}
                                               context:nil];
        CGRect messageRect = [message boundingRectWithSize:CGSizeMake(textWidth, CGFLOAT_MAX)
                                                   options:NSStringDrawingUsesLineFragmentOrigin
                                                attributes:messageAttributes
                                                   context:nil];

        CGFloat titleHeight = ceil(titleRect.size.height);
        CGFloat messageHeight = ceil(messageRect.size.height);
        CGFloat buttonHeight = 44.0;
        CGFloat buttonSpacing = 10.0;
        CGFloat cornerRadius = 26.0;
        CGFloat contentHeight = 20.0 + titleHeight + 8.0 + messageHeight + 22.0 + buttonHeight + 20.0;

        self.contentView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, contentWidth, contentHeight)];
        self.contentView.center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
        self.contentView.backgroundColor = UIColor.clearColor;
        self.contentView.layer.cornerRadius = cornerRadius;
        self.contentView.layer.shadowColor = [UIColor blackColor].CGColor;
        self.contentView.layer.shadowOpacity = isDarkMode ? 0.35 : 0.16;
        self.contentView.layer.shadowRadius = 24.0;
        self.contentView.layer.shadowOffset = CGSizeMake(0, 10.0);
        [self addSubview:self.contentView];

        // 参考图：深色高不透明度面板，背后内容仅隐约可见，文字始终清晰
        self.cardBackgroundView = [[UIView alloc] initWithFrame:self.contentView.bounds];
        self.cardBackgroundView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.cardBackgroundView.backgroundColor = isDarkMode ? [UIColor colorWithRed:44 / 255.0 green:44 / 255.0 blue:46 / 255.0 alpha:0.94]
                                                               : [UIColor colorWithRed:250 / 255.0 green:250 / 255.0 blue:252 / 255.0 alpha:0.96];
        self.cardBackgroundView.layer.cornerRadius = cornerRadius;
        self.cardBackgroundView.layer.masksToBounds = YES;
        [self.contentView addSubview:self.cardBackgroundView];

        self.cardTopHighlightView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, contentWidth, 1.0)];
        self.cardTopHighlightView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:isDarkMode ? 0.14 : 0.40];
        self.cardTopHighlightView.userInteractionEnabled = NO;
        [self.cardBackgroundView addSubview:self.cardTopHighlightView];

        self.cardBorderView = [[UIView alloc] initWithFrame:self.contentView.bounds];
        self.cardBorderView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.cardBorderView.backgroundColor = UIColor.clearColor;
        self.cardBorderView.userInteractionEnabled = NO;
        self.cardBorderView.layer.cornerRadius = cornerRadius;
        self.cardBorderView.layer.borderWidth = 0.5;
        self.cardBorderView.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:isDarkMode ? 0.16 : 0.22].CGColor;
        [self.contentView addSubview:self.cardBorderView];

        UIColor *titleColor = isDarkMode ? [UIColor colorWithWhite:1.0 alpha:0.96]
                                         : [UIColor colorWithRed:28 / 255.0 green:28 / 255.0 blue:30 / 255.0 alpha:1.0];
        UIColor *messageColor = isDarkMode ? [UIColor colorWithWhite:1.0 alpha:0.55]
                                           : [UIColor colorWithRed:99 / 255.0 green:99 / 255.0 blue:102 / 255.0 alpha:1.0];

        self.titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(horizontalPadding, 20.0, textWidth, titleHeight)];
        self.titleLabel.text = title;
        self.titleLabel.textColor = titleColor;
        self.titleLabel.font = titleFont;
        self.titleLabel.numberOfLines = 0;
        self.titleLabel.textAlignment = NSTextAlignmentLeft;
        [self.cardBackgroundView addSubview:self.titleLabel];

        self.messageLabel = [[UILabel alloc] initWithFrame:CGRectMake(horizontalPadding, CGRectGetMaxY(self.titleLabel.frame) + 8.0, textWidth, messageHeight)];
        self.messageLabel.textColor = messageColor;
        self.messageLabel.font = messageFont;
        self.messageLabel.numberOfLines = 0;
        self.messageLabel.lineBreakMode = NSLineBreakByWordWrapping;
        self.messageLabel.textAlignment = NSTextAlignmentLeft;
        self.messageLabel.attributedText = [[NSAttributedString alloc] initWithString:message attributes:messageAttributes];
        [self.cardBackgroundView addSubview:self.messageLabel];

        CGFloat buttonY = CGRectGetMaxY(self.messageLabel.frame) + 22.0;
        CGFloat buttonWidth = (contentWidth - horizontalPadding * 2.0 - buttonSpacing) / 2.0;

        self.cancelButton = [self dyyy_makePillButtonWithTitle:cancelButtonText.length > 0 ? cancelButtonText : @"取消"
                                                         frame:CGRectMake(horizontalPadding, buttonY, buttonWidth, buttonHeight)
                                                      darkMode:isDarkMode
                                                    emphasized:NO
                                                        action:@selector(cancelTapped)];
        [self.cardBackgroundView addSubview:self.cancelButton];

        self.confirmButton = [self dyyy_makePillButtonWithTitle:confirmButtonText.length > 0 ? confirmButtonText : @"确定"
                                                          frame:CGRectMake(horizontalPadding + buttonWidth + buttonSpacing, buttonY, buttonWidth, buttonHeight)
                                                       darkMode:isDarkMode
                                                     emphasized:YES
                                                         action:@selector(confirmTapped)];
        [self.cardBackgroundView addSubview:self.confirmButton];

        [DYYYUtils prepareModalOverlayView:self contentView:self.contentView];
    }
    return self;
}

- (void)show {
    UIWindow *window = [DYYYUtils getActiveWindow];
    if (!window) {
        window = UIApplication.sharedApplication.windows.firstObject;
    }
    if (!window) {
        return;
    }
    [window addSubview:self];
    [DYYYUtils animateModalOverlayViewIn:self contentView:self.contentView completion:nil];
}

- (void)dismiss {
    [self dismissWithCompletion:nil];
}

- (void)dismissWithCompletion:(void (^)(void))completion {
    [DYYYUtils animateModalOverlayViewOut:self
                             contentView:self.contentView
                              completion:^(__unused BOOL finished) {
                                [self removeFromSuperview];
                                if (completion) {
                                    completion();
                                }
                              }];
}

- (void)cancelTapped {
    void (^cancelAction)(void) = [self.onCancel copy];
    [self dismissWithCompletion:^{
      if (cancelAction) {
          cancelAction();
      }
    }];
}

- (void)confirmTapped {
    void (^confirmAction)(void) = [self.onConfirm copy];
    [self dismissWithCompletion:^{
      if (confirmAction) {
          confirmAction();
      }
    }];
}

@end
