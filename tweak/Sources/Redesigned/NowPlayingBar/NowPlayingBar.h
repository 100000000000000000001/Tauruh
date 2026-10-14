#import <UIKit/UIKit.h>

#define SGRHideBarConnect @"spotifyglass.redesign.hide.barConnect"   // the device button on the card
#define SGRKeyNowPlayingRoundedArtwork @"spotifyglass.redesign.nowPlayingBar.roundedArtwork"

@class SGModRow;

UIViewController *SGRNowPlayingBarSettingsPage(void);
NSArray<SGModRow *> *SGRNowPlayingBarRows(void);   // the Mini player section on the redesign's Player page

CGRect SGRNowPlayingCardFrameIn(UIView *host, CGFloat *radius);
// The round artwork on that card in `host`'s coordinates; CGRectNull when none was found.
CGRect SGRNowPlayingArtworkFrameIn(UIView *host);
void SGRNowPlayingBarRefresh(void);
