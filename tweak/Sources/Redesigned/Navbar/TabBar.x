#import "Core/SGCore.h"
#import "Navbar.h"
#import "Redesigned/Kit/SGRTokens.h"
#import "Settings/SGPage.h"
#import "Redesigned/NowPlayingBar/NowPlayingBar.h"
#import "Headers/SPTEncoreIconView.h"
#import "Shared/Navigation/TabIcons.h"
#import <objc/message.h>

static char kBarKey, kHostKey;
static __weak UIView *sg_stockBar;
static CGFloat sg_room, sg_glassHeight;   // see "room for the glass bar"

@interface SGRSystemTabBar : UITabBar <UITabBarDelegate, UIGestureRecognizerDelegate>
@property (nonatomic, weak) UIView *stockBar;
@property (nonatomic, copy) NSArray<UIView *> *sources;
@property (nonatomic, weak) UILongPressGestureRecognizer *hold;
@property (nonatomic, weak) UITapGestureRecognizer *tabTap;
@property (nonatomic) BOOL holding;
@property (nonatomic, weak) UITabBarItem *shown;
- (UITabBarItem *)itemAt:(CGPoint)point;
- (void)tabTapped:(UITapGestureRecognizer *)tap;
@end

static void syncBar(UIView *stockBar);

#pragma mark - hiding the glass bar

// TabBarMinimize.x decides this from a page's scroll; the host is slid down out of the way.
static BOOL sg_minimized;
static __weak UIView *sg_compactSource;
static NSUInteger sg_minimizeRequest;

BOOL SGRTabBarMinimized(void) {
    return sg_minimized;
}

void SGRSetTabBarMinimized(BOOL minimized, BOOL animated) {
    if (sg_minimized == minimized) return;
    sg_minimized = minimized;
    NSUInteger request = ++sg_minimizeRequest;
    UIView *stockBar = sg_stockBar;
    if (!stockBar) return;
    void (^apply)(void) = ^{
        if (request != sg_minimizeRequest) return;
        syncBar(stockBar);
        UIView *host = objc_getAssociatedObject(stockBar, &kHostKey);
        [host layoutIfNeeded];
        SGRNowPlayingBarFollowTabBar();
    };
    if (!animated) {
        [UIView performWithoutAnimation:apply];
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (request != sg_minimizeRequest) return;
            [UIView animateWithDuration:0.32 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:apply completion:nil];
        });
    }
}

#pragma mark - reading Spotify's items

// The items the bar shows, left to right as Navbar/Navbar.x placed them.
static NSArray<UIView *> *tabItems(UIView *tabBar) {
    NSMutableArray<UIView *> *items = [NSMutableArray array];
    for (UIView *item in SGRowIn(tabBar).arrangedSubviews) {
        if (!item.hidden && item.bounds.size.width >= 20) [items addObject:item];
    }
    return [items sortedArrayUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        return [@(SGFrameIn(a, tabBar).origin.x) compare:@(SGFrameIn(b, tabBar).origin.x)];
    }];
}

// Navbar.x never reorders Spotify's row and appends the mod's own tabs after it, so Home stays first.
static BOOL isHome(UIView *item, UIView *tabBar) {
    return item && item == SGRowIn(tabBar).arrangedSubviews.firstObject;
}

static UILabel *labelIn(UIView *item) {
    __block UILabel *label = nil;
    SGForEachView(item, ^(UIView *v) {
        if (!label && [v isKindOfClass:UILabel.class] && ((UILabel *)v).text.length) label = (UILabel *)v;
    });
    return label;
}

static UIView *iconIn(UIView *item) {
    __block UIView *icon = nil;
    SGForEachView(item, ^(UIView *v) {
        if (icon || v.bounds.size.width < 2) return;
        if ([v isKindOfClass:UIImageView.class] || [NSStringFromClass(v.class) containsString:@"IconView"]) icon = v;
    });
    return icon;
}

// Spotify paints the selected tab's label white and the rest #B3B3B3.
static BOOL isActive(UIView *item) {
    UIColor *color = labelIn(item).textColor;
    CGFloat white = 0, alpha = 0, r, g, b;
    if (![color getWhite:&white alpha:&alpha] && [color getRed:&r green:&g blue:&b alpha:&alpha]) white = MIN(r, MIN(g, b));
    return white > 0.95;
}

