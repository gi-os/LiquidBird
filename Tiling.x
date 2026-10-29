#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

// Twitter for iPad's layout on the iPhone Duo's wide poses, after gi-os/twitter's TabStackView and
// ClassicSidebar, in Liquid Glass. Down the strip the status bar sits in on the trailing edge: a small
// Twitter logo that opens the slide-over menu (the Home top bar it stands in for is hidden), a glass
// rail of the tabs (Grok left out), and at the bottom compose and a gear for NeoFreeBird's settings, in
// place of the tab bar and X's own compose button; where there's room for two columns, the current tab
// is a column card centred on a backdrop.
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
@interface _TtC11XNavigation25TabBarAccessoryButtonView : UIView
@end
@interface TFNFloatingActionButton : UIView
@end
@interface XNAVNavigationController : UINavigationController
@end
@interface _TtC32TwitterHomeFeatureImplementation35HomeTimelineContainerViewController : UIViewController
@end

static const CGFloat LBColumnWidth = 476;          // gi-os/twitter's ColumnLayout
static const CGFloat LBMinimumColumnWidth = 400;
static const CGFloat LBCardRadius = 26;
static const CGFloat LBSidebarWindow = 600;        // wider than any iPhone held upright: the Duo's poses
static const CGFloat LBGlassWidth = 52;
static const CGFloat LBRow = 48;
// Where the status bar runs down the side and the safe area doesn't say how wide its strip is: twice
// the inset of its centre line on the Duo unfolded.
static const CGFloat LBStripDefault = 66;

static const void *kLBSidebar = &kLBSidebar;
static const void *kLBGlassTabBar = &kLBGlassTabBar;
static const void *kLBWantedAlpha = &kLBWantedAlpha;
static const void *kLBTiled = &kLBTiled;

// The Duo's poses: a window wider than an iPhone held upright, or one whose status bar runs down the
// trailing edge (a safe area on that side only).
static BOOL LBSidebarWanted(UIWindow *w) {
    if (!w) return NO;
    UIEdgeInsets safe = w.safeAreaInsets;
    return w.bounds.size.width >= LBSidebarWindow || (safe.right >= 40 && safe.left < 20);
}

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

// MARK: - The sidebar

static UIButton *LBGlassButton(UIView *glass, NSString *symbol, CGFloat size, id target, SEL action, NSString *label) {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImageSymbolConfiguration *c = [UIImageSymbolConfiguration configurationWithPointSize:size weight:UIImageSymbolWeightSemibold];
    [b setImage:[UIImage systemImageNamed:symbol withConfiguration:c] forState:UIControlStateNormal];
    b.tintColor = UIColor.whiteColor;
    b.accessibilityLabel = label;
    [b addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    [((UIVisualEffectView *)glass).contentView addSubview:b];
    return b;
}

@interface LBSidebar : UIView
@property (nonatomic) CGFloat top;       // under the status bar
// How far the column's centre line sits from the strip's: iPhone Duo's side status bar is centred a
// little in from the display's rounded corner (gi-os/twitter's ClassicSidebar centerOffset, -5).
@property (nonatomic) CGFloat centreOffset;
@property (nonatomic, copy) void (^logoAction)(void);
@property (nonatomic, copy) void (^composeAction)(void);
@property (nonatomic, copy) void (^settingsAction)(void);
- (void)setLogo:(UIImage *)logo;
- (void)setTabs:(NSArray<UIView *> *)tabs selected:(NSInteger)selected activate:(void (^)(NSInteger))activate;
@end

@implementation LBSidebar {
    UIVisualEffectView *_logoGlass, *_rail, *_composeGlass, *_settingsGlass;
    UIButton *_logo, *_compose, *_settings;
    NSMutableArray<UIButton *> *_buttons;
    void (^_activate)(NSInteger);
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;
        _logoGlass = LBGlassView(nil);
        [self addSubview:_logoGlass];
        _logo = [UIButton buttonWithType:UIButtonTypeCustom];
        _logo.accessibilityLabel = @"Menu";
        _logo.imageView.contentMode = UIViewContentModeScaleAspectFit;
        [_logo addTarget:self action:@selector(logoTapped) forControlEvents:UIControlEventTouchUpInside];
        // Long-press: NeoFreeBird's settings, for when the gear has no room.
        [_logo addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(logoPressed:)]];
        [_logoGlass.contentView addSubview:_logo];
        _rail = LBGlassView(nil);
        [self addSubview:_rail];
        _composeGlass = LBGlassView([UIColor colorWithRed:0.11 green:0.61 blue:0.94 alpha:1]);
        [self addSubview:_composeGlass];
        _compose = LBGlassButton(_composeGlass, @"plus", 22, self, @selector(composeTapped), @"New Tweet");
        _settingsGlass = LBGlassView(nil);
        [self addSubview:_settingsGlass];
        _settings = LBGlassButton(_settingsGlass, @"gearshape", 15, self, @selector(settingsTapped), @"NeoFreeBird settings");
        _settings.tintColor = [UIColor colorWithWhite:0.75 alpha:1];
        _buttons = [NSMutableArray array];
    }
    return self;
}

