#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// X's classes, declared so the hooks compile. Each is hooked from its own Logos group, set up only if
// objc_getClass finds it, so a renamed class is a no-op instead of a launch crash.
@interface _TtC7XSports22SportsGameCarouselView : UIView @end
@interface TFSFeatureSwitches : NSObject @end
@interface T1ImmersiveFullScreenViewController : UIViewController @end
@interface XNAVNavigationController : UINavigationController @end
@interface T1ImmersiveViewController : UIViewController @end
@interface _TtC14T1TwitterSwift35MultiImmersiveViewControllerManager : UIViewController @end
@interface T1HostViewController : UIViewController @end
@interface TFSInstrumentedFeatureSwitches : NSObject @end
@interface TAVPlayerViewConfiguration : NSObject
- (BOOL)isFullscreen;
@end

// ---------- helpers ----------

static BOOL LBIsGrokString(NSString *s) {
    return s && [s rangeOfString:@"grok" options:NSCaseInsensitiveSearch].location != NSNotFound;
}

// A control's label names Grok as a word of its own, not inside someone's name or @handle ("Groktopus",
// "@GrokFan"), which X's profile and follow buttons put in theirs.
static BOOL LBIsGrokLabel(NSString *s) {
    return LBIsGrokString(s) && [s rangeOfString:@"(?<![@\\w])grok(?!\\w)"
        options:NSRegularExpressionSearch | NSCaseInsensitiveSearch].location != NSNotFound;
}

// Identifiers are X's own constants ("GrokButton", "NavigationBarGrokXaiLogoButton"), so any mention counts.
static BOOL LBIsGrokControl(UIView *v) {
    return LBIsGrokLabel(v.accessibilityLabel) || LBIsGrokString(v.accessibilityIdentifier);
}

// Set on a control LiquidBird hid, holding what X last asked for (hidden, then touches), so that comes back.
static const void *kLBKilled = &kLBKilled;

