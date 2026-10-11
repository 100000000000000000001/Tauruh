// AirPods gestures (Mod Settings > Player > AirPods gestures), under either look: with AirPods in,
// moving the head runs one of the player's actions. A double nod likes the song (or whatever it is
// set to), a shake of the head skips it. The motion comes from the AirPods' own sensors through
// CoreMotion, so nothing is heard or recorded: only how the head turns.
//
//     HeadGestures.m          the CoreMotion manager, the recognizer and the actions it runs
//     HeadGestures.x          the %ctor that starts it at launch when the switch is on
//     HeadGesturesSettings.m  its page, opened from the Player page
//
// It reads the same action list as the double tap zones (Shared/Gestures), so a nod and a shake are
// set to any of those, liked songs included. The switch, the two choices and the motion prompts apply
// at once; everything else about the feature lives at launch.
// Threading: main thread only. The AirPods' samples arrive on the main queue.
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
