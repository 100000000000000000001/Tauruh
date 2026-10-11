#import <UIKit/UIKit.h>

extern NSNotificationName const SGRFieldColorDidChangeNotification;

@interface SGRArtworkField : UIView
@property (nonatomic) UIEdgeInsets bleed;
@property (nonatomic) BOOL showsBackdrop;
@property (nonatomic) BOOL flows;
// Held still by the owner (the player while playback is paused).
@property (nonatomic) BOOL motionHeld;
// The backdrop's height in points from the top of the bounds; 0 is the window's height.
@property (nonatomic) CGFloat backdropHeight;
// SGRNeutralField until a colour arrives.
@property (nonatomic, readonly) UIColor *fieldColor;

- (void)setProvisionalColor:(UIColor *)color;
- (void)setPreferredColor:(UIColor *)color;
- (void)setArtwork:(UIImage *)image identity:(NSString *)identity animated:(BOOL)animated;
- (void)whenColored:(void (^)(void))colored;
@end
