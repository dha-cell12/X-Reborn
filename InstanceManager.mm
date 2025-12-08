#import "ContainerManager.h"
#import "InstanceManager.h"
#import "InstanceModel.h"
#import "LogosCompat.h"
#import <Foundation/Foundation.h>
#import <signal.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <spawn.h>
#import <stdlib.h>

#define IXClass(name) NSClassFromString(name)
#define IXShared(cls, sel) ((id(*)(id, SEL))objc_msgSend)((id)cls, NSSelectorFromString(sel))

static NSString *const kIXPrefsPath = @"/var/mobile/Library/Preferences/com.zodacios.instancex.plist";
static const NSUInteger kIXMinInstances = 2;
static const NSUInteger kIXMaxInstances = 4;
static const NSTimeInterval kIXDefaultIdleTimeout = 300; // seconds
static const NSTimeInterval kIXGCPollInterval = 60;      // seconds between GC scans

@interface IXInstanceManager ()
@property(nonatomic) dispatch_source_t gcTimer;
@end

@implementation IXInstanceManager

+ (instancetype)shared {
    static IXInstanceManager *S;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        S = [IXInstanceManager new];
    });
    return S;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        self.apps = [NSMutableDictionary new];
        self.idleTimeout = kIXDefaultIdleTimeout;
        [self _loadSavedConfig];
        [self _startGCTimer];
    }
    return self;
}

- (NSUInteger)_clampCount:(NSUInteger)count {
    return MIN(MAX(kIXMinInstances, count), kIXMaxInstances);
}

- (void)_loadSavedConfig {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:kIXPrefsPath];
    NSNumber *idleTimeout = prefs[@"idleTimeout"];
    if (idleTimeout) {
        self.idleTimeout = MAX(30.0, [idleTimeout doubleValue]);
    }
    NSDictionary *bundles = prefs[@"bundles"];
    for (NSString *bundleID in bundles) {
        NSDictionary *entry = bundles[bundleID];
        NSNumber *desired = entry[@"desiredCount"];
        IXAppState *state = [IXAppState new];
        state.bundleID = bundleID;
        state.instances = [NSMutableArray new];
        state.desiredCount = desired ? [self _clampCount:[desired unsignedIntegerValue]] : kIXMinInstances;
        self.apps[bundleID] = state;
    }
}

- (void)_persistConfig {
    NSMutableDictionary *bundles = [NSMutableDictionary new];
    for (NSString *bundleID in self.apps) {
        IXAppState *st = self.apps[bundleID];
        if (!st) continue;
        NSUInteger desired = st.desiredCount ?: st.instances.count;
        desired = [self _clampCount:desired];
        bundles[bundleID] = @{ @"desiredCount": @(desired) };
    }
    NSDictionary *payload = @{
        @"bundles": bundles,
        @"idleTimeout": @(self.idleTimeout ?: kIXDefaultIdleTimeout)
    };
    [payload writeToFile:kIXPrefsPath atomically:YES];
}

- (void)_startGCTimer {
    if (self.gcTimer) return;
    dispatch_queue_t queue = dispatch_get_main_queue();
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kIXGCPollInterval * NSEC_PER_SEC)), (uint64_t)(kIXGCPollInterval * NSEC_PER_SEC), (uint64_t)(5 * NSEC_PER_SEC));
    __weak IXInstanceManager *weakSelf = self;
    dispatch_source_set_event_handler(timer, ^{
        [weakSelf _runGarbageCollection];
    });
    dispatch_resume(timer);
    self.gcTimer = timer;
}

