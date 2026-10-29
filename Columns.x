#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

// Step 2 of the tiling: Twitter for iPad's columns where there's room beside the sidebar (the Duo
// unfolded), after gi-os/twitter's TabStackView. Opening a tweet, profile or link from the current tab
// doesn't push it: it becomes a column to the right of the one it came from (replacing any after it),
// and the newest slides in at the trailing edge, over the tab's root, which stays put underneath with
// a sliver showing. The columns are one strip you slide sideways, snapping to column edges in the
// direction you flick; a column's close button closes it and the ones after it, and tapping outside the
// columns (the dimmed sliver of the tab) closes them all. Leaving the tab closes them; narrowing
// (folding) puts them back on the tab's own stack, in order.
//
// Each column is a plain navigation controller of its own (LBColumnNavigationController: creating X's
// XNAVNavigationController outside its tabs crashed), in a container under the app's root beside the
// sidebar, not in X's tab bar controller, which expects only its own tabs. A push from inside a column
// opens the next column. If opening a column throws, the push goes ahead as usual instead.
//
// With room for both (the Duo unfolded), the tab's feed narrows and X's own trends page stands beside it
// as a column that stays, like X desktop's right sidebar; what opens from it opens as columns, which
// slide over it.

@interface XNAVNavigationController : UINavigationController
@end
@interface _TtC11XNavigation16TabBarController : UIViewController
@end

// gi-os/twitter's ColumnLayout: columns prefer 476pt, need 400, and leave at least a 160pt sliver of
// what they came from.
static const CGFloat LBCPreferred = 476, LBCMinimum = 400, LBCSliver = 160;
static BOOL LBCPassThrough;   // pushes the strip makes itself, folding columns back onto the stack

// The sidebar's strip down the trailing edge (Tiling.x): the safe area there, or its default.
static CGFloat LBCSidebarWidth(UIWindow *w) {
    CGFloat r = w.safeAreaInsets.right;
    return r >= 40 ? r : 66;
}

static CGFloat LBCAvailable(UIWindow *w) { return w ? w.bounds.size.width - LBCSidebarWidth(w) : 0; }

// Room for a column and the sliver beside the sidebar: the Duo unfolded, not folded.
static BOOL LBCColumnsWanted(UIWindow *w) { return LBCAvailable(w) >= LBCMinimum + LBCSliver; }

@class LBCStrip;
@interface LBColumnNavigationController : UINavigationController
@property (nonatomic, weak) LBCStrip *strip;
@end

static UINavigationController *LBCMakeNavigation(UIViewController *vc) {
    LBColumnNavigationController *nav = [[LBColumnNavigationController alloc] initWithRootViewController:vc];
    nav.view.accessibilityIdentifier = @"LBColumn";   // Tiling.x keeps a column's bar (its ✕)
    return nav;
}

@interface LBCStrip : UIView <UIScrollViewDelegate>
@property (nonatomic, weak) UINavigationController *rootNavigation;   // the tab's own stack
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
        [self addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(outsideTapped:)]];
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
    CGPoint p = [tap locationInView:self];
    for (UIView *card in _cards)
        if (CGRectContainsPoint([self convertRect:card.bounds fromView:card], p)) return;
    [self closeAfter:-1 animated:YES];
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
    ((LBColumnNavigationController *)nav).strip = self;
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