// Only the glass takes touches; the strip around it stays the app's.
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    for (UIView *g in @[_logoGlass, _rail, _composeGlass, _settingsGlass])
        if (!g.hidden && CGRectContainsPoint(g.frame, point)) return YES;
    return NO;
}

- (void)tapped:(UIButton *)b { if (_activate) _activate(b.tag); }
- (void)logoTapped { if (self.logoAction) self.logoAction(); }
- (void)composeTapped { if (self.composeAction) self.composeAction(); }
- (void)settingsTapped { if (self.settingsAction) self.settingsAction(); }
- (void)logoPressed:(UILongPressGestureRecognizer *)g {
    if (g.state == UIGestureRecognizerStateBegan && self.settingsAction) self.settingsAction();
}

- (void)setLogo:(UIImage *)logo {
    if ([_logo imageForState:UIControlStateNormal] != logo) [_logo setImage:logo forState:UIControlStateNormal];
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

// One column, packed from the bottom up: the gear, compose, the tab rail, and the logo on top. Packing
// from the bottom leaves the most room under the status bar, which grows with what it shows (Focus,
// Live Activities). A short pose (the Duo unfolded is about 470pt tall) drops the gear (the logo's
// long-press has it), tightens the gaps and shrinks the rows to stay under the status bar.
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat mid = round(self.bounds.size.width / 2 + self.centreOffset);
    CGFloat bottom = self.bounds.size.height - MAX(self.safeAreaInsets.bottom, 16);
    CGFloat room = bottom - self.top;
    NSUInteger n = _buttons.count;
    CGFloat pad = 4;
    CGFloat full = 40 + 14 + (n * LBRow + 2 * pad) + 14 + LBGlassWidth + 14 + 40;
    BOOL tight = full > room;
    CGFloat gap = tight ? 10 : 14, logo = tight ? 34 : 40, compose = tight ? 48 : LBGlassWidth, gear = 40;
    CGFloat fixed = logo + gap + 2 * pad + gap + compose + (tight ? 0 : gap + gear);
    CGFloat row = n ? MAX(34, MIN(LBRow, floor((room - fixed) / n))) : LBRow;

    CGFloat y = bottom;
    _settingsGlass.hidden = tight;
    if (!tight) {
        y -= gear;
        _settingsGlass.frame = CGRectMake(mid - gear / 2, y, gear, gear);
        _settingsGlass.layer.cornerRadius = gear / 2;
        _settings.frame = _settingsGlass.contentView.bounds;
        y -= gap;
    }
    y -= compose;
    _composeGlass.frame = CGRectMake(mid - compose / 2, y, compose, compose);
    _composeGlass.layer.cornerRadius = compose / 2;
    _compose.frame = _composeGlass.contentView.bounds;
    y -= gap;

    CGFloat rail = n * row + 2 * pad;
    y -= rail;
    _rail.hidden = n == 0;
    _rail.frame = CGRectMake(mid - LBGlassWidth / 2, y, LBGlassWidth, rail);
    _rail.layer.cornerRadius = LBGlassWidth / 2;
    for (NSUInteger i = 0; i < n; i++) {
        UIButton *b = _buttons[i];
        b.frame = CGRectMake(pad, pad + i * row, LBGlassWidth - 2 * pad, row);
        b.layer.cornerRadius = (LBGlassWidth - 2 * pad) / 2;
    }
    y -= gap + logo;
    _logoGlass.frame = CGRectMake(mid - logo / 2, y, logo, logo);
    _logoGlass.layer.cornerRadius = logo / 2;
    _logo.frame = CGRectInset(_logoGlass.contentView.bounds, logo * 0.2, logo * 0.2);
}
@end

// MARK: - Placing it

static UIViewController *LBFindVC(UIViewController *vc, Class cls, NSInteger depth) {
    if (!vc || !cls || depth > 8) return nil;
    if ([vc isKindOfClass:cls]) return vc;
    for (UIViewController *c in vc.childViewControllers) {
        UIViewController *r = LBFindVC(c, cls, depth + 1);
        if (r) return r;
    }
    return nil;
}

