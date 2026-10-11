#import <UIKit/UIGestureRecognizerSubclass.h>
#import <objc/runtime.h>
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Lyrics/SGRKaraokeView.h"
#import "Redesigned/Lyrics/SGRSingControl.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/Sing/SGSingController.h"
#import "Player.h"

static const CGFloat kThumbSide = 72;          // the cover once the lyrics are up
static const CGFloat kThumbGap = 16;           // between the thumbnail and the title beside it
static const CGFloat kTitleGap = 12;           // between the title and the controls at the trailing edge
static const CGFloat kTitleFade = 20;          // over how much of its end a title too long to fit fades out
static const CGFloat kThumbTop = 8;            // below the top of the artwork band
static const CGFloat kLyricsTop = 20;          // between the title row and the first line
static const CGFloat kLyricsBottom = 8;        // above the progress bar
static const CGFloat kLyricsEnterScale = 0.96;
static const NSTimeInterval kLyricsIn = 0.3, kLyricsInDelay = 0.12, kLyricsOut = 0.16;
// A track that changes while the lines are up has this long to bring its own before they are put away.
static const NSTimeInterval kLyricsGrace = 3;
// Below this the player has not laid out yet and nothing can be measured from it.
static const CGFloat kLivingHeight = 200;
static const NSTimeInterval kAloneAfter = 4;
static const NSTimeInterval kAloneOut = 0.6, kAloneBack = 0.3;

static char kOverlayKey, kPlateKey, kTitleKey, kWatcherKey;
static BOOL sg_open;
static BOOL sg_moving;                      // the transition is in flight, so no layout pass may re-place it
static BOOL sg_forceLandscapeLyrics;
static BOOL sg_alone;                       // the controls are away and the lines have the player
static BOOL sg_tapBroughtBack;              // the touch going on began with them away, so its tap seeks nowhere
static NSTimer *sg_aloneTimer;
static BOOL sg_singHeld;                    // Sing's microphone is open, preparing or explaining itself
static __weak UIView *sg_sing;              // the microphone, when Sing is on
static __weak UIView *sg_host;              // SPTNowPlayingView
static __weak UIViewController *sg_player;  // its controller
static __weak UIViewController *sg_header, *sg_info, *sg_duration, *sg_floating;
static __weak UIView *sg_titleElement;      // the arranged element view holding the title and the artist
@class SGRLandscapeLyricsController;
static __weak SGRLandscapeLyricsController *sg_landscapeLyrics;
static void showLandscapeLyrics(UIViewController *player);
static void dismissLandscapeLyrics(void);
static void setOpen(BOOL open, BOOL animated);
static void installOrientationPolicy(id delegate);
static BOOL landscapeLyricsEnabled(void);

#pragma mark - the overlay

@interface SGRPlayerLyricsOverlay : UIView
@property (nonatomic, readonly) UIView *thumb;       // the cover, at full size, moved by its transform
@property (nonatomic, readonly) UIImageView *cover;
@property (nonatomic, readonly) UIView *stage;       // holds the lines' view alone
@property (nonatomic, readonly) UILabel *empty;      // Sing's "no lyrics"
@property (nonatomic, readonly) SGRKaraokeView *lyrics;
@end

static const void *kOriginalOrientationKey;

static BOOL landscapeLyricsEnabled(void) {
    return SGRedesignedUI() && (SGHidden(SGRKeyLandscapeLyrics) || sg_forceLandscapeLyrics) && sg_open && sg_player.viewIfLoaded.window;
}

static UIInterfaceOrientationMask orientationPolicy(id delegate, SEL command, UIApplication *application, UIWindow *window) {
    if (landscapeLyricsEnabled()) return UIInterfaceOrientationMaskAllButUpsideDown;
    NSValue *saved = objc_getAssociatedObject(object_getClass(delegate), &kOriginalOrientationKey);
    IMP original = saved.pointerValue;
    if (original) return ((UIInterfaceOrientationMask (*)(id, SEL, UIApplication *, UIWindow *))original)(delegate, command, application, window);
    return UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad
        ? UIInterfaceOrientationMaskAllButUpsideDown : UIInterfaceOrientationMaskPortrait;
}

static void installOrientationPolicy(id delegate) {
    if (!delegate) return;
    SEL selector = @selector(application:supportedInterfaceOrientationsForWindow:);
    Class cls = object_getClass(delegate);
    Method existing = class_getInstanceMethod(cls, selector);
    IMP previous = existing ? method_getImplementation(existing) : NULL;
    if (previous == (IMP)orientationPolicy) return;
    if (previous) objc_setAssociatedObject((id)cls, &kOriginalOrientationKey, [NSValue valueWithPointer:previous], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    class_replaceMethod(cls, selector, (IMP)orientationPolicy, existing ? method_getTypeEncoding(existing) : "Q@:@@");
}

static void requestLandscapeGeometry(BOOL landscape) {
    if (@available(iOS 16.0, *)) {
        for (UIScene *candidate in UIApplication.sharedApplication.connectedScenes) {
            if (![candidate isKindOfClass:UIWindowScene.class]) continue;
            UIWindowScene *scene = (UIWindowScene *)candidate;
            UIInterfaceOrientationMask mask = landscape ? UIInterfaceOrientationMaskLandscape : UIInterfaceOrientationMaskPortrait;
            UIWindowSceneGeometryPreferencesIOS *preferences = [[UIWindowSceneGeometryPreferencesIOS alloc] initWithInterfaceOrientations:mask];
            [scene requestGeometryUpdateWithPreferences:preferences errorHandler:^(NSError *error) {
                SGLog(@"redesign player: orientation request failed: %@", error.localizedDescription);
            }];
            [scene.keyWindow.rootViewController setNeedsUpdateOfSupportedInterfaceOrientations];
        }
    }
}

static void refreshOrientationPolicy(void) {
    if (@available(iOS 16.0, *)) {
        [sg_player setNeedsUpdateOfSupportedInterfaceOrientations];
        for (UIScene *candidate in UIApplication.sharedApplication.connectedScenes) {
            if (![candidate isKindOfClass:UIWindowScene.class]) continue;
            UIWindowScene *scene = (UIWindowScene *)candidate;
            [scene.keyWindow.rootViewController setNeedsUpdateOfSupportedInterfaceOrientations];
        }
    }
}

void SGRPlayerLyricsOrientationChanged(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        installOrientationPolicy(UIApplication.sharedApplication.delegate);
        BOOL enabled = landscapeLyricsEnabled();
        refreshOrientationPolicy();
        UIDeviceOrientation device = UIDevice.currentDevice.orientation;
        BOOL deviceLandscape = device == UIDeviceOrientationLandscapeLeft || device == UIDeviceOrientationLandscapeRight;
        for (UIScene *candidate in UIApplication.sharedApplication.connectedScenes) {
            if (![candidate isKindOfClass:UIWindowScene.class]) continue;
            UIInterfaceOrientation orientation = ((UIWindowScene *)candidate).interfaceOrientation;
            if (!enabled && UIInterfaceOrientationIsLandscape(orientation)) requestLandscapeGeometry(NO);
            else if (enabled && deviceLandscape && !UIInterfaceOrientationIsLandscape(orientation)) requestLandscapeGeometry(YES);
        }
    });
}

