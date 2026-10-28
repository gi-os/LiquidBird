#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#define LB_GLASS_TAG 0xB1D

// Placeholder classes (unverified, see CLAUDE.md). Declared so the hooks compile; each one is
// hooked from its own Logos group, set up only if the class exists, so a wrong name is a no-op
// instead of a launch crash.
@interface T1TabBarView : UIView @end
@interface TFNSpacesBarView : UIView @end
@interface T1LiveBroadcastCell : UIView @end

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

// ---------- Liquid Glass tab bar / rail ----------

%group TabBar
%hook T1TabBarView  // placeholder: confirm in FLEX
- (void)layoutSubviews {
    %orig;
    if (@available(iOS 26, *)) {
        UIVisualEffectView *g = (UIVisualEffectView *)[self viewWithTag:LB_GLASS_TAG];
        if (!g) {
            UIGlassEffect *e = [UIGlassEffect effectWithStyle:UIGlassEffectStyleRegular];
            e.interactive = YES;
            g = [[UIVisualEffectView alloc] initWithEffect:e];
            g.tag = LB_GLASS_TAG;
            g.userInteractionEnabled = NO;
            [self insertSubview:g atIndex:0];
        }
        self.backgroundColor = UIColor.clearColor;
        for (UIView *v in self.subviews)
            if (v != g && [v isKindOfClass:UIVisualEffectView.class]) v.hidden = YES;
        g.frame = CGRectInset(self.bounds, 16, 6);
        CGFloat r = MIN(g.bounds.size.width, g.bounds.size.height) / 2;
        g.layer.cornerRadius = r;
        g.layer.cornerCurve = kCACornerCurveContinuous;
        g.layer.masksToBounds = YES;
    }
}
%end
%end

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

%ctor {
    %init;  // UIKit hooks, always present
    if (objc_getClass("T1TabBarView")) %init(TabBar);
    if (objc_getClass("TFNSpacesBarView")) %init(Spaces);
    if (objc_getClass("T1LiveBroadcastCell")) %init(Live);
}
