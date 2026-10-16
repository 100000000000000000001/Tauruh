#import <UIKit/UIKit.h>

#define SGRKeyNavbar @"spotifyglass.redesign.navbar"
// Icons only on the glass bar. Off unless set; applies as soon as the bar lays out again.
#define SGRKeyNavbarHideLabels @"spotifyglass.redesign.navbar.hideLabels"
// Whether a page's scroll hides the glass bar. On unless set; read once at launch.
#define SGRKeyNavbarMinimize @"spotifyglass.redesign.navbar.minimize"
#define SGRKeyNavbarProfilePhoto @"spotifyglass.redesign.navbar.profilePhoto"
#define SGRKeyNavbarCompact @"spotifyglass.redesign.navbar.compact"
#define SGRKeyNavbarAppleIcons @"spotifyglass.redesign.navbar.appleIcons"

extern NSString *const SGRNavbarID;      // NSString, the entry's identity
extern NSString *const SGRNavbarTitle;   // NSString, the name in the settings list and under the icon
extern NSString *const SGRNavbarURI;     // NSString, the mod's own tabs only: what a tap opens
extern NSString *const SGRNavbarIcon;    // NSString, an SPTEncoreIcon class method such as "podcasts"
extern NSString *const SGRNavbarIconSet; // NSString, SGTabIconSetSymbols when the icon is an SF Symbol
extern NSString *const SGRNavbarCustomIcon; // NSNumber, whether a stock tab has a custom glyph
extern NSString *const SGRNavbarHidden;   // NSNumber
NSArray<NSDictionary *> *SGRNavbarLayout(void);
void SGRSetNavbarLayout(NSArray<NSDictionary *> *layout);
NSString *SGRNavbarDefaultIcon(NSString *stockID);
BOOL SGRNavbarEntryHasCustomIcon(NSDictionary *entry);
// Spotify's own tabs in Spotify's order, as Navbar.x last saw them on the bar.
NSArray<NSString *> *SGRNavbarStock(void);
void SGRSetNavbarStock(NSArray<NSString *> *stock);
NSArray<NSString *> *SGRNavbarRemovedStock(void);
void SGRSetNavbarRemovedStock(NSArray<NSString *> *stock);
NSURL *SGRNavbarTabURL(NSString *uri);

// Navbar.x, called from the tab bar's layout passes in TabBar.x.
void SGRComposeTabBar(UIView *tabBar);
void SGRLogTabBarRow(UIView *tabBar);
void SGRAlignCompactTabBarToNowPlayingCard(void);
// Lays the bar out again after the Navbar page changes something, so it does not wait for a touch.
void SGRRefreshTabBar(void);
void SGRNavbarSetProfilePhotoVisible(UIView *face);
void SGRNavbarRefreshProfilePhotos(void);
// Called by the compact tab bar when its host row changes size.
void SGRNowPlayingBarFollowTabBar(void);
// The mini-player slot alongside the compact tab item, in `host` coordinates.
CGRect SGRTabBarInlineSlot(UIView *host, CGFloat height);

UIViewController *SGRNavbarSettingsPage(void);   // the tab editor, in Mod Settings
UIViewController *SGRNavbarEditorPage(void);     // the tab editor alone, for the welcome tour

// TabBar.x: whether the glass bar is hidden by a page's scroll, and hiding it (TabBarMinimize.x).
BOOL SGRTabBarMinimized(void);
void SGRSetTabBarMinimized(BOOL minimized, BOOL animated);
