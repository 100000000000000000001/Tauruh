// The AirPods gesture engine: listens to the AirPods' motion through CoreMotion, watches how the head
// turns and runs the player action the two gestures are set to. Nothing but rotation is looked at.
//
// A gesture is a run of "strokes": one stroke is the head turning one way, and the next turn the other
// way is the next stroke, so a stroke ends where the rotation rate passes back through zero or turns
// around. A double nod is four strokes on the pitch axis (down, up, down, up); a shake is three on the
// yaw axis (left, right, left). A run counts only when the strokes alternate, each is quick enough and
// far enough, they fall within one short window, the right axis leads the others, and the head is not
// being jostled by walking. The result is one action per gesture, held off for a moment afterwards.
#import <AVFoundation/AVFoundation.h>
#import <CoreMotion/CoreMotion.h>
#include <math.h>
#include <string.h>
#import "Core/SGCore.h"
#import "HeadGestures.h"
#import "Shared/Gestures/Gestures.h"
#import "Shared/Player/PlayerState.h"

// Whether the sound is coming out of Bluetooth, which is where the AirPods and their sensors are.
static BOOL sgBluetoothRoute(void) {
    for (AVAudioSessionPortDescription *output in AVAudioSession.sharedInstance.currentRoute.outputs) {
        if ([output.portType isEqualToString:AVAudioSessionPortBluetoothA2DP] ||
            [output.portType isEqualToString:AVAudioSessionPortBluetoothLE] ||
            [output.portType isEqualToString:AVAudioSessionPortBluetoothHFP]) {
            return YES;
        }
    }
    return NO;
}

// Rotation rate above which the head counts as turning, and the peak a stroke must reach, both in
// radians a second.
static const double kOnset = 0.7;
static const double kPeak = 1.1;
// How long a stroke may take, and how long the whole gesture may run, in seconds.
static const double kMinStroke = 0.05;
static const double kMaxStroke = 0.5;
static const double kWindow = 1.6;
// Strokes a gesture needs: a double nod is down, up, down, up; a shake is left, right, left.
static const NSInteger kNodStrokes = 4;
static const NSInteger kShakeStrokes = 3;
// The gesture's axis must lead the other by this much, and the head must be stiller than this (in g's)
// so a nod while walking is not taken.
static const double kDominance = 1.6;
static const double kWalk = 0.3;
// Held off this long after a gesture, so the tail of one is not read as the next.
static const NSTimeInterval kCooldown = 3.0;

enum { SGPitchAxis = 0, SGYawAxis = 1, SGAxisCount = 2, SGMaxStrokes = 8 };

typedef struct {
    double time;   // when the stroke's motion settled
    int dir;       // which way the head turned: +1 or -1
    double peak;   // the stroke's largest rotation rate, radians a second
} SGStroke;

typedef struct {
    int dir;               // the open stroke's direction, 0 for none
    double start;          // when the open stroke began
    double peak;           // the open stroke's largest rate so far
    SGStroke strokes[SGMaxStrokes];
    int count;
} SGAxis;

@interface SGHeadGestureEngine : NSObject <CMHeadphoneMotionManagerDelegate>
+ (instancetype)shared;
- (void)setEnabled:(BOOL)on;
@end

@implementation SGHeadGestureEngine {
    BOOL _enabled;
    CMHeadphoneMotionManager *_motion;
    BOOL _observing;
    SGAxis _axes[SGAxisCount];
    double _axisPeak[SGAxisCount];   // each axis's largest rate lately, for the dominance test
    double _accel;                   // user acceleration, smoothed: how much the head is being jostled
    double _lastTimestamp;
    double _cooldownUntil[SGAxisCount];
}

+ (instancetype)shared {
    static SGHeadGestureEngine *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [SGHeadGestureEngine new]; });
    return shared;
}

#pragma mark - switching it on

- (void)setEnabled:(BOOL)on {
    if (on == _enabled) return;
    _enabled = on;
    if (on) [self start]; else [self stop];
}

