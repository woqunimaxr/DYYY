#import <UIKit/UIKit.h>

@interface DYYYImagePickerDelegate : NSObject <UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property(nonatomic, copy) void (^completionBlock)(NSDictionary *info);
@end

@interface DYYYBackupPickerDelegate : NSObject <UIDocumentPickerDelegate>
@property(nonatomic, copy) void (^completionBlock)(NSURL *url);
@property(nonatomic, copy) NSString *tempFilePath;
@end

@interface DYYYSpeedColorPickerDelegate : NSObject <UIColorPickerViewControllerDelegate>
@property(nonatomic, copy) void (^colorChangeBlock)(UIColor *color);
@property(nonatomic, copy) void (^completionBlock)(UIColor *color);
@end