static id LBMsg(id target, NSString *selector) {
    SEL sel = NSSelectorFromString(selector);
    return [target respondsToSelector:sel] ? ((id (*)(id, SEL))objc_msgSend)(target, sel) : nil;
}

// X's own compose: the Liquid Glass navigation's key command, or the older tab's compose.
static void LBCompose(UIWindow *w) {
    UIViewController *root = w.rootViewController;
    UIViewController *x = LBFindVC(root, objc_getClass("_TtC14T1TwitterSwift34XTabbedAppNavigationViewController"), 0);
    SEL key = NSSelectorFromString(@"handleComposeTweetKeyCommand");
    if ([x respondsToSelector:key]) { ((void (*)(id, SEL))objc_msgSend)(x, key); return; }
    UIViewController *t1 = LBFindVC(root, objc_getClass("T1TabbedAppNavigationViewController"), 0);
    id tabNav = LBMsg(t1, @"currentTabNavigationController");
    SEL show = NSSelectorFromString(@"showComposeFromBarButtonItem:");
    if ([tabNav respondsToSelector:show]) {
        UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCompose target:nil action:nil];
        ((void (*)(id, SEL, id))objc_msgSend)(tabNav, show, item);
    }
}

// NeoFreeBird's settings (BHTManager, in BHTwitter.dylib), as a sheet: its own entry in Settings
// doesn't show on these layouts.
static void LBOpenNeoFreeBirdSettings(UIWindow *w) {
    Class manager = objc_getClass("BHTManager");
    SEL make = NSSelectorFromString(@"BHTSettingsWithAccount:");
    if (![manager respondsToSelector:make]) return;
    id account = LBMsg(LBMsg(objc_getClass("T1HostViewController"), @"sharedHostViewController"), @"currentAccount");
    UIViewController *settings = ((id (*)(id, SEL, id))objc_msgSend)(manager, make, account);
    if (!settings) return;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:settings];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    UIViewController *top = w.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    [top presentViewController:nav animated:YES completion:nil];
}

// The slide-over menu (the Dash), as the Home top bar's avatar opens it: from the current tab's screen.
static void LBToggleDash(UIWindow *w) {
    UIViewController *root = w.rootViewController;
    UIViewController *x = LBFindVC(root, objc_getClass("_TtC14T1TwitterSwift34XTabbedAppNavigationViewController"), 0)
        ?: LBFindVC(root, objc_getClass("T1TabbedAppNavigationViewController"), 0);
    if (!x) return;
    SEL isOpen = NSSelectorFromString(@"isDashOpen");
    if ([x respondsToSelector:isOpen] && ((BOOL (*)(id, SEL))objc_msgSend)(x, isOpen)) {
        SEL dismiss = NSSelectorFromString(@"dismissDashAnimated:completion:");
        if ([x respondsToSelector:dismiss]) ((void (*)(id, SEL, BOOL, id))objc_msgSend)(x, dismiss, YES, nil);
        return;
    }
    UINavigationController *nav = (UINavigationController *)LBFindVC(x, objc_getClass("XNAVNavigationController"), 0);
    UIViewController *from = nav.topViewController ?: x;
    SEL present = NSSelectorFromString(@"presentDashFromViewController:animated:completion:");
    if ([x respondsToSelector:present]) ((void (*)(id, SEL, id, BOOL, id))objc_msgSend)(x, present, from, YES, nil);
}

static UIView *LBFindView(UIView *v, Class cls, NSInteger depth) {
    if (!cls || depth > 40) return nil;
    if ([v isKindOfClass:cls]) return v;
    if ([v isKindOfClass:UITableViewCell.class] || [v isKindOfClass:UICollectionViewCell.class]) return nil;
    for (UIView *s in v.subviews) {
        UIView *r = LBFindView(s, cls, depth + 1);
        if (r) return r;
    }
    return nil;
}

// The Twitter bird from the Home top bar's title, looked for until found; the SF bird meanwhile.
static UIImage *LBTwitterLogo(UIWindow *w) {
    static UIImage *logo;
    static CFTimeInterval lastLook;
    if (logo) return logo;
    UIImageSymbolConfiguration *c = [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightSemibold];
    UIImage *bird = [[UIImage systemImageNamed:@"bird.fill" withConfiguration:c]
        imageWithTintColor:[UIColor colorWithRed:0.11 green:0.61 blue:0.94 alpha:1] renderingMode:UIImageRenderingModeAlwaysOriginal];
    if (CACurrentMediaTime() - lastLook < 2) return bird;
    lastLook = CACurrentMediaTime();
    UIView *title = LBFindView(w, objc_getClass("_UINavigationBarTitleControl"), 0);
    UIImageView *image = (UIImageView *)LBFindView(title, UIImageView.class, 0);
    if (image.image) return logo = image.image;
    return bird;
}