void SGRPlayerForceLandscapeLyrics(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!SGRedesignedUI() || !sg_player) return;
        sg_forceLandscapeLyrics = YES;
        if (!sg_open) setOpen(YES, NO);
        if (!sg_open || !landscapeLyricsEnabled()) {
            sg_forceLandscapeLyrics = NO;
            return;
        }
        installOrientationPolicy(UIApplication.sharedApplication.delegate);
        showLandscapeLyrics(sg_player);
        requestLandscapeGeometry(YES);
    });
}

%hook UIApplication
- (void)setDelegate:(id<UIApplicationDelegate>)delegate {
    %orig;
    installOrientationPolicy(delegate);
}
%end

@interface SGRLandscapeLyricsController : UIViewController
- (instancetype)initWithLyrics:(SGRKaraokeView *)lyrics;
@end

@implementation SGRLandscapeLyricsController {
    SGRArtworkField *_field;
    UIImageView *_cover;
    UILabel *_titleLabel, *_artistLabel, *_elapsedLabel, *_durationLabel;
    UIView *_lyricHost;
    UISlider *_progress;
    UIButton *_play, *_previous, *_next, *_close;
    SGRKaraokeView *_lyrics;
    NSTimer *_stateTimer;
    NSString *_shownArtwork;
    BOOL _previousIdleTimerDisabled, _holdsIdleTimer;
}

- (instancetype)initWithLyrics:(SGRKaraokeView *)lyrics {
    if (!(self = [super init])) return nil;
    _lyrics = lyrics;
    self.modalPresentationStyle = UIModalPresentationFullScreen;
    self.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    return self;
}

- (UIButton *)button:(NSString *)symbol label:(NSString *)label size:(CGFloat)size action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:size weight:UIImageSymbolWeightMedium];
    [button setImage:[UIImage systemImageNamed:symbol withConfiguration:configuration] forState:UIControlStateNormal];
    button.tintColor = UIColor.whiteColor;
    button.backgroundColor = UIColor.clearColor;
    button.accessibilityLabel = label;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [button addTarget:self action:@selector(interacted) forControlEvents:UIControlEventTouchDown];
    return button;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;
    self.view.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;

    _field = [[SGRArtworkField alloc] initWithFrame:self.view.bounds];
    _field.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _field.showsBackdrop = YES;
    _field.flows = SGEnabled(SGRKeyPlayerMotion);
    _field.motionHeld = SGPlayerState().isPaused;
    [_field setProvisionalColor:SGRPlayerField().fieldColor];
    [self.view addSubview:_field];

    _cover = [UIImageView new];
    _cover.contentMode = UIViewContentModeScaleAspectFill;
    _cover.clipsToBounds = YES;
    _cover.layer.cornerRadius = 12;
    [self.view addSubview:_cover];

    _titleLabel = [UILabel new];
    _titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle3];
    _titleLabel.textColor = UIColor.whiteColor;
    _titleLabel.adjustsFontForContentSizeCategory = YES;
    _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.view addSubview:_titleLabel];
    _artistLabel = [UILabel new];
    _artistLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    _artistLabel.textColor = [UIColor colorWithWhite:1 alpha:0.68];
    _artistLabel.adjustsFontForContentSizeCategory = YES;
    _artistLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.view addSubview:_artistLabel];

    _elapsedLabel = [UILabel new];
    _durationLabel = [UILabel new];
    for (UILabel *label in @[_elapsedLabel, _durationLabel]) {
        label.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightRegular];
        label.textColor = [UIColor colorWithWhite:1 alpha:0.62];
        [self.view addSubview:label];
    }
    _progress = [UISlider new];
    _progress.minimumTrackTintColor = UIColor.whiteColor;
    _progress.maximumTrackTintColor = [UIColor colorWithWhite:1 alpha:0.22];
    _progress.thumbTintColor = UIColor.clearColor;
    [_progress addTarget:self action:@selector(seek) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
    [self.view addSubview:_progress];

    _previous = [self button:@"backward.fill" label:@"Previous track" size:24 action:@selector(previous)];
    _play = [self button:@"pause.fill" label:@"Pause" size:30 action:@selector(playPause)];
    _next = [self button:@"forward.fill" label:@"Next track" size:24 action:@selector(next)];
    for (UIButton *button in @[_previous, _play, _next]) {
        [self.view addSubview:button];
    }
    _close = [self button:@"xmark" label:@"Close landscape lyrics" size:18 action:@selector(closeLyrics)];
    [self.view addSubview:_close];

    _lyricHost = [UIView new];
    _lyricHost.backgroundColor = UIColor.clearColor;
    [self.view addSubview:_lyricHost];
    if (!_lyrics) _lyrics = [[SGRKaraokeView alloc] initWithFrame:CGRectZero];
    _lyrics.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [_lyricHost addSubview:_lyrics];
    UITapGestureRecognizer *wake = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(interacted)];
    wake.cancelsTouchesInView = NO;
    [_cover addGestureRecognizer:wake];
    _cover.userInteractionEnabled = YES;
    [self refresh];
    _stateTimer = [NSTimer scheduledTimerWithTimeInterval:0.25 target:self selector:@selector(refresh) userInfo:nil repeats:YES];
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAllButUpsideDown;
}