static BOOL hasInk(UIImage *image) {
    CGImageRef cg = image.CGImage;
    size_t width = CGImageGetWidth(cg), height = CGImageGetHeight(cg);
    if (!width || !height) return NO;
    NSMutableData *pixels = [NSMutableData dataWithLength:width * height];
    CGContextRef context = CGBitmapContextCreate(pixels.mutableBytes, width, height, 8, width, NULL, (CGBitmapInfo)kCGImageAlphaOnly);
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), cg);
    CGContextRelease(context);
    const uint8_t *alpha = pixels.bytes;
    for (size_t i = 0; i < pixels.length; i++) if (alpha[i] > 16) return YES;
    return NO;
}

static UIImage *renderLayer(CALayer *layer, CGSize size) {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [layer renderInContext:context.CGContext];
    }];
    return hasInk(image) ? [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] : nil;
}

// The SPTEncoreIcon an icon view was built with. Encore keeps it in a Swift ivar with no getter.
static id encoreIconOf(UIView *view) {
    Ivar ivar = class_getInstanceVariable(view.class, "icon");
    const char *type = ivar ? ivar_getTypeEncoding(ivar) : NULL;
    return type && type[0] == '@' ? object_getIvar(view, ivar) : nil;
}

static NSString *titleOf(UIView *source) {
    NSString *title = labelIn(source).text;
    if ([NSStringFromClass(source.class) isEqualToString:@"SGRTabItemView"]) return title;
    for (NSDictionary *entry in SGRNavbarLayout()) {
        if ([entry[SGRNavbarID] isEqualToString:title] && !entry[SGRNavbarURI])
            return entry[SGRNavbarTitle] ?: title;
    }
    return title;
}

static NSString *appleMusicSymbolForTab(NSString *title) {
    static NSDictionary<NSString *, NSString *> *symbols;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        symbols = @{
            @"home": @"house.fill",
            @"listen now": @"house.fill",
            @"search": @"magnifyingglass",
            @"your library": @"square.stack.fill",
            @"library": @"square.stack.fill",
            @"browse": @"square.grid.2x2.fill",
            @"radio": @"dot.radiowaves.left.and.right",
        };
    });
    return symbols[title.lowercaseString];
}

static UIImage *customGlyph(NSString *name, BOOL symbols) {
    static NSCache<NSString *, UIImage *> *cache;
    if (!cache) cache = [NSCache new];
    NSString *key = [NSString stringWithFormat:@"%@:%@", symbols ? @"symbols" : @"encore", name];
    UIImage *image = [cache objectForKey:key];
    if (image) return image;
    UIView *custom = SGTabIconView(name, symbols, UIColor.whiteColor);
    CGSize size = CGSizeMake(24, 24);
    custom.translatesAutoresizingMaskIntoConstraints = YES;
    custom.frame = (CGRect){CGPointZero, size};
    [custom layoutIfNeeded];
    image = renderLayer(custom.layer, size);
    if (image) [cache setObject:image forKey:key];
    return image;
}

static UIImage *stockGlyph(NSString *name, BOOL active) {
    if (!name.length) return nil;
    static NSCache<NSString *, UIImage *> *cache;
    if (!cache) cache = [NSCache new];
    NSString *key = [NSString stringWithFormat:@"%@:%d", name, active];
    UIImage *cached = [cache objectForKey:key];
    if (cached) return cached;

    Class iconClass = NSClassFromString(@"SPTEncoreIcon");
    Class viewClass = NSClassFromString(@"SPTEncoreIconView");
    SEL glyphSelector = NSSelectorFromString(name);
    if (!iconClass || !viewClass || ![iconClass respondsToSelector:glyphSelector]) return nil;
    id icon = ((id (*)(id, SEL))objc_msgSend)(iconClass, glyphSelector);
    if (!icon) return nil;

    SPTEncoreIconView *view = [[viewClass alloc] initWithIcon:icon];
    view.frame = CGRectMake(0, 0, 24, 24);
    [view setForegroundColor:UIColor.whiteColor];
    if ([view respondsToSelector:@selector(setActiveForegroundColor:)]) [view setActiveForegroundColor:UIColor.whiteColor];
    if ([view respondsToSelector:@selector(setIsActive:)]) [view setIsActive:active];
    [view layoutIfNeeded];
    UIImage *image = renderLayer(view.layer, view.bounds.size);
    if (image) [cache setObject:image forKey:key];
    return image;
}

