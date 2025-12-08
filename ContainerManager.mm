#import <Foundation/Foundation.h>
#import "LogosCompat.h"

@interface ContainerManager : NSObject
+ (instancetype)shared;
- (NSString*)createContainerForBundle:(NSString*)bundleID instanceIndex:(NSUInteger)index;
- (BOOL)prepareLaunchEnvironmentForContainer:(NSString*)containerID intoEnv:(NSMutableDictionary*)env;
- (BOOL)useLibCrane;
@end

@implementation ContainerManager
+ (instancetype)shared { static ContainerManager *S; static dispatch_once_t once; dispatch_once(&once, ^{ S=[ContainerManager new]; }); return S; }

- (NSString *)_shmNamespaceForContainer:(NSString *)containerID {
    NSString *safeContainer = [[containerID stringByReplacingOccurrencesOfString:@"/" withString:@"_"] stringByReplacingOccurrencesOfString:@"." withString:@"_"];
    NSString *uuid = [[NSUUID UUID] UUIDString];
    return [NSString stringWithFormat:@"%@_%@", safeContainer, uuid];
}

- (BOOL)useLibCrane {
    Class crane = IXClass(@"CraneManager");
    return crane != nil;
}

- (NSString*)createContainerForBundle:(NSString*)bundleID instanceIndex:(NSUInteger)index {
    NSString *cid = [NSString stringWithFormat:@"%@.instance.%lu", bundleID, (unsigned long)index+1];
    Class craneCls = IXClass(@"CraneManager");
    if (craneCls) {
        id mgr = ((id(*)(id,SEL))objc_msgSend)(craneCls, NSSelectorFromString(@"sharedManager"));
        if (mgr && [mgr respondsToSelector:NSSelectorFromString(@"createContainerForBundleID:identifier:")]) {
            ((void(*)(id,SEL,NSString*,NSString*))objc_msgSend)(mgr, NSSelectorFromString(@"createContainerForBundleID:identifier:"), bundleID, cid);
            return cid;
        }
    }
    NSString *base = [NSString stringWithFormat:@"/var/mobile/InstanceX/containers/%@", cid];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:base]) {
        [fm createDirectoryAtPath:base withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0755} error:nil];
        [fm createDirectoryAtPath:[base stringByAppendingPathComponent:@"Documents"] withIntermediateDirectories:YES attributes:nil error:nil];
        [fm createDirectoryAtPath:[base stringByAppendingPathComponent:@"Library"] withIntermediateDirectories:YES attributes:nil error:nil];
        [fm createDirectoryAtPath:[base stringByAppendingPathComponent:@"tmp"] withIntermediateDirectories:YES attributes:nil error:nil];
    }
    return cid;
}

- (BOOL)prepareLaunchEnvironmentForContainer:(NSString*)containerID intoEnv:(NSMutableDictionary*)env {
    if (!containerID) return NO;
    env[@"IX_CONTAINER"] = containerID;
    env[@"IX_SHM_NAMESPACE"] = env[@"IX_SHM_NAMESPACE"] ?: [self _shmNamespaceForContainer:containerID];
    NSString *shim = @"/usr/lib/instancex_container_shim.dylib";
    if ([[NSFileManager defaultManager] fileExistsAtPath:shim]) {
        NSString *existing = env[@"DYLD_INSERT_LIBRARIES"] ?: @"";
        NSString *newv = existing.length ? [existing stringByAppendingFormat:@":%@", shim] : shim;
        env[@"DYLD_INSERT_LIBRARIES"] = newv;
    } else {
        if (![self useLibCrane]) return NO;
    }
    return YES;
}

- (void)removeContainerWithID:(NSString *)containerID {
    if (!containerID.length) return;
    Class craneCls = IXClass(@"CraneManager");
    if (craneCls) {
        id mgr = ((id(*)(id,SEL))objc_msgSend)(craneCls, NSSelectorFromString(@"sharedManager"));
        SEL sel = NSSelectorFromString(@"removeContainerWithIdentifier:");
        if (mgr && [mgr respondsToSelector:sel]) {
            ((void(*)(id,SEL,NSString*))objc_msgSend)(mgr, sel, containerID);
        }
    }
    NSString *base = [NSString stringWithFormat:@"/var/mobile/InstanceX/containers/%@", containerID];
    [[NSFileManager defaultManager] removeItemAtPath:base error:nil];
}

@end