- (BOOL)shouldAutorotate { return YES; }

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    return UIInterfaceOrientationLandscapeRight;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (_holdsIdleTimer) return;
    _previousIdleTimerDisabled = UIApplication.sharedApplication.idleTimerDisabled;
    _holdsIdleTimer = YES;
    UIApplication.sharedApplication.idleTimerDisabled = YES;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    _field.frame = self.view.bounds;
    CGRect safe = UIEdgeInsetsInsetRect(self.view.bounds, self.view.safeAreaInsets);
    if (safe.size.width <= safe.size.height) return;
    CGFloat gap = 24, leftWidth = floor((safe.size.width - gap) * 0.4);
    CGFloat rightX = CGRectGetMinX(safe) + leftWidth + gap;
    CGFloat rightWidth = CGRectGetMaxX(safe) - rightX;
    CGFloat coverSide = MIN(leftWidth - 36, safe.size.height * 0.48);
    CGFloat textHeight = 52, progressHeight = 34, controlsHeight = 58, spacing = 8;
    CGFloat contentHeight = coverSide + 14 + textHeight + spacing + progressHeight + spacing + controlsHeight;
    CGFloat top = CGRectGetMinY(safe) + MAX(0, (safe.size.height - contentHeight) / 2);
    CGFloat left = CGRectGetMinX(safe) + (leftWidth - coverSide) / 2;
    _cover.frame = CGRectMake(left, top, coverSide, coverSide);
    CGFloat textX = CGRectGetMinX(safe) + 14, textWidth = leftWidth - 28;
    CGFloat textY = CGRectGetMaxY(_cover.frame) + 12;
    _titleLabel.frame = CGRectMake(textX, textY, textWidth, 27);
    _artistLabel.frame = CGRectMake(textX, textY + 26, textWidth, 22);
    CGFloat rowY = textY + textHeight + spacing;
    _elapsedLabel.frame = CGRectMake(textX, rowY, 44, 18);
    _durationLabel.frame = CGRectMake(textX + textWidth - 44, rowY, 44, 18);
    _durationLabel.textAlignment = NSTextAlignmentRight;
    _progress.frame = CGRectMake(textX, rowY + 14, textWidth, 20);
    CGFloat buttonSide = 52, buttonGap = 28;
    CGFloat controlsWidth = buttonSide * 3 + buttonGap * 2;
    CGFloat controlsX = CGRectGetMinX(safe) + (leftWidth - controlsWidth) / 2;
    CGFloat controlsY = CGRectGetMaxY(_progress.frame) + 3;
    _previous.frame = CGRectMake(controlsX, controlsY, buttonSide, buttonSide);
    _play.frame = CGRectMake(controlsX + buttonSide + buttonGap, controlsY, buttonSide, buttonSide);
    _next.frame = CGRectMake(controlsX + (buttonSide + buttonGap) * 2, controlsY, buttonSide, buttonSide);
    _lyricHost.frame = CGRectMake(rightX, CGRectGetMinY(safe) + 12, rightWidth, safe.size.height - 24);
    _lyrics.frame = _lyricHost.bounds;
    [_lyrics setLineInsets:UIEdgeInsetsZero duration:0];
    _close.frame = CGRectMake(CGRectGetMaxX(safe) - 42, CGRectGetMinY(safe) + 2, 40, 40);
    [self.view bringSubviewToFront:_close];
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    if (size.width >= size.height) return;
    [coordinator animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        dismissLandscapeLyrics();
    }];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    if (_holdsIdleTimer) {
        UIApplication.sharedApplication.idleTimerDisabled = _previousIdleTimerDisabled;
        _holdsIdleTimer = NO;
    }
    [_stateTimer invalidate];
    _stateTimer = nil;
    if (sg_host) {
        SGRPlayerLyricsOverlay *overlay = objc_getAssociatedObject(sg_host, &kOverlayKey);
        if (overlay && _lyrics.superview != overlay.stage) [overlay.stage addSubview:_lyrics];
        if (overlay) _lyrics.frame = overlay.stage.bounds;
    }
    if (sg_landscapeLyrics == self) sg_landscapeLyrics = nil;
}

- (void)refresh {
    SPTPlayerState *state = SGPlayerState();
    if (!state) return;
    _field.motionHeld = state.isPaused;
    _titleLabel.text = state.track.trackTitle ?: @"";
    _artistLabel.text = state.track.artistName ?: @"";
    _durationLabel.text = [self timeText:state.duration];
    _elapsedLabel.text = [self timeText:state.position];
    _progress.maximumValue = (float)MAX(1, state.duration);
    if (!_progress.isTracking) _progress.value = (float)MAX(0, MIN(state.duration, state.position));
    NSString *symbol = state.isPaused ? @"play.fill" : @"pause.fill";
    [_play setImage:[UIImage systemImageNamed:symbol withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:30 weight:UIImageSymbolWeightMedium]] forState:UIControlStateNormal];
    _play.accessibilityLabel = state.isPaused ? @"Play" : @"Pause";
    NSString *identity = nil;
    UIImage *artwork = SGRNowPlayingArtwork(NULL, &identity);
    if (artwork && ![_shownArtwork isEqualToString:identity]) {
        _shownArtwork = [identity copy];
        _cover.image = artwork;
        [_field setArtwork:artwork identity:identity animated:YES];
    }
    if (state.isPaused) [self showControls:YES];
}

- (NSString *)timeText:(double)seconds {
    NSInteger value = MAX(0, (NSInteger)seconds);
    return [NSString stringWithFormat:@"%ld:%02ld", (long)(value / 60), (long)(value % 60)];
}