// Hidden rather than taken out: a hidden view in a stack view gives up its room anyway, and X reuses
// cells, so the same control may later show someone or something that isn't Grok. Marked only once it's
// hidden, so the setHidden: hook below never takes LiquidBird's own hide for X's.
static void LBKill(UIView *v) {
    if (objc_getAssociatedObject(v, kLBKilled)) return;
    NSArray<NSNumber *> *asked = @[@(v.hidden), @(v.userInteractionEnabled)];
    v.hidden = YES;
    v.userInteractionEnabled = NO;
    objc_setAssociatedObject(v, kLBKilled, asked, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// A control LiquidBird hid, shown again as X last asked once nothing on it says Grok any more.
static void LBRevive(UIView *v) {
    NSArray<NSNumber *> *asked = objc_getAssociatedObject(v, kLBKilled);
    if (!asked || LBIsGrokControl(v)) return;
    objc_setAssociatedObject(v, kLBKilled, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    v.hidden = asked[0].boolValue;
    v.userInteractionEnabled = asked[1].boolValue;
}

// ---------- Grok removal ----------

%hook UIControl
- (void)didMoveToWindow {
    %orig;
    if (!self.window) return;
    if (LBIsGrokControl(self)) LBKill(self);
    else LBRevive(self);
}
- (void)setAccessibilityLabel:(NSString *)l {
    %orig;
    if (LBIsGrokLabel(l)) LBKill(self);
    else LBRevive(self);
}
// X can show a control it had hidden (a reused cell's optional button) without moving or relabelling
// it, which the hooks above wouldn't see: while LiquidBird keeps one hidden, what X asks for is only
// remembered, for when it comes back.
- (void)setHidden:(BOOL)hidden {
    NSArray<NSNumber *> *asked = objc_getAssociatedObject(self, kLBKilled);
    if (!asked) { %orig; return; }
    objc_setAssociatedObject(self, kLBKilled, @[@(hidden), asked[1]], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    %orig(YES);
}
%end

%hook UITabBarController
- (void)setViewControllers:(NSArray *)vcs animated:(BOOL)a {
    NSPredicate *p = [NSPredicate predicateWithBlock:^BOOL(UIViewController *vc, id _) {
        return !LBIsGrokString(NSStringFromClass(vc.class)) && !LBIsGrokString(vc.tabBarItem.title);
    }];
    %orig([vcs filteredArrayUsingPredicate:p], a);
}
%end

%hook UIMenu
+ (UIMenu *)menuWithTitle:(NSString *)t image:(UIImage *)i identifier:(UIMenuIdentifier)d
                  options:(UIMenuOptions)o children:(NSArray<UIMenuElement *> *)c {
    NSPredicate *p = [NSPredicate predicateWithBlock:^BOOL(UIMenuElement *e, id _) {
        return !LBIsGrokString(e.title);
    }];
    return %orig(t, i, d, o, [c filteredArrayUsingPredicate:p]);
}
%end

// ---------- Feature switches ----------

// X's own switches LiquidBird turns off. These hooks load after NeoFreeBird's, so they're asked first.
// ios_tab_bar_default_show_grok: the Grok tab in the tab bar.
static BOOL LBSwitchOff(NSString *key) {
    return [key isKindOfClass:NSString.class] && [key isEqualToString:@"ios_tab_bar_default_show_grok"];
}

%group Switches
%hook TFSFeatureSwitches
- (BOOL)boolForKey:(NSString *)key { return LBSwitchOff(key) ? NO : %orig; }
- (BOOL)unsafePeekBoolForKey:(NSString *)key { return LBSwitchOff(key) ? NO : %orig; }
%end
%end

%group InstrumentedSwitches
%hook TFSInstrumentedFeatureSwitches
- (BOOL)boolForKey:(NSString *)key { return LBSwitchOff(key) ? NO : %orig; }
- (BOOL)unsafePeekBoolForKey:(NSString *)key { return LBSwitchOff(key) ? NO : %orig; }
%end
%end

// ---------- Photos ----------

// Photos and videos (T1ImmersiveFullscreenHandler) open X's full-screen viewer, T1ImmersiveFullScreenViewController
// (holding a MultiImmersiveViewControllerManager and its T1ImmersiveViewControllers), which hides the
// status bar only in landscape. The status bar goes while one is open, folded too. It changes only once
// the viewer has finished opening, and comes back once it has finished closing: hiding it takes the Duo's
// side strip away, and doing that mid-animation moved the screens under X's own transitions.
static NSHashTable<UIViewController *> *LBImmersives(void) {
    static NSHashTable *table;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ table = [NSHashTable weakObjectsHashTable]; });
    return table;
}

static BOOL LBImmersiveShowing(void) {
    for (UIViewController *vc in LBImmersives())
        if (vc.viewIfLoaded.window) return YES;
    return NO;
}

// The app's own windows are asked again (not the system's keyboard windows).
static void LBStatusBarChanged(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) {
            if (w.hidden || [NSStringFromClass(w.class) hasPrefix:@"UI"]) continue;
            for (UIViewController *v = w.rootViewController; v; v = v.presentedViewController) [v setNeedsStatusBarAppearanceUpdate];
        }
    }
}

// What iOS actually asks: the viewer is presented inside one of X's navigation controllers, an
// XNAVNavigationController with Liquid Glass on (its tfnPresentedCustomPresentFromViewController:animated:completion:
// wraps it with NavigationControllerFactoryTFNFallback and sets the wrapper's
// modalPresentationCapturesStatusBarAppearance, with a custom presentation style). That wrapper owns the
// status bar and doesn't pass the question on, so it answers.
static BOOL LBWrapsImmersive(UINavigationController *nav) {
    Class viewer = objc_getClass("T1ImmersiveFullScreenViewController");
    return viewer && [nav.topViewController isKindOfClass:viewer] && LBImmersiveShowing();
}

%group ImmersiveWrapper
%hook XNAVNavigationController
- (BOOL)prefersStatusBarHidden { return LBWrapsImmersive(self) ? YES : %orig; }
- (UIViewController *)childViewControllerForStatusBarHidden { return LBWrapsImmersive(self) ? nil : %orig; }
%end
%end

