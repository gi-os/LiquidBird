#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

// Twitter for iPad's layout on the iPhone Duo's wide poses, after gi-os/twitter's TabStackView and
// ClassicSidebar, in Liquid Glass. Down the strip the status bar sits in on the trailing edge: a small
// Twitter logo (tap: NeoFreeBird's settings; long-press: a menu with the slide-over menu, which the
// hidden Home top bar's avatar opened, and the unfolded layout's settings), a glass rail of the tabs (Grok left out), and compose (unless NeoFreeBird's
// "hide tweet button" is on), in place of the tab bar and X's own compose button; where there's room
// for two columns, the current tab is a column card centred on a backdrop.
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
@interface _TtC11XNavigation25TabBarChromeContainerView : UIView @end
@interface _TtC11XNavigation25TabBarAccessoryButtonView : UIView
@end
@interface TFNFloatingActionButton : UIView
@end
@interface _TtCC11XNavigation20NavigationControllerP33_501AD6EDA6CFD4B04EC931BB22CF90163Bar : UINavigationBar
@end
@interface _TtC32TwitterHomeFeatureImplementation35HomeTimelineContainerViewController : UIViewController
@end
@interface T1HostViewController : UIViewController
@end
@interface T1ConversationContainerViewController : UIViewController
@end
@interface _TtC13XDesignSystem19ScrollEdgeTreatment : UIView
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
static const void *kLBSideStrip = &kLBSideStrip;

// The strip down the trailing edge the Duo's status bar runs in (a safe area on that side only), or 0.
// Hiding the status bar (the media viewer, the slide-over menu) takes the strip's inset away with it, so
// it's remembered for the window's size: the sidebar stays and the layout under it doesn't change
// meanwhile (T1HostViewController keeps the inset, below). Also Columns.x's.
CGFloat LBSideStrip(UIWindow *w) {
    if (!w) return 0;
    UIEdgeInsets safe = w.safeAreaInsets;
    NSValue *size = [NSValue valueWithCGSize:w.bounds.size];
    NSArray *seen = objc_getAssociatedObject(w, kLBSideStrip);
    if (safe.right >= 40 && safe.left < 20) {
        if (![seen.lastObject isEqual:size] || fabs([seen.firstObject doubleValue] - safe.right) >= 0.5)
            objc_setAssociatedObject(w, kLBSideStrip, @[@(safe.right), size], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return safe.right;
    }
    return [seen.lastObject isEqual:size] ? [seen.firstObject doubleValue] : 0;
}

// The Duo's poses: a window wider than an iPhone held upright, or one with the side strip.
static BOOL LBSidebarWanted(UIWindow *w) {
    if (!w) return NO;
    return w.bounds.size.width >= LBSidebarWindow || LBSideStrip(w) > 0;
}

// While the status bar is hidden the app's own screens keep the strip's inset (the root's additional safe
// area stands in for it), so the timeline doesn't rewrap and jump; what's presented over them, the media
// viewer, gets the whole screen.
static void LBKeepSideStrip(UIViewController *root) {
    UIWindow *w = root.viewIfLoaded.window;
    if (!w || w.rootViewController != root) return;
    CGFloat strip = LBSideStrip(w);
    CGFloat want = strip > 0 ? MAX(0, strip - w.safeAreaInsets.right) : 0;
    UIEdgeInsets extra = root.additionalSafeAreaInsets;
    if (fabs(extra.right - want) < 0.5) return;
    LBLog(@"root right inset %.0f -> %.0f (strip %.0f, system %.0f)", extra.right, want, strip, w.safeAreaInsets.right);
    extra.right = want;
    root.additionalSafeAreaInsets = extra;
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

void LBCRelayout(UIWindow *w);   // Columns.x: lays the unfolded tabs out again
void LBLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);   // Debug.x: shown in the layout copy
CGRect LBCFitScreen(UIViewController *vc, CGRect frame);   // Columns.x: a tab's screen, across its side
NSInteger LBCFeedPosition(void);           // Columns.x: -1 left, 0 full width, 1 right
void LBCSetFeedPosition(NSInteger side);

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
@property (nonatomic) BOOL composeHidden;
@property (nonatomic, copy) void (^menuAction)(void);
@property (nonatomic, copy) void (^composeAction)(void);
@property (nonatomic, copy) void (^settingsAction)(void);
- (void)setLogo:(UIImage *)logo;
- (void)setTabs:(NSArray<UIView *> *)tabs selected:(NSInteger)selected activate:(void (^)(NSInteger))activate;
@end

@implementation LBSidebar {
    UIVisualEffectView *_logoGlass, *_rail;
    UIButton *_logo, *_compose;
    NSMutableArray<UIButton *> *_buttons;
    void (^_activate)(NSInteger);
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;
        _logoGlass = LBGlassView(nil);
        [self addSubview:_logoGlass];
        _logo = [UIButton buttonWithType:UIButtonTypeCustom];
        _logo.accessibilityLabel = @"NeoFreeBird settings";
        _logo.imageView.contentMode = UIViewContentModeScaleAspectFit;
        [_logo addTarget:self action:@selector(logoTapped) forControlEvents:UIControlEventTouchUpInside];
        // Long-press: a menu with the slide-over menu (which the hidden Home top bar's avatar opened) and
        // the unfolded layout's settings, built as it opens so it shows them as they are.
        if (@available(iOS 15, *)) {
            __weak LBSidebar *weakSelf = self;
            _logo.menu = [UIMenu menuWithChildren:@[[UIDeferredMenuElement elementWithUncachedProvider:^(void (^completion)(NSArray<UIMenuElement *> *)) {
                completion([weakSelf logoMenu]);
            }]]];
            _logo.showsMenuAsPrimaryAction = NO;
        }
        [_logoGlass.contentView addSubview:_logo];
        _rail = LBGlassView(nil);
        [self addSubview:_rail];
        // Compose is the rail's last row, a blue circle in the same glass.
        _compose = LBGlassButton(_rail, @"plus", 20, self, @selector(composeTapped), @"New Tweet");
        _compose.backgroundColor = [UIColor colorWithRed:0.11 green:0.61 blue:0.94 alpha:1];
        _compose.layer.cornerCurve = kCACornerCurveContinuous;
        _buttons = [NSMutableArray array];
    }
    return self;
}