- (void)interacted {
    [self showControls:YES];
}

- (void)showControls:(BOOL)show {
    CGFloat alpha = show ? 1 : 0;
    _titleLabel.alpha = alpha;
    _artistLabel.alpha = alpha;
    _elapsedLabel.alpha = alpha;
    _durationLabel.alpha = alpha;
    _progress.alpha = alpha;
    for (UIView *view in @[_previous, _play, _next]) view.alpha = alpha;
    if (_close) _close.alpha = 1;
}

- (void)playPause {
    id player = SGKaraokePlayer();
    if (SGPlayerState().isPaused) [player resume:nil];
    else [player pause:nil];
    [self interacted];
}

- (void)previous {
    [SGKaraokePlayer() skipToPreviousTrackWithOptions:nil];
    [self interacted];
}

- (void)next {
    [SGKaraokePlayer() skipToNextTrackWithOptions:nil];
    [self interacted];
}

- (void)seek {
    SGKaraokeSeek((NSInteger)round(_progress.value * 1000));
    [self interacted];
}

- (void)closeLyrics { SGRPlayerToggleLyrics(); }
@end

static void showLandscapeLyrics(UIViewController *player) {
    if (!landscapeLyricsEnabled() || !player || player.presentedViewController || sg_landscapeLyrics) return;
    SGRPlayerLyricsOverlay *overlay = objc_getAssociatedObject(sg_host, &kOverlayKey);
    SGRLandscapeLyricsController *controller = [[SGRLandscapeLyricsController alloc] initWithLyrics:overlay.lyrics];
    sg_landscapeLyrics = controller;
    [player presentViewController:controller animated:NO completion:nil];
}

static void dismissLandscapeLyrics(void) {
    SGRLandscapeLyricsController *controller = sg_landscapeLyrics;
    if (!controller) return;
    if (!controller.presentingViewController) {
        if (sg_landscapeLyrics == controller) sg_landscapeLyrics = nil;
        return;
    }
    if (controller.isBeingDismissed) return;
    [controller dismissViewControllerAnimated:NO completion:^{
        if (sg_landscapeLyrics == controller) sg_landscapeLyrics = nil;
    }];
}

@implementation SGRPlayerLyricsOverlay {
    UIView *_thumb, *_stage;
    UIImageView *_cover;
    UILabel *_empty;
    SGRKaraokeView *_lyrics;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _thumb = [[UIView alloc] initWithFrame:CGRectZero];
    _thumb.userInteractionEnabled = NO;
    _cover = [[UIImageView alloc] initWithFrame:CGRectZero];
    _cover.contentMode = UIViewContentModeScaleAspectFill;
    _cover.clipsToBounds = YES;
    _cover.layer.cornerCurve = kCACornerCurveContinuous;
    _cover.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [_thumb addSubview:_cover];
    _stage = [[UIView alloc] initWithFrame:CGRectZero];
    _empty = [UILabel new];
    _empty.text = @"Lyrics aren't available for this song.";
    _empty.textColor = SGRSecondary();
    _empty.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    _empty.adjustsFontForContentSizeCategory = YES;
    _empty.textAlignment = NSTextAlignmentCenter;
    _empty.numberOfLines = 0;
    [_stage addSubview:_empty];
    [self addSubview:_stage];
    [self addSubview:_thumb];
    return self;
}

- (UIView *)thumb { return _thumb; }
- (UIImageView *)cover { return _cover; }
- (UIView *)stage { return _stage; }
- (UILabel *)empty { return _empty; }

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit != self && hit != _stage) return hit;
    UIView *row = SGRPlayerLyricsOpen() && !sg_alone ? sg_info.viewIfLoaded : nil;
    UIView *inRow = row ? [row hitTest:[row convertPoint:point fromView:self] withEvent:event] : nil;
    return inRow == row ? nil : inRow;
}

- (SGRKaraokeView *)lyrics {
    if (!_lyrics) {
        _lyrics = [[SGRKaraokeView alloc] initWithFrame:_stage.bounds];
        _lyrics.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _lyrics.takesTap = ^BOOL { return !sg_tapBroughtBack; };
    }
    if (_lyrics.superview != _stage && sg_landscapeLyrics) return _lyrics;
    if (_lyrics.superview != _stage) [_stage addSubview:_lyrics];
    _lyrics.frame = _stage.bounds;
    return _lyrics;
}

@end

