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
@interface T1ImmersiveDockMorphAnimator : NSObject @end
@interface TTACoreAnatomyFeatures : NSObject @end
@interface TAVPlayerView : UIView
- (UIView *)outputView;
@end
// iOS 27.1's fold and hinge (UIView reserved regions, UIHingeInteraction), called by name: LiquidBird builds
// against an older SDK.
@protocol LBHingeInteraction
- (id)initWithUpdateHandler:(void (^)(id interaction, id update))handler;
@end
@interface NSObject (LBFold)
+ (id)divisionRegionKind;
- (NSArray *)reservedRegionsOfKind:(id)kind options:(NSUInteger)options;
- (BOOL)isActive;
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
// the viewer has appeared (its transition coordinator is still wrapping up then, which Columns.x's LBCFitScreen
// allows for), and comes back once it has finished closing: hiding it takes the Duo's side strip away, and doing
// that mid-animation moved the screens under X's own transitions.
static NSHashTable<UIViewController *> *LBImmersives(void) {
    static NSHashTable *table;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ table = [NSHashTable weakObjectsHashTable]; });
    return table;
}

void LBLogHomeTimeline(NSString *when);   // Tiling.x: where the Home timeline is scrolled to, in the layout copy
void LBLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);   // Debug.x: shown in the layout copy

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
    LBLogHomeTimeline(@"photo opened");
    [LBImmersives() addObject:self];
    UIWindow *w = self.view.window;
    [w layoutIfNeeded];
    [UIView animateWithDuration:0.2 animations:^{ LBStatusBarChanged(); [w layoutIfNeeded]; }];
    LBLogHomeTimeline(@"status bar hidden");
}
- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    [LBImmersives() removeObject:self];
    LBLogHomeTimeline(@"photo closed");
    LBStatusBarChanged();
    LBLogHomeTimeline(@"status bar shown");
    dispatch_async(dispatch_get_main_queue(), ^{ LBLogHomeTimeline(@"after the photo"); });
}
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

// ---------- Show more ----------

// "Show more" on a long post expands it in place only while two of X's server switches are on
// (ios_inline_expand_read_more_enabled and its animation one, read through TTACoreAnatomyFeatures, from
// T1StatusViewTruncationTokenAreaTapEventHandler): with the first off it opens the post instead, with the
// second off it marks the post expanded and waits for a reload that runs only once the list sits still,
// so it sometimes did nothing. Both stay on.
%group InlineExpand
%hook TTACoreAnatomyFeatures
- (BOOL)isNoteTweetInlineExpandEnabled { return YES; }
- (BOOL)isNoteTweetInlineExpandAnimationEnabled { return YES; }
%end
%end

// ---------- Videos ----------

// X's full-screen viewer fills the screen with a video, cropping it, where the timeline fits it: its player
// configuration (TAVPlayerViewConfiguration, XAppLibraries) asks for gravity 1, fill, from
// T1ImmersiveFullScreenViewController -tavPlayerViewConfiguration and the immersive page views
// (ImmersiveStandaloneVideoPageView and the rest). 0 is fit, as T1InlineMediaView picks when
// isVideoAspectFitGravityPreferred. Full screen, a video fits; a pinch still zooms it to fill.
// Except while a video shrinks into X's dock on its way out (T1ImmersiveDockMorphAnimator copies the viewer's
// configuration and asks for fill to match the dock's thumbnail, which it lays out then and there).
static BOOL LBDockMorph;

%group VideoFit
%hook TAVPlayerViewConfiguration
- (NSInteger)outputViewVideoGravity { return [self isFullscreen] && !LBDockMorph ? 0 : %orig; }
%end
%end

%group DockMorph
%hook T1ImmersiveDockMorphAnimator
+ (BOOL)runMorphWithImmersiveContainerView:(id)container immersivePlayerView:(id)player videoAspectRatio:(double)ratio callbacks:(id)callbacks {
    LBDockMorph = YES;
    BOOL ran = %orig;
    LBDockMorph = NO;
    return ran;
}
%end
%end

// ---------- Laptop mode ----------

