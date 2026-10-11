#import <UIKit/UIKit.h>

#define SGKeyControlHaptics @"spotifyglass.haptics.controls"
#define SGKeyMusicHaptics @"spotifyglass.haptics.music"
// How hard the taps are, a percentage within the range below; 100 is the feel each shipped with.
#define SGKeyControlStrength @"spotifyglass.haptics.controls.strength"
#define SGKeyMusicStrength @"spotifyglass.haptics.music.strength"
// What Music Haptics plays along with, an SGMusicFollows.
#define SGKeyMusicFollows @"spotifyglass.haptics.music.follows"
// What the keys were called while this was the redesign's alone; the %ctors move them over.
#define SGKeyControlHapticsWas @"spotifyglass.redesign.haptics.controls"
#define SGKeyMusicHapticsWas @"spotifyglass.redesign.haptics.music"
#define SGKeyControlStrengthWas @"spotifyglass.redesign.haptics.controls.strength"
#define SGKeyMusicStrengthWas @"spotifyglass.redesign.haptics.music.strength"
#define SGKeyMusicFollowsWas @"spotifyglass.redesign.haptics.music.follows"

enum {
    SGControlStrengthMin = 10, SGControlStrengthMax = 100,
    SGMusicStrengthMin = 20, SGMusicStrengthMax = 200,
    SGStrengthStep = 10,
};

typedef NS_ENUM(NSInteger, SGMusicFollows) {
    SGMusicFollowsEverything,   // a tap on each kick and snare, and the rumble under the bass
    SGMusicFollowsBeat,         // a tap on each kick and snare, no rumble
    SGMusicFollowsBass,         // a tap on each kick, and the rumble
};

typedef NS_ENUM(NSInteger, SGFeedback) {
    SGFeedbackPlay,      // playback starts
    SGFeedbackPause,     // playback stops
    SGFeedbackSkip,      // previous, next, a jump in the song (a double tap, a lyric line)
    SGFeedbackToggle,    // shuffle, repeat
    SGFeedbackAdd,       // the add button: liked songs, a playlist
    SGFeedbackGrab,      // a finger takes the scrubber
    SGFeedbackDetent,    // the scrubber passing a tenth of the song, a cover swipe passing halfway
    SGFeedbackEdge,      // the scrubber reaching the start or the end
    SGFeedbackRelease,   // the scrubber let go
};

// Plays `feedback` while Controls is on.
void SGPlayFeedback(SGFeedback feedback);
// Wakes the Taptic Engine for feedback about to follow quickly (a finger on the scrubber).
void SGPrepareFeedback(SGFeedback feedback);

// From the Music Haptics switch: starts or stops listening at once.
void SGSetMusicHapticsEnabled(BOOL on);
// From its strength and its choice of what to follow: reads them again, for the next tap.
void SGMusicHapticsSettingsChanged(void);

// A strength key's percentage as a factor, 1 for 100%, kept within its range.
double SGHapticsStrength(NSString *key);
SGMusicFollows SGMusicHapticsFollows(void);

@class SGModSection;
NSArray<SGModSection *> *SGVibrationsSections(void);
