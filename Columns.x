#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

// Step 2 of the tiling: Twitter for iPad's columns where there's room beside the sidebar (the Duo
// unfolded), after gi-os/twitter's TabStackView. Opening a tweet, profile or link from the current tab
// doesn't push it: it becomes a column to the right of the one it came from (replacing any after it),
// and the newest slides in at the trailing edge, over the tab's root, which stays put underneath with
// a sliver showing. The columns are one strip you slide sideways, snapping to column edges in the
// direction you flick; a column's close button closes it and the ones after it, and tapping outside the
// columns (the dimmed sliver of the tab) or swiping them away (left past the end, or right past the start
// when they're on the right) closes them all. Leaving the tab closes them; narrowing
// (folding) puts them back on the tab's own stack, in order.
//
// Each column is a plain navigation controller of its own (LBColumnNavigationController: creating X's
// XNAVNavigationController outside its tabs crashed), in a container under the app's root beside the
// sidebar, not in X's tab bar controller, which expects only its own tabs. A push from inside a column
// opens the next column. If opening a column throws, the push goes ahead as usual instead.
//
// With room for both (the Duo unfolded), the tab's feed narrows and X's own Explore tab (search, its
// For you / Trending / News pages, trends) stands beside it, like X desktop's right sidebar: X keeps
// Explore loaded and hidden behind the selected tab, so it's shown in that place rather than made
// again. What opens from it opens as columns, which slide over it.

@interface XNAVNavigationController : UINavigationController
@end
@interface _TtC11XNavigation16TabBarController : UIViewController
@end

// gi-os/twitter's ColumnLayout: columns prefer 476pt, need 400, and leave at least a 160pt sliver of
// what they came from.
static const CGFloat LBCPreferred = 476, LBCMinimum = 400, LBCSliver = 160;
static BOOL LBCPassThrough;   // pushes the strip makes itself, folding columns back onto the stack

CGFloat LBSidebarStrip(UIWindow *w);   // Tiling.x: the sidebar's width (the status bar's strip, or its default)
void LBLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);   // Debug.x: shown in the layout copy

static CGFloat LBCAvailable(UIWindow *w) { return w ? w.bounds.size.width - LBSidebarStrip(w) : 0; }

// The Duo unfolded: the window's short side, which turning the phone doesn't change (folded, a photo
// turned sideways makes the window 678pt wide, with the tabs turned under it).
static const CGFloat LBCUnfoldedSide = 600;
static BOOL LBCUnfolded(UIWindow *w) { return w && MIN(w.bounds.size.width, w.bounds.size.height) >= LBCUnfoldedSide; }

// Room for a column and the sliver beside the sidebar: the Duo unfolded, not folded.
static BOOL LBCColumnsWanted(UIWindow *w) { return LBCUnfolded(w) && LBCAvailable(w) >= LBCMinimum + LBCSliver; }

@class LBCStrip;
@interface LBColumnNavigationController : UINavigationController
@property (nonatomic, weak) LBCStrip *strip;
@end

static UINavigationController *LBCMakeNavigation(UIViewController *vc) {
    LBColumnNavigationController *nav = [[LBColumnNavigationController alloc] initWithRootViewController:vc];
    nav.view.accessibilityIdentifier = @"LBColumn";   // Tiling.x keeps a column's bar (its ✕)
    return nav;
}

@interface LBCStrip : UIView <UIScrollViewDelegate, UIGestureRecognizerDelegate>
@property (nonatomic, weak) UINavigationController *rootNavigation;   // the tab's own stack
@property (nonatomic) BOOL fromLeading;   // with the feed on the right, columns open over the left side
@property (nonatomic, weak) UIViewController *parent;                 // the columns' container
@property (nonatomic, readonly) NSUInteger count;
- (void)open:(UIViewController *)vc after:(UINavigationController *)from animated:(BOOL)animated;
- (void)closeAfter:(NSInteger)index animated:(BOOL)animated;          // -1: every column
- (void)foldBackOntoStack;
- (UINavigationController *)touchedColumn;
@end