static UIImage *glyphOf(UIView *item, BOOL active) {
    NSString *sourceTitle = labelIn(item).text;
    if (![NSStringFromClass(item.class) isEqualToString:@"SGRTabItemView"]) {
        NSDictionary *stockEntry = nil;
        for (NSDictionary *entry in SGRNavbarLayout()) {
            if ([entry[SGRNavbarID] isEqualToString:sourceTitle] && !entry[SGRNavbarURI]) {
                stockEntry = entry;
                NSString *icon = entry[SGRNavbarIcon];
                if (SGRNavbarEntryHasCustomIcon(entry) && [icon isKindOfClass:NSString.class]) {
                    return customGlyph(icon, [entry[SGRNavbarIconSet] isEqual:SGTabIconSetSymbols]);
                }
                break;
            }
        }
        if (SGFlag(SGRKeyNavbarAppleIcons, NO)) {
            NSString *symbol = appleMusicSymbolForTab(sourceTitle);
            if (symbol) return customGlyph(symbol, YES);
        }
        NSString *defaultIcon = SGRNavbarDefaultIcon(stockEntry[SGRNavbarID] ?: sourceTitle);
        UIImage *defaultGlyph = stockGlyph(defaultIcon, active);
        if (defaultGlyph) return defaultGlyph;
    }
    UIView *live = iconIn(item);
    if (!live) return nil;
    CGSize size = live.bounds.size;
    id icon = encoreIconOf(live);
    Class viewClass = NSClassFromString(@"SPTEncoreIconView");
    if (icon && viewClass) {
        static NSCache<NSString *, UIImage *> *cache;
        if (!cache) cache = [NSCache new];
        NSString *key = [NSString stringWithFormat:@"%@ %d %@", [icon respondsToSelector:@selector(name)] ? [icon name] : icon, active, NSStringFromCGSize(size)];
        UIImage *cached = [cache objectForKey:key];
        if (cached) return cached;
        SPTEncoreIconView *view = [[viewClass alloc] initWithIcon:icon];
        view.frame = (CGRect){CGPointZero, size};
        [view setForegroundColor:UIColor.whiteColor];
        if ([view respondsToSelector:@selector(setActiveForegroundColor:)]) [view setActiveForegroundColor:UIColor.whiteColor];
        if ([view respondsToSelector:@selector(setIsActive:)]) [view setIsActive:active];
        [view layoutIfNeeded];
        UIImage *image = renderLayer(view.layer, size);
        if (image) {
            [cache setObject:image forKey:key];
            return image;
        }
    }
    // Tabs of the mod's own draw a UIImageView, or an icon Encore would not draw off screen.
    if (size.width < 2) return nil;
    static NSCache<NSString *, UIImage *> *customItemCache;
    if (!customItemCache) customItemCache = [NSCache new];
    NSString *key = [NSString stringWithFormat:@"%@:%@", NSStringFromClass(item.class),
                     item.accessibilityIdentifier ?: NSStringFromCGSize(size)];
    UIImage *cached = [customItemCache objectForKey:key];
    if (cached) return cached;
    UIImage *image = renderLayer(live.layer, size);
    if (image) [customItemCache setObject:image forKey:key];
    return image;
}

#pragma mark - passing a tap on

static BOOL fireTapRecognizers(UIView *view) {
    Ivar targetsIvar = class_getInstanceVariable(UIGestureRecognizer.class, "_targets");
    if (!targetsIvar) return NO;
    BOOL fired = NO;
    for (UIGestureRecognizer *recognizer in view.gestureRecognizers) {
        if (![recognizer isKindOfClass:UITapGestureRecognizer.class] || !recognizer.enabled) continue;
        for (id pair in object_getIvar(recognizer, targetsIvar)) {
            Ivar targetIvar = class_getInstanceVariable([pair class], "_target");
            Ivar actionIvar = class_getInstanceVariable([pair class], "_action");
            if (!targetIvar || !actionIvar) continue;
            id target = object_getIvar(pair, targetIvar);
            SEL action = *(SEL *)((char *)(__bridge void *)pair + ivar_getOffset(actionIvar));
            if (!target || !action || ![target respondsToSelector:action]) continue;
            SGLog(@"tab bar: tap -> %@ %@", NSStringFromClass([target class]), NSStringFromSelector(action));
            ((void (*)(id, SEL, id))objc_msgSend)(target, action, recognizer);
            fired = YES;
        }
    }
    return fired;
}