- (void)start {
    if (!_motion) {
        _motion = [CMHeadphoneMotionManager new];
        _motion.delegate = self;
    }
    [self reset];
    if (!_observing) {
        _observing = YES;
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(routeChanged:)
                                                   name:AVAudioSessionRouteChangeNotification object:nil];
    }
    // The first call asks for Motion & Fitness; the samples only start once the AirPods are connected
    // and the sound is coming out of them.
    [self updateListening];
}

- (void)stop {
    if (_observing) {
        _observing = NO;
        [NSNotificationCenter.defaultCenter removeObserver:self name:AVAudioSessionRouteChangeNotification object:nil];
    }
    if (_motion.isDeviceMotionActive) [_motion stopDeviceMotionUpdates];
    [self reset];
}

- (void)routeChanged:(NSNotification *)note {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self updateListening]; });
        return;
    }
    [self updateListening];
}

- (void)updateListening {
    if (!_enabled) return;
    BOOL should = _motion.isDeviceMotionAvailable && sgBluetoothRoute();
    if (should && !_motion.isDeviceMotionActive) {
        __weak typeof(self) weakSelf = self;
        [_motion startDeviceMotionUpdatesToQueue:NSOperationQueue.mainQueue withHandler:^(CMDeviceMotion *motion, NSError *error) {
            if (motion) [weakSelf handleMotion:motion];
        }];
    } else if (!should && _motion.isDeviceMotionActive) {
        [_motion stopDeviceMotionUpdates];
        [self reset];
    }
}

#pragma mark - the manager's own

- (void)headphoneMotionManagerDidConnect:(CMHeadphoneMotionManager *)manager {
    dispatch_async(dispatch_get_main_queue(), ^{ [self updateListening]; });
}

- (void)headphoneMotionManagerDidDisconnect:(CMHeadphoneMotionManager *)manager {
    dispatch_async(dispatch_get_main_queue(), ^{ [self reset]; });
}

#pragma mark - the recognizer

- (void)reset {
    memset(_axes, 0, sizeof(_axes));
    memset(_axisPeak, 0, sizeof(_axisPeak));
    _accel = 0;
}

- (void)handleMotion:(CMDeviceMotion *)motion {
    if (!_enabled) return;
    // Only during playback: a nod at a paused player has nothing to act on.
    SPTPlayerState *state = SGPlayerState();
    if (!state.isPlaying) {
        [self reset];
        _lastTimestamp = motion.timestamp;
        return;
    }
    double t = motion.timestamp;
    if (t <= _lastTimestamp) return;
    double dt = _lastTimestamp ? t - _lastTimestamp : 0;
    _lastTimestamp = t;

    // Smoothed over a second, so a nod's own push is not mistaken for a walk; a walk is sustained.
    CMAcceleration a = motion.userAcceleration;
    double accel = sqrt(a.x * a.x + a.y * a.y + a.z * a.z);
    double blend = dt ? 1 - exp(-dt / 1.0) : 1;
    _accel = _accel * (1 - blend) + accel * blend;

    // Each axis's largest rate lately, faded so only the recent gesture counts against the others.
    double fade = dt ? exp(-dt / 1.0) : 1;
    CMRotationRate rate = motion.rotationRate;
    double values[SGAxisCount] = { rate.x, rate.y };
    for (int axis = 0; axis < SGAxisCount; axis++) {
        _axisPeak[axis] = _axisPeak[axis] * fade;
        _axisPeak[axis] = MAX(_axisPeak[axis], fabs(values[axis]));
        [self feedAxis:axis value:values[axis] time:t];
    }
}