@implementation LBCStrip {
    UIView *_dim;
    UIScrollView *_scroll;
    NSMutableArray<UIView *> *_cards;
    NSMutableArray<UINavigationController *> *_navigations;
    __weak UIView *_touched;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        // Dims the tab under the columns; a tap on it closes them all.
        _dim = [[UIView alloc] initWithFrame:self.bounds];
        _dim.backgroundColor = [UIColor colorWithWhite:0 alpha:0.4];
        _dim.alpha = 0;
        [self addSubview:_dim];
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(outsideTapped:)];
        tap.delegate = self;
        [self addGestureRecognizer:tap];
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
// Where the first column rests: past the root's sliver, or at the leading edge with the feed on the right.
- (CGFloat)firstColumnX { return self.fromLeading ? 0 : self.bounds.size.width - self.columnWidth; }

// Outside the columns the strip takes the touch (a tap there closes them all); a touch on a column marks
// it as the one the next push comes from.
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (!hit) return nil;
    if (hit == self || hit == _scroll || hit == _dim) { _touched = nil; return _cards.count ? self : nil; }
    for (UIView *card in _cards)
        if ([hit isDescendantOfView:card]) { _touched = card; break; }
    return hit;
}

- (void)outsideTapped:(UITapGestureRecognizer *)tap {
    [self closeIfOutside:[tap locationInView:self]];
}

- (void)closeIfOutside:(CGPoint)p {
    for (UIView *card in _cards)
        if (CGRectContainsPoint([self convertRect:card.bounds fromView:card], p)) return;
    [self closeAfter:-1 animated:YES];
}

// The tap counts even if one of X's own gestures recognizes it too; and should one claim it outright, the
// touch ending here still closes them.
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return YES;
}

// Only the sliver's touches: the columns' own taps (row selection runs on touchesEnded) are left alone.
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)touch {
    return touch.view == self;
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesEnded:touches withEvent:event];
    UITouch *touch = touches.anyObject;
    if (touch.view == self && touch.tapCount > 0) [self closeIfOutside:[touch locationInView:self]];
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
    _dim.frame = self.bounds;
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

