#import "Core/SGCore.h"
#import "SGRKaraokeView.h"
#import "LyricsText.h"
#import "MeaningSheet.h"
#import "Shared/LyricsSources/LyricsSources.h"
#import "Shared/Player/PlayerEvents.h"
#import "Shared/Haptics/Haptics.h"
#import "Redesigned/Kit/SGRTokens.h"

static const CGFloat kFontSize = 30, kMargin = 24, kLineGap = 24, kRowTighten = 2;
static const CGFloat kDimAlpha = 0.3, kFillEdge = 22, kLift = 2.5, kDimScale = 0.97;
static const CGFloat kAnchor = 0.28;   // where the sung line rests, as a share of the height
static const CGFloat kEdgeFade = 0.1;  // the lines fade out over this share at the top and bottom
static const CGFloat kCompactMargin = 24, kCompactGap = 6;
static const CGFloat kBlurPerLine = 1.4, kMaxBlur = 6;
// The (oh, aye) hanging under a line: smaller, a little dimmer, and just clear of it.
static const CGFloat kBackingScale = 0.62, kBackingAlpha = 0.8, kBackingGap = 4;
static const CGFloat kBubbleSide = 22, kBubbleGap = 8, kBubbleGlyph = 11, kBubbleAlpha = 0.75, kBubbleReach = 14;
static const CGFloat kUnderlineDrop = 1, kUnderlineWidth = 2, kUnderlineAlpha = 0.35;
// The line naming the source, under the lyrics and outside the fade so it does not dim with them.
static const CGFloat kCreditSize = 12, kCreditAlpha = 0.4, kCreditBottom = 10;
static const CGFloat kExtrasSide = 44, kExtrasBottom = 12, kExtrasGlyph = 17, kExtrasCreditGap = 12;
static const NSTimeInterval kRestyleFade = 0.3;   // the lines crossfading to a new style
static const NSTimeInterval kBrowseHold = 3;   // after scrolling by hand, how long until it follows the song again
static const double kFloatMinMs = 700, kFloatLeadMs = 80;   // a short word still floats up this slowly
// A line lit whole: how long its words take to come up to full white, and to float up together.
static const NSTimeInterval kWholeFade = 0.35;
static const double kWholeRiseMs = 900;
static const double kClockSnapMs = 250, kClockPull = 0.08;
static const CGFloat kSightBehind = 0.5, kSightAhead = 0.5, kSightSlack = 0.25;
static const NSTimeInterval kTransitionSlack = 0.05;   // after the player's animation, before the link is back
static NSString *const kBlurPath = @"filters.gaussianBlur.inputRadius";
// Two voices can sing at once, rarely more; past this many, the latest ones wait their turn.
enum { kMostSung = 6 };
static const NSInteger kBreakMinMs = 7000;
// The dots' size and the room between them, as shares of the font, which is Apple Music's proportion.
static const CGFloat kDotShare = 0.5, kDotGapShare = 0.27;
static const double kBreakWait = 0.25, kBreakIn = 0.4, kBreakFadeIn = 0.16, kBreathHalf = 4, kBreathLow = 0.85, kBreathHigh = 1.12;
static const double kBreakOut = 0.35, kBreakSwell = 1.2, kBreakSwellShare = 0.35, kBreakCollapse = 0.5;
// The dots' clock is set again only once it is this far from the song's, or the song stops or starts.
static const double kBreakSlack = 0.03;
// A position that has not moved for this long is a paused player, not two frames between readings.
static const CFTimeInterval kStillFor = 0.1;

@interface CAFilter : NSObject
+ (instancetype)filterWithType:(NSString *)type;
@end

static BOOL readsRightToLeft(NSString *text) {
    static NSCharacterSet *rightToLeft, *leftToRight;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableCharacterSet *scripts = [NSMutableCharacterSet new];
        [scripts addCharactersInRange:NSMakeRange(0x0590, 0x370)];    // Hebrew, Arabic, Syriac, Thaana, N'Ko and on
        [scripts addCharactersInRange:NSMakeRange(0xFB1D, 0x2E3)];    // Hebrew and Arabic presentation forms
        [scripts addCharactersInRange:NSMakeRange(0xFE70, 0x90)];     // Arabic presentation forms B
        [scripts addCharactersInRange:NSMakeRange(0x10800, 0x800)];   // the old scripts written right to left
        [scripts addCharactersInRange:NSMakeRange(0x1E800, 0x800)];   // Mende Kikakui and Adlam
        NSMutableCharacterSet *letters = [NSCharacterSet.letterCharacterSet mutableCopy];
        [letters formIntersectionWithCharacterSet:scripts.invertedSet];
        leftToRight = [letters copy];
        [scripts formIntersectionWithCharacterSet:NSCharacterSet.letterCharacterSet];
        rightToLeft = [scripts copy];
    });
    NSUInteger first = [text rangeOfCharacterFromSet:rightToLeft].location;
    return first != NSNotFound && first < [text rangeOfCharacterFromSet:leftToRight].location;
}

// Laid against the right edge: a line written right to left, or a second voice's written left to right.
static BOOL alignsRight(SGKaraokeLine *line) {
    return (line.align == SGKaraokeAlignTrailing) != readsRightToLeft(SGKaraokeLineText(line));
}

static UILabel *wordLabel(NSString *text, UIFont *font, UIColor *color, CGRect frame, BOOL rightToLeft) {
    UILabel *label = [[UILabel alloc] initWithFrame:frame];
    label.text = text;
    label.font = font;
    label.textColor = color;
    if (!rightToLeft) return label;
    NSMutableParagraphStyle *paragraph = [NSMutableParagraphStyle new];
    paragraph.baseWritingDirection = NSWritingDirectionRightToLeft;
    label.attributedText = [[NSAttributedString alloc] initWithString:text attributes:@{
        NSFontAttributeName: font, NSForegroundColorAttributeName: color, NSParagraphStyleAttributeName: paragraph}];
    return label;
}

#pragma mark - a word

@interface SGRKaraokeWordView : UIView
@property (nonatomic, readonly) SGKaraokeWord *word;
@property (nonatomic, readonly) UILabel *lit;
@property (nonatomic) CGFloat offset;   // where the word starts along its line, rows laid end to end
@property (nonatomic) BOOL whole;
@property (nonatomic) double riseStart, riseEnd;
- (void)fillTo:(CGFloat)cursor;
- (void)floatAt:(double)ms;
- (void)settle;
@end

@implementation SGRKaraokeWordView {
    CAGradientLayer *_fill;
    CGFloat _filled, _lift;
    BOOL _rightToLeft;
}

- (instancetype)initWithWord:(SGKaraokeWord *)word font:(UIFont *)font rightToLeft:(BOOL)rightToLeft {
    CGSize size = [word.text sizeWithAttributes:@{NSFontAttributeName: font}];
    self = [super initWithFrame:CGRectMake(0, 0, ceil(size.width), ceil(font.lineHeight))];
    if (!self) return nil;
    _word = word;
    _riseStart = word.start;
    _riseEnd = word.end;
    _rightToLeft = rightToLeft;
    [self addSubview:wordLabel(word.text, font, [UIColor colorWithWhite:1 alpha:kDimAlpha], self.bounds, rightToLeft)];
    _lit = wordLabel(word.text, font, UIColor.whiteColor, self.bounds, rightToLeft);
    _lit.hidden = YES;
    [self addSubview:_lit];

    CGFloat width = self.bounds.size.width + kFillEdge;
    _fill = [CAGradientLayer layer];
    _fill.colors = @[(id)UIColor.whiteColor.CGColor, (id)UIColor.whiteColor.CGColor, (id)UIColor.clearColor.CGColor];
    _fill.locations = @[@0, @((width - kFillEdge) / width), @1];
    _fill.startPoint = CGPointMake(rightToLeft ? 1 : 0, 0.5);
    _fill.endPoint = CGPointMake(rightToLeft ? 0 : 1, 0.5);
    _lit.layer.mask = _fill;
    _filled = NAN;
    [self fillTo:-CGFLOAT_MAX];
    return self;
}

- (void)fillTo:(CGFloat)cursor {
    CGFloat width = self.bounds.size.width, height = self.bounds.size.height;
    CGFloat local = MAX(-kFillEdge / 2, MIN(width + kFillEdge / 2, cursor - _offset));
    if (local == _filled) return;
    _filled = local;
    CGFloat left = _rightToLeft ? width - local - kFillEdge / 2 : local - kFillEdge / 2 - width;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _fill.frame = CGRectMake(left, -height / 2, width + kFillEdge, height * 2);
    [CATransaction commit];
}

- (void)floatAt:(double)ms {
    double x = MAX(0, ms - _riseStart + kFloatLeadMs) / MAX(_riseEnd - _riseStart, kFloatMinMs) * 5;
    CGFloat lift = kLift * (1 - (1 + x) * exp(-x));
    if (lift == _lift) return;
    _lift = lift;
    self.transform = CGAffineTransformMakeTranslation(0, -lift);
}

- (void)settle {
    _lift = 0;
    self.transform = CGAffineTransformIdentity;
}

@end

#pragma mark - how a line is set

@interface SGRKaraokeStyle : NSObject
@property (nonatomic, readonly) NSArray<NSNumber *> *order;   // SGRLyricsText, largest first, shown ones only
@property (nonatomic, readonly) UIFont *lyrics, *pronunciation, *translation;   // nil for a text not shown
@property (nonatomic, readonly) SGRKaraokeStyle *backing;   // the backing row's: smaller, its translation read with the line's
- (instancetype)initWithSize:(CGFloat)size order:(NSArray<NSNumber *> *)order pronunciation:(BOOL)pronunciation translation:(BOOL)translation;
@end

// The second and third place's sizes, as shares of the first: Apple Music's 20 and 16 under its 30.
static const CGFloat kSecondShare = 0.67, kThirdShare = 0.54;

@implementation SGRKaraokeStyle

