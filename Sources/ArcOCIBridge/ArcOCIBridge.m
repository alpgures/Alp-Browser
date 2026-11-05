#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <Security/Security.h>
#import <CommonCrypto/CommonDigest.h>
#import <objc/runtime.h>
#include <mach-o/dyld.h>
#include <mach-o/getsect.h>
#include <mach/mach.h>
#include <mach/vm_map.h>
#include <dlfcn.h>
#include <sys/stat.h>

// ============================================================================
// Alp Browser (libArcOCIBridge.dylib)
// In-process runtime bridge injected into the original `/Applications/Arc.app`
// binary (`Alp Browser.app` / `Arc-OCI.app` / `Arc2.app`) that:
// 1. Rebrands UI text from "Arc" / "Arc Browser" -> "Alp" / "Alp Browser"
// 2. Hooks `SecItemCopyMatching`, `SecItemAdd`, `SecItemUpdate`, `SecItemDelete`
//    in `__DATA_CONST,__got` + `FIRAuthKeychainServices` so ad-hoc signing NEVER
//    returns `errSecMissingEntitlement (-34018)` ("We're having trouble saving
//    the password into your keychain")
// 3. Immortalizes Firebase Auth (`identitytoolkit.googleapis.com` &
//    `securetoken.googleapis.com`) with valid 3-part JWTs so signing in works
//    instantly even after Arc's servers shut down
// 4. Routes Alp Max AI (`*.diabrowser.engineering`) to Claude Code on OCI
// 5. Silently syncs per-user AES-256 encrypted `StorableSidebar.json` to OCI
//    (strictly excluding cookies, passwords, history, and archive items for privacy)
// ============================================================================

static NSString *const kHandledPropertyKey = @"com.alpgures.AlpBrowserBridgeHandled";
static NSString *const kOCIHostAlias = @"oci-box";

@interface AlpSettingsOverlayManager : NSObject
@property (nonatomic, strong) NSMapTable<NSWindow *, NSView *> *generalOverlays;
@property (nonatomic, strong) NSMapTable<NSWindow *, NSView *> *iconOverlays;

// Icon Tab Controls
@property (nonatomic, strong) NSBox *cardApres;
@property (nonatomic, strong) NSBox *cardKumori;
@property (nonatomic, strong) NSBox *cardCustom;
@property (nonatomic, strong) NSImageView *customPreviewImageView;
@property (nonatomic, strong) NSButton *btnApres;
@property (nonatomic, strong) NSButton *btnKumori;
@property (nonatomic, strong) NSButton *btnCustom;
@property (nonatomic, strong) NSSegmentedControl *bgSegment;
@property (nonatomic, strong) NSColorWell *bgColorWell;
@property (nonatomic, strong) NSColorWell *c1ColorWell;
@property (nonatomic, strong) NSColorWell *c2ColorWell;
@property (nonatomic, strong) NSSlider *grainSlider;
@property (nonatomic, strong) NSTextField *grainValueLabel;

+ (instancetype)shared;
- (void)sanitizeAndRefreshSettingsWindow:(NSWindow *)window;
- (void)refreshSettingsWindow:(NSWindow *)window;
- (void)selectApresSki:(id)sender;
- (void)selectKumoriNashi:(id)sender;
- (void)applyCustomLogoAndExport;
- (NSString *)pathForBundledIcon:(NSString *)name;
@end

static OSStatus (*orig_SecItemCopyMatching)(CFDictionaryRef query, CFTypeRef *result) = NULL;
static OSStatus (*orig_SecItemAdd)(CFDictionaryRef attributes, CFTypeRef *result) = NULL;
static OSStatus (*orig_SecItemUpdate)(CFDictionaryRef query, CFDictionaryRef attributesToUpdate) = NULL;
static OSStatus (*orig_SecItemDelete)(CFDictionaryRef query) = NULL;

// Helper to base64url-encode NSData for valid Firebase JWT generation
static NSString *AlpBase64URLEncode(NSData *data) {
    NSString *b64 = [data base64EncodedStringWithOptions:0];
    b64 = [b64 stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
    b64 = [b64 stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    b64 = [b64 stringByReplacingOccurrencesOfString:@"=" withString:@""];
    return b64;
}

static NSString *AlpBuildValidFirebaseJWT(NSString *email, NSString *userId, NSString *name) {
    NSDictionary *header = @{@"alg": @"RS256", @"typ": @"JWT", @"kid": @"alp-browser-key-1"};
    NSDictionary *payload = @{
        @"iss": @"https://securetoken.google.com/arc-browser",
        @"aud": @"arc-browser",
        @"auth_time": @1700000000,
        @"user_id": userId ?: @"E0Lg3n10d9YdTbxX7ud1uoFiFKk1",
        @"sub": userId ?: @"E0Lg3n10d9YdTbxX7ud1uoFiFKk1",
        @"iat": @1700000000,
        @"exp": @4102444800,
        @"email": email ?: @"guresalpdeniz@gmail.com",
        @"email_verified": @YES,
        @"name": name ?: @"Alp",
        @"firebase": @{
            @"identities": @{
                @"email": @[email ?: @"guresalpdeniz@gmail.com"]
            },
            @"sign_in_provider": @"password"
        }
    };
    NSData *hData = [NSJSONSerialization dataWithJSONObject:header options:0 error:nil];
    NSData *pData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    return [NSString stringWithFormat:@"%@.%@.c2lnbmF0dXJlX2FscF9icm93c2Vy", AlpBase64URLEncode(hData), AlpBase64URLEncode(pData)];
}

// ============================================================================
// 1. Entitlement-Free Keychain Store & SecItem* GOT Interposer
// ============================================================================

@interface AlpKeychainBackingStore : NSObject
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSData *> *store;
@property (nonatomic, copy) NSString *filePath;
@end

@implementation AlpKeychainBackingStore

+ (instancetype)shared {
    static AlpKeychainBackingStore *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[AlpKeychainBackingStore alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSString *dir = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Arc"];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        _filePath = [dir stringByAppendingPathComponent:@".alp_keychain_store.plist"];
        NSDictionary *loaded = [NSDictionary dictionaryWithContentsOfFile:_filePath];
        _store = loaded ? [loaded mutableCopy] : [NSMutableDictionary dictionary];
    }
    return self;
}

- (NSString *)cacheKeyFromQuery:(NSDictionary *)query {
    if (!query) return @"default_key";
    NSString *acct = [query[(__bridge id)kSecAttrAccount] description] ?: [query[@"acct"] description] ?: @"";
    NSString *svce = [query[(__bridge id)kSecAttrService] description] ?: [query[@"svce"] description] ?: @"";
    NSString *gena = [query[(__bridge id)kSecAttrGeneric] description] ?: [query[@"gena"] description] ?: @"";
    NSString *label = [query[(__bridge id)kSecAttrLabel] description] ?: [query[@"labl"] description] ?: @"";
    return [NSString stringWithFormat:@"%@|%@|%@|%@", svce, acct, gena, label];
}

- (void)persist {
    @synchronized (self) {
        [self.store writeToFile:self.filePath atomically:YES];
        chmod(self.filePath.fileSystemRepresentation, 0600);
    }
}

- (NSData *)dataForKey:(NSString *)key {
    @synchronized (self) {
        NSData *val = self.store[key ?: @"default"];
        if (!val && [key isEqualToString:@"Arc_firebase_user"]) {
            val = self.store[@"Alp_firebase_user"];
        } else if (!val && [key isEqualToString:@"Alp_firebase_user"]) {
            val = self.store[@"Arc_firebase_user"];
        }
        return val;
    }
}

- (void)setData:(NSData *)data forKey:(NSString *)key {
    @synchronized (self) {
        if (data && [data isKindOfClass:[NSData class]]) {
            self.store[key ?: @"default"] = data;
            if ([key isEqualToString:@"Alp_firebase_user"] || [key isEqualToString:@"Arc_firebase_user"]) {
                self.store[@"Alp_firebase_user"] = data;
                self.store[@"Arc_firebase_user"] = data;
            }
        } else {
            [self.store removeObjectForKey:key ?: @"default"];
        }
        [self persist];
    }
}

- (void)removeDataForKey:(NSString *)key {
    @synchronized (self) {
        [self.store removeObjectForKey:key ?: @"default"];
        [self persist];
    }
}

@end

// Strips restricted entitlement keys (`agrp`, `dpkc`, `pdmn`) from Keychain query dictionaries
static NSMutableDictionary *AlpSanitizeKeychainDict(CFDictionaryRef cfDict) {
    if (!cfDict) return [NSMutableDictionary dictionary];
    NSDictionary *dict = (__bridge NSDictionary *)cfDict;
    NSMutableDictionary *clean = [dict mutableCopy];
    [clean removeObjectForKey:(__bridge id)kSecAttrAccessGroup];
    [clean removeObjectForKey:@"agrp"];
    [clean removeObjectForKey:@"dpkc"];
    [clean removeObjectForKey:@"u_DataProtectionKeychain"];
    [clean removeObjectForKey:(__bridge id)kSecAttrAccessible];
    [clean removeObjectForKey:@"pdmn"];
    return clean;
}

static OSStatus alp_SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result) {
    NSMutableDictionary *clean = AlpSanitizeKeychainDict(query);
    if (orig_SecItemCopyMatching) {
        OSStatus status = orig_SecItemCopyMatching((__bridge CFDictionaryRef)clean, result);
        if (status == errSecSuccess) {
            return errSecSuccess;
        }
    }

    NSDictionary *qDict = (__bridge NSDictionary *)query;
    NSString *cacheKey = [[AlpKeychainBackingStore shared] cacheKeyFromQuery:qDict];
    NSData *savedData = [[AlpKeychainBackingStore shared] dataForKey:cacheKey];
    if (savedData) {
        if (result) {
            BOOL wantsAttributes = [qDict[(__bridge id)kSecReturnAttributes] boolValue] || [qDict[@"r_Attributes"] boolValue];
            if (wantsAttributes) {
                NSMutableDictionary *attrResult = [clean mutableCopy];
                attrResult[(__bridge id)kSecValueData] = savedData;
                *result = CFBridgingRetain(attrResult);
            } else {
                *result = CFBridgingRetain(savedData);
            }
        }
        return errSecSuccess;
    }

    // Return errSecItemNotFound (-25300) instead of errSecMissingEntitlement (-34018)
    return errSecItemNotFound;
}

static OSStatus alp_SecItemAdd(CFDictionaryRef attributes, CFTypeRef *result) {
    NSDictionary *attrDict = (__bridge NSDictionary *)attributes;
    NSString *cacheKey = [[AlpKeychainBackingStore shared] cacheKeyFromQuery:attrDict];
    NSData *valData = attrDict[(__bridge id)kSecValueData] ?: attrDict[@"v_Data"];
    if ([valData isKindOfClass:[NSData class]]) {
        [[AlpKeychainBackingStore shared] setData:valData forKey:cacheKey];
    }

    NSMutableDictionary *clean = AlpSanitizeKeychainDict(attributes);
    if (orig_SecItemAdd) {
        OSStatus status = orig_SecItemAdd((__bridge CFDictionaryRef)clean, result);
        if (status == errSecDuplicateItem && orig_SecItemUpdate) {
            NSMutableDictionary *updateAttrs = [NSMutableDictionary dictionary];
            if (valData) updateAttrs[(__bridge id)kSecValueData] = valData;
            orig_SecItemUpdate((__bridge CFDictionaryRef)clean, (__bridge CFDictionaryRef)updateAttrs);
        }
    }
    if (result && !*result && valData) {
        *result = CFBridgingRetain(valData);
    }
    return errSecSuccess;
}

static OSStatus alp_SecItemUpdate(CFDictionaryRef query, CFDictionaryRef attributesToUpdate) {
    NSDictionary *qDict = (__bridge NSDictionary *)query;
    NSDictionary *uDict = (__bridge NSDictionary *)attributesToUpdate;
    NSString *cacheKey = [[AlpKeychainBackingStore shared] cacheKeyFromQuery:qDict];
    NSData *valData = uDict[(__bridge id)kSecValueData] ?: uDict[@"v_Data"] ?: qDict[(__bridge id)kSecValueData] ?: qDict[@"v_Data"];
    if ([valData isKindOfClass:[NSData class]]) {
        [[AlpKeychainBackingStore shared] setData:valData forKey:cacheKey];
    }

    NSMutableDictionary *cleanQ = AlpSanitizeKeychainDict(query);
    NSMutableDictionary *cleanU = AlpSanitizeKeychainDict(attributesToUpdate);
    if (orig_SecItemUpdate) {
        orig_SecItemUpdate((__bridge CFDictionaryRef)cleanQ, (__bridge CFDictionaryRef)cleanU);
    }
    return errSecSuccess;
}

static OSStatus alp_SecItemDelete(CFDictionaryRef query) {
    NSDictionary *qDict = (__bridge NSDictionary *)query;
    NSString *cacheKey = [[AlpKeychainBackingStore shared] cacheKeyFromQuery:qDict];
    [[AlpKeychainBackingStore shared] removeDataForKey:cacheKey];

    NSMutableDictionary *cleanQ = AlpSanitizeKeychainDict(query);
    if (orig_SecItemDelete) {
        orig_SecItemDelete((__bridge CFDictionaryRef)cleanQ);
    }
    return errSecSuccess;
}

static void AlpHookSecItemGOTInImage(const struct mach_header *header) {
    if (!header || header->magic != MH_MAGIC_64) return;
    const struct mach_header_64 *header64 = (const struct mach_header_64 *)header;

    const char *segNames[] = {"__DATA_CONST", "__DATA", "__AUTH_CONST"};
    const char *sectNames[] = {"__got", "__la_symbol_ptr", "__auth_got", "__auth_ptr"};

    for (size_t s = 0; s < sizeof(segNames) / sizeof(segNames[0]); s++) {
        for (size_t c = 0; c < sizeof(sectNames) / sizeof(sectNames[0]); c++) {
            unsigned long byteSize = 0;
            uint8_t *sectStart = getsectiondata(header64, segNames[s], sectNames[c], &byteSize);
            if (!sectStart || byteSize == 0) continue;

            vm_protect(mach_task_self(), (vm_address_t)sectStart, byteSize, FALSE, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
            void **ptrs = (void **)sectStart;
            size_t count = byteSize / sizeof(void *);
            for (size_t i = 0; i < count; i++) {
                if (ptrs[i] == (void *)orig_SecItemCopyMatching) {
                    ptrs[i] = (void *)alp_SecItemCopyMatching;
                } else if (ptrs[i] == (void *)orig_SecItemAdd) {
                    ptrs[i] = (void *)alp_SecItemAdd;
                } else if (ptrs[i] == (void *)orig_SecItemUpdate) {
                    ptrs[i] = (void *)alp_SecItemUpdate;
                } else if (ptrs[i] == (void *)orig_SecItemDelete) {
                    ptrs[i] = (void *)alp_SecItemDelete;
                }
            }
        }
    }
}

@implementation NSObject (AlpKeychainSwizzle)

- (NSData *)alp_dataForKey:(NSString *)key error:(NSError **)outError {
    if (outError) *outError = nil;
    return [[AlpKeychainBackingStore shared] dataForKey:key];
}

- (BOOL)alp_setData:(NSData *)data forKey:(NSString *)key error:(NSError **)outError {
    if (outError) *outError = nil;
    [[AlpKeychainBackingStore shared] setData:data forKey:key];
    return YES;
}

- (BOOL)alp_removeDataForKey:(NSString *)key error:(NSError **)outError {
    if (outError) *outError = nil;
    [[AlpKeychainBackingStore shared] removeDataForKey:key];
    return YES;
}

- (NSData *)alp_getItemWithQuery:(NSDictionary *)query error:(NSError **)outError {
    if (outError) *outError = nil;
    NSString *k = [[AlpKeychainBackingStore shared] cacheKeyFromQuery:query];
    return [[AlpKeychainBackingStore shared] dataForKey:k];
}

- (BOOL)alp_setItemWithQuery:(NSDictionary *)query attributes:(NSDictionary *)attributes error:(NSError **)outError {
    if (outError) *outError = nil;
    NSString *k = [[AlpKeychainBackingStore shared] cacheKeyFromQuery:query];
    NSData *val = attributes[@"v_Data"] ?: query[@"v_Data"] ?: attributes[(__bridge id)kSecValueData] ?: query[(__bridge id)kSecValueData];
    if ([val isKindOfClass:[NSData class]]) {
        [[AlpKeychainBackingStore shared] setData:val forKey:k];
    }
    return YES;
}

- (BOOL)alp_deleteItemWithQuery:(NSDictionary *)query error:(NSError **)outError {
    if (outError) *outError = nil;
    NSString *k = [[AlpKeychainBackingStore shared] cacheKeyFromQuery:query];
    [[AlpKeychainBackingStore shared] removeDataForKey:k];
    return YES;
}

- (BOOL)alp_removeItemWithQuery:(NSDictionary *)query error:(NSError **)outError {
    if (outError) *outError = nil;
    NSString *k = [[AlpKeychainBackingStore shared] cacheKeyFromQuery:query];
    [[AlpKeychainBackingStore shared] removeDataForKey:k];
    return YES;
}

@end

// ============================================================================
// 2. Comprehensive UI Rebranding Hook (Every standalone word "Arc" -> "Alp")
// ============================================================================

static NSString *AlpRebrandString(NSString *input) {
    if (!input || input.length < 3) return input;
    // Do not modify filesystem paths
    if ([input hasPrefix:@"/"] || [input containsString:@"Application Support/Arc"]) {
        return input;
    }

    NSString *out = input;
    if ([out containsString:@"arc://"]) {
        out = [out stringByReplacingOccurrencesOfString:@"arc://" withString:@"alp://"];
    }

    static NSRegularExpression *arcRegex = nil;
    static NSRegularExpression *arcUpperRegex = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        arcRegex = [NSRegularExpression regularExpressionWithPattern:@"\\bArc\\b" options:0 error:nil];
        arcUpperRegex = [NSRegularExpression regularExpressionWithPattern:@"\\bARC\\b" options:0 error:nil];
    });

    if ([out containsString:@"Arc"]) {
        out = [arcRegex stringByReplacingMatchesInString:out options:0 range:NSMakeRange(0, out.length) withTemplate:@"Alp"];
    }
    if ([out containsString:@"ARC"]) {
        out = [arcUpperRegex stringByReplacingMatchesInString:out options:0 range:NSMakeRange(0, out.length) withTemplate:@"ALP"];
    }
    if ([out containsString:@"RESOURCES.ALP.NET"] || [out containsString:@"RESOURCES.ARC.NET"]) {
        out = [out stringByReplacingOccurrencesOfString:@"RESOURCES.ALP.NET" withString:@"ALPBROWSER.APP"];
        out = [out stringByReplacingOccurrencesOfString:@"RESOURCES.ARC.NET" withString:@"ALPBROWSER.APP"];
    }
    if ([out containsString:@"The Browser Company"]) {
        out = [out stringByReplacingOccurrencesOfString:@"The Browser Company" withString:@"Alp Browser"];
    }
    if ([out containsString:@"Alp Boost"]) {
        out = [out stringByReplacingOccurrencesOfString:@"Alp Boost" withString:@"Alp Style"];
    }
    return out;
}