// The feed moved to the other side: the open columns go over the other side too, the newest in view, as
// open: leaves it.
- (void)setFromLeading:(BOOL)fromLeading {
    if (_fromLeading == fromLeading) return;
    _fromLeading = fromLeading;
    if (!_cards.count) return;
    [self setNeedsLayout];
    [self layoutIfNeeded];
    _scroll.contentOffset = CGPointMake(self.endOffset, 0);
}

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
    NSInteger kept = (NSInteger)_cards.count - 1;
    UIViewController *parent = self.parent;
    UINavigationController *nav = nil;
    UIView *card = nil;
    @try {
        nav = LBCMakeNavigation(vc);
        ((LBColumnNavigationController *)nav).strip = self;
        [parent addChildViewController:nav];
        card = [self cardFor:nav];
        [_cards addObject:card];
        [_navigations addObject:nav];
        [_scroll addSubview:card];
        [nav didMoveToParentViewController:parent];
        [self addCloseTo:vc];
        self.hidden = NO;
        [self setNeedsLayout];
        [self layoutIfNeeded];
    } @catch (NSException *e) {
        // Nothing half-made is left behind (no empty column, no ✕ that closes nothing): the caller pushes vc
        // as usual, with its own back button.
        [self closeAfter:kept animated:NO];
        if (nav.parentViewController) [nav removeFromParentViewController];
        if (vc.navigationItem.leftBarButtonItem.target == self) vc.navigationItem.leftBarButtonItem = nil;
        if (vc.parentViewController) [vc removeFromParentViewController];
        @throw;
    }
    // The newest column slides in at the trailing edge, the strip with it.
    CGFloat end = self.endOffset;
    if (animated && !UIAccessibilityIsReduceMotionEnabled()) {
        card.transform = CGAffineTransformMakeTranslation(self.columnWidth, 0);
        [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:1 initialSpringVelocity:0 options:0 animations:^{
            card.transform = CGAffineTransformIdentity;
            self->_scroll.contentOffset = CGPointMake(end, 0);
            self->_dim.alpha = 1;
        } completion:nil];
    } else {
        _scroll.contentOffset = CGPointMake(end, 0);
        _dim.alpha = 1;
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
    if (!_cards.count) {
        if (slide) [UIView animateWithDuration:0.3 animations:^{ self->_dim.alpha = 0; }];
        else { _dim.alpha = 0; self.hidden = YES; }
    }
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

// Throws every column off toward one side, then closes them. Like closeAfter:, they're out of the strip
// from the start, so a tap meanwhile reaches the tab rather than sending them back, and a fold has
// nothing to put back on the stack.
- (void)throwAwayToLeft:(BOOL)left {
    NSArray<UIView *> *cards = [_cards copy];
    NSArray<UINavigationController *> *navigations = [_navigations copy];
    [_cards removeAllObjects];
    [_navigations removeAllObjects];
    for (UINavigationController *nav in navigations) [nav willMoveToParentViewController:nil];
    CGFloat distance = (self.bounds.size.width + 40) * (left ? -1 : 1);
    [UIView animateWithDuration:0.28 delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        for (UIView *card in cards) card.transform = CGAffineTransformMakeTranslation(distance, 0);
        self->_dim.alpha = 0;
    } completion:^(BOOL finished) {
        for (NSUInteger i = 0; i < cards.count; i++) [self remove:cards[i] navigation:navigations[i]];
        // A column opened meanwhile stays.
        if (!self->_cards.count) {
            self.hidden = YES;
            self->_scroll.contentOffset = CGPointZero;
        }
        [self setNeedsLayout];
    }];
}

// Snaps to column edges, in the direction flicked (Twitter for iPad's bestOffsetForPossibleOffsets:); pulled
// on past the last column toward the left (or past the first toward the right, when the columns are on the
// right), the columns are thrown away.
- (void)scrollViewWillEndDragging:(UIScrollView *)scrollView withVelocity:(CGPoint)velocity
              targetContentOffset:(inout CGPoint *)target {
    static const CGFloat throwDistance = 120;
    CGFloat beyondEnd = scrollView.contentOffset.x - self.endOffset, beforeStart = -scrollView.contentOffset.x;
    BOOL left = beyondEnd > throwDistance || (beyondEnd > 20 && velocity.x > 1);
    BOOL right = !self.fromLeading && (beforeStart > throwDistance || (beforeStart > 20 && velocity.x < -1));
    if (left || right) {
        *target = scrollView.contentOffset;
        dispatch_async(dispatch_get_main_queue(), ^{ [self throwAwayToLeft:left]; });
        return;
    }
    CGFloat w = self.columnWidth, x = scrollView.contentOffset.x;
    CGFloat stop = velocity.x > 0.2 ? ceil(x / w) * w : velocity.x < -0.2 ? floor(x / w) * w : round(x / w) * w;
    target->x = MIN(MAX(stop, 0), self.endOffset);
}
@end

static const void *kLBCContainer = &kLBCContainer;

@implementation LBColumnNavigationController
// A push inside a column opens the next column (folded, there are no columns: it stacks as usual).
- (void)pushViewController:(UIViewController *)vc animated:(BOOL)animated {
    LBCStrip *strip = self.strip;
    if (!LBCPassThrough && strip && self.viewControllers.count && LBCColumnsWanted(self.viewIfLoaded.window)) {
        @try {
            [strip open:vc after:self animated:animated];
            return;
        } @catch (NSException *e) {
            NSLog(@"LiquidBird: couldn't open a column (%@), pushing instead", e);
        }
    }
    [super pushViewController:vc animated:animated];
}
@end