%group Immersive
%hook T1ImmersiveFullScreenViewController
- (BOOL)prefersStatusBarHidden { return LBImmersiveShowing() ? YES : %orig; }
// Animated the way X animates its own status bar changes (0.2s), so the viewer's chrome slides out from
// under the strip instead of jumping. What X left to lay out goes first, so only the strip going animates.
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    [LBImmersives() addObject:self];
    UIWindow *w = self.view.window;
    [w layoutIfNeeded];
    [UIView animateWithDuration:0.2 animations:^{ LBStatusBarChanged(); [w layoutIfNeeded]; }];
}
- (void)viewDidDisappear:(BOOL)animated { %orig; [LBImmersives() removeObject:self]; LBStatusBarChanged(); }
%end

%hook _TtC14T1TwitterSwift35MultiImmersiveViewControllerManager
- (BOOL)prefersStatusBarHidden { return LBImmersiveShowing() ? YES : %orig; }
- (UIViewController *)childViewControllerForStatusBarHidden { return LBImmersiveShowing() ? nil : %orig; }
%end

%hook T1ImmersiveViewController
- (BOOL)prefersStatusBarHidden { return LBImmersiveShowing() ? YES : %orig; }
%end

// While it's open, the app's root (asked once the viewer starts closing) says the same, so nothing
// changes until it's gone.
%hook T1HostViewController
- (BOOL)prefersStatusBarHidden { return LBImmersiveShowing() ? YES : %orig; }
- (UIViewController *)childViewControllerForStatusBarHidden { return LBImmersiveShowing() ? nil : %orig; }
%end
%end

// ---------- Videos ----------

// X's full-screen viewer fills the screen with a video, cropping it, where the timeline fits it: its player
// configuration (TAVPlayerViewConfiguration, XAppLibraries) asks for gravity 1, fill, from
// T1ImmersiveFullScreenViewController -tavPlayerViewConfiguration and the immersive page views
// (ImmersiveStandaloneVideoPageView and the rest). 0 is fit, as T1InlineMediaView picks when
// isVideoAspectFitGravityPreferred. Full screen, a video fits; a pinch still zooms it to fill.
%group VideoFit
%hook TAVPlayerViewConfiguration
- (NSInteger)outputViewVideoGravity { return [self isFullscreen] ? 0 : %orig; }
%end
%end

%group Sports
// The live games carousel at the top of the home timeline: collapsed rather than just hidden, so it
// leaves no gap.
%hook _TtC7XSports22SportsGameCarouselView
- (void)didMoveToWindow { %orig; self.hidden = YES; }
- (CGSize)intrinsicContentSize { return CGSizeZero; }
%end
%end

%ctor {
    // NeoFreeBird's own toggles (NSUserDefaults, read by its BHTSettings) cover most of the brief, so
    // LiquidBird only changes their defaults; anything Giovanni switches in its settings still wins.
    // liquid_glass: X's own Liquid Glass redesign (TabBarPill, glass bars and buttons), shipped behind
    //   the ios_liquid_glass_* feature switches, which NeoFreeBird forces on with this.
    // hide_quick_compose: the "What's happening?" bar the redesign floats over the tab bar.
    // hide_spaces: the Spaces/live line under the home tabs (T1FleetLineHeaderController).
    [NSUserDefaults.standardUserDefaults registerDefaults:@{
        @"liquid_glass": @YES,
        @"hide_quick_compose": @YES,
        @"hide_spaces": @YES,
        @"hide_grok_analyze": @YES,
        @"hide_grok_sidebar": @YES,
        @"hide_grok_create": @YES,
        @"hide_promoted": @YES,
        @"hide_premium_offer": @YES,
    }];
    if (objc_getClass("_TtC7XSports22SportsGameCarouselView")) %init(Sports);
    if (objc_getClass("TAVPlayerViewConfiguration")) %init(VideoFit);
    if (objc_getClass("TFSFeatureSwitches")) %init(Switches);
    if (objc_getClass("XNAVNavigationController") && objc_getClass("T1ImmersiveFullScreenViewController")) %init(ImmersiveWrapper);
    if (objc_getClass("T1ImmersiveFullScreenViewController") && objc_getClass("_TtC14T1TwitterSwift35MultiImmersiveViewControllerManager") &&
        objc_getClass("T1ImmersiveViewController") && objc_getClass("T1HostViewController")) %init(Immersive);
    if (objc_getClass("TFSInstrumentedFeatureSwitches")) %init(InstrumentedSwitches);

    %init;  // UIKit hooks, always present
}
