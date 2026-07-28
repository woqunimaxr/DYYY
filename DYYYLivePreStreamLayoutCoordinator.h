#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface DYYYLivePreStreamLayoutCoordinator : NSObject

+ (void)scheduleUpdateForView:(UIView *)view;
+ (void)scheduleUpdateForController:(UIViewController *)viewController;
+ (void)activateLayoutForController:(UIViewController *)viewController;
+ (void)restoreLayoutForController:(UIViewController *)viewController;

@end

NS_ASSUME_NONNULL_END
