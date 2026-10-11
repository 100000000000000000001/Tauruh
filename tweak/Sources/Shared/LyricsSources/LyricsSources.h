#import <UIKit/UIKit.h>
#import "Shared/Lyrics/Lyrics.h"

@class SGModRow;

#define SGKeyLyricsProviders @"spotifyglass.lyricsProviders"
// Offers the lyrics card on tracks Spotify itself has no lyrics for.
#define SGKeyLyricsAllTracks @"spotifyglass.lyricsAllTracks"
// Names the source the shown lines came from, on the full screen page.
#define SGKeyLyricsCredit @"spotifyglass.lyricsCredit"
#define SGKeyLyricsTranslationLanguage @"spotifyglass.lyricsTranslationLanguage"

// What a source answers with, and what the chain merges several of into one.
@interface SGLyricsResult : NSObject
@property (nonatomic, copy) NSString *provider;   // the key of the source the lines came from
@property (nonatomic) BOOL synced;                // the lines have starts of their own
@property (nonatomic) BOOL wordTimed;             // the words inside them are timed, not estimated
@property (nonatomic, copy) NSArray<NSNumber *> *starts;
@property (nonatomic, copy) NSArray<NSString *> *texts;
@property (nonatomic, copy) NSArray<SGKaraokeLine *> *karaokeLines;
@property (nonatomic, copy) NSString *title, *artist, *album;
@property (nonatomic) NSInteger seconds;
@property (nonatomic) BOOL instrumental;
@end

@interface SGLyricsQuery : NSObject
@property (nonatomic, copy) NSString *trackID;   // Spotify's base62 id
@property (nonatomic, copy) NSString *title, *artist, *album;
@property (nonatomic) NSInteger seconds;
@end

// The lines as Spotify's own page takes them, ♪ over a break and an empty line at the end.
void SGLyricsPageLines(NSArray<SGKaraokeLine *> *lines, NSArray<NSNumber *> **starts, NSArray<NSString *> **texts);

// Calls back on the main queue, nil when the source has nothing for the track.
typedef void (^SGLyricsAsk)(SGLyricsQuery *query, void (^done)(SGLyricsResult *result));

@interface SGLyricsProvider : NSObject
@property (nonatomic, copy) NSString *key;      // stored in the order, never shown
@property (nonatomic, copy) NSString *name;     // "BiniLyrics", what the credit reads
@property (nonatomic, copy) NSString *detail;   // one line under the name on the Lyrics page
@property (nonatomic) BOOL needsName;
@property (nonatomic, copy) SGLyricsAsk ask;
@end

// Every source there is, in the order a fresh install asks them.
NSArray<SGLyricsProvider *> *SGLyricsAllProviders(void);
SGLyricsProvider *SGLyricsProviderFor(NSString *key);
NSArray<NSString *> *SGLyricsOrder(void);
void SGLyricsSetOrder(NSArray<NSString *> *keys);
BOOL SGLyricsEnabled(void);   // any source at all is on

// Asks the sources in order and merges what they give, on the main queue. nil when none had lyrics.
void SGLyricsFetch(NSString *trackID, void (^done)(SGLyricsResult *result));
// NO once every source has said it has nothing for the track; safe from any thread.
BOOL SGLyricsMayHave(NSString *trackID);
void SGLyricsPrefetch(NSString *trackID);
NSInteger SGLyricsSpotifyHas(NSString *trackID);
void SGLyricsNoteSpotifyHas(NSString *trackID, BOOL has);
id SGLyricsForcedFlag(NSString *key);
// Set on the requests the mod sends to spclient itself, so the request hook leaves them alone.
extern NSString *const SGLyricsOwnRequestKey;
// The name of the source the lines shown for the track came from, nil until they arrive.
NSString *SGLyricsCreditFor(NSString *trackID);
void SGLyricsSetCredit(NSString *trackID, NSString *name);
// Turns an install's old Musixmatch switches into an order. Called once, before anything reads one.
void SGLyricsMigrateLegacyKeys(void);

// The requests the sources share; each calls back on the main queue, with nil when it failed.
NSURL *SGLyricsURL(NSString *base, NSDictionary<NSString *, NSString *> *query);
void SGLyricsGetJSON(NSURL *url, NSDictionary<NSString *, NSString *> *headers, void (^done)(id root));
void SGLyricsGetText(NSURL *url, void (^done)(NSString *text));
void SGLyricsPostJSON(NSURL *url, NSDictionary<NSString *, NSString *> *headers, id body, void (^done)(id root));
void SGLyricsNoteReply(NSURLResponse *response, NSError *error);
// What it counts as lost: the network failed, or the server answered 429 or 5xx.
BOOL SGLyricsReplyFailed(NSURLResponse *response, NSError *error);

NSArray<SGKaraokeLine *> *SGTTMLLines(NSString *xml);

NSArray<NSString *> *SGLyricsTranslationLanguages(void);
NSArray<NSString *> *SGLyricsTranslationLanguageNames(void);
// The tag of the language asked for, nil for whatever the source has.
NSString *SGLyricsTranslationLanguage(void);


// The sources themselves, each in its own file.
extern SGLyricsAsk SGBiniLyricsAsk;
extern SGLyricsAsk SGMusixmatchAsk;
extern SGLyricsAsk SGUnisonAsk;
extern SGLyricsAsk SGNetEaseAsk;
extern SGLyricsAsk SGLrcLibAsk;
extern SGLyricsAsk SGSpicyLyricsAsk;
NSString *SGSpicyLyricsAPIKey(void);
SGModRow *SGSpicyLyricsAPIKeyRow(void);

UIViewController *SGLyricsSourcesPage(void);   // the ordered list on the Lyrics page
