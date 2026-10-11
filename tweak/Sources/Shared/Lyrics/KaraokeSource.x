#import "Core/SGCore.h"
#import "Shared/Sing/SGSingController.h"
#import "Lyrics.h"
#import "Shared/LockScreenLyrics/LockScreenLyrics.h"
#import "Shared/LyricsSources/LyricsSources.h"
#import "Shared/Player/PlayerState.h"
#import "Headers/SPTPlayer.h"

NSNotificationName const SGKaraokeLinesDidChangeNotification = @"spotifyglass.karaokeLinesDidChange";

static const NSUInteger kKeptTracks = 40;
static const NSUInteger kSeenTracks = 200;
static const NSTimeInterval kRetryPause = 10, kRetryPauseMost = 60;
// What spclient needs from a request to answer it as the signed-in app.
static NSString *const kSpclientHeaders[] = {@"authorization", @"client-token", @"app-platform", @"spotify-app-version", @"user-agent", @"accept-language"};

static NSMutableDictionary<NSString *, NSArray<SGKaraokeLine *> *> *sg_lyrics;
static NSMutableSet<NSString *> *sg_requested;
static NSMutableSet<NSString *> *sg_asking;
static NSMutableDictionary<NSString *, NSNumber *> *sg_losses;   // requests lost in a row, by track
static NSDictionary<NSString *, NSString *> *sg_spclientHeaders;
static __weak id sg_player;
static NSMutableDictionary<NSString *, SPTPlayerTrack *> *sg_seenTracks;
static __weak SPTPlayerTrack *sg_lastSeen;
static NSString *sg_lastSeenID;   // the player makes a new track object on every state it reports, so the id is what tells a change
static BOOL sg_ownSources;   // a source of the mod's answers the color-lyrics request, not Spotify
static char kBodyKey;

static NSString *trackInURL(NSURL *url) {
    NSString *path = url.path;
    NSRange marker = [path rangeOfString:@"/color-lyrics/v2/track/"];
    if (marker.location == NSNotFound) return nil;
    NSString *track = [[path substringFromIndex:NSMaxRange(marker)] componentsSeparatedByString:@"/"].firstObject;
    return track.length ? track : nil;
}

static void rememberHeaders(NSURLSession *session, NSURLRequest *request) {
    if (![request.URL.host containsString:@"spclient"]) return;
    NSMutableDictionary<NSString *, NSString *> *all = [NSMutableDictionary dictionary];
    [session.configuration.HTTPAdditionalHeaders enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
        if ([key isKindOfClass:NSString.class] && [value isKindOfClass:NSString.class]) all[[key lowercaseString]] = value;
    }];
    [request.allHTTPHeaderFields enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
        all[key.lowercaseString] = value;
    }];
    if (!all[@"authorization"]) return;
    NSMutableDictionary<NSString *, NSString *> *headers = [NSMutableDictionary dictionary];
    for (NSUInteger i = 0; i < sizeof(kSpclientHeaders) / sizeof(*kSpclientHeaders); i++) {
        NSString *name = kSpclientHeaders[i];
        if (all[name]) headers[name] = all[name];
    }
    dispatch_async(dispatch_get_main_queue(), ^{ sg_spclientHeaders = headers; });
}

static SPTPlayerState *playerState(void);
static NSString *idOf(SPTPlayerTrack *track);

// The track after this one, when the player knows it.
static SPTPlayerTrack *upNextIn(SPTPlayerState *state) {
    id future = [state respondsToSelector:@selector(future)] ? state.future : nil;
    id next = [future isKindOfClass:NSArray.class] ? [(NSArray *)future firstObject] : nil;
    return [next isKindOfClass:objc_getClass("SPTPlayerTrack")] ? next : nil;
}

static void keep(NSString *track, NSArray<SGKaraokeLine *> *lines) {
    if (sg_lyrics.count >= kKeptTracks && !sg_lyrics[track]) {
        NSMutableSet<NSString *> *spared = [sg_asking mutableCopy];
        SPTPlayerState *state = playerState();
        NSString *playing = idOf(state.track), *next = idOf(upNextIn(state));
        if (playing) [spared addObject:playing];
        if (next) [spared addObject:next];
        for (NSString *kept in sg_lyrics.allKeys) {
            if ([spared containsObject:kept]) continue;
            [sg_lyrics removeObjectForKey:kept];
            [sg_requested removeObject:kept];
        }
    }
    sg_lyrics[track] = lines;
    [NSNotificationCenter.defaultCenter postNotificationName:SGKaraokeLinesDidChangeNotification object:track];
}

void SGKaraokeKeepLines(NSString *track, NSArray<SGKaraokeLine *> *lines) {
    dispatch_async(dispatch_get_main_queue(), ^{ keep(track, lines); });
}

