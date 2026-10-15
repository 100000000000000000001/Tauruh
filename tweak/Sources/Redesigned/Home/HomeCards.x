#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Home.h"

// Below this a card's picture is a glyph or a placeholder, not a cover.
static const CGFloat kCoverMinWidth = 80;

static char kImageKey;

static void roundCorners(UIView *view, CGFloat radius) {
    CALayer *layer = view.layer;
    if (layer.cornerRadius != radius) layer.cornerRadius = radius;
    if (layer.cornerCurve != kCACornerCurveContinuous) layer.cornerCurve = kCACornerCurveContinuous;
}

static char kBackingKey;

// Top picks' cards (a cover over 200pt wide) sit on a glass card, like the Music app's top shelf.
static void backing(UIView *card, BOOL large) {
    UIView *back = objc_getAssociatedObject(card, &kBackingKey);
    if (!large) { back.hidden = YES; return; }
    if (!back) {
        back = [UIView new];
        back.userInteractionEnabled = NO;
        back.accessibilityElementsHidden = YES;
        back.backgroundColor = [UIColor colorWithWhite:1 alpha:0.13];
        back.layer.cornerCurve = kCACornerCurveContinuous;
        back.layer.borderWidth = 1;
        back.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.10].CGColor;
        objc_setAssociatedObject(card, &kBackingKey, back, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (back.superview != card) [card insertSubview:back atIndex:0];
    back.hidden = NO;
    if (!CGRectEqualToRect(back.frame, card.bounds)) back.frame = card.bounds;
    CGFloat radius = 32;
    if (back.layer.cornerRadius != radius) back.layer.cornerRadius = radius;
}

static void roundCover(UIView *card) {
    UIView *holder = SGRFindByIdentifier(card, @"Encore.ImageView", &kImageKey);
    if (holder.bounds.size.width < kCoverMinWidth) return;
    BOOL large = holder.bounds.size.width >= 200;
    backing(card, large);
    for (UIView *sub in holder.subviews) {
        if (![sub isKindOfClass:UIImageView.class]) continue;
        roundCorners(sub, large ? 32 : SGRRadiusCover);
        if (!sub.layer.masksToBounds) sub.layer.masksToBounds = YES;
    }
}

static void calmDJ(UIView *card) {
    for (UIView *sub in card.subviews) {
        NSString *name = NSStringFromClass(sub.class);
        if (![name containsString:@"TranscriptView"] && ![name containsString:@"BetaBadge"]) continue;
        if (sub.alpha != 0) sub.alpha = 0;
        sub.accessibilityElementsHidden = YES;
        SGForEachView(sub, ^(UIView *v) {
            if ([v isKindOfClass:UILabel.class]) SGRSuppress(v);
        });
    }
}

static void style(UIView *button) {
    NSString *identifier = button.accessibilityIdentifier;
    if ([identifier isEqualToString:@"Shortcut.Card.Home"]) {
        CGFloat pill = MIN(18, button.bounds.size.height / 2);
        roundCorners(button, pill);
        if (button.superview.layer.cornerRadius > 0) roundCorners(button.superview, pill);
        SGRHomeStyleTile(button);
        return;
    }
    if ([identifier isEqualToString:@"Components.UI.HomeCard"]) {
        roundCover(button);
        return;
    }
    static Class dj;
    if (!dj) dj = NSClassFromString(@"_TtC30Discovery_MediumDensityCardKit9DJMDCView");
    if (dj && [button.superview isKindOfClass:dj]) {
        roundCorners(button, SGRRadiusCard);
        calmDJ(button);
        static dispatch_once_t once;
        dispatch_once(&once, ^{ SGLog(@"redesign home: DJ card at the card radius, transcript gone"); });
    }
}

%hook _TtC19LegacyUI_ECMCoreKit31InteractableLayoutBackingButton
- (void)layoutSubviews {
    %orig;
    CFTimeInterval began = SGRHomeProbeBegin();
    style((UIView *)self);
    SGRHomeProbeEnd(SGRHomeProbeCards, began);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[
        @"_TtC19LegacyUI_ECMCoreKit31InteractableLayoutBackingButton",
        @"_TtC30Discovery_MediumDensityCardKit9DJMDCView",
    ]);
}