static void AlpRebrandMenuRecursively(NSMenu *menu) {
    if (!menu) return;
    menu.title = AlpRebrandString(menu.title);
    for (NSMenuItem *item in menu.itemArray) {
        item.title = AlpRebrandString(item.title);
        if (item.submenu) {
            AlpRebrandMenuRecursively(item.submenu);
        }
    }
}

@implementation NSTextField (AlpBranding)
- (void)alp_setStringValue:(NSString *)stringValue {
    [self alp_setStringValue:AlpRebrandString(stringValue)];
}
- (NSString *)alp_stringValue {
    return AlpRebrandString([self alp_stringValue]);
}
- (void)alp_setAttributedStringValue:(NSAttributedString *)obj {
    if ([obj.string containsString:@"arc://"] || [obj.string containsString:@"Arc"] || [obj.string containsString:@"ARC"]) {
        NSMutableAttributedString *mut = [obj mutableCopy];
        NSString *s = mut.string;
        if ([s containsString:@"arc://"]) {
            NSRange r = [s rangeOfString:@"arc://"];
            while (r.location != NSNotFound) {
                [mut replaceCharactersInRange:r withString:@"alp://"];
                s = mut.string;
                r = [s rangeOfString:@"arc://"];
            }
        }
        obj = mut;
    }
    [self alp_setAttributedStringValue:obj];
}
@end

@implementation NSCell (AlpBranding)
- (void)alp_setStringValue:(NSString *)stringValue {
    [self alp_setStringValue:AlpRebrandString(stringValue)];
}
- (NSString *)alp_stringValue {
    return AlpRebrandString([self alp_stringValue]);
}
- (void)alp_setTitle:(NSString *)title {
    [self alp_setTitle:AlpRebrandString(title)];
}
- (NSString *)alp_title {
    return AlpRebrandString([self alp_title]);
}
@end

@implementation NSTextView (AlpBranding)
- (void)alp_setString:(NSString *)string {
    [self alp_setString:AlpRebrandString(string)];
}
@end

@implementation NSURL (AlpSchemeSupport)
+ (instancetype)alp_URLWithString:(NSString *)URLString {
    if ([URLString hasPrefix:@"alp://"]) {
        URLString = [@"arc://" stringByAppendingString:[URLString substringFromIndex:6]];
    }
    return [self alp_URLWithString:URLString];
}
+ (instancetype)alp_URLWithString:(NSString *)URLString relativeToURL:(NSURL *)baseURL {
    if ([URLString hasPrefix:@"alp://"]) {
        URLString = [@"arc://" stringByAppendingString:[URLString substringFromIndex:6]];
    }
    return [self alp_URLWithString:URLString relativeToURL:baseURL];
}
@end

@implementation NSMenuItem (AlpBranding)
- (void)alp_setTitle:(NSString *)title {
    [self alp_setTitle:AlpRebrandString(title)];
}
- (NSString *)alp_title {
    return AlpRebrandString([self alp_title]);
}
@end

@implementation NSMenu (AlpBranding)
- (void)alp_setTitle:(NSString *)title {
    [self alp_setTitle:AlpRebrandString(title)];
}
- (NSString *)alp_title {
    return AlpRebrandString([self alp_title]);
}
@end

@implementation NSButton (AlpBranding)
- (void)alp_setTitle:(NSString *)title {
    [self alp_setTitle:AlpRebrandString(title)];
}
- (NSString *)alp_title {
    return AlpRebrandString([self alp_title]);
}
@end

@implementation NSWindow (AlpBranding)
- (void)alp_setTitle:(NSString *)title {
    NSString *rebranded = AlpRebrandString(title);
    [self alp_setTitle:rebranded];
}
- (void)alp_setToolbar:(NSToolbar *)toolbar {
    [self alp_setToolbar:toolbar];
    NSString *clsName = NSStringFromClass([self class]);
    if ([clsName containsString:@"UserInteractionPausableWindow"] || [self.frameAutosaveName containsString:@"Settings"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[AlpSettingsOverlayManager shared] sanitizeAndRefreshSettingsWindow:self];
        });
    }
}
@end

// ============================================================================
// 3. In-Process Network Interceptor (Firebase Auth, Alp Max -> OCI Claude Code)
// ============================================================================

static NSString *AlpSHA256Hex(NSData *data) {
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        [hex appendFormat:@"%02x", digest[i]];
    }
    return hex;
}

@interface ArcOCIURLProtocol : NSURLProtocol
@property (nonatomic, assign) BOOL isCancelled;
@end

@implementation ArcOCIURLProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    if ([NSURLProtocol propertyForKey:kHandledPropertyKey inRequest:request]) {
        return NO;
    }
    NSURL *url = request.URL;
    NSString *host = url.host.lowercaseString;
    if (!host) return NO;

    if ([host hasSuffix:@"diabrowser.engineering"] ||
        [host isEqualToString:@"releases.arc.net"] ||
        [host containsString:@"sentry.io"] ||
        [host containsString:@"datadoghq."] ||
        [host containsString:@"launchdarkly.com"] ||
        [host isEqualToString:@"content.arc.net"] ||
        [host isEqualToString:@"securetoken.googleapis.com"] ||
        [host isEqualToString:@"identitytoolkit.googleapis.com"]) {
        return YES;
    }
    return NO;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

- (void)startLoading {
    NSMutableURLRequest *mutableReq = [[self request] mutableCopy];
    [NSURLProtocol setProperty:@YES forKey:kHandledPropertyKey inRequest:mutableReq];

    NSURL *url = mutableReq.URL;
    NSString *host = url.host.lowercaseString ?: @"";
    NSString *path = url.path ?: @"";

    if ([host isEqualToString:@"releases.arc.net"]) {
        NSString *emptyRSS = @"<?xml version=\"1.0\" encoding=\"utf-8\"?><rss version=\"2.0\"><channel><title>Alp Browser</title></channel></rss>";
        [self respondWithStatusCode:200 contentType:@"application/xml" data:[emptyRSS dataUsingEncoding:NSUTF8StringEncoding]];
        return;
    }

    if ([host containsString:@"sentry.io"] ||
        [host containsString:@"datadoghq."] ||
        [host containsString:@"launchdarkly.com"] ||
        [host isEqualToString:@"content.arc.net"]) {
        [self respondWithStatusCode:200 contentType:@"application/json" data:[@"{}" dataUsingEncoding:NSUTF8StringEncoding]];
        return;
    }

    if ([host isEqualToString:@"securetoken.googleapis.com"]) {
        NSString *jwt = AlpBuildValidFirebaseJWT(@"guresalpdeniz@gmail.com", @"E0Lg3n10d9YdTbxX7ud1uoFiFKk1", @"Alp");
        NSDictionary *tokenResp = @{
            @"access_token": jwt,
            @"expires_in": @"315360000",
            @"token_type": @"Bearer",
            @"refresh_token": @"alp-browser-immortal-refresh-token",
            @"id_token": jwt,
            @"user_id": @"E0Lg3n10d9YdTbxX7ud1uoFiFKk1",
            @"project_id": @"arc-browser"
        };
        NSData *json = [NSJSONSerialization dataWithJSONObject:tokenResp options:0 error:nil];
        [self respondWithStatusCode:200 contentType:@"application/json" data:json];
        return;
    }

    if ([host isEqualToString:@"identitytoolkit.googleapis.com"]) {
        NSData *reqBody = [self extractBodyFromRequest:mutableReq];
        NSDictionary *reqDict = reqBody ? [NSJSONSerialization JSONObjectWithData:reqBody options:0 error:nil] : nil;
        NSString *email = ([reqDict isKindOfClass:[NSDictionary class]] && [reqDict[@"email"] isKindOfClass:[NSString class]])
            ? reqDict[@"email"]
            : @"guresalpdeniz@gmail.com";
        NSString *password = ([reqDict isKindOfClass:[NSDictionary class]] && [reqDict[@"password"] isKindOfClass:[NSString class]])
            ? reqDict[@"password"]
            : nil;

        if ([path containsString:@"verifyPassword"] && [email.lowercaseString isEqualToString:@"guresalpdeniz@gmail.com"] && password.length > 0) {
            NSData *salted = [[NSString stringWithFormat:@"guresalpdeniz@gmail.com:%@", password] dataUsingEncoding:NSUTF8StringEncoding];
            NSString *candidateHash = AlpSHA256Hex(salted);
            if (![candidateHash isEqualToString:@"9442d31c47e83b2b276328e53fb41dc5e95a5cd190c55aa25dac5a54556c92ed"]) {
                NSDictionary *errDict = @{
                    @"error": @{
                        @"code": @400,
                        @"message": @"INVALID_PASSWORD",
                        @"errors": @[@{@"message": @"INVALID_PASSWORD", @"domain": @"global", @"reason": @"invalid"}]
                    }
                };
                NSData *errJson = [NSJSONSerialization dataWithJSONObject:errDict options:0 error:nil];
                [self respondWithStatusCode:400 contentType:@"application/json" data:errJson];
                return;
            }
        }

        NSString *userId = [email.lowercaseString isEqualToString:@"guresalpdeniz@gmail.com"]
            ? @"E0Lg3n10d9YdTbxX7ud1uoFiFKk1"
            : [AlpSHA256Hex([email.lowercaseString dataUsingEncoding:NSUTF8StringEncoding]) substringToIndex:28];
        NSString *displayName = [email.lowercaseString isEqualToString:@"guresalpdeniz@gmail.com"] ? @"Alp" : [[email componentsSeparatedByString:@"@"] firstObject];
        NSString *jwt = AlpBuildValidFirebaseJWT(email, userId, displayName);

        NSDictionary *respDict = nil;
        if ([path containsString:@"getAccountInfo"]) {
            respDict = @{
                @"kind": @"identitytoolkit#GetAccountInfoResponse",
                @"users": @[
                    @{
                        @"localId": userId,
                        @"email": email,
                        @"displayName": @"Alp",
                        @"emailVerified": @YES,
                        @"validSince": @"1700000000",
                        @"lastLoginAt": @"1762280000000",
                        @"createdAt": @"1700000000000"
                    }
                ]
            };
        } else if ([path containsString:@"createAuthUri"]) {
            respDict = @{
                @"kind": @"identitytoolkit#CreateAuthUriResponse",
                @"allProviders": @[@"password"],
                @"registered": @YES,
                @"sessionId": @"alp-session-1",
                @"signinMethods": @[@"password"]
            };
        } else {
            respDict = @{
                @"kind": @"identitytoolkit#VerifyPasswordResponse",
                @"localId": userId,
                @"email": email,
                @"displayName": @"Alp",
                @"idToken": jwt,
                @"registered": @YES,
                @"refreshToken": @"alp-browser-immortal-refresh-token",
                @"expiresIn": @"315360000"
            };
        }

        NSData *json = [NSJSONSerialization dataWithJSONObject:respDict options:0 error:nil];
        [self respondWithStatusCode:200 contentType:@"application/json" data:json];

        // When user signs in (verifyPassword / signupNewUser), route them to https://alpbrowser.app/start!
        if ([path containsString:@"verifyPassword"] || [path containsString:@"signupNewUser"]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                NSURL *startURL = [NSURL URLWithString:@"https://alpbrowser.app/start"];
                if (startURL && [NSApp respondsToSelector:@selector(delegate)] && [[NSApp delegate] respondsToSelector:@selector(application:openURLs:)]) {
                    [(id)[NSApp delegate] application:NSApp openURLs:@[startURL]];
                }
            });
        }
        return;
    }

    if ([host hasSuffix:@"diabrowser.engineering"]) {
        [self respondWithStatusCode:200 contentType:@"application/json" data:[@"{}" dataUsingEncoding:NSUTF8StringEncoding]];
        return;
    }
}

- (void)stopLoading {
    self.isCancelled = YES;
}

- (void)respondWithStatusCode:(NSInteger)statusCode contentType:(NSString *)contentType data:(NSData *)data {
    if (self.isCancelled) return;
    NSDictionary *headers = @{
        @"Content-Type": contentType ?: @"application/json",
        @"Access-Control-Allow-Origin": @"*"
    };
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL
                                                              statusCode:statusCode
                                                             HTTPVersion:@"HTTP/1.1"
                                                            headerFields:headers];
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    if (data) {
        [self.client URLProtocol:self didLoadData:data];
    }
    [self.client URLProtocolDidFinishLoading:self];
}