// Snaps to column edges, in the direction flicked (Twitter for iPad's bestOffsetForPossibleOffsets:).
- (void)scrollViewWillEndDragging:(UIScrollView *)scrollView withVelocity:(CGPoint)velocity
              targetContentOffset:(inout CGPoint *)target {
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

// MARK: - Trends beside the feed

static const CGFloat LBCWide = 600, LBCTrendsMinimum = 240, LBCTrendsMaximum = 380;
static const void *kLBCTrends = &kLBCTrends;
static BOOL LBCTrendsChecked, LBCTrendsFailed;   // this launch

static BOOL LBCTrendsWanted(UIWindow *w) {
    return LBCAvailable(w) >= LBCWide && ![NSUserDefaults.standardUserDefaults boolForKey:@"liquidbird_trends_crashed"];
}
static CGFloat LBCTrendsWidth(UIWindow *w) {
    return round(MIN(LBCTrendsMaximum, MAX(LBCTrendsMinimum, LBCAvailable(w) * 0.4)));
}

static id LBCMsg(id target, NSString *selector) {
    SEL sel = NSSelectorFromString(selector);
    return [target respondsToSelector:sel] ? ((id (*)(id, SEL))objc_msgSend)(target, sel) : nil;
}

// X's trends page, as its Explore makes it: from the account and its feature switches.
static UIViewController *LBCMakeTrends(void) {
    Class trendsClass = objc_getClass("T1TrendsLandingViewController"), featuresClass = objc_getClass("T1ExploreFeatures");
    id account = LBCMsg(LBCMsg(objc_getClass("T1HostViewController"), @"sharedHostViewController"), @"currentAccount");
    id switches = LBCMsg(account, @"featureSwitches");
    SEL initFeatures = NSSelectorFromString(@"initWithFeatureSwitches:");
    SEL initTrends = NSSelectorFromString(@"initWithFeatures:account:scribeContext:");
    if (!trendsClass || !featuresClass || !account || !switches ||
        ![featuresClass instancesRespondToSelector:initFeatures] || ![trendsClass instancesRespondToSelector:initTrends]) return nil;
    id features = ((id (*)(id, SEL, id))objc_msgSend)([featuresClass alloc], initFeatures, switches);
    return ((id (*)(id, SEL, id, id, id))objc_msgSend)([trendsClass alloc], initTrends, features, account, nil);
}

// Puts the trends column beside the feed (or takes it away), under the strip. If making it ever
// crashes the app (the flag set while it opens outlives the launch), it isn't tried again.
static LBColumnNavigationController *LBCUpdateTrends(UIWindow *w) {
    LBColumnNavigationController *trends = objc_getAssociatedObject(w, kLBCTrends);
    UIView *host = w.rootViewController.viewIfLoaded;
    if (!host || !LBCTrendsWanted(w)) {
        if (trends) {
            [trends willMoveToParentViewController:nil];
            [trends.view removeFromSuperview];
            [trends removeFromParentViewController];
            objc_setAssociatedObject(w, kLBCTrends, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        return nil;
    }
    LBCStrip *strip = LBCStripFor(w, YES);
    UIViewController *container = objc_getAssociatedObject(w, kLBCContainer);
    if (!strip || !container) return nil;
    if (!trends) {
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        if (!LBCTrendsChecked) {
            LBCTrendsChecked = YES;
            if ([defaults boolForKey:@"liquidbird_trends_opening"]) {
                [defaults setBool:YES forKey:@"liquidbird_trends_crashed"];
                [defaults removeObjectForKey:@"liquidbird_trends_opening"];
                return nil;
            }
        }
        if (LBCTrendsFailed) return nil;
        [defaults setBool:YES forKey:@"liquidbird_trends_opening"];
        UIViewController *page = nil;
        @try { page = LBCMakeTrends(); } @catch (NSException *e) { page = nil; }
        if (!page) {
            LBCTrendsFailed = YES;
            [defaults removeObjectForKey:@"liquidbird_trends_opening"];
            return nil;
        }
        trends = [[LBColumnNavigationController alloc] initWithRootViewController:page];
        trends.strip = strip;
        trends.view.accessibilityIdentifier = @"LBColumn";
        [container addChildViewController:trends];
        [host insertSubview:trends.view belowSubview:strip];
        [trends didMoveToParentViewController:container];
        objc_setAssociatedObject(w, kLBCTrends, trends, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [defaults removeObjectForKey:@"liquidbird_trends_opening"];
        });
    }
    CGFloat width = LBCTrendsWidth(w);
    CGRect frame = [host convertRect:CGRectMake(LBCAvailable(w) - width, 0, width, w.bounds.size.height) fromView:nil];
    if (!CGRectEqualToRect(trends.view.frame, frame)) trends.view.frame = frame;
    if (trends.view.superview != host) [host insertSubview:trends.view belowSubview:strip];
    return trends;
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
        // After the column last touched, or from the root (the sliver), replacing every column.
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
%end

%hook _TtC11XNavigation16TabBarController
// Keeps the strip over the content as the window changes; leaving the tab closes its columns, and
// folding puts them back on its stack.
- (void)viewDidLayoutSubviews {
    %orig;
    UIWindow *w = self.viewIfLoaded.window;
    // With the trends column beside it, the tab's feed narrows to the rest of the room.
    LBColumnNavigationController *trends = w ? LBCUpdateTrends(w) : nil;
    CGFloat feed = trends ? [self.view convertRect:CGRectMake(0, 0, LBCAvailable(w) - LBCTrendsWidth(w), 1) fromView:nil].size.width
                          : self.view.bounds.size.width;
    Class xnav = objc_getClass("XNAVNavigationController");
    for (UIViewController *c in self.childViewControllers) {
        UIView *v = c.viewIfLoaded;
        if (!v.window || ![c isKindOfClass:xnav]) continue;
        CGRect f = v.frame;
        if (fabs(f.size.width - feed) < 0.5) continue;
        f.size.width = feed;
        v.frame = f;
    }
    LBCStrip *strip = LBCStripFor(w, NO);
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