// The strip over the content, left of the sidebar: under the app's root view controller, in a plain
// container that holds the columns' navigation controllers. One per window.
static LBCStrip *LBCStripFor(UIWindow *w, BOOL create) {
    UIViewController *root = w.rootViewController;
    UIView *host = root.viewIfLoaded;
    if (!host) return nil;
    UIViewController *container = objc_getAssociatedObject(w, kLBCContainer);
    if (!container && create) {
        container = [UIViewController new];
        LBCStrip *strip = [[LBCStrip alloc] initWithFrame:CGRectZero];
        container.view = strip;
        strip.parent = container;
        [root addChildViewController:container];
        [host addSubview:strip];
        [container didMoveToParentViewController:root];
        objc_setAssociatedObject(w, kLBCContainer, container, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    LBCStrip *strip = (LBCStrip *)container.viewIfLoaded;
    if (!strip) return nil;
    // Above the content, under the sidebar.
    UIView *sidebar = nil;
    Class sidebarClass = objc_getClass("LBSidebar");
    for (UIView *v in host.subviews) if (sidebarClass && [v isKindOfClass:sidebarClass]) sidebar = v;
    if (strip.superview != host) [host addSubview:strip];
    if (sidebar) [host insertSubview:strip belowSubview:sidebar];
    else [host bringSubviewToFront:strip];
    CGRect frame = [host convertRect:CGRectMake(0, 0, LBCAvailable(w), w.bounds.size.height) fromView:nil];
    if (!CGRectEqualToRect(strip.frame, frame)) strip.frame = frame;
    return strip;
}

// MARK: - Explore beside the feed

static const CGFloat LBCWide = 600, LBCPanelMinimum = 240, LBCPanelMaximum = 380;
static const void *kLBCWantsHidden = &kLBCWantsHidden;
static const void *kLBCPanel = &kLBCPanel;
static const void *kLBCPanelRect = &kLBCPanelRect;
NSString *LBCPanelStatus = @"not laid out yet";   // for the layout copy (Debug.x)
static const void *kLBCHint = &kLBCHint;

// Tiling.x: the selected tab's name.
NSString *LBSelectedTabLabel(UIWindow *w);

static BOOL LBCPanelWanted(UIWindow *w) { return LBCUnfolded(w) && LBCAvailable(w) >= LBCWide; }
static CGFloat LBCPanelWidth(UIWindow *w) {
    return round(MIN(LBCPanelMaximum, MAX(LBCPanelMinimum, LBCAvailable(w) * 0.4)));
}

// X hides the tabs it isn't showing; what it asks for is kept, and Explore stays shown while it's the
// panel.
static BOOL LBCWantsHidden(UIView *v) { return [objc_getAssociatedObject(v, kLBCWantsHidden) boolValue]; }

static UINavigationController *LBCExploreTab(UIViewController *tabs) {
    Class guide = objc_getClass("_TtC14T1TwitterSwift28GuideContainerViewController");
    for (UIViewController *c in tabs.childViewControllers)
        if ([c isKindOfClass:UINavigationController.class] &&
            [((UINavigationController *)c).viewControllers.firstObject isKindOfClass:guide]) return (UINavigationController *)c;
    return nil;
}

// Where the feed sits: -1 narrow on the left, 0 centre (the app's own full width, no Explore panel), 1
// narrow on the right. Shared
// with the sidebar logo's menu (Tiling.x). Before the centre, only liquidbird_feed_right said.
NSInteger LBCFeedPosition(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    id side = [defaults objectForKey:@"liquidbird_feed_side"];
    if (side) return MAX(-1, MIN(1, [side integerValue]));
    return [defaults boolForKey:@"liquidbird_feed_right"] ? 1 : -1;
}
void LBCSetFeedPosition(NSInteger side) {
    [NSUserDefaults.standardUserDefaults setInteger:MAX(-1, MIN(1, side)) forKey:@"liquidbird_feed_side"];
}
static BOOL LBCFeedOnRight(void) { return LBCFeedPosition() == 1; }
// Explore beside the feed can be turned off (the sidebar logo's menu): the feed stays narrow, on its
// side, with black beside it.
static BOOL LBCExploreEnabled(void) {
    id on = [NSUserDefaults.standardUserDefaults objectForKey:@"liquidbird_explore_panel"];
    return on ? [on boolValue] : YES;
}

// A two-finger swipe left or right moves the feed a step that way (left, full width, right), Explore to
// the other side (one finger stays the timelines' own swipe between For you and Following).
@interface LBCSwipe : NSObject <UIGestureRecognizerDelegate>
@property (nonatomic, weak) UIViewController *tabs;
- (void)relayout;
@end

@implementation LBCSwipe
- (void)swiped:(UIPanGestureRecognizer *)pan {
    if (pan.state == UIGestureRecognizerStateBegan) {
        // Two fingers move the feed, not X's pages under them (For you / Following, Explore's tabs): their
        // drag is cancelled and they settle back on their page. Pages X has locked stay locked.
        for (NSUInteger i = 0; i < pan.numberOfTouches; i++) {
            UIView *hit = [pan.view hitTest:[pan locationOfTouch:i inView:pan.view] withEvent:nil];
            for (UIView *s = hit; s; s = s.superview) {
                if (![s isKindOfClass:UIScrollView.class]) continue;
                UIScrollView *scroll = (UIScrollView *)s;
                UIPanGestureRecognizer *drag = scroll.panGestureRecognizer;
                if (!drag.enabled || scroll.contentSize.width <= scroll.bounds.size.width + 1) continue;
                drag.enabled = NO;
                drag.enabled = YES;
            }
        }
        return;
    }
    if (pan.state != UIGestureRecognizerStateEnded) return;
    CGPoint d = [pan translationInView:pan.view];
    if (fabs(d.x) < 60 || fabs(d.x) < 2 * fabs(d.y)) return;
    NSInteger side = LBCFeedPosition(), next = MAX(-1, MIN(1, side + (d.x > 0 ? 1 : -1)));
    if (next == side) return;
    LBCSetFeedPosition(next);
    [self relayout];
}
- (void)relayout {
    UIView *view = self.tabs.viewIfLoaded;
    [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:1 initialSpringVelocity:0 options:0 animations:^{
        [view setNeedsLayout];
        [view layoutIfNeeded];
    } completion:nil];
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return YES;
}
// Only the tabs' own touches where the feed has sides: not the media viewer or sheets over them, not the
// columns or the sidebar, not folded.
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)touch {
    UIView *view = self.tabs.viewIfLoaded;
    return view && LBCPanelWanted(view.window) && [touch.view isDescendantOfView:view];
}
@end

static const void *kLBCSwipe = &kLBCSwipe;

// For the sidebar logo's menu (Tiling.x), after a setting changes.
void LBCRelayout(UIWindow *w) {
    [(LBCSwipe *)objc_getAssociatedObject(w, kLBCSwipe) relayout];
}

// For the sidebar logo's menu (Tiling.x): the slide-over menu opens under the strip, so the columns go first.
void LBCCloseColumns(UIWindow *w) {
    [LBCStripFor(w, NO) closeAfter:-1 animated:NO];
}

static void LBCInstallSwipe(UIWindow *w, UIViewController *tabs) {
    LBCSwipe *swipe = objc_getAssociatedObject(w, kLBCSwipe);
    if (swipe) { swipe.tabs = tabs; return; }
    swipe = [LBCSwipe new];
    swipe.tabs = tabs;
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:swipe action:@selector(swiped:)];
    pan.minimumNumberOfTouches = 2;
    pan.maximumNumberOfTouches = 2;
    pan.cancelsTouchesInView = NO;
    pan.delegate = swipe;
    [w addGestureRecognizer:pan];
    objc_setAssociatedObject(w, kLBCSwipe, swipe, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// As the panel, Explore keeps its search and pages but not its bar's buttons (the gear, the +), which
// iOS 27 shows in a floating bar beside it; they come back when Explore is the selected tab.
static const void *kLBCSavedGroups = &kLBCSavedGroups;

static void LBCTrimExploreBar(UINavigationController *explore, BOOL panel) {
    UIViewController *top = explore.viewControllers.firstObject;
    UINavigationItem *item = top.navigationItem;
    if (@available(iOS 16, *)) {
        NSArray *saved = objc_getAssociatedObject(top, kLBCSavedGroups);
        if (panel && item.trailingItemGroups.count) {
            objc_setAssociatedObject(top, kLBCSavedGroups, item.trailingItemGroups, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            item.trailingItemGroups = @[];
        } else if (!panel && saved) {
            item.trailingItemGroups = saved;
            objc_setAssociatedObject(top, kLBCSavedGroups, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
    Class floating = objc_getClass("_UIFloatingBarContainerView");
    for (UIView *v in explore.viewIfLoaded.subviews)
        if (floating && [v isKindOfClass:floating]) v.hidden = panel;
}

// In the panel's place until Explore exists: what to do about it.
static void LBCShowHint(UIView *tabsView, BOOL show) {
    UILabel *hint = objc_getAssociatedObject(tabsView, kLBCHint);
    if (!show) { hint.hidden = YES; return; }
    if (!hint) {
        hint = [UILabel new];
        hint.text = @"Open Explore once\nand it stays here";
        hint.numberOfLines = 0;
        hint.textAlignment = NSTextAlignmentCenter;
        hint.textColor = [UIColor colorWithWhite:1 alpha:0.35];
        hint.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
        objc_setAssociatedObject(tabsView, kLBCHint, hint, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UIWindow *w = tabsView.window;
    CGFloat panelWidth = LBCPanelWidth(w);
    CGFloat x = LBCFeedOnRight() ? 0 : LBCAvailable(w) - panelWidth;
    hint.frame = [tabsView convertRect:CGRectMake(x, 0, panelWidth, w.bounds.size.height) fromView:nil];
    hint.hidden = NO;
    hint.userInteractionEnabled = NO;
    if (hint.superview != tabsView) [tabsView addSubview:hint];
    [tabsView bringSubviewToFront:hint];
}

// Lays the tabs out: Explore as the panel on the feed's other side and the selected tab narrowed beside
// it, or both as X has them.
static void LBCLayoutPanel(UIViewController *tabs) {
    UIView *view = tabs.viewIfLoaded;
    UIWindow *w = view.window;
    if (!w) return;
    UINavigationController *explore = LBCExploreTab(tabs);
    UIView *exploreView = explore.viewIfLoaded;
    NSString *selected = LBSelectedTabLabel(w);
    BOOL exploreSelected = selected ? [selected isEqualToString:@"Explore"] : (exploreView && !LBCWantsHidden(exploreView));
    BOOL wide = LBCPanelWanted(w);
    BOOL centre = wide && LBCFeedPosition() == 0;
    BOOL panel = wide && LBCExploreEnabled() && exploreView && !exploreSelected && !centre;
    LBCPanelStatus = !wide ? @"no room" : !LBCExploreEnabled() ? @"turned off" : centre ? @"feed full width"
                   : !explore ? @"no Explore tab"
                   : !exploreView ? @"Explore not loaded" : exploreSelected ? @"Explore is the selected tab" : @"shown";
    // X makes a tab the first time it's shown. Switching to Explore on its behalf at launch broke Home's
    // first load (it never finished), so until it's been opened the panel's place says so instead.
    LBCShowHint(view, wide && LBCExploreEnabled() && !exploreView && !exploreSelected && !centre);
    // X lays its tabs out with constraints, which undo frames set from here, so the feed narrows through
    // the safe area its screens already respect (the sidebar's strip is outside them already, Tiling.x's
    // LBFitContent): the selected tab gets the panel's width on the panel's side. Explore keeps its full
    // frame but takes the feed's width on the other side, shows only through its strip (a mask) and takes
    // touches only there.
    CGFloat panelWidth = LBCPanelWidth(w), feed = LBCAvailable(w) - panelWidth;
    BOOL right = wide && LBCFeedOnRight();
    CGRect panelRect = CGRectMake(right ? 0 : feed, 0, panelWidth, w.bounds.size.height);
    for (UIViewController *c in tabs.childViewControllers) {
        if (![c isKindOfClass:UINavigationController.class]) continue;
        BOOL isPanel = c == explore && panel;
        UIEdgeInsets extra = c.additionalSafeAreaInsets;
        CGFloat left = !wide || (centre && !isPanel) ? 0 : isPanel ? (right ? 0 : feed) : (right ? panelWidth : 0);
        CGFloat rightInset = !wide || (centre && !isPanel) ? 0 : isPanel ? (right ? feed : 0) : (right ? 0 : panelWidth);
        if (fabs(extra.left - left) >= 0.5 || fabs(extra.right - rightInset) >= 0.5) {
            LBLog(@"%@ sides %.0f,%.0f -> %.0f,%.0f", NSStringFromClass([(UINavigationController *)c viewControllers].firstObject.class),
                  extra.left, extra.right, left, rightInset);
            extra.left = left;
            extra.right = rightInset;
            c.additionalSafeAreaInsets = extra;
        }
    }
    if (exploreView) {
        objc_setAssociatedObject(exploreView, kLBCPanel, @(panel), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        CGRect inExplore = [exploreView convertRect:panelRect fromView:nil];
        objc_setAssociatedObject(exploreView, kLBCPanelRect, panel ? [NSValue valueWithCGRect:inExplore] : nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (panel) {
            // In front of the tabs X made after it (a tab stays where X first added it): their full-width
            // views would take the panel's touches. Outside its strip, touches still fall through to the feed.
            if (exploreView.superview.subviews.lastObject != exploreView)
                [exploreView.superview bringSubviewToFront:exploreView];
            CALayer *mask = exploreView.layer.mask ?: [CALayer layer];
            mask.backgroundColor = UIColor.blackColor.CGColor;
            mask.frame = inExplore;
            exploreView.layer.mask = mask;
        } else {
            exploreView.layer.mask = nil;
        }
        [exploreView setHidden:LBCWantsHidden(exploreView)];   // re-evaluated by the hook below
    }
    if (explore.isViewLoaded) LBCTrimExploreBar(explore, panel);
    if (wide) view.backgroundColor = UIColor.blackColor;   // beside the feed, with no Explore there
    // Folded the side means nothing: the columns are about to go back on the stack.
    if (wide) LBCStripFor(w, NO).fromLeading = right;
    LBCInstallSwipe(w, tabs);
}

// The bars keep to that safe area, but X's lists don't: the timelines and Explore's pages sit in paging
// cells, which cut a safe area's sides off, and stayed full width under it. So a tab's screen is placed in
// its side outright; the navigation sets its screens' frames, not constraints, so that stays. Left alone
// mid-transition (the slide back folded), and for screens not on a tab's stack.
CGRect LBCFitScreen(UIViewController *vc, CGRect frame) {
    UINavigationController *nav = vc.navigationController;
    UIView *container = vc.viewIfLoaded.superview;
    if (!container || nav.topViewController != vc || nav.transitionCoordinator) return frame;
    if (![nav.parentViewController isKindOfClass:objc_getClass("_TtC11XNavigation16TabBarController")]) return frame;
    UIEdgeInsets extra = nav.additionalSafeAreaInsets, safe = nav.view.safeAreaInsets;
    CGFloat width = container.bounds.size.width;
    BOOL narrowed = extra.left >= 0.5 || extra.right >= 0.5;
    frame.origin.x = narrowed ? safe.left : 0;
    frame.size.width = narrowed ? MAX(0, width - safe.left - safe.right) : width;
    return frame;
}

%group Columns
%hook XNAVNavigationController
- (void)pushViewController:(UIViewController *)vc animated:(BOOL)animated {
    if (LBCPassThrough || !vc || self.viewControllers.count == 0) { %orig; return; }
    UIWindow *w = self.viewIfLoaded.window;
    if (!LBCColumnsWanted(w)) { %orig; return; }
    // Pushed on a tab's own stack, not in a sheet.
    UIViewController *tabs = self.parentViewController;
    if (self.presentingViewController || ![tabs isKindOfClass:objc_getClass("_TtC11XNavigation16TabBarController")]) {
        %orig;
        return;
    }
    LBCStrip *strip = LBCStripFor(w, YES);
    if (!strip) { %orig; return; }
    @try {
        if (strip.rootNavigation != self) [strip closeAfter:-1 animated:NO];
        strip.rootNavigation = self;
        // As LBCLayoutPanel has it, which can't reach the strip before the first push makes it.
        strip.fromLeading = LBCPanelWanted(w) && LBCFeedOnRight();
        // After the column last touched, or from the root (the sliver), replacing every column.
        LBLog(@"column for %@", NSStringFromClass(vc.class));
        [strip open:vc after:strip.touchedColumn animated:animated];
    } @catch (NSException *e) {
        NSLog(@"LiquidBird: couldn't open a column (%@), pushing instead", e);
        @try { [strip closeAfter:-1 animated:NO]; } @catch (NSException *ignored) {}
        if (vc.parentViewController) [vc removeFromParentViewController];
        LBCPassThrough = YES;
        [self pushViewController:vc animated:animated];
        LBCPassThrough = NO;
    }
}
- (void)viewDidLayoutSubviews {
    %orig;
    UIView *screen = self.topViewController.viewIfLoaded;
    if (!screen) return;
    CGRect frame = LBCFitScreen(self.topViewController, screen.frame);
    if (!CGRectEqualToRect(screen.frame, frame)) {
        LBLog(@"%@ fitted %@ -> %@", NSStringFromClass(self.topViewController.class), NSStringFromCGRect(screen.frame),
              NSStringFromCGRect(frame));
        screen.frame = frame;
    }
}
%end

%hook UILayoutContainerView
// A navigation controller's view; X hides the tabs it isn't showing this way. Explore stays shown while
// it's the panel beside the feed.
- (void)setHidden:(BOOL)hidden {
    objc_setAssociatedObject(self, kLBCWantsHidden, @(hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    %orig(hidden && ![objc_getAssociatedObject(self, kLBCPanel) boolValue]);
}
// As the panel, Explore spans the window (masked to its strip) and takes touches only in its strip.
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    NSValue *rect = objc_getAssociatedObject(self, kLBCPanelRect);
    if (rect && !CGRectContainsPoint(rect.CGRectValue, point)) return NO;
    return %orig;
}
%end

%hook _TtC11XNavigation16TabBarController
// Keeps the strip over the content as the window changes; leaving the tab closes its columns, and
// folding puts them back on its stack.
- (void)viewDidLayoutSubviews {
    %orig;
    UIWindow *w = self.viewIfLoaded.window;
    LBCLayoutPanel(self);
    LBCStrip *strip = LBCStripFor(w, NO);
    if (!strip.count) return;
    UINavigationController *root = strip.rootNavigation;
    if (!LBCColumnsWanted(self.viewIfLoaded.window)) {
        // Columns from the Explore panel, which folding hides, go on the tab that's showing instead.
        if (root.viewIfLoaded.hidden)
            for (UIViewController *c in self.childViewControllers)
                if ([c isKindOfClass:UINavigationController.class] && c.viewIfLoaded.window && !c.view.hidden) {
                    strip.rootNavigation = (UINavigationController *)c;
                    break;
                }
        [strip foldBackOntoStack];
    } else if (!root.viewIfLoaded.window || root.view.hidden) {
        [strip closeAfter:-1 animated:NO];
    }
}
%end
%end

%ctor {
    if (objc_getClass("XNAVNavigationController") && objc_getClass("_TtC11XNavigation16TabBarController")) %init(Columns);
}