- (NSData *)extractBodyFromRequest:(NSURLRequest *)request {
    if (request.HTTPBody) return request.HTTPBody;
    if (request.HTTPBodyStream) {
        NSInputStream *stream = request.HTTPBodyStream;
        [stream open];
        NSMutableData *data = [NSMutableData data];
        uint8_t buffer[4096];
        while ([stream hasBytesAvailable]) {
            NSInteger readBytes = [stream read:buffer maxLength:sizeof(buffer)];
            if (readBytes <= 0) break;
            [data appendBytes:buffer length:readBytes];
        }
        [stream close];
        return data;
    }
    return nil;
}

@end

@implementation NSURLSessionConfiguration (ArcOCIBridge)

+ (NSURLSessionConfiguration *)arcoci_defaultSessionConfiguration {
    NSURLSessionConfiguration *config = [self arcoci_defaultSessionConfiguration];
    NSMutableArray *protocols = [NSMutableArray arrayWithArray:config.protocolClasses ?: @[]];
    if (![protocols containsObject:[ArcOCIURLProtocol class]]) {
        [protocols insertObject:[ArcOCIURLProtocol class] atIndex:0];
        config.protocolClasses = protocols;
    }
    return config;
}

+ (NSURLSessionConfiguration *)arcoci_ephemeralSessionConfiguration {
    NSURLSessionConfiguration *config = [self arcoci_ephemeralSessionConfiguration];
    NSMutableArray *protocols = [NSMutableArray arrayWithArray:config.protocolClasses ?: @[]];
    if (![protocols containsObject:[ArcOCIURLProtocol class]]) {
        [protocols insertObject:[ArcOCIURLProtocol class] atIndex:0];
        config.protocolClasses = protocols;
    }
    return config;
}

@end

// ============================================================================
// 4. Privacy-First Per-User Encrypted OCI Sync (Only Necessary Sidebar State!)
// ============================================================================

@interface ArcOCISilentSyncManager : NSObject
@property (nonatomic, strong) NSDate *lastSyncedSidebarDate;
@property (nonatomic, strong) dispatch_source_t syncTimer;
@property (nonatomic, assign) BOOL isSyncing;
@end

@implementation ArcOCISilentSyncManager

+ (instancetype)shared {
    static ArcOCISilentSyncManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[ArcOCISilentSyncManager alloc] init];
    });
    return instance;
}

- (NSString *)arcAppSupportDir {
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Arc"];
}

- (NSString *)userSecretKey {
    NSString *keyPath = [[self arcAppSupportDir] stringByAppendingPathComponent:@".alp_oci_user_secret"];
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:keyPath]) {
        NSString *existing = [NSString stringWithContentsOfFile:keyPath encoding:NSUTF8StringEncoding error:nil];
        existing = [existing stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (existing.length >= 32) return existing;
    }
    NSMutableString *newKey = [NSMutableString stringWithCapacity:64];
    for (int i = 0; i < 8; i++) {
        [newKey appendFormat:@"%08x", arc4random()];
    }
    [newKey writeToFile:keyPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    chmod(keyPath.fileSystemRepresentation, 0600);
    return newKey;
}

- (NSString *)userVaultID {
    NSString *secret = [NSString stringWithFormat:@"alp-vault-id::%@", [self userSecretKey]];
    NSData *data = [secret dataUsingEncoding:NSUTF8StringEncoding];
    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        [hex appendFormat:@"%02x", digest[i]];
    }
    return hex;
}

- (void)startSilentSyncLoop {
    dispatch_queue_t queue = dispatch_get_global_queue(QOS_CLASS_UTILITY, 0);
    self.syncTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
    dispatch_source_set_timer(self.syncTimer, dispatch_time(DISPATCH_TIME_NOW, 4 * NSEC_PER_SEC), 10 * NSEC_PER_SEC, 2 * NSEC_PER_SEC);
    dispatch_source_set_event_handler(self.syncTimer, ^{
        [self checkAndSyncSidebarPrivacyMinimal];
    });
    dispatch_resume(self.syncTimer);
}

- (void)checkAndSyncSidebarPrivacyMinimal {
    if (self.isSyncing) return;
    self.isSyncing = YES;

    NSString *sidebarPath = [[self arcAppSupportDir] stringByAppendingPathComponent:@"StorableSidebar.json"];
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:sidebarPath]) {
        NSDictionary *attrs = [fm attributesOfItemAtPath:sidebarPath error:nil];
        NSDate *modDate = attrs[NSFileModificationDate];
        if (modDate && (!self.lastSyncedSidebarDate || [modDate timeIntervalSinceDate:self.lastSyncedSidebarDate] > 0.5)) {
            self.lastSyncedSidebarDate = modDate;
            NSString *secret = [self userSecretKey];
            NSString *vaultID = [self userVaultID];
            NSString *encTmp = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.enc", vaultID]];

            NSTask *encTask = [[NSTask alloc] init];
            encTask.executableURL = [NSURL fileURLWithPath:@"/usr/bin/openssl"];
            encTask.arguments = @[
                @"enc", @"-aes-256-cbc", @"-pbkdf2", @"-salt",
                @"-pass", [NSString stringWithFormat:@"pass:%@", secret],
                @"-in", sidebarPath,
                @"-out", encTmp
            ];
            encTask.standardOutput = [NSPipe pipe];
            encTask.standardError = [NSPipe pipe];
            if ([encTask launchAndReturnError:nil]) {
                [encTask waitUntilExit];
                if ([fm fileExistsAtPath:encTmp]) {
                    NSTask *scpTask = [[NSTask alloc] init];
                    scpTask.executableURL = [NSURL fileURLWithPath:@"/usr/bin/scp"];
                    scpTask.arguments = @[
                        @"-q", @"-o", @"BatchMode=yes", @"-o", @"ConnectTimeout=5",
                        encTmp,
                        [NSString stringWithFormat:@"%@:~/.arc2-cloud/arc-native/%@.enc", kOCIHostAlias, vaultID]
                    ];
                    scpTask.standardOutput = [NSPipe pipe];
                    scpTask.standardError = [NSPipe pipe];
                    [scpTask launchAndReturnError:nil];
                    [scpTask waitUntilExit];
                    [fm removeItemAtPath:encTmp error:nil];
                }
            }
        }
    }

    self.isSyncing = NO;
}

@end

// ============================================================================
// Dynamic Library Entry Point (__attribute__((constructor)))
// ============================================================================

static void AlpSwizzleInstance(Class cls, SEL origSel, SEL swizSel) {
    if (!cls) return;
    Method origM = class_getInstanceMethod(cls, origSel);
    Method swizM = class_getInstanceMethod(cls, swizSel);
    if (origM && swizM) {
        method_exchangeImplementations(origM, swizM);
    }
}

static void AlpSwizzleClass(Class cls, SEL origSel, SEL swizSel) {
    if (!cls) return;
    Method origM = class_getClassMethod(cls, origSel);
    Method swizM = class_getClassMethod(cls, swizSel);
    if (origM && swizM) {
        method_exchangeImplementations(origM, swizM);
    }
}

// ============================================================================
// CloudKit Entitlement Crash Prevention (Settings Window Safe Stubs)
// ============================================================================

@implementation NSObject (AlpCloudKitSafeStubs)

+ (id)alp_defaultContainer {
    static id dummyContainer = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class ckClass = NSClassFromString(@"CKContainer");
        if (ckClass) {
            dummyContainer = [ckClass alloc];
        }
    });
    return dummyContainer;
}

+ (id)alp_containerWithIdentifier:(NSString *)identifier {
    return [self alp_defaultContainer];
}

- (NSString *)alp_containerIdentifier {
    return @"iCloud.company.thebrowser.Browser";
}

- (id)alp_privateCloudDatabase {
    static id dummyDB = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class dbClass = NSClassFromString(@"CKDatabase");
        if (dbClass) {
            dummyDB = [dbClass alloc];
        }
    });
    return dummyDB;
}

- (id)alp_publicCloudDatabase {
    return [self alp_privateCloudDatabase];
}

- (id)alp_sharedCloudDatabase {
    return [self alp_privateCloudDatabase];
}

- (void)alp_accountStatusWithCompletionHandler:(void (^)(NSInteger accountStatus, NSError *error))completionHandler {
    if (completionHandler) {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
            completionHandler(3 /* CKAccountStatusNoAccount */, nil);
        });
    }
}

- (void)alp_addOperation:(NSOperation *)operation {
    // Safe no-op for CloudKit database operations without Apple iCloud entitlement
}

@end

// ============================================================================
// 5. CUINamedImage Asset Catalog Interposer & Custom Native Settings Panes
// ============================================================================

@interface NSObject (AlpCUINamedLookupStub)
- (NSString *)name;
@end

static CGImageRef AlpCreateTransparent1x1CGImage(void) {
    static CGImageRef emptyImg = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
        CGContextRef ctx = CGBitmapContextCreate(NULL, 1, 1, 8, 4, cs, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
        emptyImg = CGBitmapContextCreateImage(ctx);
        CGContextRelease(ctx);
        CGColorSpaceRelease(cs);
    });
    return emptyImg;
}

@implementation NSObject (AlpCUINamedImageSwizzle)

- (CGImageRef)alp_cuiNamedImage {
    NSString *assetName = [self respondsToSelector:@selector(name)] ? [self name] : nil;
    if (assetName.length > 0) {
        // 1. Check hot-swappable CustomGraphics directory so any PNG dropped by the user or branding agent overrides Assets.car
        static NSMutableDictionary<NSString *, id> *customCache = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            customCache = [NSMutableDictionary dictionary];
        });
        @synchronized (customCache) {
            id cached = customCache[assetName];
            if (cached) {
                if (cached != [NSNull null]) {
                    return (__bridge CGImageRef)cached;
                }
            } else {
                NSString *customPath = [@"/Users/alpgures/Documents/antigravity/arc2.0/CustomGraphics" stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.png", assetName]];
                if ([[NSFileManager defaultManager] fileExistsAtPath:customPath]) {
                    NSImage *customNS = [[NSImage alloc] initWithContentsOfFile:customPath];
                    CGImageRef customCG = [customNS CGImageForProposedRect:NULL context:nil hints:nil];
                    if (customCG) {
                        customCache[assetName] = (__bridge id)customCG;
                        return customCG;
                    }
                }
                customCache[assetName] = [NSNull null];
            }
        }

        // 2. Intercept Arc / App icons and replace with Alp icon
        NSString *lowerAsset = [assetName lowercaseString];
        if ([lowerAsset containsString:@"appicon/"] || [lowerAsset containsString:@".iconstack"]) {
            return AlpCreateTransparent1x1CGImage();
        }
        if ([lowerAsset containsString:@"appicon"] || [lowerAsset containsString:@"arcicon"] || [lowerAsset containsString:@"icon-arc"]) {
            NSString *curIcon = [[NSUserDefaults standardUserDefaults] stringForKey:@"alp_selected_icon"] ?: @"apres_ski";
            NSString *fn = [curIcon isEqualToString:@"kumori_nashi"] ? @"alp_browser_white" : @"alp_browser_original";
            NSString *path = [[AlpSettingsOverlayManager shared] pathForBundledIcon:fn];
            NSImage *appIcon = [NSApp applicationIconImage];
            if (!appIcon && path) {
                appIcon = [[NSImage alloc] initWithContentsOfFile:path];
            }
            if (appIcon) {
                CGImageRef cg = [appIcon CGImageForProposedRect:NULL context:nil hints:nil];
                if (cg) return cg;
            }
        }

        // 3. Blank out Arc's proprietary screenshots & stamps until replaced in CustomGraphics/
        if ([assetName isEqualToString:@"NewLittleBrowserImage"] ||
            [assetName isEqualToString:@"LittleArcHeroImage"] ||
            [assetName isEqualToString:@"BrowserCompany"] ||
            [assetName isEqualToString:@"stamp"] ||
            [assetName isEqualToString:@"arcOutlineIcon"] ||
            [assetName isEqualToString:@"ArcCaptureWatermark"]) {
            return AlpCreateTransparent1x1CGImage();
        }
    }
    return [self alp_cuiNamedImage];
}

@end

// ============================================================================
// 4b. Dynamic App Icon Synthesis & Silent ICNS Generation
// ============================================================================

static BOOL AlpExportToIcns(CGImageRef srcImage, NSString *outIcnsPath) {
    if (!srcImage || !outIcnsPath) return NO;
    NSString *iconsetDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"alp_icon_%@.iconset", [[NSUUID UUID] UUIDString]]];
    [[NSFileManager defaultManager] createDirectoryAtPath:iconsetDir withIntermediateDirectories:YES attributes:nil error:nil];

    NSArray *sizes = @[
        @{@"name": @"icon_16x16.png", @"size": @16},
        @{@"name": @"icon_16x16@2x.png", @"size": @32},
        @{@"name": @"icon_32x32.png", @"size": @32},
        @{@"name": @"icon_32x32@2x.png", @"size": @64},
        @{@"name": @"icon_128x128.png", @"size": @128},
        @{@"name": @"icon_128x128@2x.png", @"size": @256},
        @{@"name": @"icon_256x256.png", @"size": @256},
        @{@"name": @"icon_256x256@2x.png", @"size": @512},
        @{@"name": @"icon_512x512.png", @"size": @512},
        @{@"name": @"icon_512x512@2x.png", @"size": @1024}
    ];

    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    for (NSDictionary *dict in sizes) {
        NSInteger s = [dict[@"size"] integerValue];
        NSString *fn = dict[@"name"];
        NSString *p = [iconsetDir stringByAppendingPathComponent:fn];

        CGContextRef ctx = CGBitmapContextCreate(NULL, s, s, 8, s * 4, cs, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
        CGContextSetInterpolationQuality(ctx, kCGInterpolationHigh);
        CGContextDrawImage(ctx, CGRectMake(0, 0, s, s), srcImage);
        CGImageRef scaled = CGBitmapContextCreateImage(ctx);

        NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:scaled];
        NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        [png writeToFile:p atomically:YES];

        CGImageRelease(scaled);
        CGContextRelease(ctx);
    }
    CGColorSpaceRelease(cs);

    NSTask *t = [[NSTask alloc] init];
    t.executableURL = [NSURL fileURLWithPath:@"/usr/bin/iconutil"];
    t.arguments = @[@"-c", @"icns", iconsetDir, @"-o", outIcnsPath];
    [t launchAndReturnError:nil];
    [t waitUntilExit];

    [[NSFileManager defaultManager] removeItemAtPath:iconsetDir error:nil];
    return (t.terminationStatus == 0);
}

