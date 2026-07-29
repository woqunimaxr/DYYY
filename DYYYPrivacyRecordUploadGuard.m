#import "DYYYPrivacyRecordUploadGuard.h"

#import <objc/message.h>
#import <objc/runtime.h>

#import "AwemeHeaders.h"

typedef NS_ENUM(NSUInteger, DYYYPrivacyRecordUploadKind) {
    DYYYPrivacyRecordUploadKindNone,
    DYYYPrivacyRecordUploadKindProfileVisit,
    DYYYPrivacyRecordUploadKindAwemeView,
};

typedef NS_OPTIONS(NSUInteger, DYYYPrivacyRecordUploadMask) {
    DYYYPrivacyRecordUploadMaskNone = 0,
    DYYYPrivacyRecordUploadMaskProfileVisit = 1 << 0,
    DYYYPrivacyRecordUploadMaskAwemeView = 1 << 1,
};

static NSString *const kDYYYDisableProfileVisitRecordUploadKey = @"DYYYDisableProfileVisitRecordUpload";
static NSString *const kDYYYDisableAwemeViewRecordUploadKey = @"DYYYDisableAwemeViewRecordUpload";
static NSString *const kDYYYProfileVisitRecordUploadPath = @"/aweme/v1/profile/record";
static NSString *const kDYYYAwemeViewRecordUploadPath = @"/aweme/v1/familiar/video/stats";
static const void *kDYYYPrivacyRecordUploadBlockedTaskKey = &kDYYYPrivacyRecordUploadBlockedTaskKey;

@interface DYYYPrivacyRecordUploadGuard ()

+ (DYYYPrivacyRecordUploadMask)enabledUploadMask;
+ (BOOL)shouldBlockUploadKind:(DYYYPrivacyRecordUploadKind)kind enabledMask:(DYYYPrivacyRecordUploadMask)enabledMask;
+ (DYYYPrivacyRecordUploadKind)uploadKindForURLString:(nullable NSString *)URLString;
+ (nullable NSString *)normalizedPathFromURLString:(nullable NSString *)URLString;
+ (nullable id)valueForSelector:(SEL)selector fromObject:(nullable id)object;
+ (BOOL)objectContainsBlockedUpload:(nullable id)object
                        enabledMask:(DYYYPrivacyRecordUploadMask)enabledMask
                              depth:(NSUInteger)depth
                            visited:(NSMutableSet<NSValue *> *)visited;
+ (BOOL)collectionContainsBlockedUpload:(nullable id)collection
                            enabledMask:(DYYYPrivacyRecordUploadMask)enabledMask
                                  depth:(NSUInteger)depth
                                visited:(NSMutableSet<NSValue *> *)visited;

@end

@implementation DYYYPrivacyRecordUploadGuard

+ (BOOL)isProfileVisitRecordUploadDisabled {
    return DYYYGetBool(kDYYYDisableProfileVisitRecordUploadKey);
}

+ (BOOL)isAwemeViewRecordUploadDisabled {
    return DYYYGetBool(kDYYYDisableAwemeViewRecordUploadKey);
}

+ (BOOL)shouldBlockRequestObject:(id)requestObject {
    DYYYPrivacyRecordUploadMask enabledMask = [self enabledUploadMask];
    if (enabledMask == DYYYPrivacyRecordUploadMaskNone || !requestObject) {
        return NO;
    }

    NSMutableSet<NSValue *> *visited = [NSMutableSet set];
    return [self objectContainsBlockedUpload:requestObject
                                 enabledMask:enabledMask
                                       depth:0
                                     visited:visited];
}

+ (BOOL)shouldBlockAwemeViewRecordURLString:(NSString *)URLString {
    return [self isAwemeViewRecordUploadDisabled] &&
           [self uploadKindForURLString:URLString] == DYYYPrivacyRecordUploadKindAwemeView;
}

