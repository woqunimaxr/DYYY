#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface DYYYPrivacyRecordUploadGuard : NSObject

+ (BOOL)isProfileVisitRecordUploadDisabled;
+ (BOOL)isAwemeViewRecordUploadDisabled;
+ (BOOL)shouldBlockRequestObject:(nullable id)requestObject;
+ (BOOL)shouldBlockAwemeViewRecordURLString:(nullable NSString *)URLString;
+ (BOOL)markTaskForBlockingIfNeeded:(nullable id)task requestObject:(nullable id)requestObject;
+ (BOOL)isTaskMarkedForBlocking:(nullable id)task;
+ (BOOL)cancelTaskIfPossible:(nullable id)task;

@end

NS_ASSUME_NONNULL_END
