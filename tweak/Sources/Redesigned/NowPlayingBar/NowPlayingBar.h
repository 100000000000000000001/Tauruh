#import <UIKit/UIKit.h>

#define SGRHideBarConnect @"spotifyglass.redesign.hide.barConnect"   // the device button on the card
#define SGRKeyNowPlayingRoundedArtwork @"spotifyglass.redesign.nowPlayingBar.roundedArtwork"

@class SGModRow;

NSArray<SGModRow *> *SGRNowPlayingBarRows(void);   // all redesigned now-playing and mini-player options

CGRect SGRNowPlayingCardFrameIn(UIView *host, CGFloat *radius);
// The round artwork on that card in `host`'s coordinates; CGRectNull when none was found.
CGRect SGRNowPlayingArtworkFrameIn(UIView *host);
void SGRNowPlayingBarRefresh(void);