static BOOL LBIsGrokTab(UIView *tab) {
    return [tab.accessibilityLabel rangeOfString:@"grok" options:NSCaseInsensitiveSearch].location != NSNotFound;
}

// The strip down the trailing edge: the safe area there, which the status bar's strip is, or a default.
static CGFloat LBStripWidth(UIView *host) {
    CGFloat r = host.safeAreaInsets.right;
    return r >= 40 ? r : LBStripDefault;
}

// Under the status bar. Where it runs down the side (the Duo: no top safe area), iOS reports it as a
// 2pt line across the top, so this is where its clock and Wi-Fi end in that strip, measured.
static const CGFloat LBSideStatusBottom = 150;

static CGFloat LBStatusBottom(UIView *host) {
    return host.safeAreaInsets.top < 1 ? LBSideStatusBottom : host.safeAreaInsets.top + 12;
}

static void LBUpdateSidebar(UIWindow *w, NSArray<UIView *> *tabs, NSInteger selected, void (^activate)(NSInteger)) {
    LBSidebar *bar = objc_getAssociatedObject(w, kLBSidebar);
    UIView *host = w.rootViewController.viewIfLoaded;
    if (!host || !LBSidebarWanted(w) || tabs.count == 0) { [bar removeFromSuperview]; return; }
    if (!bar) {
        bar = [[LBSidebar alloc] initWithFrame:CGRectZero];
        __weak UIWindow *weakWindow = w;
        bar.logoAction = ^{ LBToggleDash(weakWindow); };
        bar.composeAction = ^{ LBCompose(weakWindow); };
        bar.settingsAction = ^{ LBOpenNeoFreeBirdSettings(weakWindow); };
        objc_setAssociatedObject(w, kLBSidebar, bar, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    // Grok stays out of the rail; the rest keep their places in the app's own list.
    NSMutableArray<UIView *> *shown = [NSMutableArray array];
    NSMutableArray<NSNumber *> *index = [NSMutableArray array];
    NSInteger shownSelected = -1;
    for (NSUInteger i = 0; i < tabs.count; i++) {
        if (LBIsGrokTab(tabs[i])) continue;
        if ((NSInteger)i == selected) shownSelected = (NSInteger)shown.count;
        [shown addObject:tabs[i]];
        [index addObject:@(i)];
    }
    CGFloat strip = LBStripWidth(host);
    if (bar.superview != host) [host addSubview:bar];
    [host bringSubviewToFront:bar];
    bar.frame = CGRectMake(host.bounds.size.width - strip, 0, strip, host.bounds.size.height);
    bar.top = LBStatusBottom(host);
    bar.centreOffset = host.safeAreaInsets.top < 1 ? -5 : 0;
    [bar setLogo:LBTwitterLogo(w)];
    [bar setTabs:shown selected:shownSelected activate:^(NSInteger i) {
        if (i < (NSInteger)index.count) activate(index[i].integerValue);
    }];
}

// MARK: - X's Liquid Glass tab bar

// X's tab bar holds three rows of TabBarItemViews at the same places: its own (faded out; the one that
// selects on accessibilityActivate), the visible copy in TabBarPortalView, and a hidden carried row.
// The first found at each place is the bar's own, breadth first.
static NSArray<UIView *> *LBGlassTabs(UIView *tabBar) {
    NSMutableArray<UIView *> *tabs = [NSMutableArray array];
    NSMutableSet<NSNumber *> *places = [NSMutableSet set];
    Class item = objc_getClass("_TtC11XNavigation14TabBarItemView");
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithArray:tabBar.subviews];
    while (queue.count && item) {
        UIView *v = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([v isKindOfClass:item]) {
            NSNumber *place = @(round([tabBar convertPoint:CGPointZero fromView:v].x));
            if (![places containsObject:place]) { [places addObject:place]; [tabs addObject:v]; }
        } else {
            [queue addObjectsFromArray:v.subviews];
        }
    }
    [tabs sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        CGFloat ax = [tabBar convertPoint:CGPointZero fromView:a].x, bx = [tabBar convertPoint:CGPointZero fromView:b].x;
        return ax < bx ? NSOrderedAscending : ax > bx ? NSOrderedDescending : NSOrderedSame;
    }];
    return tabs;
}

