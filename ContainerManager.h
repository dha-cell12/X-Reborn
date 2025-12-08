#import <Foundation/Foundation.h>

@interface ContainerManager : NSObject
+ (instancetype)shared;
- (BOOL)prepareLaunchEnvironmentForContainer:(NSString *)containerID intoEnv:(NSMutableDictionary *)env;
- (NSString *)createContainerForBundle:(NSString *)bundleID instanceIndex:(NSInteger)index;
- (void)removeContainerWithID:(NSString *)containerID;
@end