static SGRPlayerLyricsOverlay *overlayIn(UIView *host) {
    SGRPlayerLyricsOverlay *overlay = objc_getAssociatedObject(host, &kOverlayKey);
    if (!overlay) {
        overlay = [[SGRPlayerLyricsOverlay alloc] initWithFrame:host.bounds];
        objc_setAssociatedObject(host, &kOverlayKey, overlay, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (overlay.superview != host) [host addSubview:overlay];
    return overlay;
}

#pragma mark - the measurements

typedef struct {
    BOOL ok;
    CGRect cover;     // where Spotify draws the cover now, in the player
    CGRect thumb;     // where it goes
    CGRect stage;     // where the lines go
    CGRect room;      // where they go with the controls away, which is the stage's frame throughout
    CGFloat lift;     // how far the title row rises
    CGFloat shift;    // how far the title slides right to clear the thumbnail, 0 when it sits under it
} SGRLyricsLayout;

// What a view's frame would be with the translation this file put on it left out.
static CGRect untransformed(UIView *view, UIView *host) {
    CGRect frame = SGFrameIn(view, host);
    CGAffineTransform t = view.transform;
    return CGRectOffset(frame, -t.tx, -t.ty);
}

static SGRLyricsLayout layoutIn(UIView *host) {
    SGRLyricsLayout l = {0};
    UIView *info = sg_info.viewIfLoaded, *duration = sg_duration.viewIfLoaded, *title = sg_titleElement;
    if (!host || host.bounds.size.height < kLivingHeight || !info || !duration) return l;
    CGRect area = SGRPlayerArtworkAreaIn(host), cover = SGRPlayerCoverFrameIn(host);
    if (CGRectIsNull(area) || CGRectIsNull(cover)) return l;
    CGRect row = untransformed(info, host), bar = untransformed(duration, host);
    // The thumbnail takes the title's own leading edge, so the two line up down the page.
    CGFloat leading = title ? CGRectGetMinX(untransformed(title, host)) : CGRectGetMinX(area) + SGRSideMargin;
    l.cover = cover;
    l.thumb = CGRectMake(leading, CGRectGetMinY(area) + kThumbTop, kThumbSide, kThumbSide);
    // Beside the thumbnail when the title can be moved clear of it, under it when it cannot be found.
    CGFloat top = title ? CGRectGetMidY(l.thumb) - row.size.height / 2 : CGRectGetMaxY(l.thumb) + SGRGrid;
    l.lift = top - CGRectGetMinY(row);
    l.shift = title ? kThumbSide + kThumbGap : 0;
    CGFloat lines = MAX(CGRectGetMaxY(l.thumb), top + row.size.height) + kLyricsTop;
    l.stage = CGRectMake(CGRectGetMinX(area), lines, area.size.width, CGRectGetMinY(bar) - kLyricsBottom - lines);
    UIView *header = sg_header.viewIfLoaded;
    UIEdgeInsets safe = host.window.safeAreaInsets;
    CGFloat roomTop = MIN(header ? CGRectGetMinY(SGFrameIn(header, host)) : safe.top, CGRectGetMinY(l.stage));
    CGFloat roomBottom = MAX(host.bounds.size.height - safe.bottom, CGRectGetMaxY(l.stage));
    l.room = CGRectMake(CGRectGetMinX(area), roomTop, area.size.width, roomBottom - roomTop);
    l.ok = l.stage.size.height > kLivingHeight / 2 && l.lift < 0;
    return l;
}

static UIEdgeInsets bandOf(SGRLyricsLayout l, BOOL alone) {
    if (alone) return UIEdgeInsetsZero;
    return UIEdgeInsetsMake(CGRectGetMinY(l.stage) - CGRectGetMinY(l.room), 0, CGRectGetMaxY(l.room) - CGRectGetMaxY(l.stage), 0);
}

#pragma mark - the title row

static CGFloat trailingEdgeIn(UIView *info) {
    UIView *title = sg_titleElement, *row = title.superview;
    if (!title || !row) return CGFLOAT_MAX;
    CGFloat titleLeft = CGRectGetMinX(untransformed(title, info));
    CGFloat limit = CGRectGetMaxX(SGFrameIn(row, info));
    for (UIView *view in row.subviews) {
        if (view == title || view.hidden || view.alpha < 0.01 || view.bounds.size.width < 1) continue;
        CGFloat x = CGRectGetMinX(SGFrameIn(view, info));
        if (x > titleLeft && x < limit) limit = x;
    }
    return limit;
}

static void clipTitle(UIView *element, CGFloat width) {
    CGRect bounds = element.bounds;
    if (width >= bounds.size.width - 0.5 || bounds.size.height < 1) {
        element.layer.mask = nil;
        return;
    }
    CAGradientLayer *mask = [element.layer.mask isKindOfClass:CAGradientLayer.class] ? (CAGradientLayer *)element.layer.mask : nil;
    if (!mask) {
        mask = [CAGradientLayer layer];
        mask.colors = @[(id)UIColor.whiteColor.CGColor, (id)UIColor.whiteColor.CGColor, (id)UIColor.clearColor.CGColor];
        mask.startPoint = CGPointMake(0, 0.5);
        mask.endPoint = CGPointMake(1, 0.5);
        element.layer.mask = mask;
    }
    CGFloat fade = MIN(kTitleFade, width);
    CGRect frame = CGRectMake(0, 0, MAX(0, width), bounds.size.height);
    if (CGRectEqualToRect(frame, mask.frame)) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    mask.frame = frame;
    mask.locations = @[@0, @(width > 0 ? (width - fade) / width : 0), @1];
    [CATransaction commit];
}

// The unit's row lays its arranged views out after the unit's own pass, so the transforms go on after it.
static void placeTitleRow(SGRLyricsLayout l) {
    UIView *info = sg_info.viewIfLoaded;
    if (!info) return;
    [SGRowIn(info) layoutIfNeeded];
    CGFloat lift = sg_open ? l.lift : 0, shift = sg_open ? l.shift : 0;
    CGAffineTransform rise = CGAffineTransformMakeTranslation(0, round(lift));
    if (!CGAffineTransformEqualToTransform(info.transform, rise)) info.transform = rise;
    UIView *title = sg_titleElement;
    if (!title) return;
    CGAffineTransform slide = CGAffineTransformMakeTranslation(round(shift), 0);
    if (!CGAffineTransformEqualToTransform(title.transform, slide)) title.transform = slide;
    // Closed it reaches as far as Spotify meant it to; moved, only as far as the controls it moved towards.
    CGFloat room = CGFLOAT_MAX;
    if (sg_open) room = trailingEdgeIn(info) - kTitleGap - (CGRectGetMinX(untransformed(title, info)) + shift);
    clipTitle(title, room);
}

#pragma mark - the lines alone

static void showControls(CGFloat alpha, SGRPlayerLyricsOverlay *overlay) {
    sg_header.viewIfLoaded.alpha = alpha;
    UIView *stack = sg_info.viewIfLoaded.superview;
    if ([stack isKindOfClass:UIStackView.class]) stack.alpha = alpha;
    overlay.thumb.alpha = alpha;
}

static void stopAloneTimer(void) {
    [sg_aloneTimer invalidate];
    sg_aloneTimer = nil;
}

static void scheduleAlone(void);

static void placeSing(SGRPlayerLyricsOverlay *overlay, SGRLyricsLayout l) {
    CGRect band = [overlay convertRect:sg_alone ? l.room : l.stage fromView:sg_host];
    sg_sing = SGRSingControlForPage(overlay, band, sg_alone, ^(BOOL held) {
        sg_singHeld = held;
        if (held) stopAloneTimer();
        else scheduleAlone();
    });
}

static void setAlone(BOOL alone, BOOL animated) {
    if (alone == sg_alone) return;
    UIView *host = sg_host;
    SGRPlayerLyricsOverlay *overlay = host ? objc_getAssociatedObject(host, &kOverlayKey) : nil;
    SGRLyricsLayout l = layoutIn(host);
    if (alone && (!l.ok || !overlay.superview)) return;
    sg_alone = alone;
    stopAloneTimer();
    NSTimeInterval duration = animated ? (alone ? kAloneOut : kAloneBack) : 0;
    // Without a measurement the band is put back by the next layout pass (replace).
    if (l.ok && overlay.superview) [overlay.lyrics setLineInsets:bandOf(l, alone) duration:duration];
    void (^fade)(void) = ^{
        showControls(alone ? 0 : 1, overlay);
        if (l.ok && overlay.superview) {
            placeSing(overlay, l);
            [sg_sing layoutIfNeeded];
        }
    };
    if (duration > 0) {
        [UIView animateWithDuration:duration delay:0
                            options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                         animations:fade completion:nil];
    } else {
        fade();
    }
    SGLog(@"redesign player: the controls %@, the lines from %.0f to %.0f", alone ? @"away" : @"back",
          alone ? CGRectGetMinY(l.room) : CGRectGetMinY(l.stage), alone ? CGRectGetMaxY(l.room) : CGRectGetMaxY(l.stage));
}

static BOOL mayGoAlone(void) {
    UIView *host = sg_host;
    SGRPlayerLyricsOverlay *overlay = host ? objc_getAssociatedObject(host, &kOverlayKey) : nil;
    if (!sg_open || sg_moving || sg_singHeld || !host.window || !overlay.superview || overlay.lyrics.hidden) return NO;
    SPTPlayerState *state = SGPlayerState();
    if (!state || state.isPaused) return NO;
    // A sheet the player opens (the queue, the devices, the menu) is presented by its topmost controller.
    UIViewController *top = sg_player;
    while (top.parentViewController) top = top.parentViewController;
    if (top.presentedViewController) return NO;
    return !SGRPlayerIsTransitioning() && !UIAccessibilityIsVoiceOverRunning()
        && UIApplication.sharedApplication.applicationState == UIApplicationStateActive;
}

static void scheduleAlone(void) {
    stopAloneTimer();
    if (!sg_open || sg_alone) return;
    sg_aloneTimer = [NSTimer scheduledTimerWithTimeInterval:kAloneAfter repeats:NO block:^(NSTimer *timer) {
        sg_aloneTimer = nil;
        if (mayGoAlone()) setAlone(YES, YES);
        else if (sg_open && !SGPlayerState().isPaused && UIApplication.sharedApplication.applicationState == UIApplicationStateActive) scheduleAlone();
    }];
}

// A touch has begun somewhere on the player, on `view`.
static void touched(UIView *view) {
    if (sg_alone && sg_sing && [view isDescendantOfView:sg_sing]) {
        sg_tapBroughtBack = NO;
        return;
    }
    sg_tapBroughtBack = sg_alone;
    if (sg_alone) setAlone(NO, YES);
    scheduleAlone();
}

@interface SGRPlayerTouchWatcher : UIGestureRecognizer
@end

@implementation SGRPlayerTouchWatcher

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesBegan:touches withEvent:event];
    touched(touches.anyObject.view);
    self.state = UIGestureRecognizerStateFailed;
}

