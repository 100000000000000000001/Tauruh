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

static void roundCover(UIView *card) {
    UIView *holder = SGRFindByIdentifier(card, @"Encore.ImageView", &kImageKey);
    if (holder.bounds.size.width < kCoverMinWidth) return;
    for (UIView *sub in holder.subviews) {
        if (![sub isKindOfClass:UIImageView.class]) continue;
        roundCorners(sub, SGRRadiusCover);
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
        roundCorners(button, SGRRadiusCover);
        if (button.superview.layer.cornerRadius > 0) roundCorners(button.superview, SGRRadiusCover);
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