static void forwardTap(UIView *item) {
    __block BOOL sent = NO;
    SGForEachView(item, ^(UIView *v) {
        if (!sent) sent = fireTapRecognizers(v);
    });
    SGForEachView(item, ^(UIView *v) {
        if (sent || ![v isKindOfClass:UIControl.class]) return;
        SGLog(@"tab bar: tap -> control %@", NSStringFromClass(v.class));
        [(UIControl *)v sendActionsForControlEvents:UIControlEventTouchUpInside];
        sent = YES;
    });
    if (!sent) {
        NSMutableString *out = [NSMutableString stringWithFormat:@"tab bar: nothing to tap in %@", NSStringFromClass(item.class)];
        SGForEachView(item, ^(UIView *v) {
            for (UIGestureRecognizer *r in v.gestureRecognizers) [out appendFormat:@"\n  %@ on %@", r, NSStringFromClass(v.class)];
        });
        SGLogLong(@"navbar", out);
    }
}

#pragma mark - the system bar

@implementation SGRSystemTabBar

- (void)tabBar:(UITabBar *)tabBar didSelectItem:(UITabBarItem *)item {
    NSUInteger index = [self.items indexOfObject:item];
    if (index == NSNotFound || index >= self.sources.count) return;
    BOOL again = item == self.shown;
    self.shown = item;
    UIView *source = self.sources[index];
    sg_compactSource = source;
    BOOL expand = sg_minimized && SGFlag(SGRKeyNavbarCompact, YES) && (again || self.sources.count == 1);
    if (!self.holding && !expand && ![source respondsToSelector:NSSelectorFromString(@"open")])
        // Home tapped while on Home pops Spotify's stack, which would take Mod Settings straight off it.
        forwardTap(source);
    if (expand) {
        SGRSetTabBarMinimized(NO, YES);
        return;
    }
    // Spotify repaints its labels a moment later; a tap it did not take snaps the selection back.
    UIView *stockBar = self.stockBar;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (stockBar) syncBar(stockBar);
    });
}

- (void)tabTapped:(UITapGestureRecognizer *)tap {
    if (tap.state != UIGestureRecognizerStateEnded || self.holding) return;
    CGPoint point = [tap locationInView:self];
    if (!self.items.count || self.items.count != self.sources.count || self.bounds.size.width <= 0) return;
    CGFloat width = self.bounds.size.width / self.items.count;
    NSUInteger index = MIN((NSUInteger)MAX(0, floor(point.x / width)), self.items.count - 1);
    if (self.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft)
        index = self.items.count - 1 - index;
    UIView *source = self.sources[index];
    SEL open = NSSelectorFromString(@"open");
    if ([source respondsToSelector:open]) {
        sg_compactSource = source;
        UITabBarItem *item = self.items[index];
        self.shown = item;
        self.selectedItem = item;
        ((void (*)(id, SEL))objc_msgSend)(source, open);
    }
}

- (UITabBarItem *)itemAt:(CGPoint)point {
    __block UITabBarItem *nearest = nil;
    __block CGFloat best = CGFLOAT_MAX;
    SGForEachView(self, ^(UIView *v) {
        BOOL label = [v isKindOfClass:UILabel.class], glyph = [v isKindOfClass:UIImageView.class];
        if ((!label && !glyph) || v.bounds.size.width < 1) return;
        CGFloat distance = fabs([v convertPoint:CGPointMake(CGRectGetMidX(v.bounds), 0) toView:self].x - point.x);
        if (distance >= best) return;
        for (UITabBarItem *item in self.items) {
            UIImage *image = glyph ? ((UIImageView *)v).image : nil;
            if (label ? ![((UILabel *)v).text isEqualToString:item.title] : !image || (image != item.image && image != item.selectedImage)) continue;
            best = distance;
            nearest = item;
            break;
        }
    });
    return nearest;
}