- (instancetype)initWithSize:(CGFloat)size order:(NSArray<NSNumber *> *)order pronunciation:(BOOL)pronunciation translation:(BOOL)translation {
    if (!(self = [super init])) return nil;
    CGFloat sizes[3] = {size, round(size * kSecondShare), round(size * kThirdShare)};
    NSMutableArray<NSNumber *> *shown = [NSMutableArray array];
    for (NSUInteger place = 0; place < order.count && place < 3; place++) {
        SGRLyricsText text = order[place].integerValue;
        if ((text == SGRLyricsTextPronunciation && !pronunciation) || (text == SGRLyricsTextTranslation && !translation)) continue;
        CGFloat points = shown.count ? sizes[place] : size;
        UIFont *font = [UIFont systemFontOfSize:points weight:text == SGRLyricsTextTranslation ? UIFontWeightSemibold : UIFontWeightBold];
        if (text == SGRLyricsTextLyrics) _lyrics = font;
        else if (text == SGRLyricsTextPronunciation) _pronunciation = font;
        else _translation = font;
        [shown addObject:@(text)];
    }
    if (!_lyrics) {   // an order without the lyrics in it is not one to trust
        _lyrics = [UIFont systemFontOfSize:size weight:UIFontWeightBold];
        [shown insertObject:@(SGRLyricsTextLyrics) atIndex:0];
    }
    _order = shown;
    return self;
}

- (SGRKaraokeStyle *)backing {
    SGRKaraokeStyle *backing = [SGRKaraokeStyle new];
    backing->_lyrics = [UIFont systemFontOfSize:round(_lyrics.pointSize * kBackingScale) weight:UIFontWeightBold];
    if (_pronunciation) backing->_pronunciation = [UIFont systemFontOfSize:round(_pronunciation.pointSize * kBackingScale) weight:UIFontWeightBold];
    NSMutableArray<NSNumber *> *order = [_order mutableCopy];
    [order removeObject:@(SGRLyricsTextTranslation)];
    backing->_order = order;
    return backing;
}

@end

#pragma mark - where a line's words go

static const CGFloat kPairTighten = 2, kPairGap = 4, kPartGap = 6;

@interface SGRKaraokeLayout : NSObject
@property (nonatomic) BOOL right;
@property (nonatomic) CGFloat height;
@property (nonatomic, copy) NSArray<NSValue *> *lyricFrames, *spokenFrames;
@property (nonatomic, copy) NSArray<NSNumber *> *lyricOffsets, *spokenOffsets;
@property (nonatomic) CGRect translation;   // CGRectNull without one
@property (nonatomic) CGFloat backingTop;   // 0 without a backing row
@end

@implementation SGRKaraokeLayout
@end

typedef struct {
    CGFloat x, width, offset;
    NSUInteger row;
} SGRPlace;

static NSUInteger flow(NSArray<SGKaraokeWord *> *words, UIFont *font, CGFloat width, SGRPlace *places) {
    CGFloat space = ceil([@" " sizeWithAttributes:@{NSFontAttributeName: font}].width), x = 0, offset = 0;
    NSUInteger row = 0;
    for (NSUInteger i = 0; i < words.count; i++) {
        CGFloat wide = ceil([words[i].text sizeWithAttributes:@{NSFontAttributeName: font}].width);
        CGFloat lead = x > 0 && !words[i].joined ? space : 0;
        if (x > 0 && x + lead + wide > width) {
            x = lead = 0;
            row++;
        }
        x += lead;
        offset += lead;
        places[i] = (SGRPlace){x, wide, offset, row};
        x += wide;
        offset += wide;
    }
    return words.count ? row + 1 : 0;
}

static void settle(CGRect *frames, NSUInteger *groups, NSUInteger count, NSUInteger groupCount, CGFloat width, BOOL rightToLeft, BOOL right) {
    if (rightToLeft) {
        for (NSUInteger i = 0; i < count; i++) frames[i].origin.x = width - CGRectGetMaxX(frames[i]);
    }
    for (NSUInteger g = 0; g < groupCount; g++) {
        CGRect extent = CGRectNull;
        for (NSUInteger i = 0; i < count; i++) {
            if (groups[i] == g) extent = CGRectUnion(extent, frames[i]);
        }
        if (CGRectIsNull(extent)) continue;
        CGFloat shift = right ? width - CGRectGetMaxX(extent) : -CGRectGetMinX(extent);
        if (right ? shift <= 0 : shift >= 0) continue;
        for (NSUInteger i = 0; i < count; i++) {
            if (groups[i] == g) frames[i].origin.x += shift;
        }
    }
}

static NSArray<NSValue *> *boxedFrames(CGRect *frames, NSUInteger count) {
    NSMutableArray<NSValue *> *boxed = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger i = 0; i < count; i++) [boxed addObject:[NSValue valueWithCGRect:frames[i]]];
    return boxed;
}

static NSArray<NSNumber *> *offsetsOf(SGRPlace *places, NSUInteger count) {
    NSMutableArray<NSNumber *> *offsets = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger i = 0; i < count; i++) [offsets addObject:@(places[i].offset)];
    return offsets;
}

// A text of words on its own, from `top`; returns where it ends.
static CGFloat layRun(NSArray<SGKaraokeWord *> *words, UIFont *font, CGFloat width, BOOL right, CGFloat top,
                      NSArray<NSValue *> **frames, NSArray<NSNumber *> **offsets) {
    NSUInteger count = words.count;
    SGRPlace *places = calloc(count + 1, sizeof(SGRPlace));
    CGRect *rects = calloc(count + 1, sizeof(CGRect));
    NSUInteger *groups = calloc(count + 1, sizeof(NSUInteger));
    NSUInteger rows = flow(words, font, width, places);
    CGFloat row = ceil(font.lineHeight) - kRowTighten, high = ceil(font.lineHeight);
    for (NSUInteger i = 0; i < count; i++) {
        rects[i] = CGRectMake(places[i].x, top + places[i].row * row, places[i].width, high);
        groups[i] = places[i].row;
    }
    NSMutableString *text = [NSMutableString string];
    for (SGKaraokeWord *word in words) [text appendString:word.text];
    settle(rects, groups, count, rows, width, readsRightToLeft(text), right);
    *frames = boxedFrames(rects, count);
    *offsets = offsetsOf(places, count);
    free(places);
    free(rects);
    free(groups);
    return top + (rows ? rows - 1 : 0) * row + high;
}

static CGFloat layPair(NSArray<SGKaraokeWord *> *lead, UIFont *leadFont, NSArray<SGKaraokeWord *> *under, UIFont *underFont,
                       CGFloat width, BOOL right, CGFloat top, NSArray<NSValue *> **leadFrames, NSArray<NSNumber *> **leadOffsets,
                       NSArray<NSValue *> **underFrames, NSArray<NSNumber *> **underOffsets) {
    NSUInteger leads = lead.count, unders = under.count, count = leads + unders;
    SGRPlace *places = calloc(count + 1, sizeof(SGRPlace));
    CGRect *rects = calloc(count + 1, sizeof(CGRect));
    NSUInteger *groups = calloc(count + 1, sizeof(NSUInteger));
    NSUInteger rows = flow(lead, leadFont, width, places);
    flow(under, underFont, width, places + leads);   // for their places along their own sweep
    // The leading word each one goes under: the last to start by the time it does.
    NSUInteger *matched = calloc(unders + 1, sizeof(NSUInteger));
    for (NSUInteger j = 0, i = 0; j < unders; j++) {
        while (i + 1 < leads && lead[i + 1].start <= under[j].start) i++;
        matched[j] = i;
    }
    CGFloat leadRow = ceil(leadFont.lineHeight) - kRowTighten, leadHigh = ceil(leadFont.lineHeight);
    CGFloat underRow = ceil(underFont.lineHeight) - kRowTighten, underHigh = ceil(underFont.lineHeight);
    CGFloat space = ceil([@" " sizeWithAttributes:@{NSFontAttributeName: underFont}].width);
    CGFloat y = top, bottom = top;
    NSUInteger j = 0;
    for (NSUInteger r = 0; r < rows; r++) {
        for (NSUInteger i = 0; i < leads; i++) {
            if (places[i].row != r) continue;
            rects[i] = CGRectMake(places[i].x, y, places[i].width, leadHigh);
            groups[i] = r;
        }
        bottom = y + leadHigh;
        NSUInteger from = j, until = j;
        while (until < unders && places[matched[until]].row == r) until++;
        CGFloat underTop = y + leadHigh - kPairTighten, reached = 0;
        BOOL fits = YES;
        for (NSUInteger k = from; k < until && fits; k++) {
            BOOL flush = k > from && under[k].joined;
            CGFloat x = flush ? reached : MAX(places[matched[k]].x, reached + (reached > 0 ? space : 0));
            rects[leads + k] = CGRectMake(x, underTop, places[leads + k].width, underHigh);
            reached = x + places[leads + k].width;
            fits = reached <= width;
        }
        NSUInteger subRow = 0;
        if (!fits) {
            reached = 0;
            for (NSUInteger k = from; k < until; k++) {
                CGFloat wide = places[leads + k].width, lead = reached > 0 && !under[k].joined ? space : 0;
                if (reached > 0 && reached + lead + wide > width) {
                    subRow++;
                    reached = lead = 0;
                }
                rects[leads + k] = CGRectMake(reached + lead, underTop + subRow * underRow, wide, underHigh);
                reached += lead + wide;
            }
        }
        for (NSUInteger k = from; k < until; k++) groups[leads + k] = r;
        j = until;
        BOOL any = until > from;
        if (any) bottom = underTop + subRow * underRow + underHigh;
        y = any ? bottom + kPairGap : y + leadRow;
    }
    NSMutableString *text = [NSMutableString string];
    for (SGKaraokeWord *word in lead) [text appendString:word.text];
    settle(rects, groups, count, rows, width, readsRightToLeft(text), right);
    *leadFrames = boxedFrames(rects, leads);
    *underFrames = boxedFrames(rects + leads, unders);
    *leadOffsets = offsetsOf(places, leads);
    *underOffsets = offsetsOf(places + leads, unders);
    free(places);
    free(rects);
    free(groups);
    free(matched);
    return bottom;
}

