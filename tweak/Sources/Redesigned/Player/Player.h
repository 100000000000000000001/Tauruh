#import <UIKit/UIKit.h>

@class SGRArtworkField;
@class SGModSection;

// The field behind the player.
#define SGRKeyPlayerBackground @"spotifyglass.redesign.player.background"
typedef NS_ENUM(NSInteger, SGRPlayerBackgroundKind) {
    SGRPlayerBackgroundStill,
    SGRPlayerBackgroundColours,
    SGRPlayerBackgroundFluid,
    SGRPlayerBackgroundAnimated,
    SGRPlayerBackgroundVisualiser,
};
SGRPlayerBackgroundKind SGRPlayerBackground(void);
NSArray<NSString *> *SGRPlayerBackgroundNames(void);

#define SGRKeyPlayerMotion @"spotifyglass.redesign.player.movingBackground"
#pragma mark - the ⋯ menu (PlayerMenu.x)

void SGRPlayerMenuWatchMoreButton(UIView *button);

// The field behind the player, nil until the player has laid out once (PlayerField.x).
SGRArtworkField *SGRPlayerField(void);
void SGRPlayerHoldField(void);

#pragma mark - the cover (PlayerArtwork.x)

// The sideways list of covers behind the player, nil until one has laid out.
UIView *SGRPlayerCoverList(void);
CGRect SGRPlayerCoverFrameIn(UIView *host);
CGRect SGRPlayerArtworkAreaIn(UIView *host);
void SGRPlayerSetCoverHidden(BOOL hidden);
CGFloat SGRPlayerCoverScale(void);

#pragma mark - the lyrics in the player (PlayerLyrics.x)

// Allow the lyrics screen to rotate into its two-column landscape layout.
#define SGRKeyLandscapeLyrics @"spotifyglass.redesign.landscapeLyrics"
void SGRPlayerLyricsOrientationChanged(void);
void SGRPlayerForceLandscapeLyrics(void);

// Whether the playing track has lyrics the player can show.
BOOL SGRPlayerLyricsAvailable(void);
// Whether the player is showing them.
BOOL SGRPlayerLyricsOpen(void);
// Shows them, or puts the cover back; does nothing when there are none to show.
void SGRPlayerToggleLyrics(void);
void SGRPlayerLyricsChanged(void);
#define SGRKeyLyricsAutoHide @"spotifyglass.redesign.lyrics.autoHide"

// The system volume slider below the player controls.
#define SGRKeyPlayerVolume @"spotifyglass.redesign.player.volume"
BOOL SGRPlayerVolumeOn(void);
BOOL SGRPlayerPlaceVolume(UIView *stack, UIView *controls, UIView *row, CGFloat margin);

// The cover's color may tint the player's controls.
#define SGRKeyPlayerFollowsCover @"spotifyglass.redesign.player.followsCover"
BOOL SGRPlayerFollowsCover(void);
void SGRPlayerSetCoverAccent(UIColor *cover);
void SGRPlayerPaintCover(UIView *stack);

// Landscape lyrics take over the player when enabled.
#define SGRKeyLyricsLandscape @"spotifyglass.redesign.lyrics.landscape"
void SGRPlayerShowLandscape(BOOL show);

void SGRPlayerMotionLyricsChanged(void);
void SGRPlayerMotionFieldLaidOut(void);
void SGRPlayerMotionCoverLaidOut(void);
BOOL SGRPlayerMotionShowing(void);
UIView *SGRPlayerMotionPreview(void (^arrived)(void));
CGFloat SGRPlayerClipDim(CGFloat luminance, BOOL contrast, BOOL lyrics);

BOOL SGRPlayerVisualiserShowing(void);
void SGRPlayerVisualiserUpdate(void);
UIView *SGRPlayerVisualiserPreview(void);
void SGRPlayerMenuSetBackground(SGRPlayerBackgroundKind kind);

void SGRPlayerVanish(UIView *view);

UIViewController *SGRPlayerSettingsPage(NSArray<SGModSection *> *more);