// UIView asks itself this for its own recognizers too, so only the hold is answered here.
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)recognizer {
    if (recognizer == self.tabTap) return YES;
    if (recognizer != self.hold) return [super gestureRecognizerShouldBegin:recognizer];
    NSUInteger index = [self.items indexOfObject:[self itemAt:[recognizer locationInView:self]]];
    return index < self.sources.count && isHome(self.sources[index], self.stockBar);
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return YES;
}

- (void)held:(UILongPressGestureRecognizer *)hold {
    if (hold.state == UIGestureRecognizerStateBegan) {
        self.holding = YES;
        SGOpenModSettings(self);
    } else if (hold.state != UIGestureRecognizerStateChanged) {
        // The bar may still pick Home as the finger lifts, after this.
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            weakSelf.holding = NO;
        });
    }
}

@end

static const CGFloat kFadeRise = 112;
static const NSUInteger kFadeStops = 7;

@interface SGRTabBarHost : UIView
@end

@implementation SGRTabBarHost {
    CAGradientLayer *_fade;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _fade = [CAGradientLayer layer];
    NSNull *off = NSNull.null;
    _fade.actions = @{@"bounds": off, @"position": off, @"frame": off};
    // Fade to half black on a smoothstep, so there is no edge where it starts.
    NSMutableArray *colors = [NSMutableArray array], *locations = [NSMutableArray array];
    for (NSUInteger i = 0; i < kFadeStops; i++) {
        CGFloat t = (CGFloat)i / (kFadeStops - 1);
        [colors addObject:(id)[UIColor colorWithWhite:0 alpha:0.5 * t * t * (3 - 2 * t)].CGColor];
        [locations addObject:@(t)];
    }
    _fade.colors = colors;
    _fade.locations = locations;
    [self.layer insertSublayer:_fade atIndex:0];
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    CGRect fade = CGRectMake(0, -kFadeRise, bounds.size.width, bounds.size.height + kFadeRise);
    if (!CGRectEqualToRect(_fade.frame, fade)) _fade.frame = fade;
}

- (UIEdgeInsets)safeAreaInsets {
    UIEdgeInsets insets = [super safeAreaInsets];
    insets.bottom = MAX(0, insets.bottom - sg_room);
    return insets;
}
@end

@interface SGRHomeHold : UILongPressGestureRecognizer
@end

@implementation SGRHomeHold
+ (void)held:(SGRHomeHold *)hold {
    if (hold.state == UIGestureRecognizerStateBegan) SGOpenModSettings(hold.view);
}
@end

// On Spotify's own bar a hold that begins fails the item's tap recognizer, so Home is not tapped too.
static void holdHome(UIView *stockBar) {
    UIView *home = SGRowIn(stockBar).arrangedSubviews.firstObject;
    if (!home) return;
    for (UIGestureRecognizer *recognizer in home.gestureRecognizers) {
        if ([recognizer isKindOfClass:SGRHomeHold.class]) return;
    }
    [home addGestureRecognizer:[[SGRHomeHold alloc] initWithTarget:SGRHomeHold.class action:@selector(held:)]];
}

static void logBarOnce(UITabBar *bar) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            SGLogLong(@"navbar", [NSString stringWithFormat:@"system tab bar %@\n%@", NSStringFromCGRect(bar.superview.frame), [bar recursiveDescription]]);
        });
    });
}

#pragma mark - room for the glass bar

static const CGFloat kStockRow = 49;

static CGFloat glassHeight(UITabBar *bar, UIView *stockBar) {
    if (sg_room < 0.5 || sg_glassHeight <= 0) sg_glassHeight = [bar sizeThatFits:CGSizeMake(stockBar.bounds.size.width, kStockRow)].height;
    return sg_glassHeight;
}

static UIViewController *containerOf(UIView *stockBar) {
    Class containerClass = NSClassFromString(@"_TtC23NavigationUI_TabBarImpl19TabBarContainerImpl");
    for (UIResponder *r = stockBar.nextResponder; r; r = r.nextResponder) {
        if ([r isKindOfClass:containerClass]) return (UIViewController *)r;
    }
    return nil;
}

