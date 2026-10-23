// Holds the evidence the system-level reports can't: which notification name a wedge-thread posts,
// and which operation the CFX waiter sits on (description carries its identity/queue when
// Foundation builds a delivery op). Rate-capped so log volume stays sane; [spotifyglass] tag.
#import <Foundation/Foundation.h>
#import <os/log.h>
#import "Core/SGLog.h"

static os_log_t wedgeLog;

static BOOL wedgeTake(int32_t *meter) {
  int32_t old = __sync_fetch_and_add(meter, 1);
  return old < 40;
}

%hook NSNotificationCenter
- (void)postNotificationName:(NSString *)name object:(id)object userInfo:(NSDictionary *)userInfo {
  static int32_t meter = 0;
  if (wedgeLog == NULL) wedgeLog = os_log_create("spotifyglass", "wedge");
  // The app posts tens of these a second; only log while the tally is young, from any thread.
  if (wedgeTake(&meter)) os_log(wedgeLog, "post %{public}@ on %{public}@", name,
                                [NSThread currentThread].description);
  %orig;
}
%end

%hook NSOperation
- (void)waitUntilFinished {
  static int32_t meter = 0;
  if (wedgeLog == NULL) wedgeLog = os_log_create("spotifyglass", "wedge");
  if (wedgeTake(&meter)) os_log(wedgeLog, "wtf op=%{public}@", self.description);
  %orig;
}
%end
