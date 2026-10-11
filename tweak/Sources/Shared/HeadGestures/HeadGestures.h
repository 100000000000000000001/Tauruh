#import <Foundation/Foundation.h>

#define SGKeyHeadGestures @"spotifyglass.gestures.head"
// Which action a double nod and a shake run, an SGGestureAction; 8 (Like) and 4 (Next track) to start.
#define SGKeyHeadNod @"spotifyglass.gestures.head.nod"
#define SGKeyHeadShake @"spotifyglass.gestures.head.shake"

// From the switch: starts listening to the AirPods or stops at once.
void SGSetHeadGesturesEnabled(BOOL on);
// What the Status row reads out: why it is or is not listening.
NSString *SGHeadGestureStatus(void);

@class UIViewController;
// The AirPods gestures page: its switch, what a nod and a shake do, and the state of the listening.
UIViewController *SGHeadGesturesSettingsPage(void);
