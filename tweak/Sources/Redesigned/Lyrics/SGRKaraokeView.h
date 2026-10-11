#import <UIKit/UIKit.h>
#import "Shared/Lyrics/Lyrics.h"

@interface SGRKaraokeView : UIView
// Hides Spotify's own lyrics next to this view while it has lyrics to show, and brings them back when not.
- (void)syncSiblings;
@property (nonatomic, readonly) UIEdgeInsets lineInsets;
// duration 0 moves everything at once.
- (void)setLineInsets:(UIEdgeInsets)insets duration:(NSTimeInterval)duration;
- (void)useCompactFontSize:(CGFloat)size;
@property (nonatomic, copy) BOOL (^takesTap)(void);
@end