// The selected tab: the one marked selected for accessibility, else the one under the bar's selection
// glass (an XDSGlass a tab wide, at the top of the bar).
static NSInteger LBGlassSelected(UIView *tabBar, NSArray<UIView *> *tabs) {
    for (NSUInteger i = 0; i < tabs.count; i++)
        if (tabs[i].accessibilityTraits & UIAccessibilityTraitSelected) return (NSInteger)i;
    Class glass = objc_getClass("XDSGlass");
    UIView *lens = nil;
    for (UIView *row in tabBar.subviews)
        for (UIView *v in row.subviews)
            if (glass && [v isKindOfClass:glass] && v.bounds.size.width < 80) lens = v;
    if (!lens) return -1;
    CGFloat x = CGRectGetMidX([tabBar convertRect:lens.bounds fromView:lens]);
    NSInteger best = -1;
    CGFloat distance = CGFLOAT_MAX;
    for (NSUInteger i = 0; i < tabs.count; i++) {
        CGFloat d = fabs(CGRectGetMidX([tabBar convertRect:tabs[i].bounds fromView:tabs[i]]) - x);
        if (d < distance) { distance = d; best = (NSInteger)i; }
    }
    return best;
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
    NSInteger selected = LBGlassSelected(tabBar, tabs);
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

// X's own compose buttons (the floating one, and the glass tab bar's accessory) give way to the
// sidebar's.
%hook TFNFloatingActionButton
- (void)layoutSubviews {
    %orig;
    [self setAlpha:LBWantedAlpha(self)];
}
- (void)setAlpha:(CGFloat)alpha {
    %orig(LBBarAlpha(self, alpha));
}
%end
%end

%group GlassAccessory
%hook _TtC11XNavigation25TabBarAccessoryButtonView
- (void)layoutSubviews {
    %orig;
    [self setAlpha:LBWantedAlpha(self)];
}
- (void)setAlpha:(CGFloat)alpha {
    %orig(LBBarAlpha(self, alpha));
}
%end
%end

// MARK: - Home's top bar

// The Home top bar (avatar and bird) goes where the sidebar stands in for it: the sidebar's logo opens
// the slide-over menu the avatar did. Screens pushed over Home keep theirs, for the back button.
static BOOL LBHidesBar(UINavigationController *nav) {
    Class home = objc_getClass("_TtC32TwitterHomeFeatureImplementation35HomeTimelineContainerViewController");
    return home && [nav.topViewController isKindOfClass:home] && LBSidebarWanted(nav.viewIfLoaded.window);
}

%group HomeBar
%hook XNAVNavigationController
- (void)setNavigationBarHidden:(BOOL)hidden animated:(BOOL)animated {
    %orig(hidden || LBHidesBar(self), animated);
}
- (void)setNavigationBarHidden:(BOOL)hidden {
    %orig(hidden || LBHidesBar(self));
}
%end

%hook _TtC32TwitterHomeFeatureImplementation35HomeTimelineContainerViewController
// X's navigation asks the top screen whether its bar should show (TFN's tfn_prefersNavigationBarHidden)
// rather than taking setNavigationBarHidden: from outside.
- (BOOL)tfn_prefersNavigationBarHidden {
    return LBSidebarWanted(self.viewIfLoaded.window ?: self.navigationController.viewIfLoaded.window) ? YES : %orig;
}
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    SEL update = NSSelectorFromString(@"tfn_setNeedsNavigationBarHiddenUpdate");
    if ([self respondsToSelector:update]) ((void (*)(id, SEL))objc_msgSend)(self, update);
    UINavigationController *nav = self.navigationController;
    if (LBHidesBar(nav) && !nav.navigationBarHidden) [nav setNavigationBarHidden:YES animated:NO];
}
- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    UINavigationController *nav = self.navigationController;
    if (nav.navigationBarHidden && !LBHidesBar(nav)) [nav setNavigationBarHidden:NO animated:animated];
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
    // TFNFloatingActionButton rides in the GlassTabBar group: it's there either way.
    if (objc_getClass("_TtC11XNavigation10TabBarView") && objc_getClass("_TtC11XNavigation10TabBarPill") &&
        objc_getClass("TFNFloatingActionButton")) %init(GlassTabBar);
    if (objc_getClass("_TtC11XNavigation25TabBarAccessoryButtonView")) %init(GlassAccessory);
    if (objc_getClass("XNAVNavigationController") &&
        objc_getClass("_TtC32TwitterHomeFeatureImplementation35HomeTimelineContainerViewController")) %init(HomeBar);
    if (objc_getClass("T1TabbedAppNavigationViewController") && objc_getClass("T1TabBarViewController")) %init(Tiling);
}
