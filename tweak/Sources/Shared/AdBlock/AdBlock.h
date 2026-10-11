#import <UIKit/UIKit.h>

#define SGKeyHideAds @"spotifyglass.adblock.ads"
#define SGKeyHideUpsells @"spotifyglass.adblock.upsells"
#define SGKeyFakePremium @"spotifyglass.adblock.premium"
#define SGKeyHideSearchVideos @"spotifyglass.adblock.searchVideos"

// What a switch turning Spoof Premium on is told first.
extern NSString *const SGFakePremiumWarning;

// A flag the ads or upsells switch forces off while it is on. Flags.x asks, and the row for it locks.
BOOL SGAdBlockForcesFlagOff(NSString *key);

// What the hooks stopped, by kind, for the counts under the switches (nil label for all of them).
void SGAdBlockCountOne(NSString *label);
NSArray<NSString *> *SGAdBlockLabels(void);
NSUInteger SGAdBlockCount(NSString *label);
void SGResetAdBlock(void);

NSData *SGPatchCustomize(NSData *body);
NSData *SGPatchBootstrap(NSData *body);

NSData *SGStripFeed(NSData *body);

// The Premium, ads & privacy page: these switches, the ad flags they lock, telemetry, the counters.
UIViewController *SGAdsSettingsPage(void);
