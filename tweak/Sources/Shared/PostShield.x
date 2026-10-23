// Kills the wedge family at the parking ground. Every freeze we dissected shares one shape: main is
// suspended in a synchronous barrier (inside the playlist-header hook's Spotify chain, a
// dispatch_once, or a sync we ourselves briefly added), a worker posts a notification, CFX schedules
// a main-queued delivery op whose runner cannot run, and the poster parks in
// -[NSOperation waitUntilFinished] until the watchdog kills the app (0x8BADF00D). While main is
// provably unresponsive we re-dispatch the post onto main asynchronously: the poster returns
// immediately, main unwedges because the once/worker chain can finish, and delivery happens when
// main is free. Narrow gate — only non-main posts while main stalls past the heartbeat threshold —
// so ordinary semantics and delivery order stay untouched in normal running. The servo starts on the
// first post through this hook (a %ctor without %init would never install the hooks).
#import <os/log.h>
#import <Foundation/Foundation.h>

static volatile int32_t sgMainTick;   // incremented on main each landing
static volatile int32_t sgSeenTick;   // how far the servo has confirmed
static volatile BOOL     sgMainStalled;
static os_log_t          shieldLog;

static void sgShieldStart(void) {
  __block dispatch_source_t timer;
  timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                 dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0));
  dispatch_source_set_timer(timer, DISPATCH_TIME_NOW, 30 * NSEC_PER_MSEC, 10 * NSEC_PER_MSEC);
  dispatch_source_set_event_handler(timer, ^{
    int32_t seen = sgSeenTick;
    dispatch_async(dispatch_get_main_queue(), ^{ sgMainTick++; });
    usleep(22000);   // give the main-queue block a chance to land
    if (sgMainTick == seen) {
      if (!sgMainStalled) {
        sgMainStalled = YES;
        if (shieldLog == NULL) shieldLog = os_log_create("spotifyglass", "wedge");
        os_log(shieldLog, "shield: main stalled, deferring worker posts to main");
      }
    } else {
      sgSeenTick = sgMainTick;
      sgMainStalled = NO;
    }
  });
  dispatch_resume(timer);
}

%hook NSNotificationCenter
- (void)postNotificationName:(NSString *)name object:(id)object userInfo:(NSDictionary *)userInfo {
  static dispatch_once_t once;
  dispatch_once(&once, ^{ sgShieldStart(); });
  if (![NSThread isMainThread] && sgMainStalled) {
    if (shieldLog == NULL) shieldLog = os_log_create("spotifyglass", "wedge");
    os_log(shieldLog, "shield: deferring post %{public}@ from %{public}@", name,
           [NSThread currentThread].description);
    dispatch_async(dispatch_get_main_queue(), ^{
      %orig;
    });
    return;
  }
  %orig;
}
%end
