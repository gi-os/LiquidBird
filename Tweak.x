#import <UIKit/UIKit.h>

#define LB_GLASS_TAG 0xB1D

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

%hook TFNSpacesBarView      // placeholder
- (void)didMoveToWindow { %orig; self.hidden = YES; }
- (CGSize)intrinsicContentSize { return CGSizeZero; }
%end

%hook T1LiveBroadcastCell   // placeholder
- (void)didMoveToWindow { %orig; self.hidden = YES; }
%end