static void makeRoom(UIViewController *container) {
    UIView *stockBar = sg_stockBar;
    UITabBar *bar = stockBar ? objc_getAssociatedObject(stockBar, &kBarKey) : nil;
    if (!bar.window || !container.isViewLoaded || ![stockBar isDescendantOfView:container.view]) return;
    UIEdgeInsets extra = container.additionalSafeAreaInsets;
    CGFloat inset = container.view.safeAreaInsets.bottom - extra.bottom;
    CGFloat height = glassHeight(bar, stockBar);
    // Spotify's regular width bar is a fixed 76 pt that ignores the inset.
    BOOL compact = container.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassCompact;
    CGFloat room = compact ? MAX(0, ceil(height - kStockRow - inset)) : 0;
    if (fabs(extra.bottom - room) < 0.5) return;
    sg_room = extra.bottom = room;
    container.additionalSafeAreaInsets = extra;
    SGLog(@"tab bar: %.0f pt of room made under Spotify's bar for the glass bar's %.0f, over an inset of %.0f", room, height, inset);
}

static void syncBar(UIView *stockBar) {
    sg_stockBar = stockBar;

    SGRSystemTabBar *bar = objc_getAssociatedObject(stockBar, &kBarKey);
    if (!bar) {
        bar = [[SGRSystemTabBar alloc] initWithFrame:stockBar.bounds];
        bar.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        bar.delegate = bar;
        bar.stockBar = stockBar;
        UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc] initWithTarget:bar action:@selector(held:)];
        hold.delegate = bar;
        [bar addGestureRecognizer:hold];
        bar.hold = hold;
        UITapGestureRecognizer *tabTap = [[UITapGestureRecognizer alloc] initWithTarget:bar action:@selector(tabTapped:)];
        tabTap.delegate = bar;
        tabTap.cancelsTouchesInView = NO;
        [bar addGestureRecognizer:tabTap];
        bar.tabTap = tabTap;
        objc_setAssociatedObject(stockBar, &kBarKey, bar, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        SGRTabBarHost *host = [SGRTabBarHost new];
        [host addSubview:bar];
        objc_setAssociatedObject(stockBar, &kHostKey, host, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UIColor *accent = SGRAccent();
    if (![bar.tintColor isEqual:accent]) bar.tintColor = accent;
    UIView *host = objc_getAssociatedObject(stockBar, &kHostKey);

    for (UIView *sub in stockBar.subviews) {
        if (sub == host) continue;
        if (sub.alpha != 0) sub.alpha = 0;
        if (sub.userInteractionEnabled) sub.userInteractionEnabled = NO;
    }
    stockBar.superview.layer.backgroundColor = NULL;

    NSArray<UIView *> *allSources = tabItems(stockBar);
    if (!allSources.count) return;
    UIView *activeSource = nil;
    for (UIView *source in allSources) {
        if (isActive(source)) { activeSource = source; break; }
    }
    if (activeSource) sg_compactSource = activeSource;
    if (![allSources containsObject:sg_compactSource]) sg_compactSource = allSources.firstObject;
    BOOL compact = sg_minimized && SGFlag(SGRKeyNavbarCompact, YES);
    NSArray<UIView *> *sources = compact ? (sg_compactSource ? @[sg_compactSource] : @[]) : allSources;
    if (!sources.count) return;
    // An item with no title is drawn by UIKit as its glyph alone, centred, on a bar of the same height.
    BOOL hideLabels = SGFlag(SGRKeyNavbarHideLabels, YES);

    if (![sources isEqualToArray:bar.sources]) {
        NSMutableArray<UITabBarItem *> *items = [NSMutableArray array];
        for (UIView *source in sources) [items addObject:[[UITabBarItem alloc] initWithTitle:hideLabels ? nil : titleOf(source) image:nil tag:items.count]];
        bar.sources = sources;
        [bar setItems:items animated:NO];
        NSMutableString *out = [NSMutableString stringWithString:@"tab bar icons"];
        for (UIView *source in sources) {
            UIView *live = iconIn(source);
            id icon = live ? encoreIconOf(live) : nil;
            id variant = [icon respondsToSelector:NSSelectorFromString(@"active")] ? ((id (*)(id, SEL))objc_msgSend)(icon, NSSelectorFromString(@"active")) : nil;
            [out appendFormat:@"\n  %@: %@ icon %@ active-variant %@ live-isActive %d label-white %d", labelIn(source).text, NSStringFromClass(live.class),
                 [icon respondsToSelector:@selector(name)] ? [icon name] : icon, [variant respondsToSelector:@selector(name)] ? [variant name] : variant,
                 [live respondsToSelector:@selector(isActive)] ? [(SPTEncoreIconView *)live isActive] : -1, isActive(source)];
        }
        SGLogLong(@"navbar", out);
    }

    UITabBarItem *selected = nil;
    BOOL missing = NO;
    for (NSUInteger i = 0; i < sources.count; i++) {
        UITabBarItem *item = bar.items[i];
        item.image = glyphOf(sources[i], NO);
        item.selectedImage = glyphOf(sources[i], YES);
        missing |= !item.image || !item.selectedImage;
        NSString *title = hideLabels ? nil : titleOf(sources[i]);
        if (hideLabels ? item.title != nil : ![title isEqualToString:item.title]) item.title = title;
        if (!selected && (isActive(sources[i]) || (compact && sources[i] == sg_compactSource))) selected = item;
    }
    if (selected && bar.selectedItem != selected) bar.selectedItem = selected;
    // An icon view Spotify has not built yet is looked for again shortly, not on the next touch.
    static NSUInteger retries;
    if (missing && retries++ < 40) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            syncBar(stockBar);
        });
    }

    CGRect bounds = stockBar.bounds;
    CGFloat width = bounds.size.width;
    CGFloat height = MAX(bounds.size.height, glassHeight(bar, stockBar));
    CGRect frame = CGRectMake(0, CGRectGetMaxY(bounds) - height, width, height);
    if (!CGRectEqualToRect(host.frame, frame)) host.frame = frame;
    CGFloat compactWidth = host.bounds.size.height;
    CGRect barFrame = compact ? CGRectMake(0, 0, compactWidth, host.bounds.size.height) : host.bounds;
    if (!CGRectEqualToRect(bar.frame, barFrame)) bar.frame = barFrame;
    CGAffineTransform hostTransform = sg_minimized && !compact
        ? CGAffineTransformMakeTranslation(0, host.bounds.size.height) : CGAffineTransformIdentity;
    if (!CGAffineTransformEqualToTransform(host.transform, hostTransform)) host.transform = hostTransform;
    if (host.superview != stockBar) [stockBar addSubview:host];
    else if (stockBar.subviews.lastObject != host) [stockBar bringSubviewToFront:host];
    logBarOnce(bar);
    makeRoom(containerOf(stockBar));
    if (compact) SGRNowPlayingBarFollowTabBar();
}