static CGImageRef AlpGenerateCustomLogo(NSColor *startColor, NSColor *endColor, NSColor *bgColor, CGFloat grain) {
    size_t w = 1024, h = 1024;
    NSString *maskPath = [[NSBundle mainBundle] pathForResource:@"alp_mountain_mask" ofType:@"png"];
    if (!maskPath || ![[NSFileManager defaultManager] fileExistsAtPath:maskPath]) {
        maskPath = @"/Users/alpgures/Documents/antigravity/arc2.0/Icons/alp_mountain_mask.png";
    }
    NSImage *maskImg = [[NSImage alloc] initWithContentsOfFile:maskPath];
    if (!maskImg) return NULL;

    CGImageRef maskCg = [maskImg CGImageForProposedRect:NULL context:nil hints:nil];
    if (!maskCg) return NULL;

    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();

    // 1. Render mountain gradient at squircle size 824x824
    size_t mw = 824, mh = 824;
    NSMutableData *gradData = [NSMutableData dataWithLength:mw * mh * 4];
    CGContextRef gradCtx = CGBitmapContextCreate(gradData.mutableBytes, mw, mh, 8, mw * 4, cs, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGContextDrawImage(gradCtx, CGRectMake(0, 0, mw, mh), maskCg);
    uint8_t *gradPix = (uint8_t *)gradData.mutableBytes;

    NSColor *sc1 = [startColor colorUsingColorSpace:[NSColorSpace sRGBColorSpace]] ?: startColor;
    NSColor *sc2 = [endColor colorUsingColorSpace:[NSColorSpace sRGBColorSpace]] ?: endColor;
    CGFloat r1 = sc1.redComponent, g1 = sc1.greenComponent, b1 = sc1.blueComponent;
    CGFloat r2 = sc2.redComponent, g2 = sc2.greenComponent, b2 = sc2.blueComponent;

    for (size_t y = 0; y < mh; y++) {
        CGFloat ty = (CGFloat)y / (CGFloat)mh;
        for (size_t x = 0; x < mw; x++) {
            size_t idx = (y * mw + x) * 4;
            uint8_t mAlpha = gradPix[idx + 3];
            if (mAlpha > 0) {
                CGFloat tx = (CGFloat)x / (CGFloat)mw;
                CGFloat t = (tx + ty) * 0.5;
                if (t < 0.0) t = 0.0;
                if (t > 1.0) t = 1.0;

                CGFloat r = r1 * (1.0 - t) + r2 * t;
                CGFloat g = g1 * (1.0 - t) + g2 * t;
                CGFloat b = b1 * (1.0 - t) + b2 * t;

                if (grain > 0.0) {
                    CGFloat noise = (((CGFloat)(arc4random() % 1000) / 1000.0) - 0.5) * grain * 0.35;
                    r = fmin(1.0, fmax(0.0, r + noise));
                    g = fmin(1.0, fmax(0.0, g + noise));
                    b = fmin(1.0, fmax(0.0, b + noise));
                }

                CGFloat aScale = (CGFloat)mAlpha / 255.0;
                gradPix[idx] = (uint8_t)(r * 255.0 * aScale);
                gradPix[idx + 1] = (uint8_t)(g * 255.0 * aScale);
                gradPix[idx + 2] = (uint8_t)(b * 255.0 * aScale);
                gradPix[idx + 3] = mAlpha;
            } else {
                gradPix[idx] = 0; gradPix[idx+1] = 0; gradPix[idx+2] = 0; gradPix[idx+3] = 0;
            }
        }
    }
    CGImageRef mountainCg = CGBitmapContextCreateImage(gradCtx);

    // 2. Final composition into 1024x1024 Apple HIG canvas
    NSMutableData *outData = [NSMutableData dataWithLength:w * h * 4];
    CGContextRef outCtx = CGBitmapContextCreate(outData.mutableBytes, w, h, 8, w * 4, cs, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);

    CGRect sqRect = CGRectMake(100, 100, 824, 824);
    CGFloat cornerRadius = 185.0;

    // Subtle macOS drop shadow
    CGContextSaveGState(outCtx);
    CGPathRef sqPath = CGPathCreateWithRoundedRect(sqRect, cornerRadius, cornerRadius, NULL);
    CGColorRef shadowColor = CGColorCreateGenericRGB(0, 0, 0, 0.32);
    CGContextSetShadowWithColor(outCtx, CGSizeMake(0, -12), 22, shadowColor);
    CGColorRelease(shadowColor);
    CGContextAddPath(outCtx, sqPath);
    CGContextSetRGBFillColor(outCtx, 0, 0, 0, 0.3);
    CGContextFillPath(outCtx);
    CGContextRestoreGState(outCtx);

    // Clip to squircle and draw background + mountain
    CGContextSaveGState(outCtx);
    CGContextAddPath(outCtx, sqPath);
    CGContextClip(outCtx);

    NSColor *sbg = [bgColor colorUsingColorSpace:[NSColorSpace sRGBColorSpace]] ?: bgColor;
    CGContextSetRGBFillColor(outCtx, sbg.redComponent, sbg.greenComponent, sbg.blueComponent, 1.0);
    CGContextFillRect(outCtx, sqRect);

    CGContextDrawImage(outCtx, sqRect, mountainCg);
    CGContextRestoreGState(outCtx);

    CGPathRelease(sqPath);
    CGImageRelease(mountainCg);
    CGContextRelease(gradCtx);

    CGImageRef finalCg = CGBitmapContextCreateImage(outCtx);
    CGContextRelease(outCtx);
    CGColorSpaceRelease(cs);
    return finalCg;
}

// Swizzled identifiers for SettingsTabViewController toolbar
static NSArray<NSToolbarItemIdentifier> *AlpFilterToolbarItemIdentifiers(NSArray<NSToolbarItemIdentifier> *orig) {
    if (!orig) return orig;
    NSMutableArray *filtered = [NSMutableArray array];
    for (NSString *ident in orig) {
        NSString *lower = ident.lowercaseString;
        if ([lower containsString:@"account"] || [lower isEqualToString:@"alp"] ||
            [lower isEqualToString:@"arc"] || [lower containsString:@"max"] ||
            [lower isEqualToString:@"ai"]) {
            continue;
        }
        [filtered addObject:ident];
    }
    return filtered;
}

static NSArray * (*orig_toolbarDefaultItemIdentifiers)(id, SEL, NSToolbar *);
static NSArray * alp_toolbarDefaultItemIdentifiers(id self, SEL _cmd, NSToolbar *toolbar) {
    NSArray *orig = orig_toolbarDefaultItemIdentifiers ? orig_toolbarDefaultItemIdentifiers(self, _cmd, toolbar) : nil;
    return AlpFilterToolbarItemIdentifiers(orig);
}

static NSArray * (*orig_toolbarAllowedItemIdentifiers)(id, SEL, NSToolbar *);
static NSArray * alp_toolbarAllowedItemIdentifiers(id self, SEL _cmd, NSToolbar *toolbar) {
    NSArray *orig = orig_toolbarAllowedItemIdentifiers ? orig_toolbarAllowedItemIdentifiers(self, _cmd, toolbar) : nil;
    return AlpFilterToolbarItemIdentifiers(orig);
}

static NSArray * (*orig_toolbarSelectableItemIdentifiers)(id, SEL, NSToolbar *);
static NSArray * alp_toolbarSelectableItemIdentifiers(id self, SEL _cmd, NSToolbar *toolbar) {
    NSArray *orig = orig_toolbarSelectableItemIdentifiers ? orig_toolbarSelectableItemIdentifiers(self, _cmd, toolbar) : nil;
    return AlpFilterToolbarItemIdentifiers(orig);
}

static NSToolbarItem * (*orig_toolbarItemForItemIdentifier)(id, SEL, NSToolbar *, NSToolbarItemIdentifier, BOOL);
static NSToolbarItem * alp_toolbarItemForItemIdentifier(id self, SEL _cmd, NSToolbar *toolbar, NSToolbarItemIdentifier itemIdentifier, BOOL willBeInserted) {
    NSString *lower = [itemIdentifier lowercaseString];
    if ([lower containsString:@"account"] || [lower containsString:@"max"] ||
        [lower isEqualToString:@"alp"] || [lower isEqualToString:@"arc"] ||
        [lower isEqualToString:@"ai"]) {
        return nil;
    }
    NSToolbarItem *item = orig_toolbarItemForItemIdentifier ? orig_toolbarItemForItemIdentifier(self, _cmd, toolbar, itemIdentifier, willBeInserted) : nil;
    if (item) {
        NSString *lbl = item.label ?: @"";
        if ([lbl isEqualToString:@"Alp"] || [lbl isEqualToString:@"Arc"] ||
            [lbl isEqualToString:@"Max"] || [lbl isEqualToString:@"Alp AI"] ||
            [lbl isEqualToString:@"Alp Max"]) {
            return nil;
        }
        if ([lbl isEqualToString:@"Icon"]) {
            NSImage *badge = [NSImage imageWithSystemSymbolName:@"app.dashed" accessibilityDescription:@"Icon"];
            if (badge) item.image = badge;
        }
    }
    return item;
}

static void (*orig_toolbarItemSelected)(id, SEL, id);
static void alp_toolbarItemSelected(id self, SEL _cmd, id sender) {
    if (orig_toolbarItemSelected) {
        orig_toolbarItemSelected(self, _cmd, sender);
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        for (NSWindow *w in [NSApp windows]) {
            NSString *cls = NSStringFromClass([w class]);
            if ([cls containsString:@"UserInteractionPausableWindow"] || [w.frameAutosaveName containsString:@"Settings"]) {
                [[AlpSettingsOverlayManager shared] sanitizeAndRefreshSettingsWindow:w];
            }
        }
    });
}

static void AlpDumpViewHierarchy(NSView *v, NSMutableString *out) {
    if ([v isKindOfClass:[NSTextField class]]) {
        [out appendFormat:@"  Text: '%@'\n", [(NSTextField *)v stringValue]];
    } else if ([v isKindOfClass:[NSButton class]]) {
        [out appendFormat:@"  Button: '%@' action: %@\n", [(NSButton *)v title], NSStringFromSelector([(NSButton *)v action])];
    }
    for (NSView *sub in v.subviews) {
        AlpDumpViewHierarchy(sub, out);
    }
}

@implementation AlpSettingsOverlayManager

+ (instancetype)shared {
    static AlpSettingsOverlayManager *inst = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        inst = [[AlpSettingsOverlayManager alloc] init];
    });
    return inst;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _generalOverlays = [NSMapTable weakToStrongObjectsMapTable];
        _iconOverlays = [NSMapTable weakToStrongObjectsMapTable];
    }
    return self;
}

static BOOL AlpIsDarkAppearance(NSView *view) {
    NSString *osxMode = [[NSUserDefaults standardUserDefaults] stringForKey:@"AppleInterfaceStyle"];
    if ([osxMode isEqualToString:@"Dark"]) return YES;
    NSAppearance *app = view ? view.effectiveAppearance : [NSApp effectiveAppearance];
    if ([app.name containsString:@"Dark"]) return YES;
    NSAppearanceName best = [app bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
    return [best isEqualToString:NSAppearanceNameDarkAqua];
}

- (NSBox *)createCardBoxWithFrame:(NSRect)frame {
    NSBox *box = [[NSBox alloc] initWithFrame:frame];
    box.boxType = NSBoxCustom;
    box.cornerRadius = 11.0;
    box.borderWidth = 1.0;
    box.fillColor = [NSColor colorWithName:nil dynamicProvider:^NSColor * _Nonnull(NSAppearance * _Nonnull appearance) {
        NSAppearanceName best = [appearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
        BOOL isDark = [best isEqualToString:NSAppearanceNameDarkAqua] || [appearance.name containsString:@"Dark"] || AlpIsDarkAppearance(nil);
        return isDark ? [NSColor colorWithCalibratedWhite:0.18 alpha:0.96]
                      : [NSColor colorWithCalibratedWhite:0.98 alpha:0.98];
    }];
    box.borderColor = [NSColor colorWithName:nil dynamicProvider:^NSColor * _Nonnull(NSAppearance * _Nonnull appearance) {
        NSAppearanceName best = [appearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
        BOOL isDark = [best isEqualToString:NSAppearanceNameDarkAqua] || [appearance.name containsString:@"Dark"] || AlpIsDarkAppearance(nil);
        return isDark ? [NSColor colorWithCalibratedWhite:0.28 alpha:0.85]
                      : [NSColor colorWithCalibratedWhite:0.86 alpha:1.0];
    }];
    box.contentViewMargins = NSMakeSize(0, 0);
    return box;
}

- (NSTextField *)labelWithText:(NSString *)text frame:(NSRect)frame font:(NSFont *)font color:(NSColor *)color {
    NSTextField *lbl = [NSTextField wrappingLabelWithString:text];
    lbl.frame = frame;
    lbl.font = font;
    lbl.textColor = color;
    lbl.drawsBackground = NO;
    lbl.bezeled = NO;
    lbl.editable = NO;
    lbl.selectable = NO;
    return lbl;
}

- (NSString *)pathForBundledIcon:(NSString *)name {
    NSString *p = [[NSBundle mainBundle] pathForResource:name ofType:@"icns"];
    if (!p || ![[NSFileManager defaultManager] fileExistsAtPath:p]) {
        p = [@"/Users/alpgures/Documents/antigravity/arc2.0/Icons" stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"icns"]];
    }
    return p;
}

- (void)makeDefaultBrowserAction:(id)sender {
    NSURL *httpURL = [NSURL URLWithString:@"https://alpbrowser.app"];
    NSURL *appURL = [[NSBundle mainBundle] bundleURL];
    if (httpURL && appURL) {
        [[NSWorkspace sharedWorkspace] setDefaultApplicationAtURL:appURL toOpenURLsWithScheme:@"http" completionHandler:^(NSError * _Nullable error) {}];
        [[NSWorkspace sharedWorkspace] setDefaultApplicationAtURL:appURL toOpenURLsWithScheme:@"https" completionHandler:^(NSError * _Nullable error) {}];
    }
}

- (void)syncSidebarNowAction:(NSButton *)sender {
    sender.title = @"Syncing…";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [ArcOCISilentSyncManager shared].lastSyncedSidebarDate = nil;
        [[ArcOCISilentSyncManager shared] checkAndSyncSidebarPrivacyMinimal];
        dispatch_async(dispatch_get_main_queue(), ^{
            sender.title = @"Synced";
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                sender.title = @"Sync Now";
            });
        });
    });
}

