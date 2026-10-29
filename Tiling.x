#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// Twitter for iPad's layout on a wide window (the iPhone Duo unfolded), after gi-os/twitter's
// TabStackView and ClassicSidebar, in Liquid Glass: down the strip the status bar runs in on the
// trailing edge, a glass compose button under the status bar and a glass rail of the tabs at the
// bottom, in place of the tab bar and the floating compose button; the current tab is a column card
// centred on a backdrop. Narrow windows stay stock. Step 1 of 2; step 2 opens tweets, profiles and
// links as further columns.

@interface T1TabbedAppNavigationViewController : UIViewController
- (UIViewController *)selectedViewController;
- (UINavigationController *)currentTabNavigationController;
- (void)tabBarViewController:(id)tabBarViewController selectTabAtIndex:(NSInteger)index withView:(UIView *)view;
@end

@interface T1TabBarViewController : UIViewController
- (NSArray<UIView *> *)tabViews;
- (NSInteger)selectedTabIndex;
- (id)delegate;
- (void)setTabBarHidden:(BOOL)hidden withDuration:(double)duration completion:(id)completion;
@end

@interface T1TabNavigationController : UINavigationController
- (void)showComposeFromBarButtonItem:(UIBarButtonItem *)item;
@end

@interface TFNFloatingActionButton : UIView
@end

// gi-os/twitter's ColumnLayout width; corners and sizes in Liquid Glass proportions.
static const CGFloat LBColumnWidth = 476;
static const CGFloat LBCardRadius = 26;
static const CGFloat LBWideWindow = 700;
static const CGFloat LBGlassWidth = 52;
// Where iPhone Duo's status bar runs down the side, its centre line sits this far in from the edge.
static const CGFloat LBStatusCentreDefault = 50;

static BOOL LBWide(UIView *v) {
    UIWindow *w = v.window;
    return w && w.bounds.size.width >= LBWideWindow;
}

static UIColor *LBBackdrop(void) { return [UIColor colorWithRed:0.05 green:0.055 blue:0.065 alpha:1]; }

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

// The largest image a tab view shows, for the sidebar's copy of that tab.
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

@interface LBSidebar : UIView
@property (nonatomic, weak) T1TabbedAppNavigationViewController *nav;
@property (nonatomic, weak) T1TabBarViewController *tabBar;
@property (nonatomic) CGFloat topInset;
- (void)reloadTabs;
@end

@implementation LBSidebar {
    UIVisualEffectView *_composeGlass;
    UIButton *_compose;
    UIVisualEffectView *_rail;
    NSMutableArray<UIButton *> *_tabs;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;
        _composeGlass = LBGlassView([UIColor colorWithRed:0.11 green:0.61 blue:0.94 alpha:1]);
        [self addSubview:_composeGlass];
        _compose = [UIButton buttonWithType:UIButtonTypeSystem];
        UIImageSymbolConfiguration *c = [UIImageSymbolConfiguration configurationWithPointSize:19 weight:UIImageSymbolWeightSemibold];
        [_compose setImage:[UIImage systemImageNamed:@"square.and.pencil" withConfiguration:c] forState:UIControlStateNormal];
        _compose.tintColor = UIColor.whiteColor;
        _compose.accessibilityLabel = @"New Tweet";
        [_compose addTarget:self action:@selector(composeTapped) forControlEvents:UIControlEventTouchUpInside];
        [_composeGlass.contentView addSubview:_compose];
        _rail = LBGlassView(nil);
        [self addSubview:_rail];
        _tabs = [NSMutableArray array];
    }
    return self;
}

// Only the glass takes touches; the strip around it is the content's.
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    return CGRectContainsPoint(_composeGlass.frame, point) || (!_rail.hidden && CGRectContainsPoint(_rail.frame, point));
}

- (void)composeTapped {
    T1TabbedAppNavigationViewController *nav = self.nav;
    id tabNav = [nav respondsToSelector:@selector(currentTabNavigationController)] ? [nav currentTabNavigationController] : nil;
    if ([tabNav respondsToSelector:@selector(showComposeFromBarButtonItem:)]) {
        UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCompose target:nil action:nil];
        [tabNav showComposeFromBarButtonItem:item];
    }
}