// The Duo half open on its side, like a laptop, puts a full-screen video in the top half, above the fold, with the
// viewer's controls on the half below. Half open, the fold is an active "division" reserved region, a band across
// the window (-[UIView reservedRegionsOfKind:options:]); a hinge interaction says when it moves, and since the
// regions fill in a moment after it does, they're read again a few times. They're read only outside layout (asking
// for them inside a layout pass froze the app) and kept; the viewer's player (TAVPlayerView, whose outputView is
// the video's own rectangle) is then moved and, if need be, shrunk to fit that half. Opened flat, it goes back.
static const void *kLBHinge = &kLBHinge;
static const void *kLBLaptopMoved = &kLBLaptopMoved;
static CGFloat LBFoldY;   // the fold's top edge in the window, half open on its side; 0 otherwise
static CGSize LBFoldWindow;   // the window size it was read at

static NSHashTable<UIView *> *LBViewerPlayers(void) {
    static NSHashTable *table;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ table = [NSHashTable weakObjectsHashTable]; });
    return table;
}

static NSArray *LBFoldRegions(UIWindow *w) {
    Class kinds = objc_getClass("UIViewReservedRegionKind");
    if (!w || !kinds || ![kinds respondsToSelector:@selector(divisionRegionKind)] ||
        ![w respondsToSelector:@selector(reservedRegionsOfKind:options:)]) return nil;
    id regions = [w reservedRegionsOfKind:[kinds divisionRegionKind] options:1];   // 1: include inactive ones
    return [regions isKindOfClass:NSArray.class] ? regions : nil;
}

// For the layout copy: the fold regions as iOS reports them.
NSString *LBFoldDescription(UIWindow *w) {
    NSArray *regions = LBFoldRegions(w);
    if (!regions) return objc_getClass("UIViewReservedRegionKind") ? @"no regions" : @"no fold API";
    NSMutableArray *parts = [NSMutableArray array];
    for (id region in regions) {
        BOOL active = [region respondsToSelector:@selector(isActive)] && [region isActive];
        CGRect band = [region respondsToSelector:@selector(frame)] ? [(UIView *)region frame] : CGRectZero;
        [parts addObject:[NSString stringWithFormat:@"%@%@", NSStringFromCGRect(band), active ? @" active" : @""]];
    }
    return [NSString stringWithFormat:@"%@ (kept fold %.0f)", parts.count ? [parts componentsJoinedByString:@", "] : @"none", LBFoldY];
}

static CGFloat LBLaptopFold(UIWindow *w) {
    CGSize size = w.bounds.size;
    for (id region in LBFoldRegions(w)) {
        if (![region respondsToSelector:@selector(frame)] || ![region respondsToSelector:@selector(isActive)] || ![region isActive]) continue;
        CGRect band = [(UIView *)region frame];
        if (band.size.width >= size.width * 0.8 && band.size.height < band.size.width && CGRectGetMinY(band) > size.height * 0.25)
            return CGRectGetMinY(band);
    }
    return 0;
}

static void LBReadFold(UIWindow *w) {
    if (!w) return;
    CGFloat fold = LBLaptopFold(w);
    LBFoldWindow = w.bounds.size;
    if (fabs(fold - LBFoldY) < 0.5) return;
    LBFoldY = fold;
    LBLog(@"fold: %@", fold > 0 ? [NSString stringWithFormat:@"half open on its side, at %.0f", fold] : @"flat or none");
    for (UIView *player in LBViewerPlayers()) [player setNeedsLayout];
}

static void LBReadFoldSoon(UIWindow *w) {
    __weak UIWindow *weakWindow = w;
    for (NSNumber *delay in @[@0.0, @0.15, @0.4, @0.8, @1.5])
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            LBReadFold(weakWindow);
        });
}

