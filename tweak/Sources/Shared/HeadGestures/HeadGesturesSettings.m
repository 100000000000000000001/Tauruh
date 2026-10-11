// The AirPods gestures page: the switch, what a double nod and a shake of the head do, and what the
// listening is doing at the moment. The actions are the double tap zones' list, so a gesture is set to
// any of them and the names cannot drift apart.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "HeadGestures.h"
#import "Shared/Gestures/Gestures.h"

UIViewController *SGHeadGesturesSettingsPage(void) {
    NSArray<NSString *> *names = SGGestureActionNames();
    SGModRow *toggle = SGOptionRow(@"AirPods gestures", @"A double nod likes the song; a shake skips it", SGKeyHeadGestures);
    toggle.changed = ^(BOOL on) { SGSetHeadGesturesEnabled(on); };
    SGModRow *nod = SGChoiceRow(@"Double nod", nil, SGKeyHeadNod, names, SGGestureLike);
    SGModRow *shake = SGChoiceRow(@"Shake", nil, SGKeyHeadShake, names, SGGestureNextTrack);
    SGModRow *status = SGStatRow(@"Status", ^NSString *{ return SGHeadGestureStatus(); });

    SGModSection *on = SGNotedSection(nil, @[toggle],
        @"Needs AirPods with head tracking and Motion & Fitness access. Nothing is heard or recorded: only how your head turns, and only while music plays.");
    SGModSection *gestures = SGNotedSection(@"Gestures", @[nod, shake],
        @"A double nod is down, up, down, up. A shake is left, right, left.");
    SGModSection *state = SGSection(@"State", @[status]);
    return [[SGModPage alloc] initWithTitle:@"AirPods gestures" intro:nil
                                   sections:@[on, gestures, state] footer:nil];
}
