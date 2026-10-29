#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#define LB_GLASS_TAG 0xB1D

// Placeholder classes (unverified, see CLAUDE.md). Declared so the hooks compile; each one is
// hooked from its own Logos group, set up only if the class exists, so a wrong name is a no-op
// instead of a launch crash.
@interface TFNSpacesBarView : UIView @end
@interface _TtC7XSports22SportsGameCarouselView : UIView @end
@interface T1LiveBroadcastCell : UIView @end
@interface TFSFeatureSwitches : NSObject @end
@interface T1ImmersiveFullScreenViewController : UIViewController @end
@interface XNAVNavigationController : UINavigationController @end
@interface T1ImmersiveViewController : UIViewController @end
@interface _TtC14T1TwitterSwift35MultiImmersiveViewControllerManager : UIViewController @end
@interface T1HostViewController : UIViewController @end
@interface TFSInstrumentedFeatureSwitches : NSObject @end

// ---------- helpers ----------

static BOOL LBMatches(UIView *v, NSString *needle) {
    NSString *s = [NSString stringWithFormat:@"%@|%@",
                   v.accessibilityLabel ?: @"", v.accessibilityIdentifier ?: @""];
    return [s rangeOfString:needle options:NSCaseInsensitiveSearch].location != NSNotFound;
}

static void LBKill(UIView *v) {
    v.hidden = YES;
    v.userInteractionEnabled = NO;
    if ([v.superview isKindOfClass:UIStackView.class]) [v removeFromSuperview];
}

static BOOL LBIsGrokString(NSString *s) {
    return s && [s rangeOfString:@"grok" options:NSCaseInsensitiveSearch].location != NSNotFound;
}

// ---------- Grok removal ----------

%hook UIControl
- (void)didMoveToWindow {
    %orig;
    if (self.window && LBMatches(self, @"grok")) LBKill(self);
}
- (void)setAccessibilityLabel:(NSString *)l {
    %orig;
    if (LBIsGrokString(l)) LBKill(self);
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

// ---------- Live / Spaces removal ----------

%group Spaces
%hook TFNSpacesBarView      // placeholder
- (void)didMoveToWindow { %orig; self.hidden = YES; }
- (CGSize)intrinsicContentSize { return CGSizeZero; }
%end
%end

%group Live
%hook T1LiveBroadcastCell   // placeholder
- (void)didMoveToWindow { %orig; self.hidden = YES; }
%end
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
- (void)viewDidAppear:(BOOL)animated { %orig; [LBImmersives() addObject:self]; LBStatusBarChanged(); }
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
    if (objc_getClass("TFSFeatureSwitches")) %init(Switches);
    if (objc_getClass("XNAVNavigationController") && objc_getClass("T1ImmersiveFullScreenViewController")) %init(ImmersiveWrapper);
    if (objc_getClass("T1ImmersiveFullScreenViewController") && objc_getClass("_TtC14T1TwitterSwift35MultiImmersiveViewControllerManager") &&
        objc_getClass("T1ImmersiveViewController") && objc_getClass("T1HostViewController")) %init(Immersive);
    if (objc_getClass("TFSInstrumentedFeatureSwitches")) %init(InstrumentedSwitches);

    %init;  // UIKit hooks, always present
    if (objc_getClass("TFNSpacesBarView")) %init(Spaces);
    if (objc_getClass("T1LiveBroadcastCell")) %init(Live);
}