static SGRKaraokeLayout *layOut(SGKaraokeLine *line, CGFloat width, SGRKaraokeStyle *style, NSInteger right) {
    SGRKaraokeLayout *layout = [SGRKaraokeLayout new];
    layout.right = right >= 0 ? right : alignsRight(line);
    layout.translation = CGRectNull;
    NSArray<SGKaraokeWord *> *spoken = style.pronunciation ? line.pronunciation.words : nil;
    NSString *translation = style.translation ? line.translation : nil;
    NSMutableArray<NSNumber *> *parts = [NSMutableArray array];
    for (NSNumber *text in style.order) {
        if (text.integerValue == SGRLyricsTextPronunciation && !spoken.count) continue;
        if (text.integerValue == SGRLyricsTextTranslation && !translation.length) continue;
        [parts addObject:text];
    }
    NSArray<NSValue *> *frames;
    NSArray<NSNumber *> *offsets;
    CGFloat y = 0;
    for (NSUInteger p = 0; p < parts.count; p++) {
        SGRLyricsText text = parts[p].integerValue;
        if (p > 0) y += kPartGap;
        if (text == SGRLyricsTextTranslation) {
            CGRect bounds = [translation boundingRectWithSize:CGSizeMake(width, CGFLOAT_MAX) options:NSStringDrawingUsesLineFragmentOrigin
                                                   attributes:@{NSFontAttributeName: style.translation} context:nil];
            layout.translation = CGRectMake(0, y, width, ceil(bounds.size.height));
            y = CGRectGetMaxY(layout.translation);
            continue;
        }
        BOOL lyrics = text == SGRLyricsTextLyrics;
        BOOL paired = p + 1 < parts.count && parts[p + 1].integerValue != SGRLyricsTextTranslation;
        if (paired) {
            NSArray<NSValue *> *pairedFrames;
            NSArray<NSNumber *> *pairedOffsets;
            y = layPair(lyrics ? line.words : spoken, lyrics ? style.lyrics : style.pronunciation,
                        lyrics ? spoken : line.words, lyrics ? style.pronunciation : style.lyrics,
                        width, layout.right, y, &frames, &offsets, &pairedFrames, &pairedOffsets);
            layout.lyricFrames = lyrics ? frames : pairedFrames;
            layout.lyricOffsets = lyrics ? offsets : pairedOffsets;
            layout.spokenFrames = lyrics ? pairedFrames : frames;
            layout.spokenOffsets = lyrics ? pairedOffsets : offsets;
            p++;
            lyrics = YES;
        } else {
            y = layRun(lyrics ? line.words : spoken, lyrics ? style.lyrics : style.pronunciation, width, layout.right, y, &frames, &offsets);
            if (lyrics) {
                layout.lyricFrames = frames;
                layout.lyricOffsets = offsets;
            } else {
                layout.spokenFrames = frames;
                layout.spokenOffsets = offsets;
            }
        }
        if (lyrics && right < 0 && line.backing.words.count) {
            layout.backingTop = y + kBackingGap;
            y = layout.backingTop + layOut(line.backing, width, style.backing, layout.right).height;
        }
    }
    layout.height = y;
    return layout;
}

static NSArray<NSNumber *> *topsOf(NSArray<SGKaraokeLine *> *lines, CGFloat width, SGRKaraokeStyle *style, CGFloat gap) {
    NSMutableArray<NSNumber *> *tops = [NSMutableArray arrayWithCapacity:lines.count];
    CGFloat top = 0;
    for (SGKaraokeLine *line in lines) {
        [tops addObject:@(top)];
        top += layOut(line, width, style, -1).height + gap;
    }
    return tops;
}

#pragma mark - a sweep

typedef struct {
    double ms, x, slope;
} SGSweepKnot;

@interface SGRKaraokeSweep : NSObject
@property (nonatomic, readonly) NSArray<SGRKaraokeWordView *> *words;
- (instancetype)initWithWords:(NSArray<SGRKaraokeWordView *> *)words wholeFrom:(double)start;
- (void)showTime:(double)ms;
@end

@implementation SGRKaraokeSweep {
    SGSweepKnot *_knots;
    NSUInteger _knotCount;
    BOOL _whole;
}

// start: NAN to sweep the words by their own times.
- (instancetype)initWithWords:(NSArray<SGRKaraokeWordView *> *)words wholeFrom:(double)start {
    if (!(self = [super init])) return nil;
    _words = words;
    _whole = !isnan(start);
    if (_whole) {
        for (SGRKaraokeWordView *word in words) {
            word.whole = YES;
            word.riseStart = start;
            word.riseEnd = start + kWholeRiseMs;
        }
        return self;
    }
    [self buildSweep];
    return self;
}

- (void)dealloc {
    free(_knots);
}

static double secant(SGSweepKnot *knots, NSUInteger i) {
    return (knots[i + 1].x - knots[i].x) / (knots[i + 1].ms - knots[i].ms);
}

- (void)buildSweep {
    _knots = calloc(_words.count + 1, sizeof(SGSweepKnot));
    if (!_words.count) return;
    for (NSUInteger i = 0; i <= _words.count; i++) {
        SGRKaraokeWordView *word = _words[MIN(i, _words.count - 1)];
        double ms = i < _words.count ? word.word.start : word.word.end;
        double x = i == 0 ? -kFillEdge / 2 : i < _words.count ? word.offset : word.offset + word.bounds.size.width + kFillEdge / 2;
        if (_knotCount && ms <= _knots[_knotCount - 1].ms) {
            _knots[_knotCount - 1].x = x;
            continue;
        }
        _knots[_knotCount++] = (SGSweepKnot){ms, x, 0};
    }
    // Fritsch-Carlson slopes: capped so the cursor never runs backwards or overshoots a word.
    for (NSUInteger k = 0; k < _knotCount; k++) {
        BOOL first = k == 0, last = k + 1 == _knotCount;
        if (first && last) break;
        if (first || last) {
            _knots[k].slope = secant(_knots, first ? 0 : k - 1);
            continue;
        }
        double before = secant(_knots, k - 1), after = secant(_knots, k);
        double h0 = _knots[k].ms - _knots[k - 1].ms, h1 = _knots[k + 1].ms - _knots[k].ms;
        _knots[k].slope = MIN(MIN(2 * before, 2 * after), (before * h1 + after * h0) / (h0 + h1));
    }
}

- (CGFloat)cursorAt:(double)ms {
    if (!_knotCount) return -CGFLOAT_MAX;
    if (ms <= _knots[0].ms) return _knots[0].x;
    if (_knotCount == 1 || ms >= _knots[_knotCount - 1].ms) return _knots[_knotCount - 1].x;
    NSUInteger k = 0;
    while (ms >= _knots[k + 1].ms) k++;
    SGSweepKnot a = _knots[k], b = _knots[k + 1];
    double h = b.ms - a.ms, u = (ms - a.ms) / h, u2 = u * u, u3 = u2 * u;
    return (2 * u3 - 3 * u2 + 1) * a.x + (u3 - 2 * u2 + u) * h * a.slope
         + (3 * u2 - 2 * u3) * b.x + (u3 - u2) * h * b.slope;
}

- (void)showTime:(double)ms {
    // A whole run is only ever shown while its line is sung, so it is lit throughout.
    CGFloat cursor = _whole ? CGFLOAT_MAX : [self cursorAt:ms];
    for (SGRKaraokeWordView *word in _words) {
        [word fillTo:cursor];
        [word floatAt:ms];
    }
}

@end

#pragma mark - a line

@interface SGRKaraokeLineView : UIView
@property (nonatomic, readonly) SGKaraokeLine *line;
@property (nonatomic, readonly) BOOL right;
@property (nonatomic) BOOL active;
@property (nonatomic) CGFloat blur;
- (instancetype)initWithLine:(SGKaraokeLine *)line width:(CGFloat)width style:(SGRKaraokeStyle *)style under:(SGRKaraokeLineView *)under
                     blurred:(BOOL)blurred sweepsEstimates:(BOOL)sweepsEstimates;
- (void)showTime:(double)ms;
// Every word lit and left so, for lyrics with no timing: nothing is sung, so nothing is dim.
- (void)showPlain;
- (void)markMeaning:(NSArray<SGLyricsMeaning *> *)meanings;
// Where the bubble can be tapped, in the line's own space; CGRectNull without one.
@property (nonatomic, readonly) CGRect bubbleTarget;
@end

// The translation of a line being sung, brighter than a line waiting but never as bright as the words.
static const CGFloat kTranslationLit = 0.6;

@implementation SGRKaraokeLineView {
    NSArray<SGRKaraokeSweep *> *_sweeps;   // the line's words, then their pronunciation's where shown
    NSArray<SGRKaraokeWordView *> *_words;   // every word of both
    NSArray<SGRKaraokeWordView *> *_lyricWords;
    UIImageView *_bubble;
    CAShapeLayer *_underline;
    UILabel *_translation;
    NSUInteger _generation;
    SGRKaraokeLineView *_backing;
}

- (SGRKaraokeSweep *)sweepOf:(NSArray<SGKaraokeWord *> *)words font:(UIFont *)font frames:(NSArray<NSValue *> *)frames
                     offsets:(NSArray<NSNumber *> *)offsets wholeFrom:(double)start {
    if (!words.count || frames.count != words.count) return nil;
    BOOL rightToLeft = readsRightToLeft([[words valueForKey:@"text"] componentsJoinedByString:@""]);
    NSMutableArray<SGRKaraokeWordView *> *views = [NSMutableArray arrayWithCapacity:words.count];
    for (NSUInteger i = 0; i < words.count; i++) {
        SGRKaraokeWordView *view = [[SGRKaraokeWordView alloc] initWithWord:words[i] font:font rightToLeft:rightToLeft];
        CGRect frame = frames[i].CGRectValue;
        view.center = CGPointMake(CGRectGetMidX(frame), CGRectGetMidY(frame));
        view.offset = offsets[i].doubleValue;
        [self addSubview:view];
        [views addObject:view];
    }
    return [[SGRKaraokeSweep alloc] initWithWords:views wholeFrom:start];
}

