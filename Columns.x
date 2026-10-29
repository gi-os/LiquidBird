#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// Step 2 of the tiling: Twitter for iPad's columns where there's room beside the sidebar (the Duo
// unfolded), after gi-os/twitter's TabStackView. Opening a tweet, profile or link from the current tab
// doesn't push it: it becomes a column to the right of the one it came from (replacing any after it),
// and the newest slides in at the trailing edge, over the tab's root, which stays put underneath with
// a sliver showing. The columns are one strip you slide sideways, snapping to column edges in the
// direction you flick; a column's close button closes it and the ones after it. Leaving the tab closes
// them; narrowing (folding) puts them back on the tab's own stack, in order.
//
// Each column is X's own navigation controller (XNAVNavigationController), a child of X's tab bar
// controller, so its screens get X's bars and find X's navigation up their responder chain; a push
// from inside a column opens the next column.

@interface XNAVNavigationController : UINavigationController
@end
@interface _TtC11XNavigation16TabBarController : UIViewController
@end

// gi-os/twitter's ColumnLayout: columns prefer 476pt, need 400, and leave at least a 160pt sliver of
// what they came from.
static const CGFloat LBCPreferred = 476, LBCMinimum = 400, LBCSliver = 160;
static const void *kLBCStrip = &kLBCStrip;
static const void *kLBCColumnOf = &kLBCColumnOf;
static BOOL LBCPassThrough;   // pushes the strip makes itself, folding columns back onto the stack

// The sidebar's strip down the trailing edge (Tiling.x): the safe area there, or its default.
static CGFloat LBCSidebarWidth(UIWindow *w) {
    CGFloat r = w.safeAreaInsets.right;
    return r >= 40 ? r : 66;
}

static CGFloat LBCAvailable(UIWindow *w) { return w ? w.bounds.size.width - LBCSidebarWidth(w) : 0; }

// Room for a column and the sliver beside the sidebar: the Duo unfolded, not folded.
static BOOL LBCColumnsWanted(UIWindow *w) { return LBCAvailable(w) >= LBCMinimum + LBCSliver; }

static UINavigationController *LBCMakeNavigation(UIViewController *vc) {
    Class xnav = objc_getClass("XNAVNavigationController");
    Class bar = objc_getClass("_TtCC11XNavigation20NavigationControllerP33_501AD6EDA6CFD4B04EC931BB22CF90163Bar");
    UINavigationController *nav = xnav ? [[xnav alloc] initWithNavigationBarClass:bar toolbarClass:nil]
                                       : [[UINavigationController alloc] init];
    [nav setViewControllers:@[vc] animated:NO];
    return nav;
}

@interface LBCStrip : UIView <UIScrollViewDelegate>
@property (nonatomic, weak) UINavigationController *rootNavigation;   // the tab's own stack
@property (nonatomic, weak) UIViewController *parent;                 // X's tab bar controller
@property (nonatomic, readonly) NSUInteger count;
- (void)open:(UIViewController *)vc after:(UINavigationController *)from animated:(BOOL)animated;
- (void)closeAfter:(NSInteger)index animated:(BOOL)animated;          // -1: every column
- (void)foldBackOntoStack;
- (UINavigationController *)touchedColumn;
@end

@implementation LBCStrip {
    UIScrollView *_scroll;
    NSMutableArray<UIView *> *_cards;
    NSMutableArray<UINavigationController *> *_navigations;
    __weak UIView *_touched;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _scroll = [[UIScrollView alloc] initWithFrame:self.bounds];
        _scroll.delegate = self;
        _scroll.showsHorizontalScrollIndicator = NO;
        _scroll.showsVerticalScrollIndicator = NO;
        _scroll.alwaysBounceHorizontal = YES;
        _scroll.decelerationRate = UIScrollViewDecelerationRateFast;
        _scroll.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
        _scroll.clipsToBounds = NO;   // columns slide on under the leading edge rather than being cut off
        [self addSubview:_scroll];
        _cards = [NSMutableArray array];
        _navigations = [NSMutableArray array];
        self.hidden = YES;
    }
    return self;
}

- (NSUInteger)count { return _cards.count; }
- (CGFloat)columnWidth { return round(MIN(LBCPreferred, self.bounds.size.width - LBCSliver)); }
// Where the first column rests: past the root's sliver.
- (CGFloat)firstColumnX { return self.bounds.size.width - self.columnWidth; }

// The root's part of the strip is open, so touches there reach the tab underneath; a touch on a column
// marks it as the one the next push comes from.
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (!hit || hit == self || hit == _scroll) { _touched = nil; return nil; }
    for (UIView *card in _cards)
        if ([hit isDescendantOfView:card]) { _touched = card; break; }
    return hit;
}

