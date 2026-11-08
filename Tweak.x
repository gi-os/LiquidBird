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
// for them inside a layout pass froze the app) and only while the app is active, and kept. The video (the viewer
// player's outputView, TAVPlayerView's own rectangle for it) is then moved, and if need be shrunk, into that half
// with the player's sublayerTransform, which X never sets and which leaves the player's frame alone: moving the
// player itself (its transform) fed back, as X and autoresizing set its frame through that transform whenever the
// window resized (switching apps, folding), shrinking it a step each time until its size was NaN and the app
// crashed. Opened flat, it goes back.
static const void *kLBHinge = &kLBHinge;
static CGFloat LBFoldY;   // the fold's top edge in the window, half open on its side; 0 otherwise
static CGSize LBFoldWindow;   // the window size it was read at
static BOOL LBFoldReading;   // a series of reads is on its way

static NSHashTable<UIView *> *LBViewerPlayers(void) {
    static NSHashTable *table;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ table = [NSHashTable weakObjectsHashTable]; });
    return table;
}

// Asked only of a settled window (folding moves the app between screens), and never allowed to take the app down.
static NSArray *LBFoldRegions(UIWindow *w) {
    Class kinds = objc_getClass("UIViewReservedRegionKind");
    if (!w || w.hidden || !w.windowScene || w.windowScene.activationState != UISceneActivationStateForegroundActive ||
        !kinds || ![kinds respondsToSelector:@selector(divisionRegionKind)] ||
        ![w respondsToSelector:@selector(reservedRegionsOfKind:options:)]) return nil;
    @try {
        id regions = [w reservedRegionsOfKind:[kinds divisionRegionKind] options:1];   // 1: include inactive ones
        return [regions isKindOfClass:NSArray.class] ? regions : nil;
    } @catch (NSException *e) {
        LBLog(@"fold regions: %@", e.reason);
        return nil;
    }
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

// The fold's top edge half open on its side, 0 flat or upright, -1 when iOS can't be asked now.
static CGFloat LBLaptopFold(UIWindow *w) {
    NSArray *regions = LBFoldRegions(w);
    if (!regions) return -1;
    CGSize size = w.bounds.size;
    for (id region in regions) {
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
    if (fold < 0) return;   // in the background or between screens: keep what was read, and read again once back
    BOOL resized = !CGSizeEqualToSize(LBFoldWindow, w.bounds.size), moved = fabs(fold - LBFoldY) >= 0.5;
    LBFoldWindow = w.bounds.size;
    LBFoldY = fold;
    if (moved) LBLog(@"fold: %@", fold > 0 ? [NSString stringWithFormat:@"half open on its side, at %.0f", fold] : @"flat or none");
    if (moved || resized) for (UIView *player in LBViewerPlayers()) [player setNeedsLayout];
}

// A few reads over the next moment and a half; a layout pass asks only when none are on their way.
static void LBReadFoldSoon(UIWindow *w, BOOL again) {
    if (!w || (LBFoldReading && !again)) return;
    LBFoldReading = YES;
    __weak UIWindow *weakWindow = w;
    NSArray<NSNumber *> *delays = @[@0.0, @0.15, @0.4, @0.8, @1.5];
    for (NSNumber *delay in delays)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (delay == delays.lastObject) LBFoldReading = NO;
            LBReadFold(weakWindow);
        });
}

