#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// Twitter for iPad's layout on the iPhone Duo's wide poses, after gi-os/twitter's TabStackView and
// ClassicSidebar, in Liquid Glass. A glass rail of the tabs runs down the strip the status bar sits
// in on the trailing edge, between the status bar and X's own compose button, in place of the tab
// bar; where there's room for two columns, the current tab is a column card centred on a backdrop.
// Narrow windows (folded) stay stock. Step 1 of 2; step 2 opens tweets, profiles and links as
// further columns.
//
// The rail mirrors whichever tab bar the app is using: X's Liquid Glass one (XNavigation's
// TabBarView of TabBarItemViews, which select on accessibilityActivate, as VoiceOver does) or the
// older T1TabBarViewController (tabViews, selected through its delegate, as a tap is).

@interface T1TabbedAppNavigationViewController : UIViewController
- (UIViewController *)selectedViewController;
- (void)tabBarViewController:(id)tabBarViewController selectTabAtIndex:(NSInteger)index withView:(UIView *)view;
@end

@interface T1TabBarViewController : UIViewController
- (NSArray<UIView *> *)tabViews;
- (NSInteger)selectedTabIndex;
- (id)delegate;
- (void)setTabBarHidden:(BOOL)hidden withDuration:(double)duration completion:(id)completion;
@end

@interface _TtC11XNavigation10TabBarView : UIView
@end
@interface _TtC11XNavigation10TabBarPill : UIView
@end

static const CGFloat LBColumnWidth = 476;          // gi-os/twitter's ColumnLayout
static const CGFloat LBMinimumColumnWidth = 400;
static const CGFloat LBCardRadius = 26;
static const CGFloat LBSidebarWindow = 600;        // wider than any iPhone held upright: the Duo's poses
static const CGFloat LBGlassWidth = 52;
static const CGFloat LBRow = 48;
// Where the status bar runs down the side and the safe area doesn't say how wide its strip is.
static const CGFloat LBStripDefault = 100;

static const void *kLBSidebar = &kLBSidebar;
static const void *kLBGlassTabBar = &kLBGlassTabBar;
static const void *kLBCompose = &kLBCompose;
static const void *kLBWantedAlpha = &kLBWantedAlpha;
static const void *kLBTiled = &kLBTiled;

static BOOL LBSidebarWanted(UIWindow *w) { return w && w.bounds.size.width >= LBSidebarWindow; }

static UIVisualEffectView *LBGlassView(UIColor *tint) {
    UIVisualEffect *effect;
    if (@available(iOS 26, *)) {
        UIGlassEffect *g = [UIGlassEffect effectWithStyle:UIGlassEffectStyleRegular];
        g.interactive = YES;
        g.tintColor = tint;
        effect = g;
    } else {
        effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialDark];
    }
    UIVisualEffectView *v = [[UIVisualEffectView alloc] initWithEffect:effect];
    v.layer.cornerCurve = kCACornerCurveContinuous;
    return v;
}

// The largest image a tab shows, for the rail's copy of that tab.
static UIImage *LBTabImage(UIView *tab) {
    UIImage *best = nil;
    CGFloat area = 0;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:tab];
    while (queue.count) {
        UIView *v = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([v isKindOfClass:UIImageView.class] && !v.hidden) {
            UIImage *i = ((UIImageView *)v).image;
            if (i && i.size.width * i.size.height > area) { best = i; area = i.size.width * i.size.height; }
        }
        [queue addObjectsFromArray:v.subviews];
    }
    return best;
}

