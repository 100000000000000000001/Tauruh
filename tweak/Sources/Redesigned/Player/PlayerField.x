#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Player.h"

static const UIEdgeInsets kBleed = {200, 0, 600, 0};
// A cover this narrow is a placeholder glyph or the bar's, not the player's.
static const CGFloat kCoverMinWidth = 200;

static char kFieldKey, kCoverImageKey;
static __weak SGRArtworkField *sg_field;
static __weak UIScrollView *sg_coverList;
static __weak UIImage *sg_lastCover;
static NSString *sg_lastCoverURI;
// Spotify's colour for the player, which can arrive before the plane has laid out once.
static UIColor *sg_spotifyColor;

SGRArtworkField *SGRPlayerField(void) {
    return sg_field;
}

#pragma mark - the field

static void showArtwork(SGRArtworkField *field, BOOL animated) {
    NSString *identity = nil;
    UIImage *image = SGRNowPlayingArtwork(NULL, &identity);
    if (field && image) [field setArtwork:image identity:identity animated:animated];
}

static SGRArtworkField *fieldIn(UIView *plane) {
    SGRArtworkField *field = objc_getAssociatedObject(plane, &kFieldKey);
    if (field) return field;
    field = [[SGRArtworkField alloc] initWithFrame:plane.bounds];
    field.showsBackdrop = YES;
    field.flows = SGEnabled(SGRKeyPlayerMotion);
    // A paused song holds the colours still, the way it rests the cover (PlayerArtwork.x).
    field.motionHeld = SGPlayerState().isPaused;
    field.bleed = kBleed;
    objc_setAssociatedObject(plane, &kFieldKey, field, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    sg_field = field;
    [field setProvisionalColor:sg_spotifyColor];
    showArtwork(field, NO);
    SGLog(@"redesign player: field in the background plane %.0fx%.0f, artwork %@", plane.bounds.size.width, plane.bounds.size.height, SGRNowPlayingArtwork(NULL, NULL) ? @"ready" : @"not read yet");
    return field;
}

%hook _TtC21NowPlaying_ScrollImpl27NPVBackgroundViewController
- (void)viewDidLayoutSubviews {
    %orig;
    UIView *plane = ((UIViewController *)self).viewIfLoaded;
    if (!plane || plane.bounds.size.height < 200) return;
    SGRArtworkField *field = fieldIn(plane);
    sg_field = field;
    if (field.superview != plane) [plane addSubview:field];
    else if (plane.subviews.lastObject != field) [plane bringSubviewToFront:field];
    if (!CGRectEqualToRect(field.frame, plane.bounds)) field.frame = plane.bounds;
}

- (void)backgroundViewModel:(id)model didChangeColor:(id)color playerState:(id)state {
    %orig;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ SGLog(@"redesign player: Spotify's colour %@ (%@), state %@", color, [color class], [state class]); });
    if (![color isKindOfClass:UIColor.class]) return;
    sg_spotifyColor = color;
    UIView *plane = ((UIViewController *)self).viewIfLoaded;
    SGRArtworkField *field = plane ? objc_getAssociatedObject(plane, &kFieldKey) : nil;
    [field setProvisionalColor:color];
}
%end

#pragma mark - the player's own cover

static UIImage *settledCover(UIScrollView *list) {
    if (!list.window || list.isDragging || list.isDecelerating) return nil;
    CGFloat middle = CGRectGetMidX(list.bounds);
    for (UIView *cell in list.subviews) {
        if (cell.hidden || ![cell isKindOfClass:UICollectionViewCell.class] || fabs(CGRectGetMidX(cell.frame) - middle) > 1) continue;
        UIView *holder = SGRFindByIdentifier(cell, @"Encore.ImageView", &kCoverImageKey);
        if (holder.bounds.size.width < kCoverMinWidth) return nil;
        for (UIView *sub in holder.subviews) {
            UIImageView *image = (UIImageView *)sub;
            if ([sub isKindOfClass:UIImageView.class] && image.image && image.alpha > 0) return image.image;
        }
        return nil;
    }
    return nil;
}