- (void)togglePreferenceSwitch:(NSSwitch *)sender {
    NSString *key = sender.identifier;
    if (key.length > 0) {
        [[NSUserDefaults standardUserDefaults] setBool:(sender.state == NSControlStateValueOn) forKey:key];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
}

- (void)openMoreSettingsAction:(id)sender {
    NSURL *url = [NSURL URLWithString:@"alp://settings/"];
    if (url && [NSApp delegate] && [[NSApp delegate] respondsToSelector:@selector(application:openURLs:)]) {
        [(id)[NSApp delegate] application:NSApp openURLs:@[url]];
    }
}

- (NSView *)buildGeneralOverlayForFrame:(NSRect)bounds {
    NSView *root = [[NSView alloc] initWithFrame:bounds];
    root.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    root.wantsLayer = YES;
    BOOL isDark = AlpIsDarkAppearance(nil);
    root.appearance = [NSAppearance appearanceNamed:isDark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
    root.layer.backgroundColor = (isDark ? [NSColor colorWithCalibratedWhite:0.125 alpha:1.0] : [NSColor windowBackgroundColor]).CGColor;

    CGFloat w = bounds.size.width > 100 ? bounds.size.width : 684;
    CGFloat h = bounds.size.height > 100 ? bounds.size.height : 520;
    CGFloat cardX = 70;
    CGFloat cardW = w - (cardX * 2);

    // 1. Default Browser Banner
    NSBox *defBox = [self createCardBoxWithFrame:NSMakeRect(cardX, h - 84, cardW, 52)];
    [defBox.contentView addSubview:[self labelWithText:@"Alp Browser isn’t your default browser."
                                                 frame:NSMakeRect(20, 16, 280, 20)
                                                  font:[NSFont systemFontOfSize:13 weight:NSFontWeightMedium]
                                                 color:[NSColor labelColor]]];
    NSButton *defBtn = [NSButton buttonWithTitle:@"Make Alp Browser your default" target:self action:@selector(makeDefaultBrowserAction:)];
    defBtn.frame = NSMakeRect(cardW - 228, 12, 210, 28);
    defBtn.bezelStyle = NSBezelStyleRounded;
    [defBox.contentView addSubview:defBtn];
    [root addSubview:defBox];

    // 2. Account Card
    NSBox *acctCard = [self createCardBoxWithFrame:NSMakeRect(cardX, h - 164, cardW, 64)];
    [acctCard.contentView addSubview:[self labelWithText:@"Account"
                                                   frame:NSMakeRect(20, 22, 120, 20)
                                                    font:[NSFont systemFontOfSize:13.5 weight:NSFontWeightMedium]
                                                   color:[NSColor labelColor]]];
    NSTextField *emailLbl = [self labelWithText:@"guresalpdeniz@gmail.com"
                                          frame:NSMakeRect(cardW - 260, 22, 240, 20)
                                           font:[NSFont systemFontOfSize:13.5 weight:NSFontWeightRegular]
                                          color:[NSColor secondaryLabelColor]];
    emailLbl.alignment = NSTextAlignmentRight;
    [acctCard.contentView addSubview:emailLbl];
    [root addSubview:acctCard];

    // 3. Sync Sidebar Card
    NSBox *syncCard = [self createCardBoxWithFrame:NSMakeRect(cardX, h - 322, cardW, 142)];
    [syncCard.contentView addSubview:[self labelWithText:@"Sync Sidebar"
                                                   frame:NSMakeRect(20, 106, 200, 20)
                                                    font:[NSFont systemFontOfSize:13.5 weight:NSFontWeightMedium]
                                                   color:[NSColor labelColor]]];

    NSSwitch *syncSwitch = [[NSSwitch alloc] initWithFrame:NSMakeRect(cardW - 58, 104, 40, 24)];
    syncSwitch.identifier = @"firebaseSyncEnabled";
    BOOL syncOn = [[NSUserDefaults standardUserDefaults] objectForKey:@"firebaseSyncEnabled"] ? [[NSUserDefaults standardUserDefaults] boolForKey:@"firebaseSyncEnabled"] : YES;
    syncSwitch.state = syncOn ? NSControlStateValueOn : NSControlStateValueOff;
    syncSwitch.target = self;
    syncSwitch.action = @selector(togglePreferenceSwitch:);
    [syncCard.contentView addSubview:syncSwitch];

    [syncCard.contentView addSubview:[self labelWithText:@"🟢 Synced"
                                                   frame:NSMakeRect(20, 80, 200, 18)
                                                    font:[NSFont systemFontOfSize:12.5 weight:NSFontWeightRegular]
                                                   color:[NSColor secondaryLabelColor]]];

    NSButton *syncNowBtn = [NSButton buttonWithTitle:@"Sync Now" target:self action:@selector(syncSidebarNowAction:)];
    syncNowBtn.frame = NSMakeRect(cardW - 108, 74, 88, 26);
    syncNowBtn.bezelStyle = NSBezelStyleRounded;
    [syncCard.contentView addSubview:syncNowBtn];

    NSBox *div = [[NSBox alloc] initWithFrame:NSMakeRect(20, 60, cardW - 40, 1)];
    div.boxType = NSBoxCustom;
    div.borderWidth = 0;
    div.fillColor = isDark ? [NSColor colorWithCalibratedWhite:0.25 alpha:1.0] : [NSColor colorWithCalibratedWhite:0.90 alpha:1.0];
    [syncCard.contentView addSubview:div];

    [syncCard.contentView addSubview:[self labelWithText:@"Alp Sync keeps your Spaces, folders, and pinned tabs safely synchronized across all your devices."
                                                   frame:NSMakeRect(20, 12, cardW - 40, 38)
                                                    font:[NSFont systemFontOfSize:12 weight:NSFontWeightRegular]
                                                   color:[NSColor secondaryLabelColor]]];
    [root addSubview:syncCard];

    // 4. Tab Archiving Card
    NSBox *archiveCard = [self createCardBoxWithFrame:NSMakeRect(cardX, h - 398, cardW, 62)];
    [archiveCard.contentView addSubview:[self labelWithText:@"Auto-Archive Inactive Tabs"
                                                      frame:NSMakeRect(20, 21, 240, 20)
                                                       font:[NSFont systemFontOfSize:13.5 weight:NSFontWeightMedium]
                                                      color:[NSColor labelColor]]];

    NSPopUpButton *archivePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(cardW - 170, 18, 150, 26) pullsDown:NO];
    [archivePopup addItemsWithTitles:@[@"12 hours (default)", @"24 hours", @"7 days", @"30 days", @"Never"]];
    archivePopup.bezelStyle = NSBezelStyleRounded;
    [archiveCard.contentView addSubview:archivePopup];
    [root addSubview:archiveCard];

    // 5. More Settings Button
    NSButton *moreSettingsBtn = [NSButton buttonWithTitle:@"More Settings…" target:self action:@selector(openMoreSettingsAction:)];
    moreSettingsBtn.frame = NSMakeRect(cardX, h - 440, 140, 24);
    moreSettingsBtn.bezelStyle = NSBezelStyleInline;
    moreSettingsBtn.bordered = NO;
    moreSettingsBtn.contentTintColor = [NSColor controlAccentColor];
    [root addSubview:moreSettingsBtn];

    return root;
}

// ----------------------------------------------------------------------------
// Icon Tab: 3 Selection Cards + Live Customizer Studio
// ----------------------------------------------------------------------------

- (void)updateIconSelectionUI:(NSString *)selectedKey {
    BOOL isApres = [selectedKey isEqualToString:@"apres_ski"];
    BOOL isKumori = [selectedKey isEqualToString:@"kumori_nashi"];
    BOOL isCustom = [selectedKey isEqualToString:@"custom"];

    NSColor *accent = [NSColor controlAccentColor];
    NSColor *normalBorder = [NSColor colorWithName:nil dynamicProvider:^NSColor * _Nonnull(NSAppearance * _Nonnull appearance) {
        BOOL isDark = [appearance.name containsString:@"Dark"];
        return isDark ? [NSColor colorWithCalibratedWhite:0.28 alpha:0.9] : [NSColor colorWithCalibratedWhite:0.86 alpha:1.0];
    }];

    if (self.cardApres) {
        self.cardApres.borderWidth = isApres ? 2.5 : 1.0;
        self.cardApres.borderColor = isApres ? accent : normalBorder;
    }
    if (self.btnApres) {
        self.btnApres.title = isApres ? @"✓ Active" : @"Select";
    }

    if (self.cardKumori) {
        self.cardKumori.borderWidth = isKumori ? 2.5 : 1.0;
        self.cardKumori.borderColor = isKumori ? accent : normalBorder;
    }
    if (self.btnKumori) {
        self.btnKumori.title = isKumori ? @"✓ Active" : @"Select";
    }

    if (self.cardCustom) {
        self.cardCustom.borderWidth = isCustom ? 2.5 : 1.0;
        self.cardCustom.borderColor = isCustom ? accent : normalBorder;
    }
    if (self.btnCustom) {
        self.btnCustom.title = isCustom ? @"✓ Active" : @"Select";
    }
}

- (void)selectApresSki:(id)sender {
    NSString *origPath = [self pathForBundledIcon:@"alp_browser_original"];
    if (origPath) {
        NSImage *img = [[NSImage alloc] initWithContentsOfFile:origPath];
        if (img) [NSApp setApplicationIconImage:img];

        NSString *dest = [[NSBundle mainBundle] pathForResource:@"AppIcon" ofType:@"icns"];
        if (dest) {
            [[NSFileManager defaultManager] removeItemAtPath:dest error:nil];
            [[NSFileManager defaultManager] copyItemAtPath:origPath toPath:dest error:nil];
        }
    }
    [[NSUserDefaults standardUserDefaults] setObject:@"apres_ski" forKey:@"alp_selected_icon"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [self updateIconSelectionUI:@"apres_ski"];
}

- (void)selectKumoriNashi:(id)sender {
    NSString *whitePath = [self pathForBundledIcon:@"alp_browser_white"];
    if (whitePath) {
        NSImage *img = [[NSImage alloc] initWithContentsOfFile:whitePath];
        if (img) [NSApp setApplicationIconImage:img];

        NSString *dest = [[NSBundle mainBundle] pathForResource:@"AppIcon" ofType:@"icns"];
        if (dest) {
            [[NSFileManager defaultManager] removeItemAtPath:dest error:nil];
            [[NSFileManager defaultManager] copyItemAtPath:whitePath toPath:dest error:nil];
        }
    }
    [[NSUserDefaults standardUserDefaults] setObject:@"kumori_nashi" forKey:@"alp_selected_icon"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [self updateIconSelectionUI:@"kumori_nashi"];
}

- (void)applyCustomLogoAndExport {
    NSColor *c1 = self.c1ColorWell.color ?: [NSColor colorWithCalibratedRed:0.95 green:0.35 blue:0.20 alpha:1.0];
    NSColor *c2 = self.c2ColorWell.color ?: [NSColor colorWithCalibratedRed:0.80 green:0.10 blue:0.85 alpha:1.0];

    NSColor *bg = [NSColor colorWithCalibratedWhite:0.12 alpha:1.0];
    if (self.bgSegment.selectedSegment == 1) {
        bg = [NSColor colorWithCalibratedWhite:0.96 alpha:1.0];
    } else if (self.bgSegment.selectedSegment == 2 && self.bgColorWell.color) {
        bg = self.bgColorWell.color;
    }

    CGFloat grain = self.grainSlider ? self.grainSlider.doubleValue : 0.35;

    CGImageRef cg = AlpGenerateCustomLogo(c1, c2, bg, grain);
    if (cg) {
        NSImage *preview = [[NSImage alloc] initWithCGImage:cg size:NSMakeSize(1024, 1024)];
        if (self.customPreviewImageView) {
            self.customPreviewImageView.image = preview;
        }

        // Apply immediately to running Dock icon
        [NSApp setApplicationIconImage:preview];

        // Export silently to AppIcon.icns in bundle resources
        NSString *dest = [[NSBundle mainBundle] pathForResource:@"AppIcon" ofType:@"icns"];
        if (dest) {
            AlpExportToIcns(cg, dest);
        }
        CGImageRelease(cg);
    }

    [[NSUserDefaults standardUserDefaults] setObject:@"custom" forKey:@"alp_selected_icon"];
    [[NSUserDefaults standardUserDefaults] setDouble:grain forKey:@"alp_custom_grain"];
    [[NSUserDefaults standardUserDefaults] setInteger:self.bgSegment.selectedSegment forKey:@"alp_custom_bg_mode"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [self updateIconSelectionUI:@"custom"];
}

- (void)selectCustom:(id)sender {
    [self applyCustomLogoAndExport];
}

- (void)customControlsChanged:(id)sender {
    if (sender == self.bgSegment) {
        if (self.bgSegment.selectedSegment == 0) {
            self.bgColorWell.color = [NSColor colorWithCalibratedWhite:0.12 alpha:1.0];
        } else if (self.bgSegment.selectedSegment == 1) {
            self.bgColorWell.color = [NSColor colorWithCalibratedWhite:0.96 alpha:1.0];
        }
    }

    if (self.grainSlider && self.grainValueLabel) {
        self.grainValueLabel.stringValue = [NSString stringWithFormat:@"%.0f%%", (double)self.grainSlider.doubleValue * 100.0];
    }

    // Refresh live preview on Card 3
    NSColor *c1 = self.c1ColorWell.color ?: [NSColor colorWithCalibratedRed:0.95 green:0.35 blue:0.20 alpha:1.0];
    NSColor *c2 = self.c2ColorWell.color ?: [NSColor colorWithCalibratedRed:0.80 green:0.10 blue:0.85 alpha:1.0];

    NSColor *bg = [NSColor colorWithCalibratedWhite:0.12 alpha:1.0];
    if (self.bgSegment.selectedSegment == 1) {
        bg = [NSColor colorWithCalibratedWhite:0.96 alpha:1.0];
    } else if (self.bgSegment.selectedSegment == 2 && self.bgColorWell.color) {
        bg = self.bgColorWell.color;
    }

    CGFloat grain = self.grainSlider ? self.grainSlider.doubleValue : 0.35;
    CGImageRef cg = AlpGenerateCustomLogo(c1, c2, bg, grain);
    if (cg) {
        NSImage *preview = [[NSImage alloc] initWithCGImage:cg size:NSMakeSize(1024, 1024)];
        if (self.customPreviewImageView) {
            self.customPreviewImageView.image = preview;
        }

        NSString *curIcon = [[NSUserDefaults standardUserDefaults] stringForKey:@"alp_selected_icon"] ?: @"apres_ski";
        if ([curIcon isEqualToString:@"custom"]) {
            [NSApp setApplicationIconImage:preview];
            NSString *dest = [[NSBundle mainBundle] pathForResource:@"AppIcon" ofType:@"icns"];
            if (dest) AlpExportToIcns(cg, dest);
        }
        CGImageRelease(cg);
    }
}

- (void)presetSunsetAction:(id)sender {
    self.c1ColorWell.color = [NSColor colorWithCalibratedRed:0.98 green:0.38 blue:0.22 alpha:1.0];
    self.c2ColorWell.color = [NSColor colorWithCalibratedRed:0.82 green:0.10 blue:0.88 alpha:1.0];
    [self customControlsChanged:sender];
    [self applyCustomLogoAndExport];
}

- (void)presetOceanAction:(id)sender {
    self.c1ColorWell.color = [NSColor colorWithCalibratedRed:0.10 green:0.82 blue:0.85 alpha:1.0];
    self.c2ColorWell.color = [NSColor colorWithCalibratedRed:0.20 green:0.30 blue:0.95 alpha:1.0];
    [self customControlsChanged:sender];
    [self applyCustomLogoAndExport];
}

- (void)presetCyberAction:(id)sender {
    self.c1ColorWell.color = [NSColor colorWithCalibratedRed:0.20 green:0.92 blue:0.55 alpha:1.0];
    self.c2ColorWell.color = [NSColor colorWithCalibratedRed:0.15 green:0.65 blue:0.95 alpha:1.0];
    [self customControlsChanged:sender];
    [self applyCustomLogoAndExport];
}

static NSImage *AlpCreatePresetGradientPill(NSString *title, NSColor *c1, NSColor *c2, NSSize size) {
    NSImage *img = [[NSImage alloc] initWithSize:size];
    [img lockFocus];
    
    NSRect rect = NSMakeRect(0, 0, size.width, size.height);
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:13 yRadius:13];
    
    NSGradient *grad = [[NSGradient alloc] initWithStartingColor:c1 endingColor:c2];
    [grad drawInBezierPath:path angle:0.0];
    
    [[NSColor colorWithCalibratedWhite:1.0 alpha:0.35] setStroke];
    path.lineWidth = 1.0;
    [path stroke];
    
    NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
    ps.alignment = NSTextAlignmentCenter;
    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:11.5 weight:NSFontWeightBold],
        NSForegroundColorAttributeName: [NSColor whiteColor],
        NSParagraphStyleAttributeName: ps
    };
    NSSize textSize = [title sizeWithAttributes:attrs];
    NSRect textRect = NSMakeRect(0, (size.height - textSize.height) / 2.0, size.width, textSize.height);
    [title drawInRect:textRect withAttributes:attrs];
    
    [img unlockFocus];
    return img;
}

- (NSView *)buildIconOverlayForFrame:(NSRect)bounds {
    NSView *root = [[NSView alloc] initWithFrame:bounds];
    root.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    root.wantsLayer = YES;
    BOOL isDark = AlpIsDarkAppearance(nil);
    root.appearance = [NSAppearance appearanceNamed:isDark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
    root.layer.backgroundColor = (isDark ? [NSColor colorWithCalibratedWhite:0.125 alpha:1.0] : [NSColor windowBackgroundColor]).CGColor;

    CGFloat w = bounds.size.width > 100 ? bounds.size.width : 684;
    CGFloat h = bounds.size.height > 100 ? bounds.size.height : 520;

    // 3 Cards Layout: 180 pt wide each, 215 pt tall
    CGFloat cardW = 180;
    CGFloat cardH = 215;
    CGFloat gap = 18;
    CGFloat totalCardsW = (cardW * 3) + (gap * 2);
    CGFloat startX = (w - totalCardsW) / 2.0;
    CGFloat topY = h - cardH - 24;

    // --- Card 1: Après-ski ---
    self.cardApres = [self createCardBoxWithFrame:NSMakeRect(startX, topY, cardW, cardH)];
    NSImageView *iv1 = [[NSImageView alloc] initWithFrame:NSMakeRect((cardW - 96)/2, 94, 96, 96)];
    iv1.image = [[NSImage alloc] initWithContentsOfFile:[self pathForBundledIcon:@"alp_browser_original"]];
    iv1.imageScaling = NSImageScaleProportionallyUpOrDown;
    [self.cardApres.contentView addSubview:iv1];

    NSTextField *t1 = [self labelWithText:@"Après-ski" frame:NSMakeRect(10, 62, cardW - 20, 20) font:[NSFont systemFontOfSize:14 weight:NSFontWeightBold] color:[NSColor labelColor]];
    t1.alignment = NSTextAlignmentCenter;
    [self.cardApres.contentView addSubview:t1];

    NSTextField *st1 = [self labelWithText:@"Default Icon" frame:NSMakeRect(10, 42, cardW - 20, 16) font:[NSFont systemFontOfSize:11.5 weight:NSFontWeightRegular] color:[NSColor secondaryLabelColor]];
    st1.alignment = NSTextAlignmentCenter;
    [self.cardApres.contentView addSubview:st1];

    self.btnApres = [NSButton buttonWithTitle:@"Select" target:self action:@selector(selectApresSki:)];
    self.btnApres.frame = NSMakeRect((cardW - 88)/2, 12, 88, 24);
    self.btnApres.bezelStyle = NSBezelStyleRounded;
    [self.cardApres.contentView addSubview:self.btnApres];

    NSClickGestureRecognizer *clickApres = [[NSClickGestureRecognizer alloc] initWithTarget:self action:@selector(selectApresSki:)];
    [self.cardApres addGestureRecognizer:clickApres];
    [root addSubview:self.cardApres];

    // --- Card 2: Kumori-nashi ---
    self.cardKumori = [self createCardBoxWithFrame:NSMakeRect(startX + cardW + gap, topY, cardW, cardH)];
    NSImageView *iv2 = [[NSImageView alloc] initWithFrame:NSMakeRect((cardW - 96)/2, 94, 96, 96)];
    iv2.image = [[NSImage alloc] initWithContentsOfFile:[self pathForBundledIcon:@"alp_browser_white"]];
    iv2.imageScaling = NSImageScaleProportionallyUpOrDown;
    [self.cardKumori.contentView addSubview:iv2];

    NSTextField *t2 = [self labelWithText:@"Kumori-nashi" frame:NSMakeRect(10, 62, cardW - 20, 20) font:[NSFont systemFontOfSize:14 weight:NSFontWeightBold] color:[NSColor labelColor]];
    t2.alignment = NSTextAlignmentCenter;
    [self.cardKumori.contentView addSubview:t2];

    NSTextField *st2 = [self labelWithText:@"Monochrome Light" frame:NSMakeRect(10, 42, cardW - 20, 16) font:[NSFont systemFontOfSize:11.5 weight:NSFontWeightRegular] color:[NSColor secondaryLabelColor]];
    st2.alignment = NSTextAlignmentCenter;
    [self.cardKumori.contentView addSubview:st2];

    self.btnKumori = [NSButton buttonWithTitle:@"Select" target:self action:@selector(selectKumoriNashi:)];
    self.btnKumori.frame = NSMakeRect((cardW - 88)/2, 12, 88, 24);
    self.btnKumori.bezelStyle = NSBezelStyleRounded;
    [self.cardKumori.contentView addSubview:self.btnKumori];

    NSClickGestureRecognizer *clickKumori = [[NSClickGestureRecognizer alloc] initWithTarget:self action:@selector(selectKumoriNashi:)];
    [self.cardKumori addGestureRecognizer:clickKumori];
    [root addSubview:self.cardKumori];

    // --- Card 3: Custom ---
    self.cardCustom = [self createCardBoxWithFrame:NSMakeRect(startX + (cardW + gap) * 2, topY, cardW, cardH)];
    self.customPreviewImageView = [[NSImageView alloc] initWithFrame:NSMakeRect((cardW - 96)/2, 94, 96, 96)];
    self.customPreviewImageView.imageScaling = NSImageScaleProportionallyUpOrDown;
    [self.cardCustom.contentView addSubview:self.customPreviewImageView];

    NSTextField *t3 = [self labelWithText:@"Custom" frame:NSMakeRect(10, 62, cardW - 20, 20) font:[NSFont systemFontOfSize:14 weight:NSFontWeightBold] color:[NSColor labelColor]];
    t3.alignment = NSTextAlignmentCenter;
    [self.cardCustom.contentView addSubview:t3];

    NSTextField *st3 = [self labelWithText:@"Gradient & Grain" frame:NSMakeRect(10, 42, cardW - 20, 16) font:[NSFont systemFontOfSize:11.5 weight:NSFontWeightRegular] color:[NSColor secondaryLabelColor]];
    st3.alignment = NSTextAlignmentCenter;
    [self.cardCustom.contentView addSubview:st3];

    self.btnCustom = [NSButton buttonWithTitle:@"Select" target:self action:@selector(selectCustom:)];
    self.btnCustom.frame = NSMakeRect((cardW - 88)/2, 12, 88, 24);
    self.btnCustom.bezelStyle = NSBezelStyleRounded;
    [self.cardCustom.contentView addSubview:self.btnCustom];

    NSClickGestureRecognizer *clickCustom = [[NSClickGestureRecognizer alloc] initWithTarget:self action:@selector(selectCustom:)];
    [self.cardCustom addGestureRecognizer:clickCustom];
    [root addSubview:self.cardCustom];

    // --- Bottom Section: Custom Logo Studio ---
    CGFloat studioH = 205;
    CGFloat studioY = topY - studioH - 16;
    NSBox *studioBox = [self createCardBoxWithFrame:NSMakeRect(startX, studioY, totalCardsW, studioH)];

    [studioBox.contentView addSubview:[self labelWithText:@"Custom Logo Studio"
                                                   frame:NSMakeRect(20, studioH - 34, 200, 20)
                                                    font:[NSFont systemFontOfSize:13.5 weight:NSFontWeightBold]
                                                   color:[NSColor labelColor]]];

    [studioBox.contentView addSubview:[self labelWithText:@"Personalize background, logo gradient, and grain level."
                                                   frame:NSMakeRect(20, studioH - 52, 380, 16)
                                                    font:[NSFont systemFontOfSize:11.5 weight:NSFontWeightRegular]
                                                   color:[NSColor secondaryLabelColor]]];

    // Row 1: Background
    [studioBox.contentView addSubview:[self labelWithText:@"Background:"
                                                   frame:NSMakeRect(20, 114, 110, 20)
                                                    font:[NSFont systemFontOfSize:12.5 weight:NSFontWeightMedium]
                                                   color:[NSColor labelColor]]];

    self.bgSegment = [NSSegmentedControl segmentedControlWithLabels:@[@"Dark", @"Light", @"Custom Color"]
                                                       trackingMode:NSSegmentSwitchTrackingSelectOne
                                                             target:self
                                                             action:@selector(customControlsChanged:)];
    self.bgSegment.frame = NSMakeRect(140, 110, 240, 26);
    NSInteger savedBgMode = [[NSUserDefaults standardUserDefaults] integerForKey:@"alp_custom_bg_mode"];
    self.bgSegment.selectedSegment = (savedBgMode >= 0 && savedBgMode <= 2) ? savedBgMode : 0;
    [studioBox.contentView addSubview:self.bgSegment];

    self.bgColorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(390, 110, 44, 26)];
    self.bgColorWell.color = [NSColor colorWithCalibratedWhite:0.12 alpha:1.0];
    self.bgColorWell.target = self;
    self.bgColorWell.action = @selector(customControlsChanged:);
    [studioBox.contentView addSubview:self.bgColorWell];

    // Row 2: Logo Gradient
    [studioBox.contentView addSubview:[self labelWithText:@"Logo Gradient:"
                                                   frame:NSMakeRect(20, 74, 110, 20)
                                                    font:[NSFont systemFontOfSize:12.5 weight:NSFontWeightMedium]
                                                   color:[NSColor labelColor]]];

    self.c1ColorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(140, 70, 52, 26)];
    self.c1ColorWell.color = [NSColor colorWithCalibratedRed:0.95 green:0.35 blue:0.20 alpha:1.0];
    self.c1ColorWell.target = self;
    self.c1ColorWell.action = @selector(customControlsChanged:);
    [studioBox.contentView addSubview:self.c1ColorWell];

    NSTextField *arrow = [self labelWithText:@"→" frame:NSMakeRect(200, 74, 16, 20) font:[NSFont systemFontOfSize:13 weight:NSFontWeightMedium] color:[NSColor secondaryLabelColor]];
    [studioBox.contentView addSubview:arrow];

    self.c2ColorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(224, 70, 52, 26)];
    self.c2ColorWell.color = [NSColor colorWithCalibratedRed:0.80 green:0.10 blue:0.85 alpha:1.0];
    self.c2ColorWell.target = self;
    self.c2ColorWell.action = @selector(customControlsChanged:);
    [studioBox.contentView addSubview:self.c2ColorWell];

    // Presets with true gradient theme previews
    NSColor *sun1 = [NSColor colorWithCalibratedRed:0.98 green:0.38 blue:0.22 alpha:1.0];
    NSColor *sun2 = [NSColor colorWithCalibratedRed:0.82 green:0.10 blue:0.88 alpha:1.0];
    NSButton *pSunset = [NSButton buttonWithTitle:@"" target:self action:@selector(presetSunsetAction:)];
    pSunset.frame = NSMakeRect(296, 70, 68, 26);
    pSunset.bordered = NO;
    pSunset.image = AlpCreatePresetGradientPill(@"Sunset", sun1, sun2, NSMakeSize(68, 26));
    pSunset.imagePosition = NSImageOnly;
    [studioBox.contentView addSubview:pSunset];

    NSColor *oc1 = [NSColor colorWithCalibratedRed:0.10 green:0.82 blue:0.85 alpha:1.0];
    NSColor *oc2 = [NSColor colorWithCalibratedRed:0.20 green:0.30 blue:0.95 alpha:1.0];
    NSButton *pOcean = [NSButton buttonWithTitle:@"" target:self action:@selector(presetOceanAction:)];
    pOcean.frame = NSMakeRect(370, 70, 64, 26);
    pOcean.bordered = NO;
    pOcean.image = AlpCreatePresetGradientPill(@"Ocean", oc1, oc2, NSMakeSize(64, 26));
    pOcean.imagePosition = NSImageOnly;
    [studioBox.contentView addSubview:pOcean];

    NSColor *au1 = [NSColor colorWithCalibratedRed:0.20 green:0.92 blue:0.55 alpha:1.0];
    NSColor *au2 = [NSColor colorWithCalibratedRed:0.15 green:0.65 blue:0.95 alpha:1.0];
    NSButton *pCyber = [NSButton buttonWithTitle:@"" target:self action:@selector(presetCyberAction:)];
    pCyber.frame = NSMakeRect(440, 70, 66, 26);
    pCyber.bordered = NO;
    pCyber.image = AlpCreatePresetGradientPill(@"Aurora", au1, au2, NSMakeSize(66, 26));
    pCyber.imagePosition = NSImageOnly;
    [studioBox.contentView addSubview:pCyber];

    // Row 3: Grain Level
    [studioBox.contentView addSubview:[self labelWithText:@"Grain Texture:"
                                                   frame:NSMakeRect(20, 32, 110, 20)
                                                    font:[NSFont systemFontOfSize:12.5 weight:NSFontWeightMedium]
                                                   color:[NSColor labelColor]]];

    CGFloat savedGrain = [[NSUserDefaults standardUserDefaults] objectForKey:@"alp_custom_grain"] ? [[NSUserDefaults standardUserDefaults] doubleForKey:@"alp_custom_grain"] : 0.35;
    self.grainSlider = [NSSlider sliderWithValue:savedGrain minValue:0.0 maxValue:1.0 target:self action:@selector(customControlsChanged:)];
    self.grainSlider.frame = NSMakeRect(140, 30, 220, 22);
    self.grainSlider.continuous = YES;
    [studioBox.contentView addSubview:self.grainSlider];

    self.grainValueLabel = [self labelWithText:[NSString stringWithFormat:@"%.0f%%", savedGrain * 100.0]
                                         frame:NSMakeRect(370, 32, 45, 20)
                                          font:[NSFont systemFontOfSize:12 weight:NSFontWeightRegular]
                                         color:[NSColor secondaryLabelColor]];
    [studioBox.contentView addSubview:self.grainValueLabel];

    NSButton *applyCustomBtn = [NSButton buttonWithTitle:@"Apply to App Icon" target:self action:@selector(selectCustom:)];
    applyCustomBtn.frame = NSMakeRect(totalCardsW - 148, 28, 132, 28);
    applyCustomBtn.bezelStyle = NSBezelStyleRounded;
    [studioBox.contentView addSubview:applyCustomBtn];

    [root addSubview:studioBox];

    // Initialize custom icon rendering and selection
    [self customControlsChanged:nil];
    NSString *curIcon = [[NSUserDefaults standardUserDefaults] stringForKey:@"alp_selected_icon"] ?: @"apres_ski";
    [self updateIconSelectionUI:curIcon];

    return root;
}