CGRect SGRTabBarInlineSlot(UIView *host, CGFloat height) {
    UIView *stockBar = sg_stockBar;
    UITabBar *bar = stockBar ? objc_getAssociatedObject(stockBar, &kBarKey) : nil;
    if (!sg_minimized || !SGFlag(SGRKeyNavbarCompact, YES) || !host || !bar.window
        || stockBar.hidden || stockBar.alpha < 0.01) return CGRectNull;
    CGRect whole = [stockBar convertRect:stockBar.bounds toView:host];
    CGRect leading = [bar convertRect:bar.bounds toView:host];
    CGFloat left = CGRectGetMaxX(leading);
    CGFloat right = CGRectGetMaxX(whole) - 12;
    CGRect slot = CGRectMake(left, CGRectGetMidY(whole) - height / 2, right - left, height);
    CGRect inWindow = [host convertRect:slot toView:bar.window];
    if (slot.size.width < 100 || CGRectGetMinY(inWindow) < 0
        || CGRectGetMaxY(inWindow) > CGRectGetMaxY(bar.window.bounds)) return CGRectNull;
    return slot;
}

void SGRAlignCompactTabBarToNowPlayingCard(void) {
    UIView *stockBar = sg_stockBar;
    SGRSystemTabBar *bar = stockBar ? objc_getAssociatedObject(stockBar, &kBarKey) : nil;
    UIView *host = stockBar ? objc_getAssociatedObject(stockBar, &kHostKey) : nil;
    if (!sg_minimized || !SGFlag(SGRKeyNavbarCompact, YES) || !bar.window
        || bar.superview != host || bar.items.count != 1) return;

    CGRect card = SGRNowPlayingCardFrameIn(stockBar, NULL);
    if (CGRectIsNull(card)) return;

    UIImage *selectedImage = bar.selectedItem.selectedImage ?: bar.selectedItem.image;
    __block UIImageView *glyphView = nil;
    SGForEachView(bar, ^(UIView *view) {
        if (glyphView || ![view isKindOfClass:UIImageView.class]
            || view.bounds.size.width < 8 || view.bounds.size.height < 8) return;
        UIImage *image = ((UIImageView *)view).image;
        if (image == selectedImage || [image isEqual:selectedImage]) glyphView = (UIImageView *)view;
    });
    if (!glyphView) return;

    CGPoint iconCenter = [glyphView convertPoint:CGPointMake(CGRectGetMidX(glyphView.bounds),
                                                              CGRectGetMidY(glyphView.bounds)) toView:bar];
    CGPoint cardCenter = [stockBar convertPoint:CGPointMake(CGRectGetMidX(card), CGRectGetMidY(card)) toView:host];
    CGRect frame = bar.frame;
    CGFloat targetY = cardCenter.y - iconCenter.y;
    if (fabs(frame.origin.y - targetY) < 0.5) return;
    frame.origin.y = targetY;
    bar.frame = frame;
}