- (UINavigationController *)touchedColumn {
    NSUInteger i = _touched ? [_cards indexOfObject:_touched] : NSNotFound;
    return i == NSNotFound ? nil : _navigations[i];
}

- (UIView *)cardFor:(UINavigationController *)nav {
    UIView *card = [UIView new];
    card.layer.shadowColor = UIColor.blackColor.CGColor;
    card.layer.shadowOpacity = 0.6;
    card.layer.shadowRadius = 14;
    card.layer.shadowOffset = CGSizeMake(-4, 0);
    UIView *clip = [UIView new];
    clip.backgroundColor = UIColor.blackColor;
    clip.layer.cornerRadius = 22;
    clip.layer.cornerCurve = kCACornerCurveContinuous;
    clip.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMinXMaxYCorner;
    clip.layer.masksToBounds = YES;
    clip.layer.borderWidth = 0.5;
    clip.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.14].CGColor;
    clip.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [card addSubview:clip];
    nav.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [clip addSubview:nav.view];
    return card;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _scroll.frame = self.bounds;
    CGFloat w = self.columnWidth, x = self.firstColumnX, h = self.bounds.size.height;
    for (NSUInteger i = 0; i < _cards.count; i++) {
        UIView *card = _cards[i];
        card.bounds = CGRectMake(0, 0, w, h);
        card.center = CGPointMake(x + i * w + w / 2, h / 2);
        UIView *clip = card.subviews.firstObject;
        clip.frame = card.bounds;
        _navigations[i].view.frame = clip.bounds;
        card.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:card.bounds cornerRadius:22].CGPath;
    }
    _scroll.contentSize = CGSizeMake(x + _cards.count * w, h);
}

- (CGFloat)endOffset { return MAX(0, _scroll.contentSize.width - _scroll.bounds.size.width); }

// Shown in its own column, a screen closes rather than goes back.
- (void)addCloseTo:(UIViewController *)vc {
    UIBarButtonItem *close = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"xmark"]
                                                              style:UIBarButtonItemStylePlain
                                                             target:self
                                                             action:@selector(closeTapped:)];
    close.accessibilityLabel = @"Close";
    vc.navigationItem.leftBarButtonItem = close;
}

- (void)closeTapped:(UIBarButtonItem *)item {
    for (NSUInteger i = 0; i < _navigations.count; i++)
        if (_navigations[i].viewControllers.firstObject.navigationItem.leftBarButtonItem == item) {
            [self closeAfter:(NSInteger)i - 1 animated:YES];
            return;
        }
}

- (void)open:(UIViewController *)vc after:(UINavigationController *)from animated:(BOOL)animated {
    NSUInteger found = from ? [_navigations indexOfObject:from] : NSNotFound;
    [self closeAfter:found == NSNotFound ? -1 : (NSInteger)found animated:NO];
    UIViewController *parent = self.parent;
    UINavigationController *nav = LBCMakeNavigation(vc);
    objc_setAssociatedObject(nav, kLBCColumnOf, self, OBJC_ASSOCIATION_ASSIGN);
    [parent addChildViewController:nav];
    UIView *card = [self cardFor:nav];
    [_cards addObject:card];
    [_navigations addObject:nav];
    [_scroll addSubview:card];
    [nav didMoveToParentViewController:parent];
    [self addCloseTo:vc];
    self.hidden = NO;
    [self setNeedsLayout];
    [self layoutIfNeeded];
    // The newest column slides in at the trailing edge, the strip with it.
    CGFloat end = self.endOffset;
    if (animated && !UIAccessibilityIsReduceMotionEnabled()) {
        card.transform = CGAffineTransformMakeTranslation(self.columnWidth, 0);
        [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:1 initialSpringVelocity:0 options:0 animations:^{
            card.transform = CGAffineTransformIdentity;
            self->_scroll.contentOffset = CGPointMake(end, 0);
        } completion:nil];
    } else {
        _scroll.contentOffset = CGPointMake(end, 0);
    }
}

- (void)remove:(UIView *)card navigation:(UINavigationController *)nav {
    [card removeFromSuperview];
    [nav.view removeFromSuperview];
    [nav removeFromParentViewController];
}

- (void)closeAfter:(NSInteger)index animated:(BOOL)animated {
    BOOL slide = animated && !UIAccessibilityIsReduceMotionEnabled();
    while ((NSInteger)_cards.count > index + 1) {
        UIView *card = _cards.lastObject;
        UINavigationController *nav = _navigations.lastObject;
        [_cards removeLastObject];
        [_navigations removeLastObject];
        [nav willMoveToParentViewController:nil];
        if (slide) {
            [UIView animateWithDuration:0.3 animations:^{
                card.transform = CGAffineTransformMakeTranslation(card.bounds.size.width + 40, 0);
            } completion:^(BOOL finished) {
                [self remove:card navigation:nav];
                if (!self->_cards.count) self.hidden = YES;
            }];
        } else {
            [self remove:card navigation:nav];
        }
    }
    [self setNeedsLayout];
    [self layoutIfNeeded];
    if (_scroll.contentOffset.x > self.endOffset) [_scroll setContentOffset:CGPointMake(self.endOffset, 0) animated:slide];
    if (!_cards.count && !slide) self.hidden = YES;
}