- (void)sanitizeAndRefreshSettingsWindow:(NSWindow *)window {
    if (!window) return;
    NSString *clsName = NSStringFromClass([window class]);
    NSString *autosave = window.frameAutosaveName ?: @"";
    if (![clsName containsString:@"UserInteractionPausableWindow"] &&
        ![autosave containsString:@"Settings"]) {
        return;
    }

    // 1. Remove "Alp" / "Arc" and "Max" / "Alp AI" toolbar items from window.toolbar
    if (window.toolbar) {
        for (NSInteger i = (NSInteger)window.toolbar.items.count - 1; i >= 0; i--) {
            NSToolbarItem *item = window.toolbar.items[i];
            NSString *lbl = item.label ?: @"";
            NSString *iid = item.itemIdentifier ?: @"";
            if ([lbl isEqualToString:@"Alp"] || [lbl isEqualToString:@"Arc"] ||
                [lbl isEqualToString:@"Max"] || [lbl isEqualToString:@"Alp AI"] ||
                [lbl isEqualToString:@"Alp Max"] ||
                [iid.lowercaseString containsString:@"account"] || [iid.lowercaseString containsString:@"max"]) {
                [window.toolbar removeItemAtIndex:i];
            } else if ([lbl isEqualToString:@"Icon"]) {
                NSImage *badge = [NSImage imageWithSystemSymbolName:@"app.dashed" accessibilityDescription:@"Icon"];
                if (badge) item.image = badge;
            }
        }
    }

    // 2. Remove "Alp" / "Arc" and "Max" / "Alp AI" from NSTabViewController if present
    if ([window.contentViewController isKindOfClass:[NSTabViewController class]]) {
        NSTabViewController *tvc = (NSTabViewController *)window.contentViewController;
        for (NSInteger i = (NSInteger)tvc.tabViewItems.count - 1; i >= 0; i--) {
            NSTabViewItem *tvi = tvc.tabViewItems[i];
            NSString *lbl = tvi.label ?: @"";
            NSString *iid = (NSString *)tvi.identifier ?: @"";
            if ([lbl isEqualToString:@"Alp"] || [lbl isEqualToString:@"Arc"] ||
                [lbl isEqualToString:@"Max"] || [lbl isEqualToString:@"Alp AI"] ||
                [lbl isEqualToString:@"Alp Max"] ||
                [iid.lowercaseString containsString:@"account"] || [iid.lowercaseString containsString:@"max"]) {
                [tvc removeTabViewItem:tvi];
            }
        }
    }

    // 3. Determine current active tab
    NSToolbarItem *selItem = nil;
    for (NSToolbarItem *it in window.toolbar.items) {
        if ([it.itemIdentifier isEqualToString:window.toolbar.selectedItemIdentifier]) {
            selItem = it;
            break;
        }
    }
    NSString *curLabel = selItem.label ?: window.title ?: @"";

    // If currently on Alp/Arc/Max, force switch to "General"
    if ([curLabel isEqualToString:@"Alp"] || [curLabel isEqualToString:@"Arc"] ||
        [curLabel isEqualToString:@"Max"] || [curLabel isEqualToString:@"Alp AI"] ||
        [curLabel isEqualToString:@"Alp Max"] || curLabel.length == 0) {
        NSToolbarItem *generalItem = nil;
        for (NSToolbarItem *it in window.toolbar.items) {
            if ([it.label isEqualToString:@"General"]) {
                generalItem = it;
                break;
            }
        }
        if (generalItem) {
            [window.toolbar setSelectedItemIdentifier:generalItem.itemIdentifier];
            if (generalItem.target && generalItem.action) {
                #pragma clang diagnostic push
                #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                [generalItem.target performSelector:generalItem.action withObject:generalItem];
                #pragma clang diagnostic pop
            }
            window.title = @"General";
            curLabel = @"General";
        }
    }

    NSView *contentView = window.contentView;
    if (!contentView) return;

    NSView *genOverlay = [self.generalOverlays objectForKey:window];
    NSView *iconOverlay = [self.iconOverlays objectForKey:window];

    if ([curLabel isEqualToString:@"General"]) {
        if (iconOverlay) iconOverlay.hidden = YES;
        if (!genOverlay) {
            genOverlay = [self buildGeneralOverlayForFrame:contentView.bounds];
            [self.generalOverlays setObject:genOverlay forKey:window];
            [contentView addSubview:genOverlay positioned:NSWindowAbove relativeTo:nil];
        } else {
            genOverlay.frame = contentView.bounds;
            genOverlay.hidden = NO;
            [contentView addSubview:genOverlay positioned:NSWindowAbove relativeTo:nil];
        }
        for (NSView *sub in contentView.subviews) {
            if (sub != genOverlay && sub != iconOverlay) {
                sub.hidden = YES;
            }
        }
    } else if ([curLabel isEqualToString:@"Icon"]) {
        if (genOverlay) genOverlay.hidden = YES;
        if (!iconOverlay) {
            iconOverlay = [self buildIconOverlayForFrame:contentView.bounds];
            [self.iconOverlays setObject:iconOverlay forKey:window];
            [contentView addSubview:iconOverlay positioned:NSWindowAbove relativeTo:nil];
        } else {
            iconOverlay.frame = contentView.bounds;
            iconOverlay.hidden = NO;
            [contentView addSubview:iconOverlay positioned:NSWindowAbove relativeTo:nil];
        }
        for (NSView *sub in contentView.subviews) {
            if (sub != genOverlay && sub != iconOverlay) {
                sub.hidden = YES;
            }
        }
    } else {
        if (genOverlay) genOverlay.hidden = YES;
        if (iconOverlay) iconOverlay.hidden = YES;
        for (NSView *sub in contentView.subviews) {
            if (sub != genOverlay && sub != iconOverlay) {
                sub.hidden = NO;
            }
        }
    }
}

