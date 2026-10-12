#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Home.h"

typedef NS_ENUM(NSInteger, SGRHomeKind) {
    SGRHomeKindPending,   // the section's root is not in the cell yet: left as it is
    SGRHomeKindKeep,
    SGRHomeKindDrop,
};

static char kCollapsedKey;

static BOOL classNames(Class cls, NSString *marker, NSMutableDictionary<NSString *, NSMutableDictionary *> *cache) {
    if (!cls || !marker) return NO;
    NSMutableDictionary *answers = cache[marker];
    if (!answers) answers = cache[marker] = [NSMutableDictionary dictionary];
    NSNumber *answer = answers[(id<NSCopying>)cls];
    if (!answer) {
        answer = @([NSStringFromClass(cls) containsString:marker]);
        answers[(id<NSCopying>)cls] = answer;
    }
    return answer.boolValue;
}

static BOOL contentNames(UIView *content, NSString *marker) {
    static NSMutableDictionary<NSString *, NSMutableDictionary *> *cache;
    if (!cache) cache = [NSMutableDictionary dictionary];
    return content && classNames(object_getClass(content), marker, cache);
}

static BOOL isSection(UIView *content) {
    return contentNames(content, @"Home_EvoPageImpl13HomeStructure");
}

static void logOnce(NSString *what) {
    static NSMutableSet<NSString *> *logged;
    if (!logged) logged = [NSMutableSet set];
    if ([logged containsObject:what]) return;
    [logged addObject:what];
    SGLog(@"redesign home: %@", what);
}

// The shortcuts grid names no identifier; episode cards and whatever else comes as a bare list do.
static SGRHomeKind gridKind(UICollectionView *grid) {
    if (grid.accessibilityIdentifier.length) return SGRHomeKindDrop;
    UIView *cell = grid.visibleCells.firstObject;
    // A grid the list sized before it laid its own cells out: nothing but the shortcuts has come as one.
    if (!cell) return SGRHomeKindKeep;
    return contentNames(cell.subviews.firstObject, @"Home_AnchorsAndShortcutsKit") ? SGRHomeKindKeep : SGRHomeKindDrop;
}

// A LazyElementView names the element it will hold before it holds it.
static SGRHomeKind stackKind(UIStackView *stack) {
    for (UIView *part in stack.arrangedSubviews) {
        if ([NSStringFromClass(part.class) containsString:@"Discovery_DJElementKit"]) return SGRHomeKindKeep;
    }
    return stack.arrangedSubviews.count >= 2 ? SGRHomeKindDrop : SGRHomeKindPending;
}

// Before the cell is measured, so the height it reports is without the heading.
static void dropDJHeading(UIView *content) {
    UIStackView *stack = (UIStackView *)content.subviews.firstObject.subviews.firstObject;
    if (![stack isKindOfClass:UIStackView.class] || stackKind(stack) != SGRHomeKindKeep) return;
    for (UIView *part in stack.arrangedSubviews) {
        if (part.hidden || ![NSStringFromClass(part.class) containsString:@"Home_HeadingElementKit"]) continue;
        part.hidden = YES;
        logOnce(@"DJ heading hidden");
    }
}

static SGRHomeKind kindOf(UIView *content, NSString **rootName) {
    UIView *root = content.subviews.firstObject.subviews.firstObject;
    if (!root) return SGRHomeKindPending;
    *rootName = NSStringFromClass(root.class);
    static Class shelf;
    if (!shelf) shelf = NSClassFromString(@"_TtC16Home_CarouselKit29TouchCancellingCollectionView");
    if (shelf && [root isKindOfClass:shelf]) return SGRHomeKindKeep;
    if ([root isKindOfClass:UICollectionView.class]) return gridKind((UICollectionView *)root);
    if ([root isKindOfClass:UIStackView.class]) return stackKind((UIStackView *)root);
    return SGRHomeKindDrop;
}

static void collapse(UICollectionViewCell *cell, CGFloat natural) {
    UIView *content = cell.contentView;
    objc_setAssociatedObject(cell, &kCollapsedKey, @(natural), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (content.autoresizingMask & UIViewAutoresizingFlexibleHeight) content.autoresizingMask &= ~UIViewAutoresizingFlexibleHeight;
    CGRect frame = CGRectMake(0, 0, cell.bounds.size.width, natural);
    if (!CGRectEqualToRect(content.frame, frame)) content.frame = frame;
    if (!content.hidden) content.hidden = YES;
    if (!cell.clipsToBounds) cell.clipsToBounds = YES;
    cell.accessibilityElementsHidden = YES;
}

static void expand(UICollectionViewCell *cell) {
    UIView *content = cell.contentView;
    objc_setAssociatedObject(cell, &kCollapsedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    content.autoresizingMask |= UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    content.frame = cell.bounds;
    content.hidden = NO;
    cell.clipsToBounds = NO;
    cell.accessibilityElementsHidden = NO;
}

%hook _TtC12Element_List18CollectionViewCell
- (UICollectionViewLayoutAttributes *)preferredLayoutAttributesFittingAttributes:(UICollectionViewLayoutAttributes *)attributes {
    UICollectionViewCell *cell = (UICollectionViewCell *)self;
    UIView *content = cell.contentView;
    if (!isSection(content)) return %orig;
    CFTimeInterval began = SGRHomeProbeBegin();
    dropDJHeading(content);
    UICollectionViewLayoutAttributes *result = %orig;

    NSString *rootName = nil;
    SGRHomeKind kind = kindOf(content, &rootName);
    BOOL collapsed = objc_getAssociatedObject(cell, &kCollapsedKey) != nil;
    if (kind == SGRHomeKindDrop) {
        collapse(cell, MAX(1, result.size.height));
        result.size = CGSizeMake(result.size.width, 0);
        logOnce([@"dropped a section of " stringByAppendingString:rootName]);
    } else if (kind == SGRHomeKindKeep) {
        // Cells are reused across kinds: one collapsed before holds a section to keep now.
        if (collapsed) expand(cell);
        logOnce([@"kept a section of " stringByAppendingString:rootName]);
    } else {
        logOnce([@"sized a section before its root was in, left as it is: " stringByAppendingString:rootName ?: @"no root"]);
    }
    SGRHomeProbeEnd(SGRHomeProbeSections, began);
    return result;
}

// The cell's own passes may size the content to the cell again.
- (void)layoutSubviews {
    %orig;
    NSNumber *natural = objc_getAssociatedObject(self, &kCollapsedKey);
    if (natural) collapse((UICollectionViewCell *)self, natural.doubleValue);
}

- (void)prepareForReuse {
    %orig;
    if (objc_getAssociatedObject(self, &kCollapsedKey)) expand((UICollectionViewCell *)self);
}
%end

BOOL SGRHomeSectionCollapsed(UIView *cell) {
    return objc_getAssociatedObject(cell, &kCollapsedKey) != nil;
}

%ctor {
    // Registered whatever the switch says: the flag rows elsewhere lock to these while it is on.
    SGRedesignForceFlags(@"home", @{
        // The badge on the DJ card.
        @"ios-home-evopage-impl.dj_mdc_beta_badge_enabled": @NO,
        // The prompt field for Spotify's AI on Home.
        @"ios-home-evopage-impl.interactive_entrypoint_enabled": @NO,
    });
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[
        @"_TtC12Element_List18CollectionViewCell",
        @"_TtC16Home_CarouselKit29TouchCancellingCollectionView",
    ]);
}