static void received(NSURLSession *session, NSURLSessionTask *task, NSData *data) {
    rememberHeaders(session, task.currentRequest);
    if (sg_ownSources || !trackInURL(task.currentRequest.URL)) return;
    NSMutableData *body = objc_getAssociatedObject(task, &kBodyKey);
    if (!body) objc_setAssociatedObject(task, &kBodyKey, (body = [NSMutableData data]), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [body appendData:data];
}

static void completed(NSURLSessionTask *task, NSError *error) {
    NSMutableData *body = objc_getAssociatedObject(task, &kBodyKey);
    if (!body) {
        NSString *path = task.currentRequest.URL.path;
        if (!sg_ownSources && [path.lowercaseString containsString:@"lyrics"]) SGLog(@"karaoke: lyrics request not read: %@ (error %@)", path, error);
        return;
    }
    objc_setAssociatedObject(task, &kBodyKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSString *track = trackInURL(task.currentRequest.URL);
    if (error || !track) return;
    NSArray<SGKaraokeLine *> *lines = SGKaraokeLinesFromBody(body);
    SGLog(@"karaoke: lyrics for %@, %lu bytes, %lu synced lines", track, (unsigned long)body.length, (unsigned long)lines.count);
    if (lines) SGKaraokeKeepLines(track, lines);
}

NSArray<SGKaraokeLine *> *SGKaraokeLinesForTrack(NSString *trackID) {
    return trackID ? sg_lyrics[trackID] : nil;
}

static void askAgainLater(NSString *trackID) {
    NSUInteger losses = sg_losses[trackID].unsignedIntegerValue;
    sg_losses[trackID] = @(losses + 1);
    NSTimeInterval pause = MIN(kRetryPause * pow(2, losses), kRetryPauseMost);
    SGLog(@"karaoke: lyrics for %@ not answered, may ask again in %.0fs", trackID, pause);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(pause * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [sg_asking removeObject:trackID];
        [sg_requested removeObject:trackID];
    });
}

NSString *SGKaraokeSpotifyAuthorization(void) {
    return sg_spclientHeaders[@"authorization"];
}

// `retry`: the sources' walk failed on the way, so an answer with no lines is not final either.
static void requestFromSpotify(NSString *trackID, BOOL retry) {
    NSDictionary<NSString *, NSString *> *headers = sg_spclientHeaders;
    if (!headers) return;
    [sg_requested addObject:trackID];
    [sg_asking addObject:trackID];
    NSString *address = [NSString stringWithFormat:@"https://spclient.wg.spotify.com/color-lyrics/v2/track/%@?format=json&vocalRemoval=false&market=from_token", trackID];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:address]];
    [headers enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSString *value, BOOL *stop) {
        [request setValue:value forHTTPHeaderField:name];
    }];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    // The mod's own, so LyricsHook's request hook does not send it to the donor.
    [NSURLProtocol setProperty:@YES forKey:SGLyricsOwnRequestKey inRequest:request];
    [[NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *body, NSURLResponse *response, NSError *error) {
        NSArray<SGKaraokeLine *> *lines = SGKaraokeLinesFromBody(body);
        NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
        SGLog(@"karaoke: fetched lyrics for %@: status %ld, %lu lines (%@), error %@", trackID,
              (long)status, (unsigned long)lines.count,
              SGKaraokeLinesTiming(lines) == SGKaraokeTimingNone ? @"untimed" : @"line timed", error);
        BOOL lost = SGLyricsReplyFailed(response, error) || status == 401 || status == 403;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (lost || (retry && !lines)) {
                askAgainLater(trackID);
                return;
            }
            [sg_asking removeObject:trackID];
            [sg_losses removeObjectForKey:trackID];
            if (!lines) return;
            // Asked after the chain found plain text only: Spotify's replace it only when they are timed.
            NSArray<SGKaraokeLine *> *kept = sg_lyrics[trackID];
            if (kept && SGKaraokeLinesTiming(kept) <= SGKaraokeLinesTiming(lines)) return;
            keep(trackID, lines);
            SGLyricsSetCredit(trackID, @"Spotify");
        });
    }] resume];
}

void SGKaraokeAskSpotifyForTiming(NSString *trackID) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!trackID || [sg_requested containsObject:trackID]) return;
        requestFromSpotify(trackID, NO);
    });
}

void SGKaraokeRequestLyrics(NSString *trackID) {
    if (!trackID || sg_lyrics[trackID] || [sg_requested containsObject:trackID]) return;
    if (!sg_ownSources) {
        requestFromSpotify(trackID, NO);
        return;
    }
    [sg_requested addObject:trackID];
    [sg_asking addObject:trackID];
    SGLyricsFetch(trackID, ^(SGLyricsResult *lyrics) {
        [sg_asking removeObject:trackID];
        if (lyrics.karaokeLines) {
            keep(trackID, lyrics.karaokeLines);   // on the main queue, where the fetch answers
            SGLyricsSetCredit(trackID, lyrics.provider);
            // Plain text is shown while Spotify is asked whether it has the song timed.
            if (SGKaraokeLinesTiming(lyrics.karaokeLines) != SGKaraokeTimingNone) return;
        }
        [sg_requested removeObject:trackID];
        requestFromSpotify(trackID, !lyrics && SGLyricsMayHave(trackID));
    });
}