- (void)refreshSettingsWindow:(NSWindow *)window {
    [self sanitizeAndRefreshSettingsWindow:window];
}

@end

static NSImage *(*orig_NSImage_imageNamed)(id, SEL, NSImageName) = NULL;

static NSImage *alp_NSImage_imageNamed(id self, SEL _cmd, NSImageName name) {
    if (name) {
        NSString *sName = [(NSString *)name lowercaseString];
        if ([sName containsString:@"appicon"] ||
            [sName containsString:@"arcicon"] ||
            [sName containsString:@"icon-arc"] ||
            [sName containsString:@"arcoutlineicon"]) {
            NSString *curIcon = [[NSUserDefaults standardUserDefaults] stringForKey:@"alp_selected_icon"] ?: @"apres_ski";
            NSString *fn = [curIcon isEqualToString:@"kumori_nashi"] ? @"alp_browser_white" : @"alp_browser_original";
            NSString *path = [[AlpSettingsOverlayManager shared] pathForBundledIcon:fn];
            NSImage *appIcon = [NSApp applicationIconImage];
            if (!appIcon && path) appIcon = [[NSImage alloc] initWithContentsOfFile:path];
            if (appIcon) return appIcon;
        }
    }
    if (orig_NSImage_imageNamed) {
        return orig_NSImage_imageNamed(self, _cmd, name);
    }
    return nil;
}

static void (*orig_setApplicationIconImage)(id, SEL, NSImage *) = NULL;
static void alp_setApplicationIconImage(id self, SEL _cmd, NSImage *image) {
    NSString *curIcon = [[NSUserDefaults standardUserDefaults] stringForKey:@"alp_selected_icon"] ?: @"apres_ski";
    if ([curIcon isEqualToString:@"custom"]) {
        if (orig_setApplicationIconImage) orig_setApplicationIconImage(self, _cmd, image);
        return;
    }
    NSString *fn = [curIcon isEqualToString:@"kumori_nashi"] ? @"alp_browser_white" : @"alp_browser_original";
    NSString *path = [[AlpSettingsOverlayManager shared] pathForBundledIcon:fn];
    NSImage *desired = path ? [[NSImage alloc] initWithContentsOfFile:path] : image;
    if (orig_setApplicationIconImage) {
        orig_setApplicationIconImage(self, _cmd, desired ?: image);
    }
}

static void (*orig_NSAlert_layout)(id, SEL) = NULL;
static void alp_NSAlert_layout(id self, SEL _cmd) {
    NSAlert *alert = (NSAlert *)self;
    NSImage *appIcon = [NSApp applicationIconImage];
    if (appIcon) alert.icon = appIcon;
    if (orig_NSAlert_layout) orig_NSAlert_layout(self, _cmd);
}

static NSModalResponse (*orig_NSAlert_runModal)(id, SEL) = NULL;
static NSModalResponse alp_NSAlert_runModal(id self, SEL _cmd) {
    NSAlert *alert = (NSAlert *)self;
    NSImage *appIcon = [NSApp applicationIconImage];
    if (appIcon) alert.icon = appIcon;
    if (orig_NSAlert_runModal) return orig_NSAlert_runModal(self, _cmd);
    return NSModalResponseStop;
}

static void AlpReplaceArcIconInViewHierarchy(NSView *v, NSImage *appIcon) {
    if (!v || !appIcon) return;
    if ([v isKindOfClass:[NSImageView class]]) {
        NSImageView *iv = (NSImageView *)v;
        if (iv.image && iv.image != appIcon) {
            NSSize s = iv.image.size;
            if (s.width >= 32 && s.height >= 32) {
                iv.image = appIcon;
            }
        }
    }
    for (NSView *sub in v.subviews) {
        AlpReplaceArcIconInViewHierarchy(sub, appIcon);
    }
}

// Removes any default "Arc Basics" / "Alp Basics" folder or TBC onboarding tabs from StorableSidebar.json
static void AlpSanitizeSidebarFileOnDisk(void) {
    NSString *sidebarPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Arc/StorableSidebar.json"];
    NSData *data = [NSData dataWithContentsOfFile:sidebarPath];
    if (!data) return;
    NSString *raw = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!raw) return;
    if (![raw containsString:@"arcBasics"] && ![raw containsString:@"browsercompany.substack.com"] && ![raw containsString:@"arcinternet"]) {
        return;
    }
    // Restore from the latest clean backup that does not have arcBasics
    NSString *arcDir = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Arc"];
    NSArray<NSString *> *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:arcDir error:nil];
    NSArray<NSString *> *sorted = [files sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *fn in [sorted reverseObjectEnumerator]) {
        if ([fn hasPrefix:@"StorableSidebar."] && [fn hasSuffix:@".json"] && ![fn isEqualToString:@"StorableSidebar.json"]) {
            NSString *candidatePath = [arcDir stringByAppendingPathComponent:fn];
            NSString *cText = [NSString stringWithContentsOfFile:candidatePath encoding:NSUTF8StringEncoding error:nil];
            if (cText && [cText containsString:@"VIET100"] && ![cText containsString:@"arcBasics"] && ![cText containsString:@"browsercompany.substack.com"]) {
                [cText writeToFile:sidebarPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
                break;
            }
        }
    }
}

