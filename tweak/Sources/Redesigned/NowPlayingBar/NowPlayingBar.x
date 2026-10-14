#import "Core/SGCore.h"
#import "Redesigned/Navbar/Navbar.h"
#import "Redesigned/Kit/SGRRepaint.h"
#import "NowPlayingBar.h"

static const CGFloat kCardRadius = 24;
static char kGlassKey;
static __weak UIVisualEffectView *sg_cardGlass;
static __weak UIView *sg_cardArtwork;
static __weak UIViewController *sg_barContainer;
static __weak UIView *sg_inlineBar;
static NSMapTable<NSLayoutConstraint *, NSNumber *> *sg_savedEdgeConstants;
static CGRect sg_fullBarFrame, sg_narrowBarFrame;

CGRect SGRNowPlayingCardFrameIn(UIView *host, CGFloat *radius) {
    UIVisualEffectView *glass = sg_cardGlass;
    if (!glass.superview || !glass.window || !host) return CGRectNull;
    if (radius) *radius = MIN(kCardRadius, glass.bounds.size.height / 2);
    return [host convertRect:glass.bounds fromView:glass];
}

CGRect SGRNowPlayingArtworkFrameIn(UIView *host) {
    UIView *artwork = sg_cardArtwork;
    if (!artwork.window || !host) return CGRectNull;
    return [host convertRect:artwork.bounds fromView:artwork];
}

static UIView *detectColoredCard(UIView *bar) {
    __block UIView *best = nil;
    __block CGFloat bestArea = 0;
    SGForEachView(bar, ^(UIView *v) {
        if ([v isKindOfClass:UIVisualEffectView.class] || SGKeepsColor(v) || !SGLooksLikeCard(v, v.layer.backgroundColor)) return;
        CGFloat area = v.bounds.size.width * v.bounds.size.height;
        if (area > bestArea) { bestArea = area; best = v; }
    });
    return best;
}

// Fallback when nothing is painted: the box around artwork, text and the small buttons.
static CGRect contentBounds(UIView *bar, UIView *target) {
    __block CGRect box = CGRectNull;
    SGForEachView(bar, ^(UIView *v) {
        if (v.hidden || v.alpha == 0) return;
        CGFloat width = v.bounds.size.width;
        BOOL content = ([v isKindOfClass:UIImageView.class] && width >= 20 && width <= 120)
            || [v isKindOfClass:UILabel.class]
            || ([v isKindOfClass:UIControl.class] && width <= 100);
        if (content) box = CGRectUnion(box, SGFrameIn(v, target));
    });
    return CGRectIsNull(box) ? box : CGRectInset(box, -10, -8);
}

static void roundView(UIView *view, CGFloat radius) {
    view.layer.cornerRadius = radius;
    view.layer.cornerCurve = kCACornerCurveContinuous;
}

static void restoreBarEdges(UIView *bar) {
    for (NSLayoutConstraint *constraint in sg_savedEdgeConstants)
        constraint.constant = [[sg_savedEdgeConstants objectForKey:constraint] doubleValue];
    [sg_savedEdgeConstants removeAllObjects];
    if (bar.translatesAutoresizingMaskIntoConstraints && CGRectEqualToRect(bar.frame, sg_narrowBarFrame))
        bar.frame = sg_fullBarFrame;
    sg_narrowBarFrame = CGRectNull;
}

static BOOL setBarEdges(UIView *bar, CGFloat left, CGFloat right) {
    UIView *superview = bar.superview;
    if (bar.translatesAutoresizingMaskIntoConstraints) {
        CGRect frame = CGRectMake(left, bar.frame.origin.y, right - left, bar.frame.size.height);
        if (!CGRectEqualToRect(bar.frame, sg_narrowBarFrame)) sg_fullBarFrame = bar.frame;
        sg_narrowBarFrame = frame;
        if (!CGRectEqualToRect(bar.frame, frame)) bar.frame = frame;
        return YES;
    }
    if (superview.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft) return NO;
    if (!sg_savedEdgeConstants) sg_savedEdgeConstants = [NSMapTable weakToStrongObjectsMapTable];
    NSUInteger held = 0;
    for (NSLayoutConstraint *constraint in superview.constraints) {
        NSLayoutAttribute attribute = constraint.firstAttribute;
        BOOL barFirst = constraint.firstItem == bar && constraint.secondItem == superview;
        if (!constraint.active || constraint.relation != NSLayoutRelationEqual || constraint.multiplier != 1
            || attribute != constraint.secondAttribute || (!barFirst && !(constraint.secondItem == bar && constraint.firstItem == superview))) continue;
        BOOL isLeft = attribute == NSLayoutAttributeLeading || attribute == NSLayoutAttributeLeft;
        if (!isLeft && attribute != NSLayoutAttributeTrailing && attribute != NSLayoutAttributeRight) continue;
        if (![sg_savedEdgeConstants objectForKey:constraint])
            [sg_savedEdgeConstants setObject:@(constraint.constant) forKey:constraint];
        CGFloat edge = isLeft ? 0 : superview.bounds.size.width;
        CGFloat value = isLeft ? left : right;
        constraint.constant = barFirst ? value - edge : edge - value;
        held |= isLeft ? 1 : 2;
    }
    if (held == 3) return YES;
    restoreBarEdges(bar);
    return NO;
}

