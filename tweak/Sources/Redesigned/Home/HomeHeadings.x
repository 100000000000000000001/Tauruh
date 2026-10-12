#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Home.h"

static char kTitleKey, kShowAllKey, kHeldKey, kTriesKey;

// How often a heading with no title yet is looked at again.
static const NSUInteger kTries = 3;

// What the title is held on, so the constraints are made again only when it changes.
@interface SGRHeadingHold : NSObject
@property (nonatomic, weak) UILabel *label;
@property (nonatomic, weak) UIView *limit;
@property (nonatomic, copy) NSArray<NSLayoutConstraint *> *constraints;
@end

@implementation SGRHeadingHold
@end

static UIView *headingAround(UIView *button) {
    NSUInteger depth = 0;
    for (UIView *v = button.superview; v && depth < 4; v = v.superview, depth++) {
        if ([v.accessibilityIdentifier isEqualToString:@"Components.UI.SectionHeadingHome"]) return v;
    }
    return nil;
}

static BOOL shown(UIView *view, UIView *root) {
    for (UIView *v = view; v && v != root; v = v.superview) {
        if (v.hidden) return NO;
    }
    return YES;
}

static UILabel *titleLabelIn(UIView *button, UILabel *mine) {
    __block UILabel *title = nil;
    SGForEachView(button, ^(UIView *v) {
        if (v == mine || ![v isKindOfClass:UILabel.class]) return;
        UILabel *label = (UILabel *)v;
        if (!label.text.length || !shown(label, button)) return;
        if (!title || label.font.pointSize > title.font.pointSize) title = label;
    });
    return title;
}

static void restyle(UIView *button) {
    UIView *heading = headingAround(button);
    if (!heading) return;
    UILabel *mine = objc_getAssociatedObject(button, &kTitleKey);
    UILabel *theirs = titleLabelIn(button, mine);
    SGRHeadingHold *held = objc_getAssociatedObject(button, &kHeldKey);
    if (!theirs) {
        // A heading between two shelves: nothing to hold the title on until its label has text again.
        mine.hidden = YES;
        if (held.constraints) [NSLayoutConstraint deactivateConstraints:held.constraints];
        objc_setAssociatedObject(button, &kHeldKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    if (!mine) {
        mine = [UILabel new];
        mine.userInteractionEnabled = NO;
        mine.accessibilityElementsHidden = YES;
        mine.lineBreakMode = NSLineBreakByTruncatingTail;
        mine.translatesAutoresizingMaskIntoConstraints = NO;
        objc_setAssociatedObject(button, &kTitleKey, mine, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    BOOL added = mine.superview != button;
    if (added) [button addSubview:mine];
    mine.hidden = NO;

    UIFont *font = SGRFont(UIFontTextStyleTitle2, UIFontWeightBold, UIContentSizeCategoryLarge);
    if (![mine.font isEqual:font]) mine.font = font;
    if (![mine.text isEqualToString:theirs.text]) mine.text = theirs.text;
    if (![mine.textColor isEqual:theirs.textColor]) mine.textColor = theirs.textColor;
    if (theirs.alpha != 0) theirs.alpha = 0;

    UIView *showAll = SGRFindByIdentifier(heading, @"Components.UI.NavigationButtonHome", &kShowAllKey);
    BOOL offered = showAll && shown(showAll, heading);
    UIView *limit = offered ? showAll : heading;
    if (added || held.label != theirs || held.limit != limit) {
        if (held.constraints) [NSLayoutConstraint deactivateConstraints:held.constraints];
        NSMutableArray<NSLayoutConstraint *> *constraints = [NSMutableArray arrayWithArray:@[
            [mine.leadingAnchor constraintEqualToAnchor:theirs.leadingAnchor],
            [mine.firstBaselineAnchor constraintEqualToAnchor:theirs.firstBaselineAnchor],
            [mine.trailingAnchor constraintLessThanOrEqualToAnchor:heading.trailingAnchor],
        ]];
        if (offered) [constraints addObject:[mine.trailingAnchor constraintLessThanOrEqualToAnchor:showAll.leadingAnchor constant:-SGRGrid]];
        [NSLayoutConstraint activateConstraints:constraints];
        held = [SGRHeadingHold new];
        held.label = theirs;
        held.limit = limit;
        held.constraints = constraints;
        objc_setAssociatedObject(button, &kHeldKey, held, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(button, &kTriesKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        static dispatch_once_t once;
        dispatch_once(&once, ^{ SGLog(@"redesign home: heading \"%@\" %.0fpt drawn at %.0fpt, held on Spotify's label", theirs.text, theirs.font.pointSize, font.pointSize); });
    }
}

// Looks again once the layout has settled, while the heading has no label with text to hold the title on.
static void restyleWhenReady(UIView *button) {
    if (objc_getAssociatedObject(button, &kHeldKey)) return;
    NSUInteger tries = [objc_getAssociatedObject(button, &kTriesKey) unsignedIntegerValue];
    if (tries >= kTries) return;
    objc_setAssociatedObject(button, &kTriesKey, @(tries + 1), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (button.window) restyle(button);
    });
}

%hook _TtCOOOE11Home_ECMKitO19LegacyUI_ECMCoreKit10Components18SectionHeadingHome2UI7Private28NoIntrinsicContentSizeButton
- (void)layoutSubviews {
    %orig;
    CFTimeInterval began = SGRHomeProbeBegin();
    restyle((UIView *)self);
    restyleWhenReady((UIView *)self);
    SGRHomeProbeEnd(SGRHomeProbeHeadings, began);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[@"_TtCOOOE11Home_ECMKitO19LegacyUI_ECMCoreKit10Components18SectionHeadingHome2UI7Private28NoIntrinsicContentSizeButton"]);
}