static double wholeFrom(SGKaraokeLine *run, BOOL sweepsEstimates) {
    if (run.timing == SGKaraokeTimingWords || (run.timing == SGKaraokeTimingLine && sweepsEstimates)) return NAN;
    return run.start;
}

- (instancetype)initWithLine:(SGKaraokeLine *)line width:(CGFloat)width style:(SGRKaraokeStyle *)style under:(SGRKaraokeLineView *)under
                     blurred:(BOOL)blurred sweepsEstimates:(BOOL)sweepsEstimates {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    _line = line;
    BOOL backing = under != nil;
    SGRKaraokeLayout *layout = layOut(line, width, style, backing ? under.right : -1);
    _right = layout.right;
    NSMutableArray<SGRKaraokeSweep *> *sweeps = [NSMutableArray array];
    SGRKaraokeSweep *sung = [self sweepOf:line.words font:style.lyrics frames:layout.lyricFrames offsets:layout.lyricOffsets
                                wholeFrom:wholeFrom(line, sweepsEstimates)];
    SGRKaraokeSweep *spoken = [self sweepOf:line.pronunciation.words font:style.pronunciation frames:layout.spokenFrames
                                    offsets:layout.spokenOffsets wholeFrom:wholeFrom(line.pronunciation, sweepsEstimates)];
    if (sung) [sweeps addObject:sung];
    if (spoken) [sweeps addObject:spoken];
    _sweeps = sweeps;
    _words = [sung.words ?: @[] arrayByAddingObjectsFromArray:spoken.words ?: @[]];
    _lyricWords = sung.words;

    if (!CGRectIsNull(layout.translation)) {
        _translation = [[UILabel alloc] initWithFrame:layout.translation];
        _translation.numberOfLines = 0;
        _translation.font = style.translation;
        _translation.textColor = UIColor.whiteColor;
        _translation.alpha = kDimAlpha;
        _translation.textAlignment = _right ? NSTextAlignmentRight : NSTextAlignmentLeft;
        _translation.text = line.translation;
        [self addSubview:_translation];
    }
    if (layout.backingTop > 0) {
        _backing = [[SGRKaraokeLineView alloc] initWithLine:line.backing width:width style:style.backing under:self blurred:NO
                                            sweepsEstimates:sweepsEstimates];
        _backing.alpha = kBackingAlpha;
        _backing.frame = CGRectMake(0, layout.backingTop, width, _backing.bounds.size.height);
        [self addSubview:_backing];
    }
    self.frame = CGRectMake(0, 0, width, layout.height);

    // Scales toward the edge its text is aligned to, and a backing row rides its line's blur.
    if (backing) return self;
    self.layer.anchorPoint = CGPointMake(_right ? 1 : 0, 0.5);
    if (!blurred) return self;
    CAFilter *blur = [NSClassFromString(@"CAFilter") filterWithType:@"gaussianBlur"];
    if (blur) self.layer.filters = @[blur];
    return self;
}

// How many line views are made in one frame: the rest follow on the next, nearest the sung line first.
static const NSUInteger kLinesPerFrame = 4;

// Eases from wherever the blur is on screen, so a line coming into focus sharpens instead of snapping.
- (void)setBlur:(CGFloat)blur {
    if (blur == _blur) return;
    id shown = [self.layer.presentationLayer valueForKeyPath:kBlurPath];
    CGFloat from = [shown isKindOfClass:NSNumber.class] ? [shown doubleValue] : _blur;
    _blur = blur;
    if (!self.layer.filters) return;
    [self.layer setValue:@(blur) forKeyPath:kBlurPath];
    CABasicAnimation *ease = [CABasicAnimation animationWithKeyPath:kBlurPath];
    ease.fromValue = @(from);
    ease.toValue = @(blur);
    ease.duration = 0.6;
    ease.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [self.layer addAnimation:ease forKey:@"blur"];
}

- (void)setActive:(BOOL)active {
    if (active == _active) return;
    _active = active;
    _backing.active = active;
    NSUInteger generation = ++_generation;
    if (_translation) {
        [UIView animateWithDuration:active ? 0.3 : 0.5 delay:0 options:UIViewAnimationOptionBeginFromCurrentState
                         animations:^{ self->_translation.alpha = active ? kTranslationLit : kDimAlpha; } completion:nil];
    }
    if (active) {
        NSMutableArray<SGRKaraokeWordView *> *whole = [NSMutableArray array];
        for (SGRKaraokeWordView *word in _words) {
            [word.layer removeAllAnimations];
            [word.lit.layer removeAllAnimations];
            word.lit.alpha = 1;
            word.lit.hidden = NO;
            [word fillTo:word.whole ? CGFLOAT_MAX : -CGFLOAT_MAX];
            [word settle];
            if (word.whole) [whole addObject:word];
        }
        // A line lit whole comes up to white together rather than popping on, as Apple Music's do.
        if (!whole.count) return;
        for (SGRKaraokeWordView *word in whole) word.lit.alpha = 0;
        [UIView animateWithDuration:kWholeFade delay:0 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                         animations:^{ for (SGRKaraokeWordView *word in whole) word.lit.alpha = 1; } completion:nil];
        return;
    }
    [UIView animateWithDuration:0.9 delay:0 usingSpringWithDamping:1 initialSpringVelocity:0
                        options:UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        for (SGRKaraokeWordView *word in self->_words) [word settle];
    } completion:nil];
    [UIView animateWithDuration:0.5 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        for (SGRKaraokeWordView *word in self->_words) word.lit.alpha = 0;
    } completion:^(BOOL finished) {
        if (generation != self->_generation) return;
        for (SGRKaraokeWordView *word in self->_words) {
            [word fillTo:-CGFLOAT_MAX];
            word.lit.hidden = YES;
            word.lit.alpha = 1;
        }
    }];
}

- (void)showTime:(double)ms {
    for (SGRKaraokeSweep *sweep in _sweeps) [sweep showTime:ms];
    [_backing showTime:ms];   // timed on its own, so it lags the line as it is sung
}

- (void)showPlain {
    for (SGRKaraokeWordView *word in _words) {
        word.lit.hidden = NO;
        word.lit.alpha = 1;
        [word fillTo:CGFLOAT_MAX];
    }
    _translation.alpha = kTranslationLit;
    [_backing showPlain];
}

- (CGRect)bubbleTarget {
    return _bubble ? CGRectInset(_bubble.frame, -kBubbleReach, -kBubbleReach) : CGRectNull;
}

- (void)markMeaning:(NSArray<SGLyricsMeaning *> *)meanings {
    [_bubble removeFromSuperview];
    _bubble = nil;
    [_underline removeFromSuperlayer];
    _underline = nil;
    if (!meanings.count || !_lyricWords.count) return;
    if (meanings.firstObject.author == SGLyricsMeaningByArtist) {
        SGRKaraokeWordView *last = _lyricWords.lastObject;
        BOOL rightToLeft = readsRightToLeft(SGKaraokeLineText(_line));
        CGRect word = CGRectMake(last.center.x - last.bounds.size.width / 2, last.center.y - last.bounds.size.height / 2,
                                 last.bounds.size.width, last.bounds.size.height);
        CGFloat x = rightToLeft ? CGRectGetMinX(word) - kBubbleGap - kBubbleSide : CGRectGetMaxX(word) + kBubbleGap;
        UIImage *glyph = [UIImage systemImageNamed:@"quote.opening" withConfiguration:
                          [UIImageSymbolConfiguration configurationWithPointSize:kBubbleGlyph weight:UIImageSymbolWeightBold]];
        _bubble = [[UIImageView alloc] initWithImage:glyph];
        _bubble.contentMode = UIViewContentModeCenter;
        _bubble.tintColor = UIColor.blackColor;
        _bubble.backgroundColor = UIColor.whiteColor;
        _bubble.layer.cornerRadius = kBubbleSide / 2;
        _bubble.alpha = kBubbleAlpha;
        _bubble.frame = CGRectMake(x, CGRectGetMidY(word) - kBubbleSide / 2, kBubbleSide, kBubbleSide);
        _bubble.isAccessibilityElement = YES;
        _bubble.accessibilityLabel = @"Meaning from the artist";
        [self addSubview:_bubble];
        return;
    }
    // One dotted stroke under each row the line's words wrap onto.
    UIBezierPath *path = [UIBezierPath bezierPath];
    CGFloat rowY = NAN, from = 0, to = 0;
    for (SGRKaraokeWordView *word in _lyricWords) {
        CGFloat bottom = word.center.y + word.bounds.size.height / 2 + kUnderlineDrop;
        CGFloat left = word.center.x - word.bounds.size.width / 2, right = left + word.bounds.size.width;
        if (bottom != rowY) {
            if (!isnan(rowY)) {
                [path moveToPoint:CGPointMake(from, rowY)];
                [path addLineToPoint:CGPointMake(to, rowY)];
            }
            rowY = bottom;
            from = left;
            to = right;
            continue;
        }
        from = MIN(from, left);
        to = MAX(to, right);
    }
    [path moveToPoint:CGPointMake(from, rowY)];
    [path addLineToPoint:CGPointMake(to, rowY)];
    _underline = [CAShapeLayer layer];
    _underline.path = path.CGPath;
    _underline.strokeColor = [UIColor colorWithWhite:1 alpha:kUnderlineAlpha].CGColor;
    _underline.lineWidth = kUnderlineWidth;
    _underline.lineCap = kCALineCapRound;
    _underline.lineDashPattern = @[@0, @5];
    [self.layer insertSublayer:_underline atIndex:0];
}