- (void)tabTapped:(UIButton *)b {
    T1TabBarViewController *tb = self.tabBar;
    NSArray<UIView *> *views = [tb respondsToSelector:@selector(tabViews)] ? [tb tabViews] : nil;
    if (b.tag < 0 || b.tag >= (NSInteger)views.count) return;
    // As the tab bar does on a tap, so reselecting still scrolls to the top.
    id target = [tb respondsToSelector:@selector(delegate)] ? [tb delegate] : nil;
    if (![target respondsToSelector:@selector(tabBarViewController:selectTabAtIndex:withView:)]) target = self.nav;
    if ([target respondsToSelector:@selector(tabBarViewController:selectTabAtIndex:withView:)])
        [target tabBarViewController:tb selectTabAtIndex:b.tag withView:views[b.tag]];
    [self reloadTabs];
}

- (void)reloadTabs {
    T1TabBarViewController *tb = self.tabBar;
    NSArray<UIView *> *views = [tb respondsToSelector:@selector(tabViews)] ? [tb tabViews] : @[];
    NSInteger selected = [tb respondsToSelector:@selector(selectedTabIndex)] ? [tb selectedTabIndex] : -1;
    while (_tabs.count > views.count) { [_tabs.lastObject removeFromSuperview]; [_tabs removeLastObject]; }
    while (_tabs.count < views.count) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.layer.cornerCurve = kCACornerCurveContinuous;
        [b addTarget:self action:@selector(tabTapped:) forControlEvents:UIControlEventTouchUpInside];
        [_rail.contentView addSubview:b];
        [_tabs addObject:b];
    }
    for (NSUInteger i = 0; i < views.count; i++) {
        UIButton *b = _tabs[i];
        BOOL on = (NSInteger)i == selected;
        UIImage *img = LBTabImage(views[i]) ?: LBFallbackImage(views[i].accessibilityLabel, on);
        b.tag = (NSInteger)i;
        [b setImage:[img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forState:UIControlStateNormal];
        b.imageView.contentMode = UIViewContentModeScaleAspectFit;
        b.tintColor = on ? UIColor.whiteColor : [UIColor colorWithWhite:0.62 alpha:1];
        // The selected tab sits on a lighter lozenge inside the rail, as in the system's glass tab bar.
        b.backgroundColor = on ? [UIColor colorWithWhite:1 alpha:0.16] : UIColor.clearColor;
        b.accessibilityLabel = views[i].accessibilityLabel;
        b.selected = on;
    }
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize s = self.bounds.size;
    CGFloat x = round((s.width - LBGlassWidth) / 2);
    _composeGlass.frame = CGRectMake(x, self.topInset, LBGlassWidth, LBGlassWidth);
    _composeGlass.layer.cornerRadius = LBGlassWidth / 2;
    _compose.frame = _composeGlass.contentView.bounds;
    CGFloat row = 48, pad = 4;
    CGFloat railHeight = _tabs.count * row + 2 * pad;
    CGFloat bottom = s.height - MAX(self.safeAreaInsets.bottom, 12);
    _rail.hidden = _tabs.count == 0;
    _rail.frame = CGRectMake(x, bottom - railHeight, LBGlassWidth, railHeight);
    _rail.layer.cornerRadius = LBGlassWidth / 2;
    for (NSUInteger i = 0; i < _tabs.count; i++) {
        UIButton *b = _tabs[i];
        b.frame = CGRectMake(pad, pad + i * row, LBGlassWidth - 2 * pad, row);
        b.layer.cornerRadius = (LBGlassWidth - 2 * pad) / 2;
    }
}
@end

static const void *kLBTiled = &kLBTiled;
static const void *kLBSidebar = &kLBSidebar;
static const void *kLBFABWantsHidden = &kLBFABWantsHidden;

static UIViewController *LBChild(UIViewController *vc, Class cls, NSInteger depth) {
    if (!cls || depth > 4) return nil;
    for (UIViewController *c in vc.childViewControllers) {
        if ([c isKindOfClass:cls]) return c;
        UIViewController *r = LBChild(c, cls, depth + 1);
        if (r) return r;
    }
    return nil;
}

static void LBRefreshFABs(UIView *v, Class fab) {
    if ([v isKindOfClass:fab]) { v.hidden = [objc_getAssociatedObject(v, kLBFABWantsHidden) boolValue]; return; }
    for (UIView *s in v.subviews) LBRefreshFABs(s, fab);
}

// Under the status bar where it runs down the side (iPhone Duo), else under the top safe area.
static CGFloat LBSidebarTop(UIView *root) {
    CGRect sb = [root convertRect:root.window.windowScene.statusBarManager.statusBarFrame fromView:nil];
    if (!CGRectIsEmpty(sb) && CGRectGetMinX(sb) > root.bounds.size.width / 2) return CGRectGetMaxY(sb) + 12;
    if (root.safeAreaInsets.right > 0 && root.safeAreaInsets.top < 1) return 232;
    return root.safeAreaInsets.top + 12;
}