// Applies the kept fold; reads nothing from iOS. Set only when it changes, and only to something sane.
static void LBPlaceViewerVideo(UIView *player) {
    UIWindow *w = player.window;
    CALayer *layer = player.layer;
    BOOL moved = !CATransform3DIsIdentity(layer.sublayerTransform);
    BOOL settled = w && CGSizeEqualToSize(w.bounds.size, LBFoldWindow);
    if (w && !settled) LBReadFoldSoon(w, NO);   // turned or folded: read again, later
    CGRect bounds = player.bounds;
    CGFloat fold = settled && bounds.size.height > w.bounds.size.height * 0.5 ? LBFoldY : 0;
    UIView *output = [player respondsToSelector:@selector(outputView)] ? [(TAVPlayerView *)player outputView] : nil;
    CATransform3D want = CATransform3DIdentity;
    if (fold > 0 && output.superview == player) {
        CGRect video = output.frame;   // where X lays the video out in the player (the sublayer transform aside)
        CGRect top = CGRectIntersection([player convertRect:CGRectMake(0, 0, w.bounds.size.width, fold) fromView:nil], bounds);
        if (video.size.width >= 1 && video.size.height >= 1 && !CGRectIsNull(top) && top.size.height >= 1) {
            // About the layer's anchor point: p -> c + s(p - c) + t, putting the video's centre on the half's.
            CGPoint c = CGPointMake(bounds.origin.x + layer.anchorPoint.x * bounds.size.width,
                                    bounds.origin.y + layer.anchorPoint.y * bounds.size.height);
            CGFloat s = MIN(1, MIN(top.size.width / video.size.width, top.size.height / video.size.height));
            CGFloat tx = CGRectGetMidX(top) - c.x - s * (CGRectGetMidX(video) - c.x);
            CGFloat ty = CGRectGetMidY(top) - c.y - s * (CGRectGetMidY(video) - c.y);
            if (isfinite(s) && isfinite(tx) && isfinite(ty) && s >= 0.2 &&
                fabs(tx) <= bounds.size.width && fabs(ty) <= bounds.size.height) {
                want = CATransform3DMakeScale(s, s, 1);
                want.m41 = tx;
                want.m42 = ty;
            }
        }
    }
    BOOL moving = !CATransform3DIsIdentity(want);
    if (!moving && !moved) return;
    if (!CATransform3DEqualToTransform(layer.sublayerTransform, want)) layer.sublayerTransform = want;
    if (moving != moved)
        LBLog(moving ? @"laptop mode: the video to the top half (fold at %.0f)" : @"laptop mode off: the video back (fold %.0f)", fold);
}

// One hinge interaction per window, from when a viewer first shows there; and, once, a read whenever the app
// comes back (the fold may have moved while it was away).
static void LBWatchHinge(UIWindow *w) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        [NSNotificationCenter.defaultCenter addObserverForName:UISceneDidActivateNotification object:nil queue:NSOperationQueue.mainQueue
                                                    usingBlock:^(NSNotification *note) {
            UIWindow *w = LBViewerPlayers().anyObject.window;
            if (w) LBReadFoldSoon(w, YES);
        }];
    });
    Class hinge = objc_getClass("UIHingeInteraction");
    if (!w || !hinge || objc_getAssociatedObject(w, kLBHinge) || ![hinge instancesRespondToSelector:@selector(initWithUpdateHandler:)]) return;
    __weak UIWindow *weakWindow = w;
    @try {
        id interaction = [(id<LBHingeInteraction>)[hinge alloc] initWithUpdateHandler:^(id hingeInteraction, id update) {
            dispatch_async(dispatch_get_main_queue(), ^{ LBReadFoldSoon(weakWindow, YES); });
        }];
        if (![interaction conformsToProtocol:@protocol(UIInteraction)]) return;
        [w addInteraction:(id<UIInteraction>)interaction];
        objc_setAssociatedObject(w, kLBHinge, interaction, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } @catch (NSException *e) {
        LBLog(@"hinge interaction: %@", e.reason);
    }
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
    if (self.window && LBInViewer(self)) {
        [LBViewerPlayers() addObject:self];
        LBWatchHinge(self.window);
        LBReadFoldSoon(self.window, YES);
    } else if ([LBViewerPlayers() containsObject:self]) {
        // Out of the viewer (into the dock, or closed): the video goes back where X has it.
        [LBViewerPlayers() removeObject:self];
        if (!CATransform3DIsIdentity(self.layer.sublayerTransform)) self.layer.sublayerTransform = CATransform3DIdentity;
    }
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