@end

#pragma mark - a break

@interface SGRKaraokeBreakView : UIView
@property (nonatomic) BOOL right;         // against the right edge, where the line after it is
@property (nonatomic) BOOL rightToLeft;   // filling from the right, the way the line after it reads
- (instancetype)initWithFont:(UIFont *)font;
- (void)playFrom:(NSInteger)start to:(NSInteger)end;
- (void)showTime:(double)ms running:(BOOL)running at:(CFTimeInterval)shown;
@end

static const CFTimeInterval kBreakEpoch = 1;

static void atFullRate(CAAnimation *animation) {
    animation.preferredFrameRateRange = CAFrameRateRangeMake(80, 120, 120);
}

static double easeOutExpo(double p) {
    return p <= 0 ? 0 : p >= 1 ? 1 : 1 - pow(2, -10 * p);
}

static double smoothstep(double p) {
    p = MAX(0, MIN(1, p));
    return p * p * (3 - 2 * p);
}

@implementation SGRKaraokeBreakView {
    CALayer *_clock, *_group;
    NSArray<CALayer *> *_dots;
    NSInteger _start;
    CGFloat _side, _gap;
}

- (instancetype)initWithFont:(UIFont *)font {
    self = [super initWithFrame:CGRectMake(0, 0, 0, ceil(font.lineHeight))];
    if (!self) return nil;
    self.userInteractionEnabled = NO;
    _side = round(font.pointSize * kDotShare);
    _gap = round(font.pointSize * kDotGapShare);
    _clock = [CALayer layer];
    _group = [CALayer layer];
    _group.bounds = CGRectMake(0, 0, 3 * _side + 2 * _gap, _side);
    NSMutableArray<CALayer *> *dots = [NSMutableArray array];
    for (NSUInteger i = 0; i < 3; i++) {
        CALayer *dot = [CALayer layer];
        dot.frame = CGRectMake(i * (_side + _gap), 0, _side, _side);
        dot.cornerRadius = _side / 2;
        dot.backgroundColor = UIColor.whiteColor.CGColor;
        dot.opacity = kDimAlpha;
        [_group addSublayer:dot];
        [dots addObject:dot];
    }
    _dots = dots;
    _group.opacity = 0;
    [_clock addSublayer:_group];
    [self.layer addSublayer:_clock];
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    CGSize size = self.bounds.size, group = _group.bounds.size;
    _clock.frame = self.bounds;
    _group.position = CGPointMake(_right ? size.width - group.width / 2 : group.width / 2, size.height / 2);
    [CATransaction commit];
}

- (void)setRight:(BOOL)right {
    if (right == _right) return;
    _right = right;
    [self setNeedsLayout];
}

- (void)playFrom:(NSInteger)start to:(NSInteger)end {
    _start = start;
    [_group removeAllAnimations];
    for (CALayer *dot in _dots) [dot removeAllAnimations];
    double length = (end - start) / 1000.0;
    double exitAt = MAX(kBreakWait + kBreakIn, length - kBreakCollapse - kBreakOut), over = exitAt + kBreakOut;
    BOOL still = SGRReduceMotion();   // no breath and no swell, only the fades and the fill
    NSMutableArray<NSNumber *> *times = [NSMutableArray array], *scales = [NSMutableArray array], *alphas = [NSMutableArray array];
    void (^sample)(double) = ^(double t) {
        double cycle = 2 * kBreathHalf, phase = fmod(t + kBreathHalf - fmod(exitAt, cycle) + cycle, cycle);
        double low = (1 - cos(M_PI * phase / kBreathHalf)) / 2;
        double scale = (kBreathHigh + (kBreathLow - kBreathHigh) * low) * easeOutExpo((t - kBreakWait) / kBreakIn);
        double alpha = MAX(0, MIN(1, (t - kBreakWait) / kBreakFadeIn));
        if (t >= exitAt) {
            double p = (t - exitAt) / kBreakOut;
            BOOL swelling = p <= kBreakSwellShare;
            double eased = smoothstep(swelling ? p / kBreakSwellShare : (p - kBreakSwellShare) / (1 - kBreakSwellShare));
            scale = swelling ? kBreathLow + (kBreakSwell - kBreathLow) * eased : kBreakSwell * (1 - eased);
            alpha = swelling ? 1 : 1 - eased;
        }
        [times addObject:@(t / over)];
        [scales addObject:@(still ? 1 : MAX(scale, 0.001))];
        [alphas addObject:@(alpha)];
    };
    for (double t = 0; t < kBreakWait + kBreakIn; t += 0.025) sample(t);
    for (double t = kBreakWait + kBreakIn; t < exitAt; t += 0.2) sample(t);
    for (double t = exitAt; t < over; t += 0.02) sample(t);
    sample(over);

    CAKeyframeAnimation *scale = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale"];
    CAKeyframeAnimation *alpha = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
    scale.values = scales;
    alpha.values = alphas;
    for (CAKeyframeAnimation *run in @[scale, alpha]) {
        run.keyTimes = times;
        run.duration = over;
        run.beginTime = kBreakEpoch;
        run.fillMode = kCAFillModeBoth;
        run.removedOnCompletion = NO;
        atFullRate(run);
        [_group addAnimation:run forKey:run.keyPath];
    }
    // Each dot fills over its third of the time before they go, in the order the next line reads.
    for (NSUInteger i = 0; i < _dots.count; i++) {
        CABasicAnimation *fill = [CABasicAnimation animationWithKeyPath:@"opacity"];
        fill.fromValue = @(kDimAlpha);
        fill.toValue = @1;
        fill.beginTime = kBreakEpoch + (_rightToLeft ? _dots.count - 1 - i : i) * exitAt / 3;
        fill.duration = exitAt / 3;
        fill.fillMode = kCAFillModeBoth;
        fill.removedOnCompletion = NO;
        atFullRate(fill);
        [_dots[i] addAnimation:fill forKey:@"fill"];
    }
}

- (void)showTime:(double)ms running:(BOOL)running at:(CFTimeInterval)shown {
    double local = kBreakEpoch + (ms - _start) / 1000.0;
    CFTimeInterval parent = [self.layer convertTime:shown fromLayer:nil];
    BOOL stopped = _clock.speed == 0;
    double now = stopped ? _clock.timeOffset : (parent - _clock.beginTime) * _clock.speed + _clock.timeOffset;
    if (stopped != running && fabs(now - local) < kBreakSlack) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (running) {
        _clock.speed = 1;
        _clock.timeOffset = 0;
        _clock.beginTime = parent - local;
    } else {
        _clock.speed = 0;
        _clock.beginTime = 0;
        _clock.timeOffset = local;
    }
    [CATransaction commit];
}

@end

#pragma mark - the page

// When each line is sung, kept apart from the lines so the page can ask on every frame.
typedef struct {
    NSInteger start, end;   // its start, and when it is sung out (SGKaraokeSungEnd)
} SGRKaraokeSpan;

// A pause long enough for the dots, and the line after it.
typedef struct {
    NSInteger start, end, line;
} SGRKaraokeBreak;

@interface SGRKaraokeView () <UIScrollViewDelegate>
@end

@implementation SGRKaraokeView {
    UIScrollView *_scroll;
    BOOL _browsing;
    CADisplayLink *_link;
    NSString *_track;
    NSArray<SGKaraokeLine *> *_lines;
    // The song is placed from its lines' heights alone; views exist for the lines in and near sight.
    NSArray<NSNumber *> *_tops;   // where each line starts in the stack
    NSMutableDictionary<NSNumber *, SGRKaraokeLineView *> *_shown;   // the views there are, by line
    CGFloat _focusTop;            // the top of the line the stack is arranged around
    CGFloat _sightOffset, _sightFocus;   // what the views in sight were last chosen for
    NSUInteger _sightArrangement;
    NSUInteger _build;   // counts the songs and widths measured, so a measurement that is late is dropped
    UIFont *_font;
    SGRKaraokeSpan *_spans;
    SGRKaraokeBreak *_breaks;
    NSUInteger _breakCount;
    NSInteger _sung[kMostSung];
    NSUInteger _sungCount;
    NSInteger _focus;       // the line the stack is arranged around, -1 before the first
    NSInteger _openBreak;   // the line the open break comes before, -1 while no break is open
    NSUInteger _arrangement;   // counts the changes to the three above, for the views in sight
    SGRKaraokeBreakView *_dots;
    NSInteger _dotsLine;   // the line the break the dots are timed for comes before
    CFTimeInterval _stillSince;   // when the position stopped moving, 0 while it moves
    SGRKaraokeStyle *_style;   // how the lines were laid out
    BOOL _hasSpoken, _hasTranslation;   // whether the song has any line with either
    UIButton *_extras;
    CGFloat _builtWidth;
    BOOL _showing;
    CAGradientLayer *_fade;
    UILabel *_credit;
    CGFloat _fontSize, _margin, _lineGap, _blurPerLine, _maxBlur;
    BOOL _crediting;   // the switch is read once: the page asks for the source on every frame until it has one
    double _clock;
    NSInteger _reported;
    CFTimeInterval _clockTime;
    BOOL _sweepsEstimates;   // the Lyrics page's "Simulate word-by-word timing", read once like the credit
    BOOL _plain;             // the song has no timing at all: every line lit, nothing follows the clock
    NSDictionary<NSNumber *, NSArray<SGLyricsMeaning *> *> *_meanings;   // Genius's, by line
    NSUInteger _meaningsAsked;
    // The room the lines have (lineInsets), and the fade's edges on their way to it from _bandFrom.
    UIEdgeInsets _band, _bandFrom;
    CFTimeInterval _bandSince, _bandFor;
    BOOL _compact;   // the small preview under the player's cover: no credit, no extras, no scrolling
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.hidden = YES;
    _focus = _openBreak = -1;
    _fontSize = kFontSize;
    _margin = kMargin;
    _lineGap = kLineGap;
    _blurPerLine = kBlurPerLine;
    _maxBlur = kMaxBlur;
    _shown = [NSMutableDictionary dictionary];
    _sightArrangement = NSUIntegerMax;
    _fade = [CAGradientLayer layer];
    _fade.colors = @[(id)UIColor.clearColor.CGColor, (id)UIColor.whiteColor.CGColor,
                     (id)UIColor.whiteColor.CGColor, (id)UIColor.clearColor.CGColor];
    _fade.locations = @[@0, @(kEdgeFade), @(1 - kEdgeFade), @1];
    _scroll = [[UIScrollView alloc] initWithFrame:self.bounds];
    _scroll.layer.mask = _fade;
    _scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _scroll.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    _scroll.showsVerticalScrollIndicator = NO;
    _scroll.alwaysBounceVertical = YES;
    _scroll.scrollsToTop = NO;
    _scroll.delegate = self;
    [self addSubview:_scroll];
    _credit = [[UILabel alloc] initWithFrame:CGRectZero];
    _credit.font = [UIFont systemFontOfSize:kCreditSize weight:UIFontWeightSemibold];
    _credit.textColor = [UIColor colorWithWhite:1 alpha:kCreditAlpha];
    _credit.hidden = YES;
    _crediting = SGFlag(SGKeyLyricsCredit, NO);
    _sweepsEstimates = SGFlag(SGKeyLyricsSimulateWords, NO);
    [self addSubview:_credit];
    [self addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped:)]];
    [self addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(held:)]];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(playerTransitionChanged:) name:SGPlayerTransitionNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(playerTransitionChanged:) name:SGPlayerTransitionEndedNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(restyle) name:SGRLyricsTextDidChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(scheduleLink) name:UIApplicationDidBecomeActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(scheduleLink) name:UIApplicationWillResignActiveNotification object:nil];
    return self;
}

