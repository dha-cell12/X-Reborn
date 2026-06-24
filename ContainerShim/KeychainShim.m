#include <CoreFoundation/CoreFoundation.h>
#include <Security/Security.h>
#include <dlfcn.h>
#include <Foundation/Foundation.h>

static OSStatus (*orig_SecItemAdd)(CFDictionaryRef, CFTypeRef *) = NULL;
static OSStatus (*orig_SecItemCopyMatching)(CFDictionaryRef, CFTypeRef *) = NULL;
static OSStatus (*orig_SecItemUpdate)(CFDictionaryRef, CFDictionaryRef) = NULL;
static OSStatus (*orig_SecItemDelete)(CFDictionaryRef) = NULL;

static NSString *namespaceKeyForContainer(NSString *orig) {
    const char *c = getenv("IX_CONTAINER");
    if (!c || !orig) return orig;
    NSString *cid = [NSString stringWithUTF8String:c];
    if ([orig hasPrefix:cid]) return orig;
    return [cid stringByAppendingFormat:@":%@", orig];
}

static CFDictionaryRef _namespaceDict(CFDictionaryRef dict) {
    if (!dict) return dict;
    NSDictionary *orig = (__bridge NSDictionary *)dict;
    NSMutableDictionary *m = [NSMutableDictionary dictionaryWithDictionary:orig];

    // Key identifiers to namespace
    NSArray *keysToNamespace = @[(id)kSecAttrService, (id)kSecAttrAccount, (id)kSecAttrAccessGroup, (id)kSecAttrLabel];

    for (id key in keysToNamespace) {
        id value = m[key];
        if (value && [value isKindOfClass:NSString.class]) {
            m[key] = namespaceKeyForContainer(value);
        }
    }

    return CFBridgingRetain(m);
}

OSStatus SecItemAdd(CFDictionaryRef attributes, CFTypeRef *result) {
    if (!orig_SecItemAdd) orig_SecItemAdd = dlsym(RTLD_NEXT, "SecItemAdd");
    CFDictionaryRef n = _namespaceDict(attributes);
    OSStatus r = orig_SecItemAdd(n, result);
    if (n) CFRelease(n);
    return r;
}

OSStatus SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result) {
    if (!orig_SecItemCopyMatching) orig_SecItemCopyMatching = dlsym(RTLD_NEXT, "SecItemCopyMatching");
    CFDictionaryRef n = _namespaceDict(query);
    OSStatus r = orig_SecItemCopyMatching(n, result);
    if (n) CFRelease(n);
    return r;
}

OSStatus SecItemUpdate(CFDictionaryRef query, CFDictionaryRef attributesToUpdate) {
    if (!orig_SecItemUpdate) orig_SecItemUpdate = dlsym(RTLD_NEXT, "SecItemUpdate");
    CFDictionaryRef qn = _namespaceDict(query);
    CFDictionaryRef an = _namespaceDict(attributesToUpdate);
    OSStatus r = orig_SecItemUpdate(qn, an);
    if (qn) CFRelease(qn);
    if (an) CFRelease(an);
    return r;
}

OSStatus SecItemDelete(CFDictionaryRef query) {
    if (!orig_SecItemDelete) orig_SecItemDelete = dlsym(RTLD_NEXT, "SecItemDelete");
    CFDictionaryRef n = _namespaceDict(query);
    OSStatus r = orig_SecItemDelete(n);
    if (n) CFRelease(n);
    return r;
}
