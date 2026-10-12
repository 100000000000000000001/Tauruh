// What the lock screen fills the screen with, the lyrics' style and whether the downloads run in Low Data
// Mode. iOS 26 and up only.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "AnimatedArtwork.h"
#import "Shared/LockScreenArtwork/LockScreenArtwork.h"

SGLockArtwork SGLockScreenArtwork(void) {
    if (@available(iOS 26.0, *)) {
        // The old switch's YES and NO read as Moving artwork and Off, the enum's first two.
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
            SGMigrateKey(SGKeyLockScreenMotion, SGKeyFullScreenArtwork);
            SGMigrateKey(SGKeyLegacyLockScreenArtwork, SGKeyFullScreenArtwork);
            if (![store objectForKey:SGKeyFullScreenArtwork]) {
                SGSetInt(SGKeyFullScreenArtwork, SGFlag(SGKeyLegacyLockScreenArtwork, YES)
                         ? SGLockArtworkMotion : SGLockArtworkOff);
            }
            if (![store objectForKey:SGKeyMotionSources]) {
                NSArray<NSString *> *legacy = SGArtworkOrder();
                if (legacy.count) [store setObject:legacy forKey:SGKeyMotionSources];
            }
        });
        return (SGLockArtwork)SGInt(SGKeyFullScreenArtwork, SGLockArtworkOff);
    }
    return SGLockArtworkOff;
}

BOOL SGLockScreenCanvasLyricsEnabled(void) {
    return SGHidden(SGKeyLockScreenCanvasLyrics);
}

void SGLockScreenCanvasLyricsSetEnabled(BOOL enabled) {
    SGSetEnabled(SGKeyLockScreenCanvasLyrics, enabled);
}

NSArray *SGLockScreenMotionRows(void) {
    if (@available(iOS 26.0, *)) {
        SGLockScreenArtwork();   // moves the old switch over before the row reads the new key
        SGModRow *style = SGChoiceRow(@"Lyrics style", @"Still draws each line once; Animated breathes the cover behind it",
                                      SGKeyLockScreenLyricsStyle, @[@"Still", @"Animated"], 0);
        style.visible = ^BOOL { return SGLockScreenArtwork() == SGLockArtworkLyrics; };
        SGModRow *canvasLyrics = SGOptionRow(@"Canvas lyrics", @"Show synced lines over the moving artwork",
                                             SGKeyLockScreenCanvasLyrics);
        canvasLyrics.visible = ^BOOL { return SGLockArtworkHasMotion(SGLockScreenArtwork()); };
        SGModRow *star = SGOptionRow(@"Switch with the star", @"Use the lock-screen favorite star to toggle Canvas lyrics",
                                     SGKeyLockScreenStar);
        star.visible = ^BOOL { return SGLockArtworkHasMotion(SGLockScreenArtwork()); };
        SGModRow *lowData = SGOptionRow(@"Download in Low Data Mode", @"Moving artwork, up to about 7 MB a song", SGKeyMotionLowData);
        lowData.visible = ^BOOL { return SGLockArtworkHasMotion(SGLockScreenArtwork()); };
        SGModRow *sources = SGMotionSourcesRow();
        sources.visible = lowData.visible;
        return @[
            SGChoiceRow(@"Full-screen artwork", @"The Canvas or Apple Music's animated cover, or the lyrics a line at a time. "
                                                 @"Every song puts the cover over a moving blur of it where a song has neither",
                        SGKeyFullScreenArtwork, @[@"Off", @"Moving artwork", @"Lyrics", @"Every song"], SGLockArtworkOff),
            style,
            canvasLyrics,
            star,
            sources,
            lowData,
        ];
    }
    return @[SGLockScreenArtworkNeedsRow()];
}

// Below iOS 26 the section stays, with one row that says why there is nothing to pick.
SGModRow *SGLockScreenArtworkNeedsRow(void) {
    return SGStatActionRow(@"Full-screen artwork", nil, ^NSString *{ return @"Needs iOS 26"; }, ^{
        NSString *message = [NSString stringWithFormat:@"This iPhone has iOS %@. The lock screen takes moving artwork "
                                                       @"from apps from iOS 26 on, so the Canvas and Apple Music's animated "
                                                       @"covers can show there once the iPhone is updated.", UIDevice.currentDevice.systemVersion];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Needs iOS 26" message:message
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [SGTopController() presentViewController:alert animated:YES completion:nil];
    });
}
