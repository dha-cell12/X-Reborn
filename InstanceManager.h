#import <Foundation/Foundation.h>
#import "InstanceModel.h"

@interface IXInstanceManager : NSObject
@property(nonatomic) NSMutableDictionary<NSString*, IXAppState*> *apps;
@property(nonatomic) NSTimeInterval idleTimeout; // seconds before GC reclaims idle instances
+ (instancetype)shared;
- (void)createInstancesForBundle:(NSString*)bundleID count:(NSUInteger)count;
- (void)addInstanceForBundle:(NSString*)bundleID;
- (void)handleProcessExitPid:(pid_t)pid;
@end

extern IXInstanceManager *IXManager(void);
