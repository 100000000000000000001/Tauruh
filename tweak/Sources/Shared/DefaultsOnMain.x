// Default writes from background threads wedge the app: Foundation posts the defaults-change
// notification from the writing thread, CFX pins that delivery to an operation on the main queue and
// the poster blocks in -[NSOperation waitUntilFinished] until it runs. When main is busy that closes
// a cycle and the watchdog kills the app (0x8BADF00D). Spotted live: -[NSUserDefaults setURL:forKey:]
// on com.apple.root.background-qos (Spotify-...-163035.ips, t11). Marshalling every non-main write
// onto main keeps posting there, where delivery is inline and never builds the parking operation.
// Reads are untouched. Braces stay multi-line: logos.m's parser eats the closing brace of a 1-line
// `{ %orig; return; }` statement, which collapses the next statement into the if.
#import <Foundation/Foundation.h>

// Implementation exists, iOS headers just don't declare these convenience setters.
@interface NSUserDefaults (SGUndeclaredSetters)
- (void)setString:(NSString *)value forKey:(NSString *)key;
- (void)setData:(NSData *)value forKey:(NSString *)key;
- (void)setArray:(NSArray *)value forKey:(NSString *)key;
- (void)setDictionary:(NSDictionary *)value forKey:(NSString *)key;
@end

%hook NSUserDefaults
- (void)setObject:(id)value forKey:(NSString *)key {
  if ([NSThread isMainThread]) {
    %orig;
    return;
  }
  dispatch_sync(dispatch_get_main_queue(), ^{
    [self setObject:value forKey:key];
  });
}

- (void)setURL:(NSURL *)url forKey:(NSString *)key {
  if ([NSThread isMainThread]) {
    %orig;
    return;
  }
  dispatch_sync(dispatch_get_main_queue(), ^{
    [self setURL:url forKey:key];
  });
}

- (void)setString:(NSString *)value forKey:(NSString *)key {
  if ([NSThread isMainThread]) {
    %orig;
    return;
  }
  dispatch_sync(dispatch_get_main_queue(), ^{
    [self setString:value forKey:key];
  });
}

- (void)setInteger:(NSInteger)value forKey:(NSString *)key {
  if ([NSThread isMainThread]) {
    %orig;
    return;
  }
  dispatch_sync(dispatch_get_main_queue(), ^{
    [self setInteger:value forKey:key];
  });
}

- (void)setBool:(BOOL)value forKey:(NSString *)key {
  if ([NSThread isMainThread]) {
    %orig;
    return;
  }
  dispatch_sync(dispatch_get_main_queue(), ^{
    [self setBool:value forKey:key];
  });
}

- (void)setFloat:(float)value forKey:(NSString *)key {
  if ([NSThread isMainThread]) {
    %orig;
    return;
  }
  dispatch_sync(dispatch_get_main_queue(), ^{
    [self setFloat:value forKey:key];
  });
}

- (void)setDouble:(double)value forKey:(NSString *)key {
  if ([NSThread isMainThread]) {
    %orig;
    return;
  }
  dispatch_sync(dispatch_get_main_queue(), ^{
    [self setDouble:value forKey:key];
  });
}

- (void)setData:(NSData *)value forKey:(NSString *)key {
  if ([NSThread isMainThread]) {
    %orig;
    return;
  }
  dispatch_sync(dispatch_get_main_queue(), ^{
    [self setData:value forKey:key];
  });
}

- (void)setArray:(NSArray *)value forKey:(NSString *)key {
  if ([NSThread isMainThread]) {
    %orig;
    return;
  }
  dispatch_sync(dispatch_get_main_queue(), ^{
    [self setArray:value forKey:key];
  });
}

- (void)setDictionary:(NSDictionary *)value forKey:(NSString *)key {
  if ([NSThread isMainThread]) {
    %orig;
    return;
  }
  dispatch_sync(dispatch_get_main_queue(), ^{
    [self setDictionary:value forKey:key];
  });
}

- (void)removeObjectForKey:(NSString *)key {
  if ([NSThread isMainThread]) {
    %orig;
    return;
  }
  dispatch_sync(dispatch_get_main_queue(), ^{
    [self removeObjectForKey:key];
  });
}

- (void)registerDefaults:(NSDictionary *)dict {
  if ([NSThread isMainThread]) {
    %orig;
    return;
  }
  dispatch_sync(dispatch_get_main_queue(), ^{
    [self registerDefaults:dict];
  });
}
%end