- (BOOL)canPreventGestureRecognizer:(UIGestureRecognizer *)other { return NO; }
- (BOOL)canBePreventedByGestureRecognizer:(UIGestureRecognizer *)other { return NO; }

@end

static void watchTouches(UIView *host) {
    if (objc_getAssociatedObject(host, &kWatcherKey)) return;
    SGRPlayerTouchWatcher *watcher = [[SGRPlayerTouchWatcher alloc] initWithTarget:nil action:NULL];
    watcher.cancelsTouchesInView = NO;
    watcher.delaysTouchesEnded = NO;
    [host addGestureRecognizer:watcher];
    objc_setAssociatedObject(host, &kWatcherKey, watcher, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

#pragma mark - opening and closing

BOOL SGRPlayerLyricsAvailable(void) {
    NSString *track = SGKaraokePlayingTrack();
    return track != nil && (SGKaraokeLinesForTrack(track) != nil || SGSingAvailable());
}

BOOL SGRPlayerLyricsOpen(void) {
    return sg_open;
}

static void place(SGRPlayerLyricsOverlay *overlay, UIView *host, SGRLyricsLayout l) {
    overlay.frame = CGRectUnion(l.cover, CGRectUnion(l.thumb, l.room));
    CGRect cover = [overlay convertRect:l.cover fromView:host], stage = [overlay convertRect:l.room fromView:host];
    overlay.thumb.bounds = (CGRect){CGPointZero, cover.size};
    overlay.thumb.center = CGPointMake(CGRectGetMidX(cover), CGRectGetMidY(cover));
    overlay.cover.frame = overlay.thumb.bounds;
    SGRShadowPlate *plate = SGRShadowPlateIn(overlay.thumb, &kPlateKey);
    plate.bounds = overlay.thumb.bounds;
    plate.center = CGPointMake(CGRectGetMidX(overlay.thumb.bounds), CGRectGetMidY(overlay.thumb.bounds));
    overlay.stage.bounds = (CGRect){CGPointZero, stage.size};
    overlay.stage.center = CGPointMake(CGRectGetMidX(stage), CGRectGetMidY(stage));
    overlay.empty.frame = UIEdgeInsetsInsetRect(overlay.stage.bounds, bandOf(l, NO));
}

static CGAffineTransform thumbTransform(SGRLyricsLayout l) {
    CGFloat scale = l.cover.size.width > 0 ? l.thumb.size.width / l.cover.size.width : 1;
    CGAffineTransform move = CGAffineTransformMakeTranslation(round(CGRectGetMidX(l.thumb) - CGRectGetMidX(l.cover)),
                                                             round(CGRectGetMidY(l.thumb) - CGRectGetMidY(l.cover)));
    return CGAffineTransformConcat(CGAffineTransformMakeScale(scale, scale), move);
}

static CGFloat thumbRadius(SGRLyricsLayout l, BOOL open) {
    if (!open) return SGRRadiusArtwork;
    CGFloat scale = l.cover.size.width > 0 ? l.thumb.size.width / l.cover.size.width : 1;
    return scale > 0 ? SGRRadiusCover / scale : SGRRadiusArtwork;
}

static void setOpen(BOOL open, BOOL animated) {
    UIView *host = sg_host;
    if (open == sg_open) return;
    if (!host) {
        SGLog(@"redesign player: the lyrics were asked for before the player laid out");
        return;
    }
    SGRLyricsLayout l = layoutIn(host);
    if (open && !l.ok) {
        SGLog(@"redesign player: the lyrics have nowhere to go (stage %.0fx%.0f, lift %.0f)", l.stage.size.width, l.stage.size.height, l.lift);
        return;
    }
    UIImage *picture = SGRNowPlayingArtwork(NULL, NULL);
    if (open && !picture) {
        SGLog(@"redesign player: no artwork read yet, the lyrics stay down");
        return;
    }
    // The controls come back first: the thumbnail flying back to the cover is one of them.
    if (!open) {
        sg_forceLandscapeLyrics = NO;
        setAlone(NO, animated);
        stopAloneTimer();
        dismissLandscapeLyrics();
    }
    sg_open = open;
    SGRPlayerLyricsOrientationChanged();
    SGRPlayerLyricsChanged();

    SGRPlayerLyricsOverlay *overlay = overlayIn(host);
    if (!open) SGRSingControlDismiss(overlay);
    place(overlay, host, l);
    CGAffineTransform away = thumbTransform(l);
    // The state it starts from, so the animation has both ends of every value and nothing jumps into it.
    overlay.thumb.transform = open ? CGAffineTransformIdentity : away;
    overlay.cover.layer.cornerRadius = thumbRadius(l, !open);
    if (open) {
        overlay.cover.image = SGRNowPlayingArtwork(NULL, NULL);
        overlay.stage.alpha = 0;
        overlay.stage.transform = CGAffineTransformMakeScale(kLyricsEnterScale, kLyricsEnterScale);
        [overlay.lyrics setLineInsets:bandOf(l, NO) duration:0];
        placeSing(overlay, l);
        sg_sing.alpha = 0;
        SGRPlayerCoverList().alpha = 0;
    }

    void (^move)(void) = ^{
        overlay.thumb.transform = open ? away : CGAffineTransformIdentity;
        overlay.cover.layer.cornerRadius = thumbRadius(l, open);
        placeTitleRow(l);
        sg_floating.viewIfLoaded.alpha = open ? 0 : 1;
    };
    void (^show)(void) = ^{
        overlay.stage.alpha = open ? 1 : 0;
        overlay.stage.transform = open ? CGAffineTransformIdentity
                                       : CGAffineTransformMakeScale(kLyricsEnterScale, kLyricsEnterScale);
        sg_sing.alpha = open ? 1 : 0;
    };
    void (^settled)(BOOL) = ^(BOOL finished) {
        sg_moving = NO;
        if (sg_open) return;   // opened again while it was going away
        SGRPlayerCoverList().alpha = 1;
        [overlay removeFromSuperview];
    };

    if (!animated) {
        move();
        show();
        settled(YES);
    } else {
        sg_moving = YES;
        SGRAnimate(SGRMotionLayout, move, settled);
        // The lines come in behind the cover leaving, and go before it comes back.
        [UIView animateWithDuration:open ? kLyricsIn : kLyricsOut delay:open ? kLyricsInDelay : 0
                            options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState
                         animations:show completion:nil];
    }
    if (open) {
        scheduleAlone();
        if (host.bounds.size.width > host.bounds.size.height) showLandscapeLyrics(sg_player);
    }
    SGLog(@"redesign player: lyrics %@, thumbnail %.0fx%.0f at %.0f,%.0f, title row up %.0f and right %.0f, lines %.0fx%.0f",
          open ? @"up" : @"away", l.thumb.size.width, l.thumb.size.height, l.thumb.origin.x, l.thumb.origin.y,
          -l.lift, l.shift, l.stage.size.width, l.stage.size.height);
}

void SGRPlayerToggleLyrics(void) {
    if (!sg_open && !SGRPlayerLyricsAvailable()) return;
    setOpen(!sg_open, YES);
}

static void replace(void) {
    UIView *host = sg_host;
    if (!host || sg_moving) return;   // a pass in the middle of the transition would cut it short
    SGRLyricsLayout l = layoutIn(host);
    if (sg_open && !l.ok) return;
    placeTitleRow(l);
    sg_floating.viewIfLoaded.alpha = sg_open ? 0 : 1;
    if (!sg_open) return;
    SGRPlayerLyricsOverlay *overlay = objc_getAssociatedObject(host, &kOverlayKey);
    if (!overlay.superview) return;
    place(overlay, host, l);
    overlay.thumb.transform = thumbTransform(l);
    overlay.cover.layer.cornerRadius = thumbRadius(l, YES);
    if (overlay.lyrics.superview == overlay.stage) overlay.lyrics.frame = overlay.stage.bounds;
    [overlay.lyrics setLineInsets:bandOf(l, sg_alone) duration:0];
    if (sg_alone) showControls(0, overlay);
    placeSing(overlay, l);
    SGRPlayerCoverList().alpha = 0;
}

#pragma mark - the units

%hook _TtC19NowPlaying_ViewImpl24NowPlayingViewController
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    if (landscapeLyricsEnabled()) return UIInterfaceOrientationMaskAllButUpsideDown;
    return %orig;
}

- (BOOL)shouldAutorotate {
    if (landscapeLyricsEnabled()) return YES;
    return %orig;
}

- (void)viewDidLayoutSubviews {
    %orig;
    UIView *host = ((UIViewController *)self).viewIfLoaded;
    if (!host || host.bounds.size.height < kLivingHeight) return;
    if (sg_host != host) {
        sg_host = host;
        SGLog(@"redesign player: the lyrics have the player's view %.0fx%.0f", host.bounds.size.width, host.bounds.size.height);
    }
    sg_player = (UIViewController *)self;
    watchTouches(host);
    replace();
    if (landscapeLyricsEnabled() && host.bounds.size.width > host.bounds.size.height) showLandscapeLyrics((UIViewController *)self);
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    %orig;
    BOOL landscape = size.width > size.height;
    [coordinator animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        if (landscape && landscapeLyricsEnabled()) showLandscapeLyrics((UIViewController *)self);
        else if (!landscape) dismissLandscapeLyrics();
    }];
}

