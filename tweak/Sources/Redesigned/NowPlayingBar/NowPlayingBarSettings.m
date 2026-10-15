#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Redesigned/Navbar/Navbar.h"
#import "NowPlayingBar.h"
#import "Redesigned/Player/Player.h"

UIViewController *SGRNowPlayingBarSettingsPage(void) {
    return [[SGModPage alloc] initWithTitle:@"Now playing" intro:SGRestartNote sections:@[
        SGSection(nil, @[
            SGHideRow(@"Hide the device button", nil, SGRHideBarConnect),
        ]),
        SGSection(nil, @[
            SGSwitchRow(@"Moving background", nil, SGRKeyPlayerMotion),
        ]),
    ] footer:nil];
}

// The Mini player section on the redesign's Player page: compact merging while scrolling and artwork shape.
NSArray<SGModRow *> *SGRNowPlayingBarRows(void) {
    SGModRow *roundedArtwork = SGOptionRow(@"Rounded-square album art", @"Use rounded corners instead of a circle",
                                            SGRKeyNowPlayingRoundedArtwork);
    roundedArtwork.changed = ^(BOOL on) { SGRNowPlayingBarRefresh(); };
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
    ];
}
