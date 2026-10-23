// Records the wedge as it forms. In normal operation -[NSOperation waitUntilFinished] is only
// reached by the CFX waiter when a post parks on a delivery operation, so its first calls narrate
// the wedge: the posting thread and its queue, the operation it parks on, and the last notification
// names that thread posted. Silent in normal use, capped in case waits do happen often.
// (No thread-local ObjC storage: __thread + ARC pointers crash this compiler; the thread dictionary
// carries the ring instead.)
#import <os/log.h>
#import <Foundation/Foundation.h>

static os_log_t wedgeLog;
static int32_t wedgeMeter = 0;

static NSMutableArray *wedgeRing(void) {
  NSMutableDictionary *mine = [NSThread currentThread].threadDictionary;
  NSMutableArray *ring = mine[@"sgWedgeRing"];
  if (!ring) {
    ring = [[NSMutableArray alloc] init];
    mine[@"sgWedgeRing"] = ring;
  }
  return ring;
}

static void wedgeRemember(NSString *name) {
  NSMutableArray *ring = wedgeRing();
  [ring addObject:name ?: @""];
  while (ring.count > 3) [ring removeObjectAtIndex:0];
}

%hook NSNotificationCenter
- (void)postNotificationName:(NSString *)name object:(id)object userInfo:(NSDictionary *)userInfo {
  wedgeRemember(name);
  %orig;
}
%end

%hook NSOperation
- (void)waitUntilFinished {
  int32_t old = __sync_fetch_and_add(&wedgeMeter, 1);
  if (old < 30) {
    if (wedgeLog == NULL) wedgeLog = os_log_create("spotifyglass", "wedge");
    NSMutableArray *ring = wedgeRing();
    os_log(wedgeLog, "wtf thread=%{public}@ lane=%{public}@ lastposts=[%{public}@ | %{public}@ | %{public}@] op=%{public}@",
           [NSThread currentThread].description, [NSOperationQueue currentQueue].description,
           ring.count > 0 ? ring[0] : @"-", ring.count > 1 ? ring[1] : @"-", ring.count > 2 ? ring[2] : @"-",
           self.description);
  }
  %orig;
}
%end