static void publishCover(void) {
    UIImage *cover = settledCover(sg_coverList);
    if (!cover) return;
    NSString *uri = SGURIString(SGPlayerState().track.URI);
    if (!uri || (cover == sg_lastCover && [uri isEqualToString:sg_lastCoverURI])) return;
    sg_lastCover = cover;
    sg_lastCoverURI = uri;
    SGRSetNowPlayingArtwork(cover, uri, SGRArtworkQualityHigh);
    static NSUInteger logged;
    if (logged++ < 3) SGLog(@"redesign player: cover %.0fx%.0f published for %@", cover.size.width, cover.size.height, uri);
}

%hook _TtC35NowPlaying_ContentLayerPlatformImpl24AccessibleCollectionView
- (void)layoutSubviews {
    %orig;
    sg_coverList = (UIScrollView *)self;
    publishCover();
}
%end

@interface SGRPlayerCoverWatcher : NSObject <SGPlayerStateObserver>
@end

@implementation SGRPlayerCoverWatcher {
    NSString *_track;
}

- (void)playerStateDidChange:(SPTPlayerState *)state {
    sg_field.motionHeld = state.isPaused;
    NSString *track = SGURIString(state.track.URI);
    if (!track || [track isEqualToString:_track]) return;
    _track = track;
    for (NSNumber *delay in @[@0.3, @1, @2.5]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ publishCover(); });
    }
}

@end

static SGRPlayerCoverWatcher *sg_coverWatcher;

%ctor {
    // Registered whatever the switch says: the flag rows elsewhere lock to these while it is on.
    NSMutableDictionary<NSString *, id> *flags = [@{
        // The artwork is the picture; Canvas video would cover the field and the corners.
        @"ios-feature-canvas.canvas_enabled": @NO,
        @"ios-feature-nowplaying.new_redesign_header_with_context_menu_enabled": @YES,
        @"ios-feature-encoreexperiments.new_npv_slider_enabled": @YES,
        @"ios-feature-nowplaying.bottom_sheet_queue_enabled": @YES,
        @"ios-feature-nowplaying-elements.enable_connect_bottom_sheet": @YES,
        @"ios-feature-nowplaying.sheet_style_npv": @YES,
        // Art around the play disc would sit under a bare glyph.
        @"ios-feature-nowplaying-elements.mixing_play_button": @NO,
    } mutableCopy];
    for (NSString *egg in @[@"ariana_petal_play_button_easter_egg", @"attack_on_titan_easter_egg_enabled", @"barbie_easter_egg_enabled",
                            @"black_panther_easter_egg_enabled", @"demogorgon_easter_egg", @"harry_potter_play_button_surround_easter_egg",
                            @"luma_easter_egg", @"pokemon_easter_egg_enabled", @"sanremo_easter_egg_enabled", @"sanrio_easter_egg_enabled",
                            @"spiderman_easter_egg_enabled", @"star_easter_egg", @"wednesday_easter_egg", @"wicked_easter_egg_enabled",
                            @"world_cup_easter_egg"]) {
        flags[[@"ios-feature-nowplaying." stringByAppendingString:egg]] = @NO;
    }
    SGRedesignForceFlags(@"player", flags);
    if (!SGRedesignedUI()) return;
    %init;
    sg_coverWatcher = [SGRPlayerCoverWatcher new];
    SGAddPlayerStateObserver(sg_coverWatcher);
    [NSNotificationCenter.defaultCenter addObserverForName:SGRNowPlayingArtworkDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        showArtwork(sg_field, YES);
    }];
    SGRequireClasses(@[
        @"_TtC21NowPlaying_ScrollImpl27NPVBackgroundViewController",
        @"_TtC35NowPlaying_ContentLayerPlatformImpl24AccessibleCollectionView",
    ]);
}
