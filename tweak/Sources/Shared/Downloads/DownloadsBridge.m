#import "Core/SGCore.h"
#import "Downloads.h"
#import "DownloadsBridge.h"

NSNotificationName const SGDownloadsDidChangeNotification = @"spotifyglass.downloads.changed";

Class<SGDownloadsCompanion> SGDownloadsCompanion(void) {
    static Class<SGDownloadsCompanion> companion;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class found = NSClassFromString(@"SAPTaurusBridge");
        if (found && [found respondsToSelector:@selector(interfaceVersion)]
            && [(Class<SGDownloadsCompanion>)found interfaceVersion] >= 1) companion = (Class<SGDownloadsCompanion>)found;
    });
    return companion;
}

BOOL SGDownloadsAvailable(void) { return SGDownloadsCompanion() != nil; }

BOOL SGDownloadsActive(void) { return [SGDownloadsCompanion() downloadActive]; }

NSString *SGDownloadsSummary(void) {
    Class<SGDownloadsCompanion> companion = SGDownloadsCompanion();
    if (!companion) return @"Downloads need Spotify 9.1.90";
    return [companion downloadSummary] ?: @"No download started";
}

NSString *SGDownloadsRowSummary(void) {
    if (!SGDownloadsAvailable()) return @"Unavailable";
    return SGDownloadsActive() ? @"Downloading" : @"Ready";
}