static UIImage *LBFallbackImage(NSString *label, BOOL selected) {
    NSDictionary<NSString *, NSString *> *map = @{@"home": @"house", @"search": @"magnifyingglass",
        @"explore": @"magnifyingglass", @"notification": @"bell", @"message": @"envelope", @"grok": @"sparkles",
        @"communit": @"person.2", @"profile": @"person", @"bookmark": @"bookmark", @"list": @"list.bullet"};
    NSString *name = @"circle";
    for (NSString *k in map)
        if ([label rangeOfString:k options:NSCaseInsensitiveSearch].location != NSNotFound) { name = map[k]; break; }
    if (selected && ![name isEqualToString:@"magnifyingglass"]) name = [name stringByAppendingString:@".fill"];
    UIImageSymbolConfiguration *c = [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightRegular];
    return [UIImage systemImageNamed:name withConfiguration:c] ?: [UIImage systemImageNamed:@"circle" withConfiguration:c];
}

// MARK: - The rail

@interface LBSidebar : UIView
@property (nonatomic) CGFloat top;       // under the status bar
@property (nonatomic) CGFloat bottom;    // above the compose button
- (void)setTabs:(NSArray<UIView *> *)tabs selected:(NSInteger)selected activate:(void (^)(NSInteger))activate;
@end

@implementation LBSidebar {
    UIVisualEffectView *_rail;
    NSMutableArray<UIButton *> *_buttons;
    void (^_activate)(NSInteger);
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;
        _rail = LBGlassView(nil);
        [self addSubview:_rail];
        _buttons = [NSMutableArray array];
    }
    return self;
}

// Only the glass takes touches; the strip around it stays the app's.
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    return !_rail.hidden && CGRectContainsPoint(_rail.frame, point);
}

- (void)tapped:(UIButton *)b {
    if (_activate) _activate(b.tag);
}

- (void)setTabs:(NSArray<UIView *> *)tabs selected:(NSInteger)selected activate:(void (^)(NSInteger))activate {
    _activate = [activate copy];
    while (_buttons.count > tabs.count) { [_buttons.lastObject removeFromSuperview]; [_buttons removeLastObject]; }
    while (_buttons.count < tabs.count) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.layer.cornerCurve = kCACornerCurveContinuous;
        [b addTarget:self action:@selector(tapped:) forControlEvents:UIControlEventTouchUpInside];
        [_rail.contentView addSubview:b];
        [_buttons addObject:b];
    }
    for (NSUInteger i = 0; i < tabs.count; i++) {
        UIButton *b = _buttons[i];
        BOOL on = (NSInteger)i == selected;
        UIImage *img = LBTabImage(tabs[i]) ?: LBFallbackImage(tabs[i].accessibilityLabel, on);
        b.tag = (NSInteger)i;
        [b setImage:[img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forState:UIControlStateNormal];
        b.imageView.contentMode = UIViewContentModeScaleAspectFit;
        b.tintColor = on ? UIColor.whiteColor : [UIColor colorWithWhite:0.62 alpha:1];
        // The selected tab sits on a lighter lozenge inside the rail, as in the system's glass tab bar.
        b.backgroundColor = on ? [UIColor colorWithWhite:1 alpha:0.16] : UIColor.clearColor;
        b.accessibilityLabel = tabs[i].accessibilityLabel;
        b.selected = on;
    }
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat pad = 4;
    CGFloat height = _buttons.count * LBRow + 2 * pad;
    CGFloat room = self.bottom - self.top;
    // Centred between the status bar and compose, or from the top when that's all the room there is.
    CGFloat y = room > height ? self.top + round((room - height) / 2) : self.top;
    _rail.hidden = _buttons.count == 0;
    _rail.frame = CGRectMake(round((self.bounds.size.width - LBGlassWidth) / 2), y, LBGlassWidth, height);
    _rail.layer.cornerRadius = LBGlassWidth / 2;
    for (NSUInteger i = 0; i < _buttons.count; i++) {
        UIButton *b = _buttons[i];
        b.frame = CGRectMake(pad, pad + i * LBRow, LBGlassWidth - 2 * pad, LBRow);
        b.layer.cornerRadius = (LBGlassWidth - 2 * pad) / 2;
    }
}
@end

// MARK: - Placing it