+ (BOOL)markTaskForBlockingIfNeeded:(id)task requestObject:(id)requestObject {
    if (!task || ![self shouldBlockRequestObject:requestObject]) {
        return NO;
    }

    objc_setAssociatedObject(task,
                             kDYYYPrivacyRecordUploadBlockedTaskKey,
                             @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return YES;
}

+ (BOOL)isTaskMarkedForBlocking:(id)task {
    if (!task) {
        return NO;
    }

    id marker = objc_getAssociatedObject(task, kDYYYPrivacyRecordUploadBlockedTaskKey);
    return [marker respondsToSelector:@selector(boolValue)] && [marker boolValue];
}

+ (BOOL)cancelTaskIfPossible:(id)task {
    SEL cancelSelector = @selector(cancel);
    if (!task || ![task respondsToSelector:cancelSelector]) {
        return NO;
    }

    @try {
        ((void (*)(id, SEL))objc_msgSend)(task, cancelSelector);
        return YES;
    } @catch (__unused NSException *exception) {
        return NO;
    }
}

#pragma mark - URL 识别

+ (DYYYPrivacyRecordUploadMask)enabledUploadMask {
    DYYYPrivacyRecordUploadMask enabledMask = DYYYPrivacyRecordUploadMaskNone;
    if ([self isProfileVisitRecordUploadDisabled]) {
        enabledMask |= DYYYPrivacyRecordUploadMaskProfileVisit;
    }
    if ([self isAwemeViewRecordUploadDisabled]) {
        enabledMask |= DYYYPrivacyRecordUploadMaskAwemeView;
    }
    return enabledMask;
}

+ (BOOL)shouldBlockUploadKind:(DYYYPrivacyRecordUploadKind)kind enabledMask:(DYYYPrivacyRecordUploadMask)enabledMask {
    switch (kind) {
        case DYYYPrivacyRecordUploadKindProfileVisit:
            return (enabledMask & DYYYPrivacyRecordUploadMaskProfileVisit) != 0;
        case DYYYPrivacyRecordUploadKindAwemeView:
            return (enabledMask & DYYYPrivacyRecordUploadMaskAwemeView) != 0;
        case DYYYPrivacyRecordUploadKindNone:
            return NO;
    }
    return NO;
}

+ (DYYYPrivacyRecordUploadKind)uploadKindForURLString:(NSString *)URLString {
    if (![URLString isKindOfClass:NSString.class] || URLString.length == 0) {
        return DYYYPrivacyRecordUploadKindNone;
    }

    BOOL mayBeProfileVisit = [URLString containsString:kDYYYProfileVisitRecordUploadPath];
    BOOL mayBeAwemeView = [URLString containsString:kDYYYAwemeViewRecordUploadPath];
    if (!mayBeProfileVisit && !mayBeAwemeView) {
        return DYYYPrivacyRecordUploadKindNone;
    }

    NSString *path = [self normalizedPathFromURLString:URLString];
    if (mayBeProfileVisit && [path isEqualToString:kDYYYProfileVisitRecordUploadPath]) {
        return DYYYPrivacyRecordUploadKindProfileVisit;
    }
    if (mayBeAwemeView && [path isEqualToString:kDYYYAwemeViewRecordUploadPath]) {
        return DYYYPrivacyRecordUploadKindAwemeView;
    }
    return DYYYPrivacyRecordUploadKindNone;
}

+ (NSString *)normalizedPathFromURLString:(NSString *)URLString {
    if (![URLString isKindOfClass:NSString.class]) {
        return nil;
    }

    NSString *trimmedURLString = [URLString stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmedURLString.length == 0) {
        return nil;
    }

    NSURLComponents *components = [NSURLComponents componentsWithString:trimmedURLString];
    NSString *path = components.path;
    if (path.length == 0 && [trimmedURLString hasPrefix:@"/"]) {
        NSRange queryRange = [trimmedURLString rangeOfString:@"?"];
        NSRange fragmentRange = [trimmedURLString rangeOfString:@"#"];
        NSUInteger endIndex = trimmedURLString.length;
        if (queryRange.location != NSNotFound) {
            endIndex = MIN(endIndex, queryRange.location);
        }
        if (fragmentRange.location != NSNotFound) {
            endIndex = MIN(endIndex, fragmentRange.location);
        }
        path = [trimmedURLString substringToIndex:endIndex];
    }

    if (![path hasPrefix:@"/"]) {
        return nil;
    }

    while (path.length > 1 && [path hasSuffix:@"/"]) {
        path = [path substringToIndex:path.length - 1];
    }
    return path;
}

+ (id)valueForSelector:(SEL)selector fromObject:(id)object {
    if (!object || !selector || ![object respondsToSelector:selector]) {
        return nil;
    }

    Method method = class_getInstanceMethod(object_getClass(object), selector);
    if (!method || method_getNumberOfArguments(method) != 2) {
        return nil;
    }

    char returnType[16] = {0};
    method_getReturnType(method, returnType, sizeof(returnType));
    const char *unqualifiedReturnType = returnType;
    while (*unqualifiedReturnType == 'r' ||
           *unqualifiedReturnType == 'n' ||
           *unqualifiedReturnType == 'N' ||
           *unqualifiedReturnType == 'o' ||
           *unqualifiedReturnType == 'O' ||
           *unqualifiedReturnType == 'R' ||
           *unqualifiedReturnType == 'V') {
        unqualifiedReturnType++;
    }
    if (*unqualifiedReturnType != '@') {
        return nil;
    }

    @try {
        return ((id (*)(id, SEL))objc_msgSend)(object, selector);
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

+ (BOOL)objectContainsBlockedUpload:(id)object
                        enabledMask:(DYYYPrivacyRecordUploadMask)enabledMask
                              depth:(NSUInteger)depth
                            visited:(NSMutableSet<NSValue *> *)visited {
    if (!object || depth > 8) {
        return NO;
    }

    if ([object isKindOfClass:NSString.class]) {
        DYYYPrivacyRecordUploadKind kind = [self uploadKindForURLString:(NSString *)object];
        return [self shouldBlockUploadKind:kind enabledMask:enabledMask];
    }
    if ([object isKindOfClass:NSURL.class]) {
        DYYYPrivacyRecordUploadKind kind = [self uploadKindForURLString:[(NSURL *)object absoluteString]];
        return [self shouldBlockUploadKind:kind enabledMask:enabledMask];
    }
    if ([object isKindOfClass:NSURLRequest.class]) {
        DYYYPrivacyRecordUploadKind kind =
            [self uploadKindForURLString:((NSURLRequest *)object).URL.absoluteString];
        return [self shouldBlockUploadKind:kind enabledMask:enabledMask];
    }

    NSValue *identity = [NSValue valueWithPointer:(__bridge const void *)object];
    if ([visited containsObject:identity]) {
        return NO;
    }
    [visited addObject:identity];

    if ([object isKindOfClass:NSDictionary.class] ||
        [object isKindOfClass:NSArray.class] ||
        [object isKindOfClass:NSSet.class]) {
        return [self collectionContainsBlockedUpload:object
                                         enabledMask:enabledMask
                                               depth:depth
                                             visited:visited];
    }

    SEL selectors[] = {
        @selector(URL),
        @selector(url),
        @selector(requestURL),
        @selector(requestUrl),
        @selector(requestUrlString),
        @selector(URLString),
        @selector(urlString),
        @selector(absoluteString),
        @selector(request),
        @selector(currentRequest),
        @selector(originalRequest),
        NSSelectorFromString(@"outerApiParams"),
    };

    for (NSUInteger index = 0; index < sizeof(selectors) / sizeof(selectors[0]); index++) {
        id value = [self valueForSelector:selectors[index] fromObject:object];
        if (!value || value == object) {
            continue;
        }

        if ([self objectContainsBlockedUpload:value
                                  enabledMask:enabledMask
                                        depth:depth + 1
                                      visited:visited]) {
            return YES;
        }
    }
    return NO;
}

+ (BOOL)collectionContainsBlockedUpload:(id)collection
                            enabledMask:(DYYYPrivacyRecordUploadMask)enabledMask
                                  depth:(NSUInteger)depth
                                visited:(NSMutableSet<NSValue *> *)visited {
    NSEnumerator *enumerator = nil;
    if ([collection isKindOfClass:NSDictionary.class]) {
        enumerator = [(NSDictionary *)collection objectEnumerator];
    } else if ([collection respondsToSelector:@selector(objectEnumerator)]) {
        enumerator = [collection objectEnumerator];
    }

    for (id value in enumerator) {
        if ([self objectContainsBlockedUpload:value
                                  enabledMask:enabledMask
                                        depth:depth + 1
                                      visited:visited]) {
            return YES;
        }
    }
    return NO;
}

@end