- (void)useCompactFontSize:(CGFloat)size {
    if (!_compact) {
        _compact = YES;
        _crediting = NO;
        _margin = kCompactMargin;
        _lineGap = kCompactGap;
        _blurPerLine = 0;
        _maxBlur = 0;
        _scroll.scrollEnabled = NO;
        _scroll.alwaysBounceVertical = NO;
        self.userInteractionEnabled = NO;
        for (UIGestureRecognizer *gesture in self.gestureRecognizers) gesture.enabled = NO;
    }
    if (fabs(size - _fontSize) < 0.5) return;
    _fontSize = size;
    _font = [UIFont systemFontOfSize:_fontSize weight:UIFontWeightBold];
    if (_lines && _tops) [self restyle];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    free(_spans);
    free(_breaks);
}

- (void)tapped:(UITapGestureRecognizer *)tap {
    if (self.takesTap && !self.takesTap()) return;
    if (_extras && !_extras.hidden && CGRectContainsPoint(_extras.frame, [tap locationInView:self])) return;
    CGPoint point = [tap locationInView:_scroll];
    for (SGRKaraokeLineView *view in _shown.allValues) {
        CGRect target = view.bubbleTarget;
        if (CGRectIsNull(target) || !CGRectContainsPoint(target, [_scroll convertPoint:point toView:view])) continue;
        [self explainLine:view];
        return;
    }
    if (_plain) return;   // a line with no time has nowhere to seek to
    for (SGRKaraokeLineView *view in _shown.allValues) {
        if (!CGRectContainsPoint(CGRectInset(view.frame, -_margin, -_lineGap / 2), point)) continue;
        SGKaraokeSeek(view.line.start);
        SGPlayFeedback(SGFeedbackSkip);
        [self followSong];
        return;
    }
}

- (void)held:(UILongPressGestureRecognizer *)hold {
    if (hold.state != UIGestureRecognizerStateBegan || !_meanings.count) return;
    CGPoint point = [hold locationInView:_scroll];
    for (SGRKaraokeLineView *view in _shown.allValues) {
        if (!CGRectContainsPoint(CGRectInset(view.frame, -_margin, -_lineGap / 2), point)) continue;
        [self explainLine:view];
        return;
    }
}

- (void)explainLine:(SGRKaraokeLineView *)view {
    NSNumber *index = [_shown allKeysForObject:view].firstObject;
    NSArray<SGLyricsMeaning *> *meanings = index ? _meanings[index] : nil;
    if (!meanings.count) return;
    SGPlayFeedback(SGFeedbackSkip);
    SGRShowMeanings(SGKaraokeLineText(view.line), meanings);
}

// Genius is asked once the song's lines are in; lines that change under it are matched again.
- (void)askMeanings {
    if (_compact) return;   // the preview shows the line alone; nothing there explains a word
    _meanings = nil;
    NSUInteger asked = ++_meaningsAsked;
    NSArray<SGKaraokeLine *> *lines = _lines;
    __weak SGRKaraokeView *weakSelf = self;
    SGLyricsMeaningsFor(_track, lines, ^(NSDictionary<NSNumber *, NSArray<SGLyricsMeaning *> *> *byLine) {
        SGRKaraokeView *page = weakSelf;
        if (!page || asked != page->_meaningsAsked || lines != page->_lines) return;
        page->_meanings = byLine;
        for (NSNumber *key in page->_shown) [page->_shown[key] markMeaning:byLine[key]];
    });
}

#pragma mark - scrolling by hand

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(followSong) object:nil];
    _browsing = YES;
    for (SGRKaraokeLineView *view in _shown.allValues) view.blur = 0;
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    [self showLinesInSight];
}

// Plain text has no song to follow back to: it stays where it was scrolled to, as a page of text does.
- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    if (!decelerate && !_plain) [self performSelector:@selector(followSong) withObject:nil afterDelay:kBrowseHold];
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    if (!_plain) [self performSelector:@selector(followSong) withObject:nil afterDelay:kBrowseHold];
}

- (void)followSong {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(followSong) object:nil];
    if (!_browsing) return;
    _browsing = NO;
    [UIView animateWithDuration:0.7 delay:0 usingSpringWithDamping:0.9 initialSpringVelocity:0
                        options:UIViewAnimationOptionAllowUserInteraction
                     animations:^{ self->_scroll.contentOffset = CGPointZero; } completion:nil];
    [self placeLinesAnimated:YES];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (!self.window) {
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(followSong) object:nil];
        _browsing = NO;
    }
    [self scheduleLink];
}

- (void)scheduleLink {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(startLink) object:nil];
    [_link invalidate];
    _link = nil;
    if (!self.window) return;
    NSTimeInterval wait = SGPlayerTransitionEnds() - CACurrentMediaTime();
    if (wait <= 0) [self startLink];
    else [self performSelector:@selector(startLink) withObject:nil afterDelay:wait + kTransitionSlack inModes:@[NSRunLoopCommonModes]];
}

- (void)startLink {
    if (!self.window || _link) return;
    if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
    _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick)];
    _link.preferredFrameRateRange = CAFrameRateRangeMake(80, 120, 120);
    [_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}

- (void)playerTransitionChanged:(NSNotification *)note {
    [self scheduleLink];
}

- (void)alignFade {
    CALayer *shown = (CALayer *)_scroll.layer.presentationLayer ?: _scroll.layer;
    UIEdgeInsets band = [self shownBand];
    CGRect frame = CGRectMake(0, shown.bounds.origin.y + band.top, self.bounds.size.width,
                              MAX(0, self.bounds.size.height - band.top - band.bottom));
    if (CGRectEqualToRect(frame, _fade.frame)) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _fade.frame = frame;
    [CATransaction commit];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self alignFade];
    _scroll.contentSize = self.bounds.size;
    [_credit sizeToFit];
    CGFloat bottom = self.bounds.size.height - _band.bottom;
    _credit.frame = CGRectMake(_margin, bottom - _credit.bounds.size.height - kCreditBottom,
                               _credit.bounds.size.width, _credit.bounds.size.height);
    if (_extras && !_extras.hidden) {
        _extras.frame = CGRectMake(_margin, bottom - kExtrasSide - kExtrasBottom, kExtrasSide, kExtrasSide);
        _credit.center = CGPointMake(CGRectGetMaxX(_extras.frame) + kExtrasCreditGap + _credit.bounds.size.width / 2, _extras.center.y);
    }
    if (_lines && self.bounds.size.width != _builtWidth) [self rebuild];
}

#pragma mark - the lines' room

- (UIEdgeInsets)lineInsets {
    return _band;
}

- (void)setLineInsets:(UIEdgeInsets)insets duration:(NSTimeInterval)duration {
    if (UIEdgeInsetsEqualToEdgeInsets(insets, _band)) return;
    BOOL animated = duration > 0 && self.window && !SGRReduceMotion();
    _bandFrom = animated ? [self shownBand] : insets;
    _bandSince = CACurrentMediaTime();
    _bandFor = animated ? duration : 0;
    _band = insets;
    _sightArrangement = NSUIntegerMax;   // which lines are in sight is worked out again for the new room
    [self placeLinesAnimated:animated];
    [self setNeedsLayout];
    if (animated) {
        [UIView animateWithDuration:duration delay:0
                            options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                         animations:^{ [self layoutIfNeeded]; } completion:nil];
    }
    [self alignFade];
}

// The room as the fade draws it at this moment, eased from where it was to where it is going.
- (UIEdgeInsets)shownBand {
    double p = _bandFor > 0 ? smoothstep((CACurrentMediaTime() - _bandSince) / _bandFor) : 1;
    return UIEdgeInsetsMake(_bandFrom.top + (_band.top - _bandFrom.top) * p, 0,
                            _bandFrom.bottom + (_band.bottom - _bandFrom.bottom) * p, 0);
}

// Only the room takes touches: the rest of the view can lie over its host's controls.
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (!CGRectContainsPoint(UIEdgeInsetsInsetRect(self.bounds, _band), point)) return nil;
    return [super hitTest:point withEvent:event];
}