static UIView *LBFind(UIView *v, Class cls, NSInteger depth) {
    if (!cls || depth > 30) return nil;
    if ([v isKindOfClass:cls]) return v;
    if ([v isKindOfClass:UITableViewCell.class] || [v isKindOfClass:UICollectionViewCell.class]) return nil;
    for (UIView *s in v.subviews) {
        UIView *r = LBFind(s, cls, depth + 1);
        if (r) return r;
    }
    return nil;
}

// The strip down the trailing edge: the safe area there, which the status bar's strip is, or a default.
static CGFloat LBStripWidth(UIView *host) {
    CGFloat r = host.safeAreaInsets.right;
    return r >= 40 ? r : LBStripDefault;
}

// Under the status bar where it runs down the side (iPhone Duo), else under the top safe area.
static CGFloat LBStatusBottom(UIView *host) {
    CGRect sb = [host convertRect:host.window.windowScene.statusBarManager.statusBarFrame fromView:nil];
    if (!CGRectIsEmpty(sb) && CGRectGetMinX(sb) > host.bounds.size.width / 2) return CGRectGetMaxY(sb) + 16;
    if (host.safeAreaInsets.right > 0 && host.safeAreaInsets.top < 1) return 232;
    return host.safeAreaInsets.top + 16;
}