static void placeInlineBar(UIViewController *container) {
    UIView *view = container.view;
    UIView *bar = container.childViewControllers.firstObject.viewIfLoaded;
    CGRect slot = !bar || bar.superview != view
        ? CGRectNull : SGRTabBarInlineSlot(view.superview, bar.bounds.size.height);
    CGPoint origin = CGPointMake(view.center.x - view.bounds.size.width / 2,
                                 view.center.y - view.bounds.size.height / 2);
    if (CGRectIsNull(slot) || !setBarEdges(bar, CGRectGetMinX(slot) - origin.x, CGRectGetMaxX(slot) - origin.x)) {
        if (sg_inlineBar) restoreBarEdges(bar);
        sg_inlineBar = nil;
        if (!CGAffineTransformIsIdentity(view.transform)) view.transform = CGAffineTransformIdentity;
        return;
    }
    CGAffineTransform transform = CGAffineTransformMakeTranslation(
        0, CGRectGetMidY(slot) - origin.y - CGRectGetMidY(bar.frame));
    if (!CGAffineTransformEqualToTransform(view.transform, transform)) view.transform = transform;
    sg_inlineBar = view;
}

void SGRNowPlayingBarFollowTabBar(void) {
    UIViewController *container = sg_barContainer;
    if (!container.isViewLoaded) return;
    placeInlineBar(container);
    [container.view setNeedsLayout];
    [container.view layoutIfNeeded];
}

static void restyleCardContent(UIView *card) {
    SGForEachView(card, ^(UIView *v) {
        CGSize size = v.bounds.size;
        BOOL square = size.width >= 36 && size.width <= 48 && fabs(size.width - size.height) < 1;
        if (!square || v.layer.cornerRadius <= 0) return;
        if (v.layer.cornerRadius >= size.width / 2) {
            if (!sg_cardArtwork) sg_cardArtwork = v;
            return;
        }
        UIView *outer = v;
        for (UIView *u = v; u && u != card && CGSizeEqualToSize(u.bounds.size, size); u = u.superview) {
            roundView(u, size.width / 2);
            u.clipsToBounds = YES;
            outer = u;
        }
        sg_cardArtwork = outer;
    });
    SGForEachView(card, ^(UIView *v) {
        CGRect f = v.frame;
        if (f.size.height > 3 || f.size.width < 200 || v.superview.bounds.size.height < 40) return;
        CGRect target = CGRectMake(52, card.bounds.size.height - 6, 226, 2);
        if (CGRectEqualToRect(f, target)) return;
        v.frame = target;
        [v setNeedsLayout];
        [v layoutIfNeeded];
    });
}

static void styleNowPlayingBar(UIViewController *container) {
    UIViewController *barVC = container.childViewControllers.firstObject;
    UIView *bar = barVC.viewIfLoaded ?: container.view;
    sg_barContainer = container;
    sgr_nowPlayingRoot = bar;

    UIView *card = sgr_nowPlayingCard;
    if (!card || !SGIsInside(card, bar)) card = sgr_nowPlayingCard = detectColoredCard(bar);

    container.view.layer.backgroundColor = NULL;
    SGStripBackgrounds(bar);
    placeInlineBar(container);

    CGRect frame = card ? SGFrameIn(card, container.view) : contentBounds(bar, container.view);
    if (CGRectIsNull(frame)) return;
    frame.size.height = MIN(frame.size.height, 80);
    if (frame.size.height < 30 || frame.size.width < 100) return;

    CGFloat radius = MIN(kCardRadius, frame.size.height / 2);
    if (card) {
        roundView(card, radius);
        restyleCardContent(card);
    }

    UIVisualEffectView *glass = SGGlassFor(container.view, &kGlassKey);
    if (glass.overrideUserInterfaceStyle != UIUserInterfaceStyleDark) glass.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    sg_cardGlass = glass;
    glass.frame = frame;
    SGShapeGlass(glass, radius, NO);

    static dispatch_once_t once;
    dispatch_once(&once, ^{
        SGLog(@"now playing card %@ at %@ (bar %@, container %@)", card.class, NSStringFromCGRect(frame),
              NSStringFromCGRect(bar.frame), NSStringFromCGRect(container.view.bounds));
    });
}

%hook _TtC18NowPlaying_BarImpl36NowPlayingBarContainerViewController
- (void)viewDidLayoutSubviews {
    %orig;
    styleNowPlayingBar((UIViewController *)self);
}
%end

%hook _TtC18NowPlaying_BarImpl27NowPlayingBarViewController
- (void)viewDidLayoutSubviews {
    %orig;
    UIViewController *parent = ((UIViewController *)self).parentViewController;
    if ([NSStringFromClass(parent.class) containsString:@"NowPlayingBarContainer"]) styleNowPlayingBar(parent);
}
%end

%hook _TtC22NowPlaying_BarPageImplP33_CCC0D2EEA6D4725EECD8965E8C38C86D20TouchPassthroughView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = %orig;
    UIView *moved = sg_inlineBar;
    if ((hit && hit != (UIView *)self) || ![moved isDescendantOfView:(UIView *)self]) return hit;
    UIView *inside = [moved hitTest:[(UIView *)self convertPoint:point toView:moved] withEvent:event];
    return inside && inside != moved ? inside : hit;
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[
        @"_TtC18NowPlaying_BarImpl36NowPlayingBarContainerViewController",
        @"_TtC18NowPlaying_BarImpl27NowPlayingBarViewController",
        @"_TtC22NowPlaying_BarPageImplP33_CCC0D2EEA6D4725EECD8965E8C38C86D20TouchPassthroughView",
    ]);
}