// How far in from the trailing edge the status bar's centre line runs, where it runs down the side.
static CGFloat LBStatusCentreInset(UIView *root) {
    CGRect sb = [root convertRect:root.window.windowScene.statusBarManager.statusBarFrame fromView:nil];
    if (!CGRectIsEmpty(sb) && CGRectGetMinX(sb) > root.bounds.size.width / 2 && sb.size.height > sb.size.width)
        return root.bounds.size.width - CGRectGetMidX(sb);
    return LBStatusCentreDefault;
}

static void LBApplyTiling(T1TabbedAppNavigationViewController *nav) {
    UIView *root = nav.viewIfLoaded;
    if (!root.window) return;
    BOOL wide = LBWide(root);
    BOOL was = [objc_getAssociatedObject(nav, kLBTiled) boolValue];
    T1TabBarViewController *tb = (T1TabBarViewController *)LBChild(nav, objc_getClass("T1TabBarViewController"), 0);
    UIViewController *selected = [nav respondsToSelector:@selector(selectedViewController)] ? [nav selectedViewController] : nil;
    UIView *card = selected.viewIfLoaded;
    LBSidebar *bar = objc_getAssociatedObject(nav, kLBSidebar);

    if (wide != was) {
        objc_setAssociatedObject(nav, kLBTiled, @(wide), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if ([tb respondsToSelector:@selector(setTabBarHidden:withDuration:completion:)])
            [tb setTabBarHidden:wide withDuration:0 completion:nil];
        Class fab = objc_getClass("TFNFloatingActionButton");
        if (fab) LBRefreshFABs(root, fab);
        if (!wide) {
            [bar removeFromSuperview];
            for (UIViewController *c in nav.childViewControllers) {
                UIView *v = c.viewIfLoaded;
                if (v.layer.cornerRadius == LBCardRadius) { v.layer.cornerRadius = 0; v.layer.masksToBounds = NO; v.layer.borderWidth = 0; }
            }
            if (card.superview) card.frame = card.superview.bounds;
        }
    }
    if (!wide) return;

    CGFloat sidebarWidth = 2 * LBStatusCentreInset(root);
    if (!bar) {
        bar = [[LBSidebar alloc] initWithFrame:CGRectZero];
        objc_setAssociatedObject(nav, kLBSidebar, bar, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    bar.nav = nav;
    bar.tabBar = tb;
    bar.topInset = LBSidebarTop(root);
    if (bar.superview != root) [root addSubview:bar];
    [root bringSubviewToFront:bar];
    bar.frame = CGRectMake(root.bounds.size.width - sidebarWidth, 0, sidebarWidth, root.bounds.size.height);
    [bar reloadTabs];

    root.backgroundColor = LBBackdrop();
    UIView *container = card.superview;
    if (!container) return;
    if (container != root) container.backgroundColor = LBBackdrop();
    CGRect area = [container convertRect:CGRectMake(0, 0, root.bounds.size.width - sidebarWidth, root.bounds.size.height)
                                fromView:root];
    // In from the top as far as the bottom keeps clear (gi-os/twitter's card margins).
    CGFloat m = MAX(root.safeAreaInsets.bottom, 12);
    CGFloat w = MIN(LBColumnWidth, area.size.width - 2 * m);
    CGRect f = CGRectMake(round(CGRectGetMidX(area) - w / 2), CGRectGetMinY(area) + m, w, area.size.height - 2 * m);
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
// The tab bar stays hidden while the sidebar stands in for it (scrolling would otherwise bring it back).
- (void)setTabBarHidden:(BOOL)hidden withDuration:(double)duration completion:(id)completion {
    %orig(hidden || LBWide(self.viewIfLoaded), duration, completion);
}
%end
%end

%group FAB
%hook TFNFloatingActionButton
// Compose lives in the sidebar on a wide window; remember what the app wants for when it narrows.
- (void)setHidden:(BOOL)hidden {
    objc_setAssociatedObject(self, kLBFABWantsHidden, @(hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    %orig(hidden || LBWide(self));
}
- (void)didMoveToWindow {
    %orig;
    [self setHidden:[objc_getAssociatedObject(self, kLBFABWantsHidden) boolValue]];
}
%end
%end

%ctor {
    if (objc_getClass("T1TabbedAppNavigationViewController") && objc_getClass("T1TabBarViewController")) %init(Tiling);
    if (objc_getClass("TFNFloatingActionButton")) %init(FAB);
}