// X's compose button where it sits in the strip, looked up again only when the one found has gone.
static CGFloat LBComposeTop(UIWindow *w, UIView *host, CGFloat strip) {
    CGFloat fallback = host.bounds.size.height - MAX(host.safeAreaInsets.bottom, 12) - 96;
    UIView *compose = [objc_getAssociatedObject(w, kLBCompose) nonretainedObjectValue];
    if (!compose || compose.window != w) {
        compose = nil;
        for (NSString *name in @[@"TFNFloatingActionButton", @"_TtC11XNavigation25TabBarAccessoryButtonView"]) {
            compose = LBFind(host, objc_getClass(name.UTF8String), 0);
            if (compose) break;
        }
        objc_setAssociatedObject(w, kLBCompose, compose ? [NSValue valueWithNonretainedObject:compose] : nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (!compose || compose.hidden || compose.alpha < 0.01) return fallback;
    CGRect f = [host convertRect:compose.bounds fromView:compose];
    if (CGRectGetMidX(f) < host.bounds.size.width - strip) return fallback;
    return CGRectGetMinY(f) - 16;
}

static void LBUpdateSidebar(UIWindow *w, NSArray<UIView *> *tabs, NSInteger selected, void (^activate)(NSInteger)) {
    LBSidebar *bar = objc_getAssociatedObject(w, kLBSidebar);
    UIView *host = w.rootViewController.viewIfLoaded;
    if (!host || !LBSidebarWanted(w) || tabs.count == 0) { [bar removeFromSuperview]; return; }
    if (!bar) {
        bar = [[LBSidebar alloc] initWithFrame:CGRectZero];
        objc_setAssociatedObject(w, kLBSidebar, bar, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    CGFloat strip = LBStripWidth(host);
    if (bar.superview != host) [host addSubview:bar];
    [host bringSubviewToFront:bar];
    bar.frame = CGRectMake(host.bounds.size.width - strip, 0, strip, host.bounds.size.height);
    bar.top = LBStatusBottom(host);
    bar.bottom = LBComposeTop(w, host, strip);
    [bar setTabs:tabs selected:selected activate:activate];
}

// MARK: - X's Liquid Glass tab bar

static NSArray<UIView *> *LBGlassTabs(UIView *tabBar) {
    NSMutableArray<UIView *> *tabs = [NSMutableArray array];
    Class item = objc_getClass("_TtC11XNavigation14TabBarItemView");
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithArray:tabBar.subviews];
    while (queue.count && item) {
        UIView *v = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([v isKindOfClass:item]) [tabs addObject:v];
        else [queue addObjectsFromArray:v.subviews];
    }
    [tabs sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        CGFloat ax = [tabBar convertPoint:CGPointZero fromView:a].x, bx = [tabBar convertPoint:CGPointZero fromView:b].x;
        return ax < bx ? NSOrderedAscending : ax > bx ? NSOrderedDescending : NSOrderedSame;
    }];
    return tabs;
}

// X's tab bar fades out while the rail stands in for it; the alpha the app asks for is kept for when
// the window narrows again. (Faded below 0.01, it takes no touches either.)
static CGFloat LBWantedAlpha(UIView *v) {
    NSNumber *n = objc_getAssociatedObject(v, kLBWantedAlpha);
    return n ? n.doubleValue : 1;
}

static CGFloat LBBarAlpha(UIView *v, CGFloat wanted) {
    objc_setAssociatedObject(v, kLBWantedAlpha, @(wanted), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return LBSidebarWanted(v.window) ? 0 : wanted;
}

static void LBSyncGlassTabBar(UIView *tabBar) {
    UIWindow *w = tabBar.window;
    if (!w) return;
    objc_setAssociatedObject(w, kLBGlassTabBar, [NSValue valueWithNonretainedObject:tabBar], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSArray<UIView *> *tabs = LBGlassTabs(tabBar);
    NSInteger selected = -1;
    for (NSUInteger i = 0; i < tabs.count; i++)
        if (tabs[i].accessibilityTraits & UIAccessibilityTraitSelected) { selected = (NSInteger)i; break; }
    __weak UIView *weakBar = tabBar;
    LBUpdateSidebar(w, tabs, selected, ^(NSInteger i) {
        NSArray<UIView *> *now = LBGlassTabs(weakBar);
        if (i < (NSInteger)now.count) [now[i] accessibilityActivate];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [weakBar setNeedsLayout];
        });
    });
}

%group GlassTabBar
%hook _TtC11XNavigation10TabBarView
- (void)layoutSubviews {
    %orig;
    [self setAlpha:LBWantedAlpha(self)];
    LBSyncGlassTabBar(self);
}
- (void)setAlpha:(CGFloat)alpha {
    %orig(LBBarAlpha(self, alpha));
}
%end

%hook _TtC11XNavigation10TabBarPill
- (void)layoutSubviews {
    %orig;
    [self setAlpha:LBWantedAlpha(self)];
}
- (void)setAlpha:(CGFloat)alpha {
    %orig(LBBarAlpha(self, alpha));
}
%end
%end

// MARK: - The older tab bar, and the column card

static UIViewController *LBChild(UIViewController *vc, Class cls, NSInteger depth) {
    if (!cls || depth > 4) return nil;
    for (UIViewController *c in vc.childViewControllers) {
        if ([c isKindOfClass:cls]) return c;
        UIViewController *r = LBChild(c, cls, depth + 1);
        if (r) return r;
    }
    return nil;
}

static UIColor *LBBackdrop(void) { return [UIColor colorWithRed:0.05 green:0.055 blue:0.065 alpha:1]; }

static void LBUncard(UIView *card) {
    if (card.layer.cornerRadius != LBCardRadius) return;
    card.layer.cornerRadius = 0;
    card.layer.masksToBounds = NO;
    card.layer.borderWidth = 0;
    if (card.superview) card.frame = card.superview.bounds;
}

static void LBApplyTiling(T1TabbedAppNavigationViewController *nav) {
    UIView *root = nav.viewIfLoaded;
    UIWindow *w = root.window;
    if (!w) return;
    BOOL side = LBSidebarWanted(w);
    BOOL was = [objc_getAssociatedObject(nav, kLBTiled) boolValue];
    T1TabBarViewController *tb = (T1TabBarViewController *)LBChild(nav, objc_getClass("T1TabBarViewController"), 0);
    UIViewController *selectedVC = [nav respondsToSelector:@selector(selectedViewController)] ? [nav selectedViewController] : nil;
    UIView *card = selectedVC.viewIfLoaded;
    // With X's glass tab bar in this window, that drives the rail.
    BOOL glass = [objc_getAssociatedObject(w, kLBGlassTabBar) nonretainedObjectValue] != nil;

    if (side != was) {
        objc_setAssociatedObject(nav, kLBTiled, @(side), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (!glass && [tb respondsToSelector:@selector(setTabBarHidden:withDuration:completion:)])
            [tb setTabBarHidden:side withDuration:0 completion:nil];
        if (!side) LBUncard(card);
    }
    if (!side) return;

    if (!glass) {
        NSArray<UIView *> *tabs = [tb respondsToSelector:@selector(tabViews)] ? [tb tabViews] : @[];
        NSInteger selected = [tb respondsToSelector:@selector(selectedTabIndex)] ? [tb selectedTabIndex] : -1;
        __weak T1TabBarViewController *weakTB = tb;
        __weak T1TabbedAppNavigationViewController *weakNav = nav;
        LBUpdateSidebar(w, tabs, selected, ^(NSInteger i) {
            T1TabBarViewController *t = weakTB;
            NSArray<UIView *> *views = [t tabViews];
            if (i >= (NSInteger)views.count) return;
            // As the tab bar does on a tap, so reselecting still scrolls to the top.
            id target = [t delegate];
            if (![target respondsToSelector:@selector(tabBarViewController:selectTabAtIndex:withView:)]) target = weakNav;
            [target tabBarViewController:t selectTabAtIndex:i withView:views[i]];
            [weakNav.viewIfLoaded setNeedsLayout];
        });
    }

    // The current tab as a column card, where the space left of the strip holds two columns.
    UIView *container = card.superview;
    if (!container) return;
    CGFloat strip = LBStripWidth(w.rootViewController.viewIfLoaded ?: root);
    CGRect area = [container convertRect:CGRectMake(0, 0, root.bounds.size.width - strip, root.bounds.size.height) fromView:root];
    if (area.size.width < 2 * LBMinimumColumnWidth) { LBUncard(card); return; }
    root.backgroundColor = LBBackdrop();
    if (container != root) container.backgroundColor = LBBackdrop();
    // In from the top as far as the bottom keeps clear (gi-os/twitter's card margins).
    CGFloat m = MAX(root.safeAreaInsets.bottom, 12);
    CGFloat width = MIN(LBColumnWidth, area.size.width - 2 * m);
    CGRect f = CGRectMake(round(CGRectGetMidX(area) - width / 2), CGRectGetMinY(area) + m, width, area.size.height - 2 * m);
    if (!CGRectEqualToRect(card.frame, f)) card.frame = f;
    card.layer.cornerRadius = LBCardRadius;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.layer.masksToBounds = YES;
    card.layer.borderWidth = 1 / MAX(root.traitCollection.displayScale, 1);
    card.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.12].CGColor;
}

%group Tiling
%hook T1TabbedAppNavigationViewController
- (void)viewDidLayoutSubviews {
    %orig;
    LBApplyTiling(self);
}
%end

%hook T1TabBarViewController
// The older tab bar stays hidden while the rail stands in for it (scrolling would otherwise bring it back).
- (void)setTabBarHidden:(BOOL)hidden withDuration:(double)duration completion:(id)completion {
    UIWindow *w = self.viewIfLoaded.window;
    BOOL glass = [objc_getAssociatedObject(w, kLBGlassTabBar) nonretainedObjectValue] != nil;
    %orig(hidden || (!glass && LBSidebarWanted(w)), duration, completion);
}
%end
%end

%ctor {
    if (objc_getClass("_TtC11XNavigation10TabBarView") && objc_getClass("_TtC11XNavigation10TabBarPill")) %init(GlassTabBar);
    if (objc_getClass("T1TabbedAppNavigationViewController") && objc_getClass("T1TabBarViewController")) %init(Tiling);
}