- (void)_runGarbageCollection {
    NSTimeInterval timeout = self.idleTimeout > 0 ? self.idleTimeout : kIXDefaultIdleTimeout;
    NSDate *now = [NSDate date];
    NSMutableArray<NSString *> *empty = [NSMutableArray new];

    for (NSString *bundleID in [self.apps allKeys]) {
        IXAppState *st = self.apps[bundleID];
        if (!st) continue;
        NSMutableArray<IXInstanceRecord *> *toRemove = [NSMutableArray new];
        for (IXInstanceRecord *rec in [st.instances copy]) {
            BOOL alive = rec.pid > 0 && kill(rec.pid, 0) == 0;
            NSDate *last = rec.lastUsedAt ?: st.lastActiveAt ?: [NSDate distantPast];
            BOOL expired = ([now timeIntervalSinceDate:last] > timeout);
            if (!alive || expired) {
                if (alive) kill(rec.pid, SIGKILL);
                if (rec.containerID.length) [[ContainerManager shared] removeContainerWithID:rec.containerID];
                [toRemove addObject:rec];
            }
        }
        if (toRemove.count) {
            [st.instances removeObjectsInArray:toRemove];
        }
        st.desiredCount = st.instances.count;
        st.lastActiveAt = st.instances.count ? now : st.lastActiveAt;
        if (st.instances.count == 0) {
            [empty addObject:bundleID];
        }
    }

    for (NSString *bid in empty) {
        [self.apps removeObjectForKey:bid];
    }

    [self _persistConfig];
}

- (void)createInstancesForBundle:(NSString*)bundleID count:(NSUInteger)count {
    if (!bundleID) return;
    count = [self _clampCount:count];
    IXAppState *state = self.apps[bundleID];
    if (!state) { state = [IXAppState new]; state.bundleID = bundleID; state.instances = [NSMutableArray new]; self.apps[bundleID] = state; }
    state.desiredCount = count;
    for (IXInstanceRecord *r in [state.instances copy]) {
        if (r.pid > 0) kill(r.pid, SIGKILL);
    }
    [state.instances removeAllObjects];
    for (NSUInteger i=0;i<count;i++) {
        IXInstanceRecord *rec = [self _launchInstanceForBundle:bundleID index:i];
        if (rec) [state.instances addObject:rec];
    }
    [self _applyLayoutForBundle:bundleID];
    [self _persistConfig];
}

- (void)addInstanceForBundle:(NSString*)bundleID {
    IXAppState *state = self.apps[bundleID];
    if (!state) { state = [IXAppState new]; state.bundleID = bundleID; state.instances = [NSMutableArray new]; self.apps[bundleID] = state; }
    if (state.instances.count >= kIXMaxInstances) return;
    IXInstanceRecord *rec = [self _launchInstanceForBundle:bundleID index:state.instances.count];
    if (rec) [state.instances addObject:rec];
    [self _applyLayoutForBundle:bundleID];
    state.desiredCount = [self _clampCount:state.instances.count];
    [self _persistConfig];
}

