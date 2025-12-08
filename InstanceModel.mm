#import "InstanceModel.h"

@implementation IXInstanceRecord

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.bundleID forKey:@"bundleID"];
    [coder encodeObject:self.containerID forKey:@"containerID"];
    [coder encodeObject:self.sceneID forKey:@"sceneID"];
    [coder encodeInt:self.pid forKey:@"pid"];
    [coder encodeInteger:self.slotIndex forKey:@"slotIndex"];
    [coder encodeObject:self.lastUsedAt forKey:@"lastUsedAt"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        self.bundleID = [coder decodeObjectOfClass:[NSString class] forKey:@"bundleID"];
        self.containerID = [coder decodeObjectOfClass:[NSString class] forKey:@"containerID"];
        self.sceneID = [coder decodeObjectOfClass:[NSString class] forKey:@"sceneID"];
        self.pid = [coder decodeIntForKey:@"pid"];
        self.slotIndex = [coder decodeIntegerForKey:@"slotIndex"];
        self.lastUsedAt = [coder decodeObjectOfClass:[NSDate class] forKey:@"lastUsedAt"];
    }
    return self;
}

@end

@implementation IXAppState

@end