- (void)dropLineViews {
    for (UIView *view in _shown.allValues) [view removeFromSuperview];
    [_shown removeAllObjects];
    _tops = nil;
    _sightArrangement = NSUIntegerMax;
    _build++;
    [self forgetSung];
}

- (void)forgetSung {
    _sungCount = 0;
    _focus = _openBreak = -1;
    _arrangement++;
    [_dots removeFromSuperview];
    _dots = nil;
}

// When each line is sung and where the breaks are, worked out once per song for the frames to read.
- (void)timeLines {
    free(_spans);
    free(_breaks);
    NSUInteger count = _lines.count;
    _spans = calloc(count + 1, sizeof(SGRKaraokeSpan));
    _breaks = calloc(count + 1, sizeof(SGRKaraokeBreak));
    _breakCount = 0;
    _hasSpoken = _hasTranslation = NO;
    _plain = SGKaraokeLinesTiming(_lines) == SGKaraokeTimingNone;
    NSInteger sungTo = 0;   // the top of the song counts as where the singing before the first line ends
    for (NSUInteger i = 0; i < count; i++) {
        SGKaraokeLine *line = _lines[i];
        _spans[i] = (SGRKaraokeSpan){line.start, SGKaraokeSungEnd(line)};
        if (!_plain && line.start - sungTo >= kBreakMinMs) _breaks[_breakCount++] = (SGRKaraokeBreak){sungTo, line.start, (NSInteger)i};
        sungTo = MAX(sungTo, _spans[i].end);
        _hasSpoken = _hasSpoken || line.pronunciation || line.backing.pronunciation;
        _hasTranslation = _hasTranslation || line.translation.length;
    }
    [self offerExtras];
    [self askMeanings];
}

- (void)rebuild {
    [self dropLineViews];
    _browsing = NO;
    _scroll.contentOffset = CGPointZero;
    _builtWidth = self.bounds.size.width;
    CGFloat width = _builtWidth - 2 * _margin;
    if (width <= 0) return;
    _font = [UIFont systemFontOfSize:_fontSize weight:UIFontWeightBold];
    SGRKaraokeStyle *style = _style = [self styleNow];
    NSArray<SGKaraokeLine *> *lines = _lines;
    CGFloat gap = _lineGap;
    NSUInteger build = _build;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0), ^{
        NSArray<NSNumber *> *tops = topsOf(lines, width, style, gap);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (build != self->_build) return;   // the song or the width moved on meanwhile
            self->_tops = tops;
            [self placeLinesAnimated:NO];
        });
    });
}

#pragma mark - the pronunciation and the translation

// What a line shows besides its words: what the song has, of what the lyrics menu has switched on.
- (SGRKaraokeStyle *)styleNow {
    if (_compact) {   // the preview sets the line alone, however the words are switched for the page
        return [[SGRKaraokeStyle alloc] initWithSize:_fontSize order:SGRLyricsTextOrder() pronunciation:NO translation:NO];
    }
    return [[SGRKaraokeStyle alloc] initWithSize:_fontSize order:SGRLyricsTextOrder()
                                   pronunciation:_hasSpoken && SGFlag(SGRKeyLyricsPronunciation, NO)
                                     translation:_hasTranslation && SGFlag(SGRKeyLyricsTranslation, NO)];
}

- (void)restyle {
    [self offerExtras];
    if (!_lines || !_tops || _builtWidth <= 0) return;   // the next build picks the style up
    SGRKaraokeStyle *style = [self styleNow];
    NSArray<SGKaraokeLine *> *lines = _lines;
    CGFloat width = _builtWidth - 2 * _margin, gap = _lineGap;
    NSUInteger build = ++_build;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0), ^{
        NSArray<NSNumber *> *tops = topsOf(lines, width, style, gap);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (build != self->_build) return;
            [self showStyle:style tops:tops];
        });
    });
}

- (void)showStyle:(SGRKaraokeStyle *)style tops:(NSArray<NSNumber *> *)tops {
    CATransition *fade = [CATransition animation];
    fade.type = kCATransitionFade;
    fade.duration = kRestyleFade;
    [_scroll.layer addAnimation:fade forKey:@"restyle"];
    for (UIView *view in _shown.allValues) [view removeFromSuperview];
    [_shown removeAllObjects];
    _style = style;
    _tops = tops;
    _sightArrangement = NSUIntegerMax;
    [self placeLinesAnimated:NO];
    [self showLinesInSight];   // placing stands still while the page is scrolled by hand; the views do not
    for (NSUInteger i = 0; i < _sungCount; i++) [self viewForLine:_sung[i]].active = YES;
    for (SGRKaraokeLineView *view in _shown.allValues) [view.layer removeAnimationForKey:@"blur"];
}

- (void)offerExtras {
    if (_compact) {   // the preview has no room for the button, and nothing to open
        _extras.hidden = YES;
        return;
    }
    BOOL offered = _lines && (_hasSpoken || _hasTranslation);
    if (!offered) {
        _extras.hidden = YES;
        return;
    }
    if (!_extras) {
        UIImage *glyph = [UIImage systemImageNamed:@"translate" withConfiguration:
                          [UIImageSymbolConfiguration configurationWithPointSize:kExtrasGlyph weight:UIImageSymbolWeightSemibold]];
        UIButtonConfiguration *config;
        if (@available(iOS 26.0, *)) {
            config = [UIButtonConfiguration glassButtonConfiguration];
        } else {
            config = [UIButtonConfiguration filledButtonConfiguration];
            config.baseBackgroundColor = SGRSolidGlassFill();
        }
        config.image = glyph;
        config.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
        config.baseForegroundColor = UIColor.whiteColor;
        _extras = [UIButton buttonWithConfiguration:config primaryAction:nil];
        _extras.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        _extras.showsMenuAsPrimaryAction = YES;
        _extras.preferredMenuElementOrder = UIContextMenuConfigurationElementOrderFixed;
        _extras.accessibilityLabel = @"Pronunciation and translation";
        [self addSubview:_extras];
    }
    NSMutableArray<UIMenuElement *> *items = [NSMutableArray array];
    if (_hasSpoken) {
        BOOL on = SGFlag(SGRKeyLyricsPronunciation, NO);
        [items addObject:[UIAction actionWithTitle:on ? @"Hide Pronunciation" : @"Show Pronunciation"
                                             image:[UIImage systemImageNamed:@"character.phonetic"] identifier:nil
                                           handler:^(UIAction *action) { SGRSetLyricsTextShown(SGRLyricsTextPronunciation, !on); }]];
    }
    if (_hasTranslation) {
        BOOL on = SGFlag(SGRKeyLyricsTranslation, NO);
        [items addObject:[UIAction actionWithTitle:on ? @"Hide Translation" : @"Show Translation"
                                             image:[UIImage systemImageNamed:@"character.bubble"] identifier:nil
                                           handler:^(UIAction *action) { SGRSetLyricsTextShown(SGRLyricsTextTranslation, !on); }]];
    }
    _extras.menu = [UIMenu menuWithChildren:items];
    _extras.hidden = NO;
    [self setNeedsLayout];
}

- (CGFloat)topOfLine:(NSInteger)index {
    CGFloat room = self.bounds.size.height - _band.top - _band.bottom;
    CGFloat top = _band.top + room * kAnchor + _tops[index].doubleValue - _focusTop;
    return _openBreak >= 0 && index >= _openBreak ? top + [self breakRoom] : top;
}

- (CGFloat)breakRoom {
    return ceil(_font.lineHeight) + _lineGap;
}

- (BOOL)isSung:(NSInteger)index {
    for (NSUInteger i = 0; i < _sungCount; i++) {
        if (_sung[i] == index) return YES;
    }
    return NO;
}

- (NSInteger)distanceOf:(NSInteger)index {
    if (_plain) return 0;   // nothing is sung, so every line reads as clearly as the rest
    if (_openBreak >= 0) return index >= _openBreak ? index - _openBreak + 1 : _openBreak - index;
    if (!_sungCount) return labs(index - _focus);
    NSInteger nearest = NSIntegerMax;
    for (NSUInteger i = 0; i < _sungCount; i++) nearest = MIN(nearest, labs(index - _sung[i]));
    return nearest;
}

// The view of a line, made the first time it is asked for and placed where the stack has it.
- (SGRKaraokeLineView *)viewForLine:(NSInteger)index {
    SGRKaraokeLineView *view = _shown[@(index)];
    if (view || !_tops || index < 0 || index >= (NSInteger)_tops.count) return view;
    view = [[SGRKaraokeLineView alloc] initWithLine:_lines[index] width:_builtWidth - 2 * _margin style:_style under:nil
                                            blurred:_maxBlur > 0 && !_plain sweepsEstimates:_sweepsEstimates];
    if (_plain) [view showPlain];
    [view markMeaning:_meanings[@(index)]];
    [_scroll addSubview:view];
    _shown[@(index)] = view;
    [self placeLine:view at:index animated:NO];
    return view;
}