// The bar morphs back out of a full size cover as the player closes, so the thumbnail is put away first.
- (void)viewWillDisappear:(BOOL)animated {
    BOOL showingLandscape = sg_landscapeLyrics && landscapeLyricsEnabled();
    if (sg_open && !showingLandscape) setOpen(NO, NO);
    %orig;
}
%end

// The header row goes with the rest of the controls while the lines are alone.
%hook _TtC20NowPlaying_ModesImpl18HeaderElementsUnit
- (void)viewDidLayoutSubviews {
    %orig;
    sg_header = (UIViewController *)self;
    if (sg_alone) sg_header.viewIfLoaded.alpha = 0;
}
%end

%hook _TtC20NowPlaying_ModesImpl23InformationElementsUnit
- (void)viewDidLayoutSubviews {
    %orig;
    UIViewController *unit = (UIViewController *)self;
    sg_info = unit;
    UIView *host = unit.viewIfLoaded;
    // The title and the artist are two labels of one arranged element view, which is what moves.
    UIView *label = SGRFindByIdentifier(host, @"now-playing-title-label", &kTitleKey);
    UIView *element = nil;
    for (UIView *v = label; v && v != host; v = v.superview) {
        if ([v.superview isKindOfClass:UIStackView.class]) { element = v; break; }
    }
    if (element && sg_titleElement != element) {
        sg_titleElement = element;
        static dispatch_once_t once;
        dispatch_once(&once, ^{ SGLog(@"redesign player: the title rides on %@ %@", NSStringFromClass(element.class), NSStringFromCGRect(element.frame)); });
    }
    replace();
}
%end