- (IXInstanceRecord*)_launchInstanceForBundle:(NSString*)bundleID index:(NSUInteger)index {
    Class FBSSystemService = IXClass(@"FBSSystemService");
    if (FBSSystemService) {
        id svc = IXShared(FBSSystemService, @"sharedService");
        SEL sel = NSSelectorFromString(@"createAndActivateApplicationSceneWithBundleIdentifier:options:completion:");
        if (svc && [svc respondsToSelector:sel]) {
            IXInstanceRecord *rec = [IXInstanceRecord new];
            rec.bundleID = bundleID;
            rec.slotIndex = index;
            NSDictionary *opts = @{@"IXInstanceSlot": @(index)};
            void (^cb)(id) = ^(id info){
                if ([info isKindOfClass:NSDictionary.class]) {
                    id sid = info[@"sceneID"];
                    if ([sid isKindOfClass:NSString.class]) rec.sceneID = sid;
                    id pidv = info[@"pid"];
                    if (pidv) rec.pid = (pid_t)[pidv intValue];
                }
            };
            ((void(*)(id,SEL,NSString*,NSDictionary*,id))objc_msgSend)(svc, sel, bundleID, opts, cb);
            rec.lastUsedAt = [NSDate date];
            return rec;
        }
    }

    ContainerManager *cm = [ContainerManager shared];
    NSString *cid = [cm createContainerForBundle:bundleID instanceIndex:index];
    if (!cid) return nil;

    NSString *binaryPath = nil;
    Class LSApplicationProxy = IXClass(@"LSApplicationProxy");
    if (LSApplicationProxy && [LSApplicationProxy respondsToSelector:NSSelectorFromString(@"applicationProxyForIdentifier:")]) {
        id proxy = ((id(*)(id,SEL,NSString*))objc_msgSend)(LSApplicationProxy, NSSelectorFromString(@"applicationProxyForIdentifier:"), bundleID);
        if (proxy && [proxy respondsToSelector:NSSelectorFromString(@"bundleURL")]) {
            NSURL *url = ((id(*)(id,SEL))objc_msgSend)(proxy, NSSelectorFromString(@"bundleURL"));
            NSString *infoPath = [[url path] stringByAppendingPathComponent:@"Info.plist"];
            NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPath];
            NSString *exe = info[@"CFBundleExecutable"];
            if (exe) binaryPath = [[url path] stringByAppendingPathComponent:exe];
        }
    }

    if (!binaryPath || ![[NSFileManager defaultManager] fileExistsAtPath:binaryPath]) {
        Class LSWorkspace = IXClass(@"LSApplicationWorkspace");
        id ws = IXShared(LSWorkspace, @"defaultWorkspace");
        if (ws && [ws respondsToSelector:NSSelectorFromString(@"openApplicationWithBundleID:")]) {
            ((void(*)(id,SEL,NSString*))objc_msgSend)(ws, NSSelectorFromString(@"openApplicationWithBundleID:"), bundleID);
            return nil;
        }
        return nil;
    }

    extern char **environ;
    NSMutableDictionary *env = [NSMutableDictionary new];
    for (char **e = environ; *e; ++e) {
        NSString *s = [NSString stringWithUTF8String:*e];
        NSRange r = [s rangeOfString:@"="];
        if (r.location != NSNotFound) {
            NSString *k = [s substringToIndex:r.location];
            NSString *v = [s substringFromIndex:r.location+1];
            env[k] = v;
        }
    }
    if (![[ContainerManager shared] prepareLaunchEnvironmentForContainer:cid intoEnv:env]) return nil;

    NSUInteger n = env.count;
    char **envp = (char **)malloc((n+1) * sizeof(char*));
    NSUInteger i = 0;
    for (NSString *k in env) {
        NSString *v = env[k];
        NSString *pair = [NSString stringWithFormat:@"%@=%@", k, v];
        envp[i] = strdup([pair UTF8String]);
        i++;
    }
    envp[i] = NULL;

    const char *path = [binaryPath UTF8String];
    char *argv[] = { (char *)path, NULL };
    pid_t pid;
    int res = posix_spawn(&pid, path, NULL, NULL, argv, envp);
    for (NSUInteger j=0;j<i;j++) free(envp[j]);
    free(envp);

    if (res == 0 && pid > 0) {
        IXInstanceRecord *rec = [IXInstanceRecord new];
        rec.bundleID = bundleID;
        rec.containerID = cid;
        rec.pid = pid;
        rec.slotIndex = index;
        rec.lastUsedAt = [NSDate date];
        return rec;
    }
    return nil;
}

- (void)handleProcessExitPid:(pid_t)pid {
    for (IXAppState *st in self.apps.allValues) {
        NSUInteger idx = [st.instances indexOfObjectPassingTest:^BOOL(IXInstanceRecord * _Nonnull obj, NSUInteger i, BOOL * _Nonnull stop) {
            return obj.pid == pid;
        }];
        if (idx != NSNotFound) {
            [st.instances removeObjectAtIndex:idx];
            [self _applyLayoutForBundle:st.bundleID];
            break;
        }
    }
}

- (void)_applyLayoutForBundle:(NSString*)bundleID {
    IXAppState *st = self.apps[bundleID];
    if (!st) return;
    NSDate *now = [NSDate date];
    st.lastActiveAt = now;
    for (IXInstanceRecord *rec in st.instances) {
        rec.lastUsedAt = now;
    }
    extern void IXApplyLayoutsForBundle(NSString*, NSArray*, IXLayoutMode);
    IXLayoutMode mode = (IXLayoutMode)MAX(2, (int)st.instances.count);
    IXApplyLayoutsForBundle(bundleID, st.instances, mode);
}

@end

IXInstanceManager *IXManager(void) {
    return [IXInstanceManager shared];
}
