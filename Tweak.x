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
@interface TFNFullscreenMediaTransition : NSObject @end
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

// The full-screen media viewer keeps the status bar hidden throughout, chrome shown or not; it
// takes the status bar over from whatever presented it.
%group Photos
%hook T1ImmersiveFullScreenViewController
- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)modalPresentationCapturesStatusBarAppearance { return YES; }
%end
%end

// Photos and videos open in X's immersive viewer (MultiImmersiveViewControllerManager, holding
// T1ImmersiveViewControllers), which decides the status bar through its children; it's hidden there, and
// the app's root hides it too while one is on screen, however it was put there.
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

static void LBStatusBarChanged(UIViewController *vc) {
    UIViewController *root = vc.viewIfLoaded.window.rootViewController;
    for (UIViewController *v = root; v; v = v.presentedViewController) [v setNeedsStatusBarAppearanceUpdate];
}

%group Immersive
%hook _TtC14T1TwitterSwift35MultiImmersiveViewControllerManager
- (BOOL)prefersStatusBarHidden { return YES; }
- (UIViewController *)childViewControllerForStatusBarHidden { return nil; }
- (BOOL)modalPresentationCapturesStatusBarAppearance { return YES; }
- (void)viewWillAppear:(BOOL)animated { %orig; [LBImmersives() addObject:self]; LBStatusBarChanged(self); }
- (void)viewDidAppear:(BOOL)animated { %orig; LBStatusBarChanged(self); }
- (void)viewDidDisappear:(BOOL)animated { %orig; [LBImmersives() removeObject:self]; LBStatusBarChanged(self); }
%end

%hook T1ImmersiveViewController
- (BOOL)prefersStatusBarHidden { return YES; }
- (void)viewWillAppear:(BOOL)animated { %orig; [LBImmersives() addObject:self]; LBStatusBarChanged(self); }
- (void)viewDidAppear:(BOOL)animated { %orig; LBStatusBarChanged(self); }
- (void)viewDidDisappear:(BOOL)animated { %orig; [LBImmersives() removeObject:self]; LBStatusBarChanged(self); }
%end

%hook T1HostViewController
- (BOOL)prefersStatusBarHidden { return LBImmersiveShowing() ? YES : %orig; }
- (UIViewController *)childViewControllerForStatusBarHidden { return LBImmersiveShowing() ? nil : %orig; }
%end
%end

// The transition that presents it decides too, for whatever it presents.
%group MediaTransition
%hook TFNFullscreenMediaTransition
+ (BOOL)_prefersStatusBarHidden:(id)controller { return YES; }
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
    if (objc_getClass("T1ImmersiveFullScreenViewController")) %init(Photos);
    if (objc_getClass("TFNFullscreenMediaTransition")) %init(MediaTransition);
    if (objc_getClass("_TtC14T1TwitterSwift35MultiImmersiveViewControllerManager") && objc_getClass("T1ImmersiveViewController") &&
        objc_getClass("T1HostViewController")) %init(Immersive);
    if (objc_getClass("TFSInstrumentedFeatureSwitches")) %init(InstrumentedSwitches);

    %init;  // UIKit hooks, always present
    if (objc_getClass("TFNSpacesBarView")) %init(Spaces);
    if (objc_getClass("T1LiveBroadcastCell")) %init(Live);
}
