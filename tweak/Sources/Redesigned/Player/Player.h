#import <UIKit/UIKit.h>

@class SGRArtworkField;

#define SGRKeyPlayerMotion @"spotifyglass.redesign.player.movingBackground"
#pragma mark - the ⋯ menu (PlayerMenu.x)

void SGRPlayerMenuWatchMoreButton(UIView *button);

// The field behind the player, nil until the player has laid out once (PlayerField.x).
SGRArtworkField *SGRPlayerField(void);

#pragma mark - the cover (PlayerArtwork.x)

// The sideways list of covers behind the player, nil until one has laid out.
UIView *SGRPlayerCoverList(void);
CGRect SGRPlayerCoverFrameIn(UIView *host);
CGRect SGRPlayerArtworkAreaIn(UIView *host);
void SGRPlayerSetCoverHidden(BOOL hidden);

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

void SGRPlayerVanish(UIView *view);