#pragma mark - hooks

static UIView *tabBarOf(UIView *item) {
    Class barClass = NSClassFromString(@"_TtC23NavigationUI_TabBarImpl10TabBarView");
    for (UIView *v = item.superview; v; v = v.superview) if ([v isKindOfClass:barClass]) return v;
    return nil;
}

// Set while the bar lays its items out itself, so each item's pass leaves the work to the bar's one.
static BOOL sg_barPass, sg_itemsLaidOut;

%hook _TtC23NavigationUI_TabBarImpl10TabBarView
- (void)layoutSubviews {
    %orig;
    SGRComposeTabBar((UIView *)self);
    sg_barPass = YES;
    sg_itemsLaidOut = NO;
    for (UIView *sub in ((UIView *)self).subviews) {
        if (![sub isKindOfClass:SGRTabBarHost.class]) [sub layoutIfNeeded];
    }
    sg_barPass = NO;
    if (sg_itemsLaidOut) SGRComposeTabBar((UIView *)self);
    holdHome((UIView *)self);
    syncBar((UIView *)self);
    SGRLogTabBarRow((UIView *)self);
}
%end

// The bar's own pass runs before Spotify has filled the row; the items lay out as they arrive.
static void itemDidLayOut(UIView *item) {
    if (sg_barPass) {
        sg_itemsLaidOut = YES;
        return;
    }
    UIView *bar = tabBarOf(item);
    if (!bar) return;
    SGRComposeTabBar(bar);
    holdHome(bar);
    syncBar(bar);
    SGRLogTabBarRow(bar);
}

%hook _TtC23NavigationUI_TabBarImpl21TabBarItemElementView
- (void)layoutSubviews {
    %orig;
    itemDidLayOut((UIView *)self);
}
%end

%hook _TtC25CreateMenu_TabBarItemImpl24CreateMenuTabBarItemView
- (void)layoutSubviews {
    %orig;
    itemDidLayOut((UIView *)self);
}
%end

// A tab changed from elsewhere (a link, the side drawer) repaints the labels without a layout pass.
%hook _TtC23NavigationUI_TabBarImpl19TabBarContainerImpl
- (void)setSelectedViewController:(UIViewController *)controller {
    %orig;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *bar = sg_stockBar;
        if (bar) syncBar(bar);
    });
}
- (void)viewSafeAreaInsetsDidChange {
    %orig;
    makeRoom((UIViewController *)self);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[
        @"_TtC23NavigationUI_TabBarImpl10TabBarView",
        @"_TtC23NavigationUI_TabBarImpl21TabBarItemElementView",
        @"_TtC25CreateMenu_TabBarItemImpl24CreateMenuTabBarItemView",
        @"_TtC23NavigationUI_TabBarImpl19TabBarContainerImpl",
    ]);
}
