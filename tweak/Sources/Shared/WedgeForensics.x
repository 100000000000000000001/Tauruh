// Holds the evidence the system-level reports cannot: at a CFX wedge the post parks on a delivery
// operation and blocks in -[NSOperation waitUntilFinished], which in normal operation nobody reaches.
// Its first calls therefore narrate the wedge: the posting thread (and its queue), the operation it
// parks on, and this thread's last three posted notification names. Silent in normal use; capped so
// log volume stays sane even when waits do happen.
#import <os/log.h>
#import <Foundation/Foundation.h>

static os_log_t wedgeLog;
static int32_t wedgeMeter = 0;
static __thread NSString *sgPost0, *sgPost1, *sgPost2;

%hook NSNotificationCenter
- (void)postNotificationName:(NSString *)name object:(id)object userInfo:(NSDictionary *)userInfo {
  sgPost2 = sgPost1; sgPost1 = sgPost0; sgPost0 = name;
  %orig;
}
%end

%hook NSOperation
- (void)waitUntilFinished {
  int32_t old = __sync_fetch_and_add(&wedgeMeter, 1);
  if (old < 30) {
    if (wedgeLog == NULL) wedgeLog = os_log_create("spotifyglass", "wedge");
    NSOperationQueue *lane = [NSOperationQueue currentQueue];
    os_log(wedgeLog, "wtf thread=%{public}@ lane=%{public}@ lastposts=[%{public}@ | %{public}@ | %{public}@] op=%{public}@",
           [NSThread currentThread].description, lane.description, sgPost0, sgPost1, sgPost2, self.description);
  }
  %orig;
}
%end