// Only the glass takes touches; the strip around it stays the app's.
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    for (UIView *g in @[_logoGlass, _rail])
        if (!g.hidden && CGRectContainsPoint(g.frame, point)) return YES;
    return NO;
}

- (void)tapped:(UIButton *)b { if (_activate) _activate(b.tag); }
- (void)logoTapped { if (self.settingsAction) self.settingsAction(); }
- (void)composeTapped { if (self.composeAction) self.composeAction(); }
- (NSArray<UIMenuElement *> *)logoMenu {
    __weak LBSidebar *weakSelf = self;
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    UIAction *menu = [UIAction actionWithTitle:@"Slide-over menu" image:[UIImage systemImageNamed:@"sidebar.left"]
                                    identifier:nil handler:^(UIAction *a) { if (weakSelf.menuAction) weakSelf.menuAction(); }];
    id explore = [defaults objectForKey:@"liquidbird_explore_panel"];
    BOOL exploreOn = explore ? [explore boolValue] : YES;
    UIAction *panel = [UIAction actionWithTitle:@"Explore beside the feed" image:[UIImage systemImageNamed:@"sidebar.right"]
                                     identifier:nil handler:^(UIAction *a) {
        [defaults setBool:!exploreOn forKey:@"liquidbird_explore_panel"];
        LBCRelayout(weakSelf.window);
    }];
    panel.state = exploreOn ? UIMenuElementStateOn : UIMenuElementStateOff;
    NSInteger position = LBCFeedPosition();
    NSArray *places = @[@[@"Feed on the left", @"rectangle.lefthalf.filled"], @[@"Feed full width", @"rectangle.inset.filled"],
                        @[@"Feed on the right", @"rectangle.righthalf.filled"]];
    NSMutableArray<UIAction *> *sides = [NSMutableArray array];
    for (NSInteger i = 0; i < 3; i++) {
        UIAction *a = [UIAction actionWithTitle:places[i][0] image:[UIImage systemImageNamed:places[i][1]]
                                     identifier:nil handler:^(UIAction *action) {
            LBCSetFeedPosition(i - 1);
            LBCRelayout(weakSelf.window);
        }];
        a.state = position == i - 1 ? UIMenuElementStateOn : UIMenuElementStateOff;
        [sides addObject:a];
    }
    UIMenu *side = [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:sides];
    return @[menu, panel, side];
}