- (void)feedAxis:(int)axis value:(double)value time:(double)t {
    SGAxis *a = &_axes[axis];
    double mag = fabs(value);
    int dir = value > 0 ? 1 : (value < 0 ? -1 : 0);

    if (mag < kOnset) {
        if (a->dir != 0) [self closeAxis:axis at:t];
        return;
    }
    if (a->dir == 0) {
        a->dir = dir;
        a->start = t;
        a->peak = mag;
        return;
    }
    if (dir != a->dir) {
        // The head turned around: the stroke that was open ends here and the next begins.
        [self closeAxis:axis at:t];
        a->dir = dir;
        a->start = t;
        a->peak = mag;
        return;
    }
    if (mag > a->peak) a->peak = mag;
}

- (void)closeAxis:(int)axis at:(double)t {
    SGAxis *a = &_axes[axis];
    double duration = t - a->start;
    if (a->peak >= kPeak && duration >= kMinStroke && duration <= kMaxStroke) {
        if (a->count == SGMaxStrokes) {
            memmove(a->strokes, a->strokes + 1, sizeof(SGStroke) * (SGMaxStrokes - 1));
            a->count--;
        }
        a->strokes[a->count++] = (SGStroke){ t, a->dir, a->peak };
    }
    a->dir = 0;
    [self evaluateAxis:axis at:t];
}

- (void)evaluateAxis:(int)axis at:(double)t {
    SGAxis *a = &_axes[axis];
    while (a->count && t - a->strokes[0].time > kWindow) {
        memmove(a->strokes, a->strokes + 1, sizeof(SGStroke) * (SGMaxStrokes - 1));
        a->count--;
    }
    NSInteger need = axis == SGPitchAxis ? kNodStrokes : kShakeStrokes;
    if (a->count < need) return;

    double sum = 0;
    for (NSInteger k = 0; k < need; k++) {
        SGStroke *stroke = &a->strokes[a->count - 1 - k];
        if (t - stroke->time > kWindow) return;
        if (k && stroke->dir == a->strokes[a->count - k].dir) return;   // they must alternate
        sum += stroke->peak;
    }
    // The gesture's own axis has to lead the other, and the head must not be bouncing along with a walk.
    if (sum / need <= kDominance * _axisPeak[axis == SGPitchAxis ? SGYawAxis : SGPitchAxis]) return;
    if (_accel > kWalk) return;
    if (t < _cooldownUntil[axis]) return;

    SGGestureAction action = (SGGestureAction)SGInt(axis == SGPitchAxis ? SGKeyHeadNod : SGKeyHeadShake,
                                                    axis == SGPitchAxis ? SGGestureLike : SGGestureNextTrack);
    a->count = 0;
    if (action == SGGestureNothing) return;
    _cooldownUntil[axis] = t + kCooldown;
    SGPerformGestureAction(action);
}

@end

#pragma mark - what the switch and the Status row read

// A manager of its own for the questions the page asks: one exists whether or not the feature is
// listening, and building one starts nothing.
static CMHeadphoneMotionManager *sgStatusManager(void) {
    static CMHeadphoneMotionManager *manager;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ manager = [CMHeadphoneMotionManager new]; });
    return manager;
}

NSString *SGHeadGestureStatus(void) {
    if (!SGFlag(SGKeyHeadGestures, NO)) return @"Off";
    if (!sgStatusManager().isDeviceMotionAvailable) return @"This iPhone cannot track AirPods motion";
    switch (CMHeadphoneMotionManager.authorizationStatus) {
        case CMAuthorizationStatusDenied:
            return @"Turn on Motion & Fitness for Spotify in Settings";
        case CMAuthorizationStatusRestricted:
            return @"Motion & Fitness is restricted on this iPhone";
        case CMAuthorizationStatusNotDetermined:
            return @"Waiting for Motion & Fitness access";
        case CMAuthorizationStatusAuthorized:
            break;
    }
    if (!sgBluetoothRoute()) return @"Connect your AirPods";
    return @"Listening for a nod or a shake";
}

void SGSetHeadGesturesEnabled(BOOL on) {
    [[SGHeadGestureEngine shared] setEnabled:on];
}