%hook _TtC20NowPlaying_ModesImpl19DurationElementUnit
- (void)viewDidLayoutSubviews {
    %orig;
    sg_duration = (UIViewController *)self;
    replace();
}
%end

%hook _TtC20NowPlaying_ModesImpl20FloatingElementsUnit
- (void)viewDidLayoutSubviews {
    %orig;
    sg_floating = (UIViewController *)self;
    replace();
}
%end

#pragma mark - the track changing under them

static void awaitLyrics(void) {
    for (NSNumber *delay in @[@1, @(kLyricsGrace)]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
            SGRPlayerLyricsChanged();
            if (sg_open && delay.doubleValue >= kLyricsGrace && !SGRPlayerLyricsAvailable()) {
                SGLog(@"redesign player: no lyrics for the track that came on, the cover is back");
                setOpen(NO, YES);
            }
        });
    }
}

static void singAvailabilityChanged(void) {
    static BOOL available;
    if (SGSingAvailable() == available) return;
    available = !available;
    SGRPlayerLyricsChanged();
    if (!sg_open) return;
    if (!SGRPlayerLyricsAvailable()) setOpen(NO, YES);
    else replace();
}

@interface SGRPlayerLyricsWatcher : NSObject <SGPlayerStateObserver>
@end

@implementation SGRPlayerLyricsWatcher {
    NSString *_track;
    BOOL _paused;
}

- (void)playerStateDidChange:(SPTPlayerState *)state {
    // Paused, the controls come back for the play button and stay; playing again, the wait starts over.
    if (state.isPaused != _paused) {
        _paused = state.isPaused;
        if (_paused) {
            setAlone(NO, YES);
            stopAloneTimer();
        } else {
            scheduleAlone();
        }
    }
    NSString *track = SGURIString(state.track.URI);
    if (!track || [track isEqualToString:_track]) return;
    _track = track;
    awaitLyrics();
}

@end

static SGRPlayerLyricsWatcher *sg_watcher;

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    installOrientationPolicy(UIApplication.sharedApplication.delegate);
    sg_watcher = [SGRPlayerLyricsWatcher new];
    SGAddPlayerStateObserver(sg_watcher);
    [NSNotificationCenter.defaultCenter addObserverForName:SGKaraokeLinesDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        SGRPlayerLyricsChanged();
    }];
    [NSNotificationCenter.defaultCenter addObserverForName:SGSingDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        singAvailabilityChanged();
    }];
    [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil
                                                     queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        // Spotify's own request may have been answered with nothing while the app was away.
        SGKaraokeRequestLyrics(SGKaraokePlayingTrack());
        SGRPlayerLyricsChanged();
        awaitLyrics();
    }];
    [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil
                                                     queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        if (!sg_aloneTimer) scheduleAlone();   // the wait gave up while the app was away
    }];
    [NSNotificationCenter.defaultCenter addObserverForName:SGRNowPlayingArtworkDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        if (!sg_open) return;
        SGRPlayerLyricsOverlay *overlay = objc_getAssociatedObject(sg_host, &kOverlayKey);
        overlay.cover.image = SGRNowPlayingArtwork(NULL, NULL);
    }];
    SGRequireClasses(@[
        @"_TtC19NowPlaying_ViewImpl24NowPlayingViewController",
        @"_TtC20NowPlaying_ModesImpl18HeaderElementsUnit",
        @"_TtC20NowPlaying_ModesImpl23InformationElementsUnit",
        @"_TtC20NowPlaying_ModesImpl19DurationElementUnit",
        @"_TtC20NowPlaying_ModesImpl20FloatingElementsUnit",
    ]);
}
