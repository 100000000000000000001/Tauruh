// The wedge's main-side suspension happens inside our playlist-header hooks (their decoration chain
// reaches Spotify's queue.sync). While a decoration hook runs, SGMainSuspensionArmed is true and
// PostShield defers worker-thread posts to main (async) instead of letting CFX park their poster in
// -[NSOperation waitUntilFinished] inside an un-runnable main-pinned delivery op — the catch-22 that
// a stall-detector is always a few ms late for is closed exactly here, at zero latency.
#import <Foundation/Foundation.h>

extern volatile BOOL SGMainSuspensionArmed;