// Folded, there's no room for columns: what they show goes back on the tab's stack, in order, with
// its back button instead of the close one.
- (void)foldBackOntoStack {
    UINavigationController *root = self.rootNavigation;
    NSMutableArray<UIViewController *> *screens = [NSMutableArray array];
    for (UINavigationController *nav in _navigations) {
        [screens addObjectsFromArray:nav.viewControllers];
        [nav setViewControllers:@[] animated:NO];
    }
    [self closeAfter:-1 animated:NO];
    LBCPassThrough = YES;
    for (UIViewController *vc in screens) {
        vc.navigationItem.leftBarButtonItem = nil;
        [root pushViewController:vc animated:NO];
    }
    LBCPassThrough = NO;
}

// Snaps to column edges, in the direction flicked (Twitter for iPad's bestOffsetForPossibleOffsets:).
- (void)scrollViewWillEndDragging:(UIScrollView *)scrollView withVelocity:(CGPoint)velocity
              targetContentOffset:(inout CGPoint *)target {
    CGFloat w = self.columnWidth, x = scrollView.contentOffset.x;
    CGFloat stop = velocity.x > 0.2 ? ceil(x / w) * w : velocity.x < -0.2 ? floor(x / w) * w : round(x / w) * w;
    target->x = MIN(MAX(stop, 0), self.endOffset);
}
@end

// The strip over a tab bar controller's content, left of the sidebar.
static LBCStrip *LBCStripFor(UIViewController *tabs, BOOL create) {
    UIView *view = tabs.viewIfLoaded;
    UIWindow *w = view.window;
    if (!w) return nil;
    LBCStrip *strip = objc_getAssociatedObject(tabs, kLBCStrip);
    if (!strip && create) {
        strip = [[LBCStrip alloc] initWithFrame:CGRectZero];
        strip.parent = tabs;
        objc_setAssociatedObject(tabs, kLBCStrip, strip, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (!strip) return nil;
    if (strip.superview != view) [view addSubview:strip];
    [view bringSubviewToFront:strip];
    CGRect frame = [view convertRect:CGRectMake(0, 0, LBCAvailable(w), w.bounds.size.height) fromView:nil];
    if (!CGRectEqualToRect(strip.frame, frame)) strip.frame = frame;
    return strip;
}

%group Columns
%hook XNAVNavigationController
- (void)pushViewController:(UIViewController *)vc animated:(BOOL)animated {
    if (LBCPassThrough || !vc || self.viewControllers.count == 0) { %orig; return; }
    UIWindow *w = self.viewIfLoaded.window;
    // Pushed from inside a column: the next column.
    LBCStrip *owner = objc_getAssociatedObject(self, kLBCColumnOf);
    if (owner) {
        if (LBCColumnsWanted(w)) [owner open:vc after:self animated:animated];
        else %orig;
        return;
    }
    // Pushed on a tab's own stack (not in a sheet): a column after the one last touched, or the root.
    UIViewController *tabs = self.parentViewController;
    if (!LBCColumnsWanted(w) || self.presentingViewController ||
        ![tabs isKindOfClass:objc_getClass("_TtC11XNavigation16TabBarController")]) { %orig; return; }
    LBCStrip *strip = LBCStripFor(tabs, YES);
    if (!strip) { %orig; return; }
    if (strip.rootNavigation != self) [strip closeAfter:-1 animated:NO];
    strip.rootNavigation = self;
    [strip open:vc after:strip.touchedColumn animated:animated];
}
%end

%hook _TtC11XNavigation16TabBarController
// Keeps the strip over the content as the window changes; leaving the tab closes its columns, and
// folding puts them back on its stack.
- (void)viewDidLayoutSubviews {
    %orig;
    LBCStrip *strip = LBCStripFor(self, NO);
    if (!strip.count) return;
    UINavigationController *root = strip.rootNavigation;
    if (!LBCColumnsWanted(self.viewIfLoaded.window)) [strip foldBackOntoStack];
    else if (!root.viewIfLoaded.window || root.view.hidden) [strip closeAfter:-1 animated:NO];
}
%end
%end

%ctor {
    if (objc_getClass("XNAVNavigationController") && objc_getClass("_TtC11XNavigation16TabBarController")) %init(Columns);
}