id SGKaraokePlayer(void) {
    return sg_player;
}

static SPTPlayerState *playerState(void) {
    id player = sg_player;
    return [player respondsToSelector:@selector(state)] ? [(id<SPTPlayer>)player state] : nil;
}

NSString *SGKaraokePlayingTrack(void) {
    id uri = playerState().track.URI;
    NSString *text = [uri isKindOfClass:NSURL.class] ? ((NSURL *)uri).absoluteString : [uri description];
    return [text hasPrefix:@"spotify:track:"] ? [text substringFromIndex:@"spotify:track:".length] : nil;
}

NSInteger SGKaraokePositionMs(void) {
    SPTPlayerState *state = playerState();
    if (!state) return -1;
    double position;
    if (!SGSingPosition(state, &position)) position = state.isPaused ? state.positionAsOfTimestamp : state.position;
    return (NSInteger)(position * 1000);
}

void SGKaraokeSeek(NSInteger ms) {
    id player = sg_player;
    if (![player respondsToSelector:@selector(seekTo:)]) return;
    [(id<SPTPlayer>)player seekTo:ms / 1000.0];
}

static NSString *idOf(SPTPlayerTrack *track) {
    id uri = track.URI;
    NSString *text = [uri isKindOfClass:NSURL.class] ? ((NSURL *)uri).absoluteString : [uri description];
    return [text hasPrefix:@"spotify:track:"] ? [text substringFromIndex:@"spotify:track:".length] : nil;
}

static void remember(SPTPlayerTrack *track, NSString *trackID) {
    @synchronized (sg_seenTracks) {
        if (sg_seenTracks.count >= kSeenTracks) {
            [sg_seenTracks removeAllObjects];
            SPTPlayerTrack *playing = sg_lastSeen;
            NSString *playingID = playing ? idOf(playing) : nil;
            if (playingID) sg_seenTracks[playingID] = playing;
        }
        sg_seenTracks[trackID] = track;
    }
}

SPTPlayerTrack *SGKaraokeTrackFor(NSString *trackID) {
    if (!trackID) return nil;
    @synchronized (sg_seenTracks) { return sg_seenTracks[trackID]; }
}

void SGKaraokeRememberTrack(SPTPlayerTrack *track) {
    if (!sg_seenTracks) return;
    NSString *trackID = idOf(track);
    if (trackID) remember(track, trackID);
}

static void prefetch(SPTPlayerTrack *track, NSString *trackID, SPTPlayerState *state) {
    if (!sg_ownSources) return;
    SGLyricsPrefetch(trackID);
    SPTPlayerTrack *next = upNextIn(state);
    NSString *nextID = idOf(next);
    if (!nextID || [nextID isEqualToString:trackID]) return;
    remember(next, nextID);
    SGLyricsPrefetch(nextID);
}

%hook SPTEsperantoPlayer
- (id)state {
    if (!sg_player) sg_player = self;
    SPTPlayerState *state = %orig;
    SPTPlayerTrack *track = state.track;
    if (track && track != sg_lastSeen) {
        sg_lastSeen = track;
        NSString *trackID = idOf(track);
        if (trackID && ![trackID isEqualToString:sg_lastSeenID]) {
            sg_lastSeenID = trackID;
            remember(track, trackID);
            prefetch(track, trackID, state);
        }
    }
    return state;
}
%end

@interface SGKaraokeTrackWatcher : NSObject <SGPlayerStateObserver>
@end

@implementation SGKaraokeTrackWatcher
- (void)playerStateDidChange:(SPTPlayerState *)state {
    playerState();
}
@end

static SGKaraokeTrackWatcher *sg_trackWatcher;

%hook SPTDataLoaderService
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    received(session, task, data);
    %orig;
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    completed(task, error);
    %orig;
}
%end

%hook _TtC26Connectivity_HttpClientKit20HttpClientURLSession
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    received(session, task, data);
    %orig;
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    completed(task, error);
    %orig;
}
%end

%ctor {
    if (!SGRedesignedUI() && !SGFlag(SGKeyLockScreenLyrics, YES) && !SGLyricsEnabled()) return;
    sg_seenTracks = [NSMutableDictionary dictionary];
    sg_lyrics = [NSMutableDictionary dictionary];
    sg_requested = [NSMutableSet set];
    sg_asking = [NSMutableSet set];
    sg_losses = [NSMutableDictionary dictionary];
    sg_ownSources = SGLyricsEnabled();
    %init;
    sg_trackWatcher = [SGKaraokeTrackWatcher new];
    SGAddPlayerStateObserver(sg_trackWatcher);
    [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil
                                                     queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        SPTPlayerState *state = playerState();
        NSString *trackID = idOf(state.track);
        if (trackID) prefetch(state.track, trackID, state);
    }];
    SGLog(@"karaoke: on");
    SGRequireClasses(@[
        @"SPTEsperantoPlayer", @"SPTPlayerState",
        @"SPTDataLoaderService", @"_TtC26Connectivity_HttpClientKit20HttpClientURLSession",
    ]);
}
