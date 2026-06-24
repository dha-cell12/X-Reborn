#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <spawn.h>

@interface InstanceXPrefs : PSListController
@end

@implementation InstanceXPrefs
- (NSArray *)specifiers {
    if (!_specifiers) _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    return _specifiers;
}
- (void)respring {
    pid_t pid;
    const char *args[] = {"sbreload", NULL};
    posix_spawn(&pid, "/usr/bin/sbreload", NULL, NULL, (char* const*)args, NULL);
}
@end

@interface IXAppListController : PSListController
@end

@implementation IXAppListController
- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [NSMutableArray new];
        PSSpecifier* group = [PSSpecifier groupSpecifierWithName:@"Applications"];
        [group setProperty:@"Select an app to manage its containers." forKey:@"footerText"];
        [(NSMutableArray*)_specifiers addObject:group];
        // TODO: Populate with installed apps that have instances
    }
    return _specifiers;
}
@end
