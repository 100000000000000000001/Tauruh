#import <UIKit/UIKit.h>
#import "Redesigned/Kit/SGRHeaderInfo.h"

// The artist page `view` is on, or nil: the TemplateView with the identifier creator-page.
UIView *SGRArtistPageOf(UIView *view);

UIColor *SGRArtistFieldColor(UIView *view);
// The artist's photo, for the page's field to take its colour from. The same image again is a no-op.
void SGRArtistSetArtwork(UIView *view, UIImage *image);

BOOL SGRArtistFollowing(UIView *page, NSString *moreIdentifier, BOOL *following, void (^changed)(void));

// The artist's upcoming concerts as a glass card under the row of buttons (ArtistConcerts.m). Asks once per
// artist; `changed` runs once the card is in or out, for the page to lay itself out again.
void SGRArtistConcerts(SGRHeaderInfo *info, UIView *page, NSString *name, void (^changed)(void));
