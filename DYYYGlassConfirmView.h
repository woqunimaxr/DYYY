#import <UIKit/UIKit.h>

@interface DYYYGlassConfirmView : UIView

@property(nonatomic, copy) void (^onCancel)(void);
@property(nonatomic, copy) void (^onConfirm)(void);

- (instancetype)initWithTitle:(NSString *)title
                      message:(NSString *)message
             cancelButtonText:(NSString *)cancelButtonText
            confirmButtonText:(NSString *)confirmButtonText;

+ (void)showWithTitle:(NSString *)title
              message:(NSString *)message
     cancelButtonText:(NSString *)cancelButtonText
    confirmButtonText:(NSString *)confirmButtonText
          cancelAction:(void (^)(void))cancelAction
         confirmAction:(void (^)(void))confirmAction;

- (void)show;
- (void)dismiss;

@end
