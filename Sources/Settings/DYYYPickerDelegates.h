#import <UIKit/UIKit.h>

@interface DYYYImagePickerDelegate : NSObject <UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property(nonatomic, copy) void (^completionBlock)(NSDictionary *info);
@end

@interface DYYYBackupPickerDelegate : NSObject <UIDocumentPickerDelegate>
@property(nonatomic, copy) void (^completionBlock)(NSURL *url);
@property(nonatomic, copy) NSString *tempFilePath;
@end