- (void)setComposeHidden:(BOOL)hidden {
    if (_composeHidden == hidden) return;
    _composeHidden = hidden;
    [self setNeedsLayout];
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

// One column, packed from the bottom up: the tab rail (compose its last row), and the logo on top. Packing from the
// bottom leaves the most room under the status bar, which grows with what it shows (Focus, Live
// Activities). A short pose (the Duo unfolded is about 470pt tall) tightens the gaps and shrinks the
// rows to stay under the status bar.
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat mid = round(self.bounds.size.width / 2 + self.centreOffset);
    CGFloat bottom = self.bounds.size.height - MAX(self.safeAreaInsets.bottom, 16);
    CGFloat room = bottom - self.top;
    NSUInteger n = _buttons.count;
    BOOL compose = !self.composeHidden;
    CGFloat pad = 4, inner = LBGlassWidth - 2 * pad;   // a row's lozenge; compose's circle
    CGFloat composeRoom = compose ? pad + inner : 0;
    CGFloat full = 40 + 14 + (n * LBRow + 2 * pad) + composeRoom;
    BOOL tight = full > room;
    CGFloat gap = tight ? 10 : 14, logo = tight ? 34 : 40;
    CGFloat fixed = logo + gap + 2 * pad + composeRoom;
    CGFloat row = n ? MAX(34, MIN(LBRow, floor((room - fixed) / n))) : LBRow;

    CGFloat y = bottom;
    CGFloat rail = n * row + 2 * pad + composeRoom;
    y -= rail;
    _rail.hidden = n == 0 && !compose;
    _rail.frame = CGRectMake(mid - LBGlassWidth / 2, y, LBGlassWidth, rail);
    _rail.layer.cornerRadius = LBGlassWidth / 2;
    for (NSUInteger i = 0; i < n; i++) {
        UIButton *b = _buttons[i];
        b.frame = CGRectMake(pad, pad + i * row, inner, row);
        b.layer.cornerRadius = inner / 2;
    }
    _compose.hidden = !compose;
    _compose.frame = CGRectMake(pad, pad + n * row + pad, inner, inner);
    _compose.layer.cornerRadius = inner / 2;
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
    CGFloat r = LBSideStrip(host.window);
    return r > 0 ? r : LBStripDefault;
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
        bar.menuAction = ^{ LBToggleDash(weakWindow); };
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
    // NeoFreeBird's "hide tweet button" (BHTSettings, in the standard defaults) takes compose out here too.
    bar.composeHidden = [NSUserDefaults.standardUserDefaults boolForKey:@"hide_tweet_button"];
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

// For Columns.x: the selected tab's name, through X's glass tab bar.
NSString *LBSelectedTabLabel(UIWindow *w) {
    UIView *tabBar = [objc_getAssociatedObject(w, kLBGlassTabBar) nonretainedObjectValue];
    if (!tabBar.window) return nil;
    NSArray<UIView *> *tabs = LBGlassTabs(tabBar);
    NSInteger i = LBGlassSelected(tabBar, tabs);
    return i >= 0 && i < (NSInteger)tabs.count ? tabs[i].accessibilityLabel : nil;
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
// Faded as soon as it's on screen (unfolded, the + was laid out before it had a window).
- (void)didMoveToWindow {
    %orig;
    [self setAlpha:LBWantedAlpha(self)];
}
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
// Faded as soon as it's on screen (unfolded, the + was laid out before it had a window).
- (void)didMoveToWindow {
    %orig;
    [self setAlpha:LBWantedAlpha(self)];
}
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
// Faded as soon as it's on screen (unfolded, the + was laid out before it had a window).
- (void)didMoveToWindow {
    %orig;
    [self setAlpha:LBWantedAlpha(self)];
}
- (void)layoutSubviews {
    %orig;
    [self setAlpha:LBWantedAlpha(self)];
}
- (void)setAlpha:(CGFloat)alpha {
    %orig(LBBarAlpha(self, alpha));
}
%end
%end

// The whole layer X floats its tab bar chrome in. Its + sits in a glass container, which draws it whatever
// the button's own alpha (unfolded it stayed on screen), so the layer above the container fades too.
%group TabBarChrome
%hook _TtC11XNavigation25TabBarChromeContainerView
- (void)didMoveToWindow {
    %orig;
    [self setAlpha:LBWantedAlpha(self)];
}
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
// Faded as soon as it's on screen (unfolded, the + was laid out before it had a window).
- (void)didMoveToWindow {
    %orig;
    [self setAlpha:LBWantedAlpha(self)];
}
- (void)layoutSubviews {
    %orig;
    [self setAlpha:LBWantedAlpha(self)];
}
- (void)setAlpha:(CGFloat)alpha {
    %orig(LBBarAlpha(self, alpha));
}
%end
%end

// MARK: - Home's and an opened tweet's top bar

// The Home top bar (avatar and bird) goes where the sidebar stands in for it: the sidebar's logo opens
// the slide-over menu the avatar did. X's navigation ignores setNavigationBarHidden: and the screen's
// tfn_prefersNavigationBarHidden, and places its Bar itself (overriding frame and center), so on Home
// the bar is faded out. The row of timelines under it (AccessoryStackView) and the timeline's insets
// are laid out from X's own idea of the bar, so Home's whole view moves up by the band the bar leaves
// (where X puts that row, less a small margin) and grows by as much at the bottom: the row comes to the
// top and the first tweet stays right under it. Screens pushed over Home keep their bar, for the back
// button.
// The screens whose bar goes where the sidebar shows: Home (avatar and bird) and an opened tweet (just
// "Tweet"; back is the left-edge swipe, or Home in the sidebar). Not in a column, whose bar holds its ✕.
static BOOL LBHidesBar(UINavigationController *nav) {
    if (!LBSidebarWanted(nav.viewIfLoaded.window)) return NO;
    if ([nav.viewIfLoaded.accessibilityIdentifier isEqualToString:@"LBColumn"]) return NO;
    UIViewController *top = nav.topViewController;
    Class home = objc_getClass("_TtC32TwitterHomeFeatureImplementation35HomeTimelineContainerViewController");
    Class tweet = objc_getClass("T1ConversationContainerViewController");
    return (home && [top isKindOfClass:home]) || (tweet && [top isKindOfClass:tweet]);
}

static BOOL LBBarOnHome(UINavigationBar *bar) {
    id delegate = bar.delegate;
    UINavigationController *nav = [delegate isKindOfClass:UINavigationController.class] ? delegate : nil;
    for (UIResponder *r = bar.nextResponder; r && !nav; r = r.nextResponder)
        if ([r isKindOfClass:UINavigationController.class]) nav = (UINavigationController *)r;
    return nav && LBHidesBar(nav);
}

static const void *kLBHomeShift = &kLBHomeShift;
static const void *kLBHomeRowBottom = &kLBHomeRowBottom;
static const void *kLBHomeExtra = &kLBHomeExtra;

static void LBShiftHome(UIViewController *home) {
    UIView *view = home.viewIfLoaded, *container = view.superview;
    // Off screen (a tweet open over it), Home's safe area reads zero; measuring then would change the
    // timeline's inset and move its scroll position on the way back.
    if (!view || !container || !view.window) return;
    // X puts the row of timelines at its bar's bottom edge. Measured from the bar whenever it's fully
    // shown (not collapsed on scroll), as the latest value, not the largest ever seen: one odd layout
    // (unfolding) once left Home shifted far enough to hide the row.
    CGFloat shift = [objc_getAssociatedObject(home, kLBHomeShift) doubleValue];
    CGFloat rowBottom = [objc_getAssociatedObject(home, kLBHomeRowBottom) doubleValue];
    UINavigationBar *bar = home.navigationController.navigationBar;
    Class row = objc_getClass("_TtC11XNavigation18AccessoryStackView");
    CGFloat rowHeight = 44;
    for (UIView *v in view.subviews) if (row && [v isKindOfClass:row]) rowHeight = v.frame.size.height;
    CGRect barFrame = bar.frame;
    if (barFrame.origin.y >= 0 && barFrame.size.height > 20 && CGRectGetMaxY(barFrame) < 160) {
        CGFloat measured = round(CGRectGetMaxY(barFrame) - 6);
        if (fabs(measured - shift) >= 0.5) {
            LBLog(@"Home shift %.0f -> %.0f (bar %@)", shift, measured, NSStringFromCGRect(barFrame));
            shift = measured;
            objc_setAssociatedObject(home, kLBHomeShift, @(shift), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        CGFloat bottom = CGRectGetMaxY(barFrame) + rowHeight;
        if (fabs(bottom - rowBottom) >= 0.5) {
            LBLog(@"Home row bottom %.0f -> %.0f", rowBottom, bottom);
            rowBottom = bottom;
            objc_setAssociatedObject(home, kLBHomeRowBottom, @(rowBottom), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
    // Shifted whenever the sidebar shows, whether or not Home is on top: changing it while a tweet is
    // open over Home moved the timeline's scroll position on the way back. Only the vertical is set, so
    // the navigation's slide is left alone.
    UINavigationController *nav = home.navigationController;
    BOOL hide = LBSidebarWanted(nav.viewIfLoaded.window ?: view.window);
    CGRect bounds = container.bounds;
    CGRect frame = hide ? CGRectMake(view.frame.origin.x, -shift, bounds.size.width, bounds.size.height + shift)
                        : CGRectMake(view.frame.origin.x, 0, bounds.size.width, bounds.size.height);
    frame = LBCFitScreen(home, frame);   // unfolded, narrowed to the feed's side
    if (!CGRectEqualToRect(view.frame, frame)) {
        LBLog(@"Home frame %@ -> %@", NSStringFromCGRect(view.frame), NSStringFromCGRect(frame));
        view.frame = frame;
    }

    // The timeline's top inset comes from Home's safe area, which moving the view up shortens (126 to
    // 68pt on the Duo), so the first tweet started under the row. The timelines' pager (Home's first
    // child) gets the difference, up to the row's bottom with the row shown.
    UIViewController *pager = nil;
    for (UIViewController *c in home.childViewControllers)
        if ([NSStringFromClass(c.class) rangeOfString:@"SegmentedViewController"].location != NSNotFound) pager = c;
    if (!pager) return;
    // Measured only once Home has settled on top, shifted, with no navigation transition running (sliding
    // back in from a tweet, its safe area reads as if unshifted for a moment), and kept: any change to it
    // moves the timeline's scroll position.
    CGFloat measured = [objc_getAssociatedObject(home, kLBHomeExtra) doubleValue];
    BOOL settled = nav.topViewController == home && !nav.transitionCoordinator && fabs(view.frame.origin.y + shift) < 0.5;
    if (hide && settled && rowBottom > 0) {
        CGFloat was = measured;
        measured = MAX(0, round(rowBottom - view.safeAreaInsets.top));
        if (fabs(was - measured) >= 0.5)
            LBLog(@"Home timeline extra measured %.0f -> %.0f (safe top %.0f)", was, measured, view.safeAreaInsets.top);
        objc_setAssociatedObject(home, kLBHomeExtra, @(measured), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    CGFloat extra = hide ? measured : 0;
    UIEdgeInsets insets = pager.additionalSafeAreaInsets;
    if (fabs(insets.top - extra) < 0.5) return;
    LBLog(@"Home timeline inset %.0f -> %.0f", insets.top, extra);
    insets.top = extra;
    pager.additionalSafeAreaInsets = insets;
}

// An opened tweet with its bar hidden starts at the top: its safe area (the bar's height) is taken back.
static const void *kLBTweetLifted = &kLBTweetLifted;

static void LBLiftTweet(UIViewController *tweet) {
    UINavigationController *nav = tweet.navigationController;
    BOOL lift = nav.topViewController == tweet && LBHidesBar(nav);
    BOOL lifted = [objc_getAssociatedObject(tweet, kLBTweetLifted) boolValue];
    if (!lift && !lifted) return;
    UIEdgeInsets extra = tweet.additionalSafeAreaInsets;
    CGFloat base = tweet.view.safeAreaInsets.top - extra.top;
    CGFloat want = lift ? round(8 - base) : 0;
    objc_setAssociatedObject(tweet, kLBTweetLifted, @(lift), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (fabs(extra.top - want) < 0.5) return;
    LBLog(@"tweet lift %.0f -> %.0f", extra.top, want);
    extra.top = want;
    tweet.additionalSafeAreaInsets = extra;
}

// X's own blur at a list's edges (XDesignSystem's ScrollEdgeTreatment: a blur along the top, one along the
// bottom). Where the sidebar shows there's no tab bar for the bottom one to sit under, and the top one
// goes on the screens whose bar is hidden.
static void LBTrimEdgeTreatment(UIView *treatment) {
    UIWindow *w = treatment.window;
    BOOL side = LBSidebarWanted(w);
    UIResponder *r = treatment.nextResponder;
    while (r && ![r isKindOfClass:UIViewController.class]) r = r.nextResponder;
    UINavigationController *nav = ((UIViewController *)r).navigationController;
    BOOL barHidden = side && nav && LBHidesBar(nav);
    Class blur = objc_getClass("XDSBlur");
    CGFloat mid = treatment.bounds.size.height / 2;
    for (UIView *v in treatment.subviews) {
        if (!blur || ![v isKindOfClass:blur]) continue;
        BOOL bottom = CGRectGetMidY(v.frame) > mid;
        v.hidden = bottom ? side : barHidden;
    }
}

%group EdgeTreatment
%hook _TtC13XDesignSystem19ScrollEdgeTreatment
- (void)layoutSubviews {
    %orig;
    LBTrimEdgeTreatment(self);
}
- (void)didMoveToWindow {
    %orig;
    LBTrimEdgeTreatment(self);
}
%end
%end

%group TweetBar
%hook T1ConversationContainerViewController
- (void)viewDidLayoutSubviews {
    %orig;
    LBLiftTweet(self);
}
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    LBLiftTweet(self);
}
%end
%end

%group HomeBar
%hook _TtC32TwitterHomeFeatureImplementation35HomeTimelineContainerViewController
- (void)viewDidLayoutSubviews {
    %orig;
    LBShiftHome(self);
}
%end

%hook _TtCC11XNavigation20NavigationControllerP33_501AD6EDA6CFD4B04EC931BB22CF90163Bar
- (void)setAlpha:(CGFloat)alpha {
    objc_setAssociatedObject(self, kLBWantedAlpha, @(alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    %orig(LBBarOnHome(self) ? 0 : alpha);
}
- (void)layoutSubviews {
    %orig;
    [self setAlpha:LBWantedAlpha(self)];
}
%end
%end

// MARK: - Scroll edge effects

// iOS 26 blurs a scroll view's edge where a bar sits over it. With the tab bar replaced by the sidebar,
// nothing sits over the bottom; on Home, nothing over the top either.
static BOOL LBInsideHome(UIView *v) {
    Class home = objc_getClass("_TtC32TwitterHomeFeatureImplementation35HomeTimelineContainerViewController");
    for (; v && home; v = v.superview)
        if ([v.nextResponder isKindOfClass:home]) return YES;
    return NO;
}

%group EdgeEffects
%hook UIScrollView
- (void)didMoveToWindow {
    %orig;
    if (@available(iOS 26, *)) {
        if (!LBSidebarWanted(self.window)) return;
        self.bottomEdgeEffect.hidden = YES;
        if (LBInsideHome(self)) self.topEdgeEffect.hidden = YES;
    }
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

// MARK: - Folded, upright

// Folded, the feed stays upright. The Duo's two poses are different displays (466pt across folded,
// about 669pt unfolded), so the screen, not the window, says which: turning the phone doesn't change it.
// The app's root decides for everything that isn't presented over it, so a photo can still turn.
%group Orientation
%hook T1HostViewController
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    UIScreen *screen = self.viewIfLoaded.window.windowScene.screen;
    if (screen && MIN(screen.bounds.size.width, screen.bounds.size.height) < LBSidebarWindow)
        return UIInterfaceOrientationMaskPortrait;
    return %orig;
}
- (void)viewSafeAreaInsetsDidChange {
    %orig;
    LBKeepSideStrip(self);
}
- (void)viewDidLayoutSubviews {
    %orig;
    LBKeepSideStrip(self);
}
%end
%end

%ctor {
    // TFNFloatingActionButton rides in the GlassTabBar group: it's there either way.
    if (objc_getClass("_TtC11XNavigation10TabBarView") && objc_getClass("_TtC11XNavigation10TabBarPill") &&
        objc_getClass("TFNFloatingActionButton")) %init(GlassTabBar);
    if (objc_getClass("_TtC11XNavigation25TabBarAccessoryButtonView")) %init(GlassAccessory);
    if (objc_getClass("_TtC11XNavigation25TabBarChromeContainerView")) %init(TabBarChrome);
    if (objc_getClass("_TtCC11XNavigation20NavigationControllerP33_501AD6EDA6CFD4B04EC931BB22CF90163Bar") &&
        objc_getClass("_TtC32TwitterHomeFeatureImplementation35HomeTimelineContainerViewController")) %init(HomeBar);
    %init(EdgeEffects);
    if (objc_getClass("_TtC13XDesignSystem19ScrollEdgeTreatment")) %init(EdgeTreatment);
    if (objc_getClass("T1ConversationContainerViewController")) %init(TweetBar);
    if (objc_getClass("T1HostViewController")) %init(Orientation);
    if (objc_getClass("T1TabbedAppNavigationViewController") && objc_getClass("T1TabBarViewController")) %init(Tiling);
}