// Applies the kept fold; reads nothing from iOS. The transform is set only when it changes.
static void LBPlaceViewerVideo(UIView *player) {
    UIWindow *w = player.window;
    BOOL moved = [objc_getAssociatedObject(player, kLBLaptopMoved) boolValue];
    if (w && !CGSizeEqualToSize(w.bounds.size, LBFoldWindow)) LBReadFoldSoon(w);   // turned or folded: read again, later
    CGFloat fold = w && CGSizeEqualToSize(w.bounds.size, LBFoldWindow) && player.bounds.size.height > w.bounds.size.height * 0.5 ? LBFoldY : 0;
    UIView *output = [player respondsToSelector:@selector(outputView)] ? [(TAVPlayerView *)player outputView] : nil;
    UIView *holder = player.superview;
    CGAffineTransform want = CGAffineTransformIdentity;
    if (fold > 0 && output && holder && [output isDescendantOfView:player]) {
        // The video's rectangle where X lays it out, from the player's own bounds and centre (its transform aside).
        CGRect inPlayer = [output convertRect:output.bounds toView:player];
        CGPoint centre = player.center;
        CGSize size = player.bounds.size;
        CGRect video = CGRectOffset(inPlayer, centre.x - size.width / 2 - player.bounds.origin.x, centre.y - size.height / 2 - player.bounds.origin.y);
        CGRect top = [holder convertRect:CGRectMake(0, 0, w.bounds.size.width, fold) fromView:nil];
        if (video.size.width >= 1 && video.size.height >= 1 && top.size.height >= 1) {
            CGFloat scale = MIN(1, MIN(top.size.width / video.size.width, top.size.height / video.size.height));
            CGFloat tx = CGRectGetMidX(top) - centre.x - scale * (CGRectGetMidX(video) - centre.x);
            CGFloat ty = CGRectGetMidY(top) - centre.y - scale * (CGRectGetMidY(video) - centre.y);
            want = CGAffineTransformMake(scale, 0, 0, scale, tx, ty);
        }
    }
    BOOL moving = !CGAffineTransformIsIdentity(want);
    if (!moving && !moved) return;   // never laid a hand on it: X's transform stays X's
    if (!CGAffineTransformEqualToTransform(player.transform, want)) player.transform = want;
    if (moving != moved) {
        LBLog(moving ? @"laptop mode: the video to the top half (fold at %.0f)" : @"laptop mode off: the video back (fold %.0f)", fold);
        objc_setAssociatedObject(player, kLBLaptopMoved, moving ? @YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

// One hinge interaction per window, from when a viewer first shows there.
static void LBWatchHinge(UIWindow *w) {
    Class hinge = objc_getClass("UIHingeInteraction");
    if (!w || !hinge || objc_getAssociatedObject(w, kLBHinge) || ![hinge instancesRespondToSelector:@selector(initWithUpdateHandler:)]) return;
    __weak UIWindow *weakWindow = w;
    id interaction = [(id<LBHingeInteraction>)[hinge alloc] initWithUpdateHandler:^(id hingeInteraction, id update) {
        dispatch_async(dispatch_get_main_queue(), ^{ LBReadFoldSoon(weakWindow); });
    }];
    if (![interaction conformsToProtocol:@protocol(UIInteraction)]) return;
    [w addInteraction:(id<UIInteraction>)interaction];
    objc_setAssociatedObject(w, kLBHinge, interaction, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static BOOL LBInViewer(UIView *v) {
    Class viewer = objc_getClass("T1ImmersiveFullScreenViewController");
    for (UIResponder *r = v.nextResponder; r && viewer; r = r.nextResponder)
        if ([r isKindOfClass:viewer]) return YES;
    return NO;
}

%group LaptopVideo
%hook TAVPlayerView
- (void)didMoveToWindow {
    %orig;
    if (!self.window || !LBInViewer(self)) return;
    [LBViewerPlayers() addObject:self];
    LBWatchHinge(self.window);
    LBReadFoldSoon(self.window);
}
- (void)layoutSubviews {
    %orig;
    if ([LBViewerPlayers() containsObject:self]) LBPlaceViewerVideo(self);
}
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
    if (objc_getClass("TTACoreAnatomyFeatures")) %init(InlineExpand);
    if (objc_getClass("TAVPlayerView") && objc_getClass("T1ImmersiveFullScreenViewController")) %init(LaptopVideo);
    if (objc_getClass("T1ImmersiveDockMorphAnimator")) %init(DockMorph);
    if (objc_getClass("TFSFeatureSwitches")) %init(Switches);
    if (objc_getClass("XNAVNavigationController") && objc_getClass("T1ImmersiveFullScreenViewController")) %init(ImmersiveWrapper);
    if (objc_getClass("T1ImmersiveFullScreenViewController") && objc_getClass("_TtC14T1TwitterSwift35MultiImmersiveViewControllerManager") &&
        objc_getClass("T1ImmersiveViewController") && objc_getClass("T1HostViewController")) %init(Immersive);
    if (objc_getClass("TFSInstrumentedFeatureSwitches")) %init(InstrumentedSwitches);

    %init;  // UIKit hooks, always present
}