__attribute__((constructor))
static void ArcOCIBridgeInitialize(void) {
    @autoreleasepool {
        NSString *procName = [[NSProcessInfo processInfo] processName] ?: @"";
        [[NSString stringWithFormat:@"ProcName: '%@'\n", procName] writeToFile:@"/tmp/alp_proc_name.txt" atomically:YES encoding:NSUTF8StringEncoding error:nil];
        if (![procName containsString:@"Arc"] && ![procName containsString:@"Alp"]) {
            return;
        }

        // 0. Ensure StorableSidebar.json never contains default TBC/Arc Basics onboarding tabs
        AlpSanitizeSidebarFileOnDisk();

        // 1. Capture original SecItem* function pointers and hook GOT across loaded images
        orig_SecItemCopyMatching = dlsym(RTLD_DEFAULT, "SecItemCopyMatching");
        orig_SecItemAdd = dlsym(RTLD_DEFAULT, "SecItemAdd");
        orig_SecItemUpdate = dlsym(RTLD_DEFAULT, "SecItemUpdate");
        orig_SecItemDelete = dlsym(RTLD_DEFAULT, "SecItemDelete");

        uint32_t imgCount = _dyld_image_count();
        for (uint32_t i = 0; i < imgCount; i++) {
            const char *name = _dyld_get_image_name(i);
            if (name && (strstr(name, "/Contents/MacOS/Arc") || strstr(name, "FirebaseFirestoreInternal"))) {
                AlpHookSecItemGOTInImage(_dyld_get_image_header(i));
            }
        }

        // 2. Also swizzle FIRAuthKeychainServices Objective-C methods
        Class kcClass = NSClassFromString(@"FIRAuthKeychainServices");
        if (kcClass) {
            AlpSwizzleInstance(kcClass, NSSelectorFromString(@"dataForKey:error:"), @selector(alp_dataForKey:error:));
            AlpSwizzleInstance(kcClass, NSSelectorFromString(@"setData:forKey:error:"), @selector(alp_setData:forKey:error:));
            AlpSwizzleInstance(kcClass, NSSelectorFromString(@"removeDataForKey:error:"), @selector(alp_removeDataForKey:error:));
            AlpSwizzleInstance(kcClass, NSSelectorFromString(@"getItemWithQuery:error:"), @selector(alp_getItemWithQuery:error:));
            AlpSwizzleInstance(kcClass, NSSelectorFromString(@"setItemWithQuery:attributes:error:"), @selector(alp_setItemWithQuery:attributes:error:));
            AlpSwizzleInstance(kcClass, NSSelectorFromString(@"deleteItemWithQuery:error:"), @selector(alp_deleteItemWithQuery:error:));
            AlpSwizzleInstance(kcClass, NSSelectorFromString(@"removeItemWithQuery:error:"), @selector(alp_removeItemWithQuery:error:));
        }

        // 2b. Swizzle CloudKit (CKContainer / CKDatabase) to prevent missing-entitlement SIGABRT when opening Settings
        Class ckContainerClass = NSClassFromString(@"CKContainer");
        if (ckContainerClass) {
            AlpSwizzleClass(ckContainerClass, NSSelectorFromString(@"defaultContainer"), @selector(alp_defaultContainer));
            AlpSwizzleClass(ckContainerClass, NSSelectorFromString(@"containerWithIdentifier:"), @selector(alp_containerWithIdentifier:));
            AlpSwizzleInstance(ckContainerClass, NSSelectorFromString(@"containerIdentifier"), @selector(alp_containerIdentifier));
            AlpSwizzleInstance(ckContainerClass, NSSelectorFromString(@"privateCloudDatabase"), @selector(alp_privateCloudDatabase));
            AlpSwizzleInstance(ckContainerClass, NSSelectorFromString(@"publicCloudDatabase"), @selector(alp_publicCloudDatabase));
            AlpSwizzleInstance(ckContainerClass, NSSelectorFromString(@"sharedCloudDatabase"), @selector(alp_sharedCloudDatabase));
            AlpSwizzleInstance(ckContainerClass, NSSelectorFromString(@"accountStatusWithCompletionHandler:"), @selector(alp_accountStatusWithCompletionHandler:));
        }
        Class ckDatabaseClass = NSClassFromString(@"CKDatabase");
        if (ckDatabaseClass) {
            AlpSwizzleInstance(ckDatabaseClass, NSSelectorFromString(@"addOperation:"), @selector(alp_addOperation:));
        }

        // 2c. Swizzle CUINamedImage -image to replace proprietary Arc screenshots & support hot-swappable CustomGraphics
        Class cuiNamedImageClass = NSClassFromString(@"CUINamedImage");
        if (cuiNamedImageClass) {
            AlpSwizzleInstance(cuiNamedImageClass, @selector(image), @selector(alp_cuiNamedImage));
        }

        // Permanently disable ChatGPT in Command Bar
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"gptSiteSearchEnabled"];

        // 3. Swizzle AppKit UI text getters & setters to rebrand every word "Arc" -> "Alp"
        AlpSwizzleInstance([NSTextField class], @selector(setStringValue:), @selector(alp_setStringValue:));
        AlpSwizzleInstance([NSTextField class], @selector(stringValue), @selector(alp_stringValue));
        AlpSwizzleInstance([NSTextField class], @selector(setAttributedStringValue:), @selector(alp_setAttributedStringValue:));
        AlpSwizzleInstance([NSCell class], @selector(setStringValue:), @selector(alp_setStringValue:));
        AlpSwizzleInstance([NSCell class], @selector(stringValue), @selector(alp_stringValue));
        AlpSwizzleInstance([NSCell class], @selector(setTitle:), @selector(alp_setTitle:));
        AlpSwizzleInstance([NSCell class], @selector(title), @selector(alp_title));
        AlpSwizzleInstance([NSTextView class], @selector(setString:), @selector(alp_setString:));
        AlpSwizzleClass([NSURL class], @selector(URLWithString:), @selector(alp_URLWithString:));
        AlpSwizzleClass([NSURL class], @selector(URLWithString:relativeToURL:), @selector(alp_URLWithString:relativeToURL:));

        AlpSwizzleInstance([NSMenuItem class], @selector(setTitle:), @selector(alp_setTitle:));
        AlpSwizzleInstance([NSMenuItem class], @selector(title), @selector(alp_title));
        AlpSwizzleInstance([NSMenu class], @selector(setTitle:), @selector(alp_setTitle:));
        AlpSwizzleInstance([NSMenu class], @selector(title), @selector(alp_title));
        AlpSwizzleInstance([NSButton class], @selector(setTitle:), @selector(alp_setTitle:));
        AlpSwizzleInstance([NSButton class], @selector(title), @selector(alp_title));
        AlpSwizzleInstance([NSWindow class], @selector(setTitle:), @selector(alp_setTitle:));
        AlpSwizzleInstance([NSWindow class], @selector(setToolbar:), @selector(alp_setToolbar:));

        // 3b. Swizzle Settings Tab View Controller toolbar item delegate to filter out Alp / Max tabs
        Class settingsTabVcClass = NSClassFromString(@"_TtC8Settings25SettingsTabViewController");
        if (settingsTabVcClass) {
            Method mDef = class_getInstanceMethod(settingsTabVcClass, @selector(toolbarDefaultItemIdentifiers:));
            if (mDef) {
                orig_toolbarDefaultItemIdentifiers = (void *)method_getImplementation(mDef);
                method_setImplementation(mDef, (IMP)alp_toolbarDefaultItemIdentifiers);
            }
            Method mAll = class_getInstanceMethod(settingsTabVcClass, @selector(toolbarAllowedItemIdentifiers:));
            if (mAll) {
                orig_toolbarAllowedItemIdentifiers = (void *)method_getImplementation(mAll);
                method_setImplementation(mAll, (IMP)alp_toolbarAllowedItemIdentifiers);
            }
            Method mSel = class_getInstanceMethod(settingsTabVcClass, @selector(toolbarSelectableItemIdentifiers:));
            if (mSel) {
                orig_toolbarSelectableItemIdentifiers = (void *)method_getImplementation(mSel);
                method_setImplementation(mSel, (IMP)alp_toolbarSelectableItemIdentifiers);
            }
            Method mItem = class_getInstanceMethod(settingsTabVcClass, @selector(toolbar:itemForItemIdentifier:willBeInsertedIntoToolbar:));
            if (mItem) {
                orig_toolbarItemForItemIdentifier = (void *)method_getImplementation(mItem);
                method_setImplementation(mItem, (IMP)alp_toolbarItemForItemIdentifier);
            }
        }

        Class toolbarItemVcClass = NSClassFromString(@"_TtC8Settings30ToolbarItemStyleViewController");
        if (toolbarItemVcClass) {
            Method mClk = class_getInstanceMethod(toolbarItemVcClass, @selector(toolbarItemSelected:));
            if (mClk) {
                orig_toolbarItemSelected = (void *)method_getImplementation(mClk);
                method_setImplementation(mClk, (IMP)alp_toolbarItemSelected);
            }
        }

        // 3c. Intercept Arc/App icons for alerts & quit dialogs
        Method mImageNamed = class_getClassMethod([NSImage class], @selector(imageNamed:));
        if (mImageNamed) {
            orig_NSImage_imageNamed = (void *)method_getImplementation(mImageNamed);
            method_setImplementation(mImageNamed, (IMP)alp_NSImage_imageNamed);
        }

        Method mAlertLayout = class_getInstanceMethod([NSAlert class], @selector(layout));
        if (mAlertLayout) {
            orig_NSAlert_layout = (void *)method_getImplementation(mAlertLayout);
            method_setImplementation(mAlertLayout, (IMP)alp_NSAlert_layout);
        }

        Method mAlertRun = class_getInstanceMethod([NSAlert class], @selector(runModal));
        if (mAlertRun) {
            orig_NSAlert_runModal = (void *)method_getImplementation(mAlertRun);
            method_setImplementation(mAlertRun, (IMP)alp_NSAlert_runModal);
        }

        Method mSetAppIcon = class_getInstanceMethod([NSApplication class], @selector(setApplicationIconImage:));
        if (mSetAppIcon) {
            orig_setApplicationIconImage = (void *)method_getImplementation(mSetAppIcon);
            method_setImplementation(mSetAppIcon, (IMP)alp_setApplicationIconImage);
        }

        void (^applyAlpIcon)(void) = ^{
            NSString *curIcon = [[NSUserDefaults standardUserDefaults] stringForKey:@"alp_selected_icon"] ?: @"apres_ski";
            if ([curIcon isEqualToString:@"apres_ski"]) {
                [[AlpSettingsOverlayManager shared] selectApresSki:nil];
            } else if ([curIcon isEqualToString:@"kumori_nashi"]) {
                [[AlpSettingsOverlayManager shared] selectKumoriNashi:nil];
            } else if ([curIcon isEqualToString:@"custom"]) {
                [[AlpSettingsOverlayManager shared] applyCustomLogoAndExport];
            }
        };

        [[NSNotificationCenter defaultCenter] addObserverForName:NSApplicationWillFinishLaunchingNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification * _Nonnull note) {
            applyAlpIcon();
        }];

        [[NSNotificationCenter defaultCenter] addObserverForName:NSApplicationWillTerminateNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification * _Nonnull note) {
            applyAlpIcon();
        }];

        void (^settingsRefreshBlock)(NSNotification *) = ^(NSNotification *note) {
            NSWindow *win = [note.object isKindOfClass:[NSWindow class]] ? (NSWindow *)note.object : nil;
            if (win) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [[AlpSettingsOverlayManager shared] refreshSettingsWindow:win];
                });
            }
        };
        [[NSNotificationCenter defaultCenter] addObserverForName:@"AlpWindowTitleDidChangeNotification" object:nil queue:[NSOperationQueue mainQueue] usingBlock:settingsRefreshBlock];
        [[NSNotificationCenter defaultCenter] addObserverForName:NSWindowDidBecomeKeyNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:settingsRefreshBlock];
        [[NSNotificationCenter defaultCenter] addObserverForName:NSWindowDidResizeNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:settingsRefreshBlock];

        [[NSNotificationCenter defaultCenter] addObserverForName:NSApplicationDidFinishLaunchingNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification * _Nonnull note) {
            AlpRebrandMenuRecursively([NSApp mainMenu]);

            // Restore user's preferred Dock icon
            NSString *savedIcon = [[NSUserDefaults standardUserDefaults] stringForKey:@"alp_selected_icon"] ?: @"apres_ski";
            if ([savedIcon isEqualToString:@"apres_ski"]) {
                [[AlpSettingsOverlayManager shared] selectApresSki:nil];
            } else if ([savedIcon isEqualToString:@"kumori_nashi"]) {
                [[AlpSettingsOverlayManager shared] selectKumoriNashi:nil];
            } else if ([savedIcon isEqualToString:@"custom"]) {
                [[AlpSettingsOverlayManager shared] applyCustomLogoAndExport];
            }

            if (getenv("ALP_OPEN_SETTINGS")) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [NSApp sendAction:NSSelectorFromString(@"showPreferences:") to:nil from:nil];
                });
            }

            // Open https://alpbrowser.app/start on first launch after setup
            NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
            if (![defs boolForKey:@"AlpBrowserOpenedInitialStartPage_v1"]) {
                [defs setBool:YES forKey:@"AlpBrowserOpenedInitialStartPage_v1"];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    NSURL *startURL = [NSURL URLWithString:@"https://alpbrowser.app/start"];
                    if (startURL && [NSApp delegate] && [[NSApp delegate] respondsToSelector:@selector(application:openURLs:)]) {
                        [(id)[NSApp delegate] application:NSApp openURLs:@[startURL]];
                    }
                });
            }
        }];

        [[NSDistributedNotificationCenter defaultCenter] addObserverForName:@"AlpOpenSettingsWindowNotification"
                                                                      object:nil
                                                                       queue:[NSOperationQueue mainQueue]
                                                                  usingBlock:^(NSNotification * _Nonnull note) {
            [NSApp activateIgnoringOtherApps:YES];
            for (NSMenuItem *item in [NSApp mainMenu].itemArray) {
                if ([item hasSubmenu]) {
                    for (NSMenuItem *sub in item.submenu.itemArray) {
                        if ([sub.title containsString:@"Settings"] || [sub.title containsString:@"Preferences"]) {
                            if (sub.action) {
                                id target = sub.target ?: [NSApp targetForAction:sub.action];
                                if (target) {
                                    #pragma clang diagnostic push
                                    #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                                    [target performSelector:sub.action withObject:sub];
                                    #pragma clang diagnostic pop
                                    return;
                                }
                            }
                        }
                    }
                }
            }
            [NSApp sendAction:NSSelectorFromString(@"showPreferences:") to:nil from:nil];
        }];

        [[NSDistributedNotificationCenter defaultCenter] addObserverForName:@"AlpSelectIconTabNotification"
                                                                      object:nil
                                                                       queue:[NSOperationQueue mainQueue]
                                                                  usingBlock:^(NSNotification * _Nonnull note) {
            for (NSWindow *win in [NSApp windows]) {
                if (win.toolbar) {
                    for (NSToolbarItem *it in win.toolbar.items) {
                        if ([it.label isEqualToString:@"Icon"]) {
                            [win.toolbar setSelectedItemIdentifier:it.itemIdentifier];
                            if (it.target && it.action) {
                                #pragma clang diagnostic push
                                #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                                [it.target performSelector:it.action withObject:it];
                                #pragma clang diagnostic pop
                            }
                            win.title = @"Icon";
                            [[AlpSettingsOverlayManager shared] refreshSettingsWindow:win];
                            break;
                        }
                    }
                }
            }
        }];

        [[NSDistributedNotificationCenter defaultCenter] addObserverForName:@"AlpSelectGeneralTabNotification"
                                                                      object:nil
                                                                       queue:[NSOperationQueue mainQueue]
                                                                  usingBlock:^(NSNotification * _Nonnull note) {
            for (NSWindow *win in [NSApp windows]) {
                if (win.toolbar) {
                    for (NSToolbarItem *it in win.toolbar.items) {
                        if ([it.label isEqualToString:@"General"]) {
                            [win.toolbar setSelectedItemIdentifier:it.itemIdentifier];
                            if (it.target && it.action) {
                                #pragma clang diagnostic push
                                #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                                [it.target performSelector:it.action withObject:it];
                                #pragma clang diagnostic pop
                            }
                            win.title = @"General";
                            [[AlpSettingsOverlayManager shared] refreshSettingsWindow:win];
                            break;
                        }
                    }
                }
            }
        }];

        [[NSNotificationCenter defaultCenter] addObserverForName:NSMenuDidBeginTrackingNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification * _Nonnull note) {
            AlpRebrandMenuRecursively([NSApp mainMenu]);
        }];

        // 4. Register URLProtocol & swizzle NSURLSessionConfiguration
        [NSURLProtocol registerClass:[ArcOCIURLProtocol class]];
        Method origDefault = class_getClassMethod([NSURLSessionConfiguration class], @selector(defaultSessionConfiguration));
        Method swizDefault = class_getClassMethod([NSURLSessionConfiguration class], @selector(arcoci_defaultSessionConfiguration));
        if (origDefault && swizDefault) method_exchangeImplementations(origDefault, swizDefault);

        Method origEphem = class_getClassMethod([NSURLSessionConfiguration class], @selector(ephemeralSessionConfiguration));
        Method swizEphem = class_getClassMethod([NSURLSessionConfiguration class], @selector(arcoci_ephemeralSessionConfiguration));
        if (origEphem && swizEphem) method_exchangeImplementations(origEphem, swizEphem);

        // 5. Disable Sparkle Auto-Updates
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"SUEnableAutomaticChecks"];
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"SUAutomaticallyUpdate"];

        // 6. Start Silent Privacy-Minimal Encrypted OCI Sync
        [[ArcOCISilentSyncManager shared] startSilentSyncLoop];

        // 7. IPC Command Watcher (/tmp/alp_command.txt)
        static dispatch_source_t s_cmdTimer = nil;
        s_cmdTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0));
        dispatch_source_set_timer(s_cmdTimer, dispatch_walltime(NULL, 0), (uint64_t)(0.25 * NSEC_PER_SEC), (uint64_t)(0.05 * NSEC_PER_SEC));
        dispatch_source_set_event_handler(s_cmdTimer, ^{
            dispatch_async(dispatch_get_main_queue(), ^{
                NSMutableString *winLog = [NSMutableString string];
                for (NSWindow *w in [NSApp windows]) {
                    [winLog appendFormat:@"Window: '%@' class: %@ frame: %@ visible: %d\n",
                        w.title, NSStringFromClass([w class]), NSStringFromRect(w.frame), w.isVisible];
                    AlpDumpViewHierarchy(w.contentView, winLog);

                    NSString *clsName = NSStringFromClass([w class]);
                    if ([clsName containsString:@"UserInteractionPausableWindow"] || [w.frameAutosaveName containsString:@"Settings"]) {
                        [[AlpSettingsOverlayManager shared] sanitizeAndRefreshSettingsWindow:w];
                    }

                    NSString *wTitle = w.title ?: @"";
                    if ([winLog.lowercaseString containsString:@"quit"] || [wTitle.lowercaseString containsString:@"quit"]) {
                        NSImage *appIcon = [NSApp applicationIconImage];
                        if (appIcon) {
                            AlpReplaceArcIconInViewHierarchy(w.contentView, appIcon);
                        }
                    }
                }
                [winLog writeToFile:@"/tmp/alp_windows.txt" atomically:YES encoding:NSUTF8StringEncoding error:nil];
            });

            NSString *cmdPath = @"/tmp/alp_command.txt";
            if ([[NSFileManager defaultManager] fileExistsAtPath:cmdPath]) {
                NSString *cmd = [NSString stringWithContentsOfFile:cmdPath encoding:NSUTF8StringEncoding error:nil];
                [[NSFileManager defaultManager] removeItemAtPath:cmdPath error:nil];
                cmd = [cmd stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                dispatch_async(dispatch_get_main_queue(), ^{
                    if ([cmd isEqualToString:@"settings"]) {
                        [NSApp activateIgnoringOtherApps:YES];
                        NSMutableString *menuLog = [NSMutableString string];
                        for (NSMenuItem *item in [NSApp mainMenu].itemArray) {
                            [menuLog appendFormat:@"Top Menu: '%@'\n", item.title];
                            if (item.hasSubmenu) {
                                for (NSMenuItem *sub in item.submenu.itemArray) {
                                    [menuLog appendFormat:@"  Sub: '%@' action: %@ target: %@\n",
                                        sub.title, NSStringFromSelector(sub.action), NSStringFromClass([sub.target class])];
                                    if ([sub.title containsString:@"Settings"] || [sub.title containsString:@"Preferences"]) {
                                        [NSApp sendAction:sub.action to:sub.target from:sub];
                                    }
                                }
                            }
                        }
                        [menuLog writeToFile:@"/tmp/alp_menu_dump.txt" atomically:YES encoding:NSUTF8StringEncoding error:nil];
                        [NSApp sendAction:NSSelectorFromString(@"showPreferences:") to:nil from:nil];
                    } else if ([cmd isEqualToString:@"icon"]) {
                        for (NSWindow *win in [NSApp windows]) {
                            if (win.toolbar) {
                                for (NSToolbarItem *it in win.toolbar.items) {
                                    if ([it.label isEqualToString:@"Icon"]) {
                                        [win.toolbar setSelectedItemIdentifier:it.itemIdentifier];
                                        if (it.target && it.action) {
                                            #pragma clang diagnostic push
                                            #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                                            [it.target performSelector:it.action withObject:it];
                                            #pragma clang diagnostic pop
                                        }
                                        win.title = @"Icon";
                                        [[AlpSettingsOverlayManager shared] sanitizeAndRefreshSettingsWindow:win];
                                        break;
                                    }
                                }
                            }
                        }
                    } else if ([cmd isEqualToString:@"general"]) {
                        for (NSWindow *win in [NSApp windows]) {
                            if (win.toolbar) {
                                for (NSToolbarItem *it in win.toolbar.items) {
                                    if ([it.label isEqualToString:@"General"]) {
                                        [win.toolbar setSelectedItemIdentifier:it.itemIdentifier];
                                        if (it.target && it.action) {
                                            #pragma clang diagnostic push
                                            #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                                            [it.target performSelector:it.action withObject:it];
                                            #pragma clang diagnostic pop
                                        }
                                        win.title = @"General";
                                        [[AlpSettingsOverlayManager shared] sanitizeAndRefreshSettingsWindow:win];
                                        break;
                                    }
                                }
                            }
                        }
                    }
                });
            }
        });
        dispatch_resume(s_cmdTimer);
    }
}
