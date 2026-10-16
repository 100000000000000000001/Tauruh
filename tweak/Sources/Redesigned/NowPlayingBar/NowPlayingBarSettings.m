#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Redesigned/Navbar/Navbar.h"
#import "NowPlayingBar.h"
#import "Redesigned/Player/Player.h"

// The mini player settings on the redesign's Player page.
NSArray<SGModRow *> *SGRNowPlayingBarRows(void) {
    SGModRow *roundedArtwork = SGOptionRow(@"Rounded-square album art", @"Use rounded corners instead of a circle",
                                            SGRKeyNowPlayingRoundedArtwork);
    roundedArtwork.changed = ^(BOOL on) { SGRNowPlayingBarRefresh(); };
    SGModRow *hideDevice = SGHideRow(@"Hide the device button", @"Hide the Connect button in the mini player",
                                     SGRHideBarConnect);
    SGModRow *movingBackground = SGSwitchRow(@"Moving background", nil, SGRKeyPlayerMotion);
    SGModRow *merge = SGSwitchRow(@"Mini player transition animations", @"Merge the mini player into the compact tab while scrolling",
                                  SGRKeyNavbarCompact);
    merge.changed = ^(BOOL on) {
        SGSetFlagOverride(@"ios-feature-nowplaying.miniplayer_transition_animations", on ? @YES : nil);
        SGRSetTabBarMinimized(SGRTabBarMinimized(), NO);
        SGRRefreshTabBar();
        SGRNowPlayingBarFollowTabBar();
    };
    return @[
        merge,
        roundedArtwork,
        hideDevice,
        movingBackground,
    ];
}
