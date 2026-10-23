// Posts no longer wait for main. Every playlist-fade hang we traced bottoms out the same way: a
// worker queue (core-http, CFNetwork protocols, the Mobius model store, Spotify's widget manager)
// posts a notification, and CFX delivers block observers registered on NSOperationQueue.main by
// scheduling an operation on main and blocking the poster with -[NSOperation waitUntilFinished]
// until it ran. If main is meanwhile queue.syncing into the poster's queue (Spotify's page builds
// do that during play), the two close a cycle and the watchdog kills us. Re-routing main-queue
// block observers through a queue:nil registration plus one async hop keeps their semantics — the
// block still runs on main — while the post never waits. Command-line timestamped observers that
// post on main deliver inline as before. Shared: applies in both looks.
#import <Foundation/Foundation.h>

%hook NSNotificationCenter
- (id)addObserverForName:(NSString *)name object:(id)obj queue:(NSOperationQueue *)queue usingBlock:(void (^)(NSNotification *note))block {
  if (!block || queue != NSOperationQueue.mainQueue) return %orig;
  return %orig(name, obj, nil, ^(NSNotification *note) {
    dispatch_async(dispatch_get_main_queue(), ^{ block(note); });
  });
}
%end