- (void)showLinesInSight {
    if (!_tops.count) return;
    CGFloat offset = ((CALayer *)_scroll.layer.presentationLayer ?: _scroll.layer).bounds.origin.y;
    if (offset == _sightOffset && _focusTop == _sightFocus && _arrangement == _sightArrangement) return;
    _sightOffset = offset;
    _sightFocus = _focusTop;
    _sightArrangement = _arrangement;
    // Sight is measured from the lines' room, not the whole view, which can be much taller.
    CGFloat height = MAX(0, self.bounds.size.height - _band.top - _band.bottom), seen = offset + _band.top;
    CGFloat from = seen - kSightBehind * height, to = seen + (1 + kSightAhead) * height, slack = kSightSlack * height;
    NSMutableArray<NSNumber *> *gone = [NSMutableArray array];
    for (NSNumber *key in _shown) {
        NSInteger index = key.integerValue;
        CGFloat top = [self topOfLine:index], bottom = top + _shown[key].bounds.size.height;
        if (![self isSung:index] && (bottom < from - slack || top > to + slack)) [gone addObject:key];
    }
    for (NSNumber *key in gone) {
        [_shown[key] removeFromSuperview];
        [_shown removeObjectForKey:key];
    }
    NSInteger count = (NSInteger)_tops.count;
    NSMutableArray<NSNumber *> *wanted = [NSMutableArray array];
    for (NSInteger index = 0; index < count; index++) {
        if (_shown[@(index)]) continue;
        CGFloat top = [self topOfLine:index];
        CGFloat bottom = index + 1 < count ? [self topOfLine:index + 1] - _lineGap : top + height;
        if (bottom < from || top > to) continue;
        [wanted addObject:@(index)];
    }
    CGFloat middle = seen + height / 2;
    [wanted sortUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) {
        CGFloat da = fabs([self topOfLine:a.integerValue] - middle), db = fabs([self topOfLine:b.integerValue] - middle);
        return da < db ? NSOrderedAscending : da > db ? NSOrderedDescending : NSOrderedSame;
    }];
    NSUInteger made = 0;
    for (NSNumber *index in wanted) {
        if (made++ == kLinesPerFrame) {
            _sightOffset = -CGFLOAT_MAX;
            break;
        }
        [self viewForLine:index.integerValue];
    }
}

- (void)placeLine:(SGRKaraokeLineView *)view at:(NSInteger)index animated:(BOOL)animated {
    CGFloat height = self.bounds.size.height;
    NSInteger distance = [self distanceOf:index], below = index - _focus;
    CGRect frame = CGRectMake(_margin, [self topOfLine:index], view.bounds.size.width, view.bounds.size.height);
    CGPoint center = CGPointMake(view.right ? CGRectGetMaxX(frame) : _margin, CGRectGetMidY(frame));
    CGFloat scale = distance == 0 ? 1 : kDimScale;
    CGAffineTransform transform = CGAffineTransformMakeScale(scale, scale);
    view.blur = distance == 0 || _browsing ? 0 : MIN(_maxBlur, distance * _blurPerLine);
    BOOL near = CGRectIntersectsRect(CGRectInset(self.bounds, 0, -height / 2), frame)
             || CGRectIntersectsRect(CGRectInset(self.bounds, 0, -height / 2), view.frame);
    if (!animated || !near) {
        view.center = center;
        view.transform = transform;
        return;
    }
    NSTimeInterval delay = below > 0 ? MIN(0.3, below * 0.04) : 0;
    [UIView animateWithDuration:0.7 delay:delay usingSpringWithDamping:0.86 initialSpringVelocity:0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        view.center = center;
        view.transform = transform;
    } completion:nil];
}

- (void)placeLinesAnimated:(BOOL)animated {
    if (_browsing || !_tops.count) return;
    _focusTop = _tops[(NSUInteger)MAX(_focus, 0)].doubleValue;
    [self showLinesInSight];
    for (NSNumber *key in _shown) [self placeLine:_shown[key] at:key.integerValue animated:animated];
    [self placeBreak];
    // Room to scroll until the first line or the last one reaches the anchor.
    CGFloat lastTop = _tops.lastObject.doubleValue + (_openBreak >= 0 ? [self breakRoom] : 0);
    _scroll.contentInset = UIEdgeInsetsMake(_focusTop, 0, MAX(0, lastTop - _focusTop), 0);
}

- (void)placeBreak {
    if (_openBreak < 0) {
        [_dots removeFromSuperview];
        return;
    }
    if (!_dots) {
        _dots = [[SGRKaraokeBreakView alloc] initWithFont:_font];
        _dotsLine = -1;
    }
    if (_dotsLine != _openBreak) {
        _dots.rightToLeft = readsRightToLeft(SGKaraokeLineText(_lines[(NSUInteger)_openBreak]));
        for (NSUInteger i = 0; i < _breakCount; i++) {
            if (_breaks[i].line == _openBreak) [_dots playFrom:_breaks[i].start to:_breaks[i].end];
        }
        _dotsLine = _openBreak;
    }
    if (_dots.superview != _scroll) [_scroll addSubview:_dots];
    _dots.right = alignsRight(_lines[(NSUInteger)_openBreak]);
    CGFloat top = [self topOfLine:_openBreak] - [self breakRoom];
    _dots.frame = CGRectMake(_margin, top, _builtWidth - 2 * _margin, _dots.bounds.size.height);
}

- (void)creditTo:(NSString *)source {
    NSString *text = source.length && _crediting ? [NSString stringWithFormat:@"Lyrics from %@", source] : nil;
    if (text == _credit.text || [text isEqualToString:_credit.text]) return;
    _credit.text = text;
    _credit.hidden = !_showing || !text.length;
    [self setNeedsLayout];
}

- (void)syncSiblings {
    for (UIView *sibling in self.superview.subviews) {
        if (sibling != self && _showing) sibling.alpha = 0;
    }
}

- (void)setShowing:(BOOL)showing {
    if (showing == _showing) return;
    _showing = showing;
    self.hidden = !showing;
    _credit.hidden = !showing || !_credit.text.length;
    for (UIView *sibling in self.superview.subviews) {
        if (sibling != self) sibling.alpha = showing ? 0 : 1;
    }
}

- (double)clockMs {
    NSInteger raw = SGKaraokePositionMs();
    CFTimeInterval shown = _link.targetTimestamp;
    BOOL running = raw != _reported;   // a paused player reports the same position every frame
    if (running) _stillSince = 0;
    else if (!_stillSince) _stillSince = shown;
    double reported = raw + (running ? (shown - CACurrentMediaTime()) * 1000 : 0);
    double predicted = _clock + (running ? (shown - _clockTime) * 1000 : 0);
    double error = reported - predicted;
    _clock = raw < 0 || fabs(error) > kClockSnapMs ? reported : predicted + error * kClockPull;
    _reported = raw;
    _clockTime = shown;
    return _clock;
}

- (void)tick {
    NSString *track = SGKaraokePlayingTrack();
    if (!(track == _track || [track isEqualToString:_track])) {
        if (!_compact) SGLog(@"karaoke: page shows track %@, lyrics %@", track, SGKaraokeLinesForTrack(track) ? @"captured" : @"not captured yet");
        _track = track;
        _lines = nil;
        _builtWidth = 0;
        [self creditTo:nil];
        [self dropLineViews];
        [self offerExtras];
    }
    // Plain text is shown while Spotify is asked whether it has the song timed; its answer replaces it.
    NSArray<SGKaraokeLine *> *kept = _plain && _lines && track ? SGKaraokeLinesForTrack(track) : nil;
    if (kept && kept != _lines) {
        if (!_compact) SGLog(@"karaoke: timed lines of %@ came in over the plain text", track);
        _lines = nil;
        _builtWidth = 0;
        [self creditTo:nil];
        [self dropLineViews];
    }
    if (!_lines && track && (_lines = SGKaraokeLinesForTrack(track))) {
        if (!_compact) SGLog(@"karaoke: showing %lu lines of %@", (unsigned long)_lines.count, track);
        [self timeLines];
        [self setNeedsLayout];
    }
    [self setShowing:_tops != nil && !(_compact && _plain)];
    // The source is settled a moment after the lines are, so it is asked for until it answers.
    if (_crediting && _lines && !_credit.text.length) [self creditTo:SGLyricsCreditFor(track)];
    if (!_tops) return;
    [self alignFade];
    if (_plain) {
        [self showLinesInSight];   // it moves only when scrolled by hand
        return;
    }

    double now = [self clockMs];
    NSInteger sung[kMostSung], focus, openBreak;
    NSUInteger count = [self sungAt:now into:sung focus:&focus openBreak:&openBreak];
    if (focus != _focus || openBreak != _openBreak || count != _sungCount || memcmp(sung, _sung, count * sizeof(NSInteger))) {
        // Lines sung out go back to dim, lines coming in light up, the ones sung throughout carry on.
        for (NSUInteger i = 0; i < _sungCount; i++) {
            BOOL still = NO;
            for (NSUInteger j = 0; j < count; j++) still = still || sung[j] == _sung[i];
            if (!still) _shown[@(_sung[i])].active = NO;
        }
        for (NSUInteger j = 0; j < count; j++) {
            if (![self isSung:sung[j]]) [self viewForLine:sung[j]].active = YES;
        }
        BOOL jump = labs(focus - _focus) > 2;   // a seek, not the song moving on
        memcpy(_sung, sung, count * sizeof(NSInteger));
        _sungCount = count;
        _focus = focus;
        _openBreak = openBreak;
        _arrangement++;
        if (openBreak < 0) [_dots removeFromSuperview];
        [self placeLinesAnimated:!jump];
    } else {
        [self showLinesInSight];   // the page may be scrolling by hand, or springing back
    }
    for (NSUInteger i = 0; i < _sungCount; i++) [_shown[@(_sung[i])] showTime:now];
    if (_dots.superview) [_dots showTime:now running:!_stillSince || _link.targetTimestamp - _stillSince < kStillFor at:_link.targetTimestamp];
}

- (NSUInteger)sungAt:(double)now into:(NSInteger *)sung focus:(NSInteger *)focus openBreak:(NSInteger *)openBreak {
    NSInteger count = (NSInteger)_lines.count, last = -1;
    while (last + 1 < count && _spans[last + 1].start <= now) last++;
    *openBreak = -1;
    NSInteger breakLine = -1;
    for (NSUInteger i = 0; i < _breakCount; i++) {
        SGRKaraokeBreak pause = _breaks[i];
        if (now < pause.start || now >= pause.end) continue;
        breakLine = pause.line;
        if (now < pause.end - kBreakCollapse * 1000) *openBreak = pause.line;
    }
    NSUInteger found = 0;
    for (NSInteger i = 0; i <= last && found < kMostSung; i++) {
        if (_spans[i].end > now || (i == last && breakLine < 0)) sung[found++] = i;
    }
    *focus = breakLine >= 0 ? breakLine : found ? sung[0] : last;
    return found;
}

@end
