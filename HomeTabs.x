#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// Home's row of timelines (For you, Following, pinned lists: XNavigation's AccessoryStackView, a band under the top
// bar) as one Liquid Glass bar, the way the system's own apps carry a segmented control in their top bar. On an
// ordinary iPhone it sits in Home's top bar, centred between the bar's buttons (the avatar and whatever X has on the
// other side) in place of the bird, and the band X kept for the row goes back to the timeline (Tiling.x's
// LBShiftHome, through LBHomeTabsReclaim). Where the sidebar shows (the Duo, an iPad) Home's top bar is hidden and
// the bird is the sidebar's, so the glass bar floats where the row was, centred over the feed.
//
// X's row isn't rebuilt, only stood in for, the way the sidebar's rail stands in for X's tab bar: its timelines are
// read from the row (the accessibility elements in it that carry a title), X's own row is masked out and left in
// place, and a tap on the glass bar activates the matching element as VoiceOver would. If that doesn't change the
// timeline (X's element didn't take it), the pages themselves are scrolled to it. If fewer than two timelines can be
// read from the row, or the top bar has no room, nothing is changed and X's row stays as it is.

@interface _TtC32TwitterHomeFeatureImplementation35HomeTimelineContainerViewController : UIViewController
@end
@interface _TtC11XNavigation18AccessoryStackView : UIView
@end

BOOL LBSidebarWanted(UIWindow *w);                 // Tiling.x: the Duo's poses, where the sidebar shows
UIVisualEffectView *LBGlassView(UIColor *tint);    // Tiling.x: Liquid Glass (a blur before iOS 26)
void LBLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);   // Debug.x: shown in the layout copy

static const CGFloat LBHTHeight = 40, LBHTPad = 4;

static const void *kLBHTBar = &kLBHTBar;
static const void *kLBHTReclaim = &kLBHTReclaim;
static const void *kLBHTWatcher = &kLBHTWatcher;
static const void *kLBHTMasked = &kLBHTMasked;
static const void *kLBHTMask = &kLBHTMask;
static const void *kLBHTTouches = &kLBHTTouches;
static const void *kLBHTTitleHidden = &kLBHTTitleHidden;
static const void *kLBHTLogged = &kLBHTLogged;

void LBSyncHomeTabs(UIViewController *home);

// MARK: - The glass bar

@interface LBHomeTabsBar : UIView
@property (nonatomic, copy) void (^activate)(NSInteger);
@property (nonatomic, readonly) CGFloat fittingWidth;
@property (nonatomic, readonly) NSInteger selected;
- (void)setTitles:(NSArray<NSString *> *)titles selected:(NSInteger)selected animated:(BOOL)animated;
@end

@implementation LBHomeTabsBar {
    UIVisualEffectView *_glass;
    UIScrollView *_scroll;
    UIView *_lozenge;
    NSMutableArray<UIButton *> *_buttons;
    NSArray<NSString *> *_titles;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _glass = LBGlassView(nil);
        [self addSubview:_glass];
        // More timelines than fit between the bar's buttons scroll inside the glass.
        _scroll = [[UIScrollView alloc] initWithFrame:CGRectZero];
        _scroll.showsHorizontalScrollIndicator = NO;
        _scroll.showsVerticalScrollIndicator = NO;
        _scroll.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
        _scroll.scrollsToTop = NO;
        _scroll.layer.cornerCurve = kCACornerCurveContinuous;
        [_glass.contentView addSubview:_scroll];
        // The selected timeline sits on a lighter lozenge, as in the sidebar's rail and the system's glass bars.
        _lozenge = [UIView new];
        _lozenge.userInteractionEnabled = NO;
        _lozenge.backgroundColor = [UIColor.labelColor colorWithAlphaComponent:0.14];
        _lozenge.layer.cornerCurve = kCACornerCurveContinuous;
        [_scroll addSubview:_lozenge];
        _buttons = [NSMutableArray array];
        _titles = @[];
        _selected = -1;
    }
    return self;
}

- (UIFont *)font { return [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold]; }

- (CGFloat)widthFor:(NSString *)title {
    CGFloat text = ceil([title sizeWithAttributes:@{NSFontAttributeName: self.font}].width);
    return MAX(64, text + 28);
}

- (CGFloat)fittingWidth {
    CGFloat width = 2 * LBHTPad;
    for (NSString *title in _titles) width += [self widthFor:title];
    return width;
}

- (void)tapped:(UIButton *)b {
    [self select:b.tag animated:YES];   // at once; X's own row confirms it, or puts it back
    if (self.activate) self.activate(b.tag);
}

- (void)setTitles:(NSArray<NSString *> *)titles selected:(NSInteger)selected animated:(BOOL)animated {
    if (![_titles isEqualToArray:titles]) {
        _titles = [titles copy];
        for (UIButton *b in _buttons) [b removeFromSuperview];
        [_buttons removeAllObjects];
        for (NSUInteger i = 0; i < titles.count; i++) {
            UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
            b.tag = (NSInteger)i;
            b.titleLabel.font = self.font;
            [b setTitle:titles[i] forState:UIControlStateNormal];
            [b addTarget:self action:@selector(tapped:) forControlEvents:UIControlEventTouchUpInside];
            [_scroll addSubview:b];
            [_buttons addObject:b];
        }
        _selected = -2;   // the new buttons get their colours below
        animated = NO;
        [self setNeedsLayout];
    }
    // X's row didn't say which (-1): what was selected stays.
    if (selected >= 0 && selected < (NSInteger)_buttons.count) [self select:selected animated:animated];
    else if (_selected == -2) [self select:-1 animated:NO];
}

- (void)select:(NSInteger)selected animated:(BOOL)animated {
    if (_selected == selected) return;
    _selected = selected;
    for (UIButton *b in _buttons) {
        BOOL on = b.tag == selected;
        [b setTitleColor:on ? UIColor.labelColor : UIColor.secondaryLabelColor forState:UIControlStateNormal];
        b.accessibilityTraits = UIAccessibilityTraitButton | (on ? UIAccessibilityTraitSelected : 0);
    }
    if (!animated || !self.window || UIAccessibilityIsReduceMotionEnabled()) { [self setNeedsLayout]; return; }
    [self layoutIfNeeded];
    [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.86 initialSpringVelocity:0
                        options:UIViewAnimationOptionBeginFromCurrentState animations:^{
        [self setNeedsLayout];
        [self layoutIfNeeded];
    } completion:nil];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat h = self.bounds.size.height, inner = h - 2 * LBHTPad;
    _glass.frame = self.bounds;
    _glass.layer.cornerRadius = h / 2;
    _scroll.frame = _glass.contentView.bounds;
    _scroll.layer.cornerRadius = h / 2;
    CGFloat x = LBHTPad;
    UIButton *on = nil;
    for (NSUInteger i = 0; i < _buttons.count; i++) {
        UIButton *b = _buttons[i];
        CGFloat width = [self widthFor:_titles[i]];
        b.frame = CGRectMake(x, LBHTPad, width, inner);
        if (b.tag == _selected) on = b;
        x += width;
    }
    _scroll.contentSize = CGSizeMake(x + LBHTPad, h);
    _lozenge.hidden = on == nil;
    if (on) {
        _lozenge.frame = on.frame;
        _lozenge.layer.cornerRadius = inner / 2;
        [_scroll sendSubviewToBack:_lozenge];
        // Kept in view where the timelines scroll inside the glass.
        if (_scroll.contentSize.width > _scroll.bounds.size.width + 0.5 && !_scroll.isTracking && !_scroll.isDecelerating) {
            CGFloat end = _scroll.contentSize.width - _scroll.bounds.size.width;
            CGFloat want = MIN(MAX(CGRectGetMidX(on.frame) - _scroll.bounds.size.width / 2, 0), end);
            if (fabs(want - _scroll.contentOffset.x) >= 0.5) _scroll.contentOffset = CGPointMake(want, 0);
        } else if (_scroll.contentSize.width <= _scroll.bounds.size.width + 0.5 && _scroll.contentOffset.x != 0) {
            _scroll.contentOffset = CGPointZero;
        }
    }
}
@end

// MARK: - Reading X's row

@interface LBHTItem : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, weak) UIView *view;
@property (nonatomic) CGFloat x;
@end
@implementation LBHTItem
@end

// The first text an element shows: a timeline's name. An element with none (an icon button) isn't a timeline.
static NSString *LBHTText(UIView *v, NSInteger depth) {
    if ([v isKindOfClass:UILabel.class]) {
        NSString *text = [((UILabel *)v).text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        return text.length ? text : nil;
    }
    if (depth > 6) return nil;
    for (UIView *s in v.subviews) {
        if (s.hidden) continue;
        NSString *text = LBHTText(s, depth + 1);
        if (text) return text;
    }
    return nil;
}

// Whether a view shows two different texts: an element that does is the whole row of timelines read as one (a
// segmented control), not a timeline, and is looked into.
static void LBHTTexts(UIView *v, NSMutableSet<NSString *> *texts, NSInteger depth) {
    if (texts.count >= 2 || depth > 8 || v.hidden) return;
    if ([v isKindOfClass:UILabel.class]) {
        NSString *text = LBHTText(v, 0);
        if (text) [texts addObject:text];
        return;
    }
    for (UIView *s in v.subviews) LBHTTexts(s, texts, depth + 1);
}

// The row's timelines, left to right: its accessibility elements that carry a title (X's tab views; failing that
// their labels, which are elements themselves), one for each place across the row (X may keep a second copy of a
// row at the same places, as its tab bar does).
static NSArray<LBHTItem *> *LBHTItems(UIView *row) {
    NSMutableArray<LBHTItem *> *items = [NSMutableArray array];
    if (!row) return items;
    NSMutableSet<NSNumber *> *places = [NSMutableSet set];
    NSMutableArray<UIView *> *queue = [row.subviews mutableCopy];
    for (NSUInteger seen = 0; queue.count && seen < 400; seen++) {
        UIView *v = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if (v.hidden || v.bounds.size.width < 1 || [v isKindOfClass:LBHomeTabsBar.class]) continue;
        if (!(v.isAccessibilityElement && v.accessibilityLabel.length > 0)) {
            [queue addObjectsFromArray:v.subviews];
            continue;
        }
        NSMutableSet<NSString *> *texts = [NSMutableSet set];
        LBHTTexts(v, texts, 0);
        if (texts.count >= 2) {
            [queue addObjectsFromArray:v.subviews];
            continue;
        }
        NSString *title = LBHTText(v, 0);
        if (!title) continue;
        CGFloat x = CGRectGetMidX([row convertRect:v.bounds fromView:v]);
        NSNumber *place = @(round(x));
        if ([places containsObject:place]) continue;
        [places addObject:place];
        LBHTItem *item = [LBHTItem new];
        item.title = title;
        item.view = v;
        item.x = x;
        [items addObject:item];
    }
    [items sortUsingComparator:^NSComparisonResult(LBHTItem *a, LBHTItem *b) {
        return a.x < b.x ? NSOrderedAscending : a.x > b.x ? NSOrderedDescending : NSOrderedSame;
    }];
    return items;
}

// The view that holds all of them and nothing above: what's masked out when the row has more in it than timelines.
static UIView *LBHTCommon(NSArray<LBHTItem *> *items, UIView *row) {
    UIView *common = nil;
    for (LBHTItem *item in items) {
        UIView *v = item.view;
        if (!v) continue;
        if (!common) { common = v.superview ?: row; continue; }
        while (common && common != row && ![v isDescendantOfView:common]) common = common.superview;
        if (!common) return row;
    }
    return common && [common isDescendantOfView:row] ? common : row;
}

static UIViewController *LBHTPager(UIViewController *home) {
    for (UIViewController *c in home.childViewControllers)
        if ([NSStringFromClass(c.class) rangeOfString:@"SegmentedViewController"].location != NSNotFound) return c;
    return nil;
}

// The timelines' pages: the sideways paging list in Home's pager (a collection view of paging cells).
static UIScrollView *LBHTPages(UIViewController *home) {
    UIView *pager = LBHTPager(home).viewIfLoaded;
    if (!pager) return nil;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:pager];
    for (NSUInteger seen = 0; queue.count && seen < 200; seen++) {
        UIView *v = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([v isKindOfClass:UITableView.class] || [v isKindOfClass:UITableViewCell.class] ||
            [v isKindOfClass:UICollectionViewCell.class]) continue;
        if ([v isKindOfClass:UIScrollView.class]) {
            UIScrollView *scroll = (UIScrollView *)v;
            if (scroll.bounds.size.height > 100 && (scroll.pagingEnabled || [v isKindOfClass:UICollectionView.class])) return scroll;
            continue;
        }
        [queue addObjectsFromArray:v.subviews];
    }
    return nil;
}

// The timeline showing: the one element X marks selected, else the page showing; -1 if neither says.
static NSInteger LBHTSelected(NSArray<LBHTItem *> *items, UIScrollView *pages) {
    NSInteger found = -1, marked = 0;
    for (NSUInteger i = 0; i < items.count; i++) {
        // The element, or the tab view around it where the element is only its label.
        BOOL on = NO;
        UIView *v = items[i].view;
        for (NSInteger up = 0; v && up < 2 && !on; up++, v = v.superview) {
            if ([v isKindOfClass:objc_getClass("_TtC11XNavigation18AccessoryStackView")]) break;
            on = (v.accessibilityTraits & UIAccessibilityTraitSelected) != 0 ||
                 ([v isKindOfClass:UIControl.class] && ((UIControl *)v).selected);
        }
        if (on) { found = (NSInteger)i; marked++; }
    }
    if (marked == 1) return found;
    if (pages && pages.bounds.size.width > 1 && !pages.isDragging && !pages.isDecelerating) {
        NSInteger page = lround(pages.contentOffset.x / pages.bounds.size.width);
        if (page >= 0 && page < (NSInteger)items.count) return page;
    }
    return -1;
}

static UIView *LBHTRow(UIViewController *home) {
    Class rowClass = objc_getClass("_TtC11XNavigation18AccessoryStackView");
    if (!rowClass) return nil;
    for (UIView *v in home.viewIfLoaded.subviews)
        if ([v isKindOfClass:rowClass] && !v.hidden) return v;
    return nil;
}

// MARK: - Standing in for it

// X's row, or the part of it holding the timelines, masked out and out of reach of touches and VoiceOver (the glass
// bar's buttons are what's read), but still laid out and still X's to update: it's what the glass bar reads.
static void LBHTRestore(UIView *v) {
    if (!v) return;
    if (v.layer.mask && v.layer.mask == objc_getAssociatedObject(v, kLBHTMask)) v.layer.mask = nil;
    NSNumber *touches = objc_getAssociatedObject(v, kLBHTTouches);
    if (touches) v.userInteractionEnabled = touches.boolValue;
    v.accessibilityElementsHidden = NO;
    objc_setAssociatedObject(v, kLBHTMask, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(v, kLBHTTouches, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void LBHTMaskOut(UIViewController *home, UIView *target) {
    NSHashTable<UIView *> *held = objc_getAssociatedObject(home, kLBHTMasked);
    UIView *was = held.anyObject;
    if (was != target) {
        LBHTRestore(was);
        [held removeAllObjects];
    }
    if (!target) return;
    if (!held) {
        held = [NSHashTable weakObjectsHashTable];
        objc_setAssociatedObject(home, kLBHTMasked, held, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [held addObject:target];
    CALayer *mask = objc_getAssociatedObject(target, kLBHTMask);
    if (!mask) {
        mask = [CALayer layer];   // nothing in it: nothing of the row shows
        objc_setAssociatedObject(target, kLBHTMask, mask, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(target, kLBHTTouches, @(target.userInteractionEnabled), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (target.layer.mask != mask) target.layer.mask = mask;
    if (target.userInteractionEnabled) target.userInteractionEnabled = NO;
    if (!target.accessibilityElementsHidden) target.accessibilityElementsHidden = YES;
}

// The bird in Home's top bar gives its place to the glass bar, and takes it back whenever the bar isn't there (the
// title control is the navigation bar's, shared with the screens pushed over Home).
static void LBHTShowTitle(UINavigationBar *navBar, BOOL show) {
    Class titleClass = objc_getClass("_UINavigationBarTitleControl");
    if (!navBar || !titleClass) return;
    NSMutableArray<UIView *> *queue = [navBar.subviews mutableCopy];
    for (NSUInteger seen = 0; queue.count && seen < 300; seen++) {
        UIView *v = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([v isKindOfClass:LBHomeTabsBar.class]) continue;
        if (![v isKindOfClass:titleClass]) { [queue addObjectsFromArray:v.subviews]; continue; }
        BOOL hidden = [objc_getAssociatedObject(v, kLBHTTitleHidden) boolValue];
        if (!show) {
            if (!hidden) objc_setAssociatedObject(v, kLBHTTitleHidden, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            if (v.alpha != 0) v.alpha = 0;
        } else if (hidden) {
            objc_setAssociatedObject(v, kLBHTTitleHidden, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            v.alpha = 1;
        }
    }
}

// Where the glass bar goes in the top bar: centred on the bar if that clears its buttons, else centred between
// them, on their line. The buttons are the bar's controls narrower than half of it that don't span its middle (the
// title does). CGRectNull if there's no room worth having.
static CGRect LBHTSlot(UINavigationBar *navBar, CGFloat fitting) {
    CGFloat width = navBar.bounds.size.width;
    CGFloat leading = 52, trailing = width - 52, lines = 0;
    NSInteger count = 0;
    Class titleClass = objc_getClass("_UINavigationBarTitleControl");
    NSMutableArray<UIView *> *queue = [navBar.subviews mutableCopy];
    for (NSUInteger seen = 0; queue.count && seen < 300; seen++) {
        UIView *v = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if (v.hidden || v.alpha < 0.01 || [v isKindOfClass:LBHomeTabsBar.class] || (titleClass && [v isKindOfClass:titleClass])) continue;
        if (![v isKindOfClass:UIControl.class]) { [queue addObjectsFromArray:v.subviews]; continue; }
        CGRect r = [navBar convertRect:v.bounds fromView:v];
        if (r.size.width < 20 || r.size.width > width * 0.45 || (CGRectGetMinX(r) < width / 2 && CGRectGetMaxX(r) > width / 2)) continue;
        if (CGRectGetMidX(r) < width / 2) leading = MAX(leading, CGRectGetMaxX(r));
        else trailing = MIN(trailing, CGRectGetMinX(r));
        lines += CGRectGetMidY(r);
        count++;
    }
    leading += 12;
    trailing -= 12;
    CGFloat w = MIN(fitting, trailing - leading);
    if (w < 120) return CGRectNull;
    CGFloat x = MIN(MAX(width / 2 - w / 2, leading), trailing - w);
    CGFloat line = count ? lines / count : navBar.bounds.size.height / 2;
    return CGRectMake(round(x), round(line - LBHTHeight / 2), round(w), LBHTHeight);
}

// MARK: - Keeping it in step

// Follows X's row: after a tap on the glass bar, and after a swipe between the timelines' pages (X changes its
// row's selection without laying anything out).
@interface LBHTWatcher : NSObject
@property (nonatomic, weak) UIViewController *home;
@property (nonatomic, weak) UIScrollView *pages;
- (void)watch:(UIScrollView *)pages;
- (void)activate:(NSInteger)index;
@end

@implementation LBHTWatcher
- (void)syncSoon {
    __weak LBHTWatcher *weakSelf = self;
    for (NSNumber *delay in @[@0.12, @0.45, @0.9, @1.4])
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIViewController *home = weakSelf.home;
            if (home) LBSyncHomeTabs(home);
        });
}

- (void)watch:(UIScrollView *)pages {
    if (self.pages == pages) return;
    [self.pages.panGestureRecognizer removeTarget:self action:@selector(panned:)];
    self.pages = pages;
    [pages.panGestureRecognizer addTarget:self action:@selector(panned:)];
}

- (void)panned:(UIPanGestureRecognizer *)pan {
    if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) [self syncSoon];
}

// As VoiceOver activates a timeline in X's row: the element, or the first view above it in the row that takes it
// (a control's own action, failing that). Checked a moment later, and if X's row and pages are still elsewhere
// the pages are scrolled there, which X follows as it follows a swipe.
- (void)activate:(NSInteger)index {
    UIViewController *home = self.home;
    UIView *row = LBHTRow(home);
    NSArray<LBHTItem *> *items = LBHTItems(row);
    if (index < 0 || index >= (NSInteger)items.count) return;
    BOOL taken = NO;
    NSString *by = @"nothing";
    for (UIView *v = items[index].view; v && !taken; v = v.superview) {
        taken = [v accessibilityActivate];
        if (!taken && [v isKindOfClass:UIControl.class] && ((UIControl *)v).allTargets.count) {
            [(UIControl *)v sendActionsForControlEvents:UIControlEventTouchUpInside];
            taken = YES;
        }
        if (taken) by = NSStringFromClass(v.class);
        if (v == row) break;
    }
    LBLog(@"Home tabs: %@ tapped, taken by %@", items[index].title, by);
    __weak LBHTWatcher *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIViewController *home = weakSelf.home;
        UIScrollView *pages = LBHTPages(home);
        NSArray<LBHTItem *> *now = LBHTItems(LBHTRow(home));
        if (!pages || index >= (NSInteger)now.count || LBHTSelected(now, pages) == index) return;
        CGFloat x = index * pages.bounds.size.width;
        if (x > pages.contentSize.width - pages.bounds.size.width + 0.5) return;
        LBLog(@"Home tabs: X's row didn't follow, pages scrolled to %ld", (long)index);
        [pages setContentOffset:CGPointMake(x, pages.contentOffset.y) animated:YES];
        [weakSelf syncSoon];
    });
    [self syncSoon];
}
@end

// For Tiling.x's LBShiftHome: the height of the row's band under the top bar, where the glass bar has taken the
// row's place in the bar itself; 0 wherever the row keeps its band.
CGFloat LBHomeTabsReclaim(UIViewController *home) {
    return [objc_getAssociatedObject(home, kLBHTReclaim) doubleValue];
}

static void LBHTSetReclaim(UIViewController *home, CGFloat reclaim) {
    if (fabs(LBHomeTabsReclaim(home) - reclaim) < 0.5) return;
    LBLog(@"Home tabs: row band %.0f -> %.0f back to the timeline", LBHomeTabsReclaim(home), reclaim);
    objc_setAssociatedObject(home, kLBHTReclaim, @(reclaim), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [home.viewIfLoaded setNeedsLayout];   // LBShiftHome applies it
}

// In the layout copy, when it changes: what was read from X's row and where the glass bar went.
static void LBHTLogState(UIViewController *home, NSString *state) {
    if ([objc_getAssociatedObject(home, kLBHTLogged) isEqualToString:state]) return;
    objc_setAssociatedObject(home, kLBHTLogged, state, OBJC_ASSOCIATION_COPY_NONATOMIC);
    LBLog(@"Home tabs: %@", state);
}

// X's row as it was: nothing read from it, or nowhere to put the glass bar.
static void LBHTStandDown(UIViewController *home, NSString *why) {
    LBHomeTabsBar *bar = objc_getAssociatedObject(home, kLBHTBar);
    [bar removeFromSuperview];
    LBHTMaskOut(home, nil);
    LBHTShowTitle(home.navigationController.navigationBar, YES);
    LBHTSetReclaim(home, 0);
    LBHTLogState(home, why);
}

void LBSyncHomeTabs(UIViewController *home) {
    static BOOL busy;
    UIView *view = home.viewIfLoaded;
    UIWindow *w = view.window;
    if (!w || busy) return;
    busy = YES;
    UIView *row = LBHTRow(home);
    NSArray<LBHTItem *> *items = LBHTItems(row);
    if (items.count < 2 || items.count > 12) {
        LBHTStandDown(home, [NSString stringWithFormat:@"X's row kept (%@, %lu timelines read)",
                             row ? NSStringFromClass(row.class) : @"no row", (unsigned long)items.count]);
        busy = NO;
        return;
    }
    UINavigationController *nav = home.navigationController;
    UINavigationBar *navBar = nav.navigationBar;
    BOOL side = LBSidebarWanted(w), top = nav.topViewController == home;

    LBHomeTabsBar *bar = objc_getAssociatedObject(home, kLBHTBar);
    LBHTWatcher *watcher = objc_getAssociatedObject(home, kLBHTWatcher);
    if (!watcher) {
        watcher = [LBHTWatcher new];
        watcher.home = home;
        objc_setAssociatedObject(home, kLBHTWatcher, watcher, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (!bar) {
        bar = [[LBHomeTabsBar alloc] initWithFrame:CGRectZero];
        __weak LBHTWatcher *weakWatcher = watcher;
        bar.activate = ^(NSInteger i) { [weakWatcher activate:i]; };
        objc_setAssociatedObject(home, kLBHTBar, bar, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UIScrollView *pages = LBHTPages(home);
    [watcher watch:pages];
    NSMutableArray<NSString *> *titles = [NSMutableArray array];
    for (LBHTItem *item in items) [titles addObject:item.title];
    [bar setTitles:titles selected:LBHTSelected(items, pages) animated:bar.window != nil];

    // The timelines' own part of the row, in Home's view; the whole row is masked out if that's all there is to it.
    UIView *common = LBHTCommon(items, row);
    CGRect inRow = [row convertRect:common.bounds fromView:common];
    BOOL whole = common == row || (inRow.size.width >= row.bounds.size.width * 0.9 && inRow.size.height >= row.bounds.size.height - 1);
    CGFloat fitting = bar.fittingWidth;
    CGRect frame = CGRectNull;
    UIView *parent = nil;
    if (side) {
        // Home's top bar is hidden here: over the feed, where the row was, clear of the sidebar's strip.
        UIEdgeInsets safe = view.safeAreaInsets;
        CGFloat left = safe.left + 12, right = view.bounds.size.width - safe.right - 12;
        CGFloat width = MIN(fitting, right - left);
        CGFloat line = CGRectGetMidY([view convertRect:common.bounds fromView:common]);
        if (width >= 120)
            frame = CGRectMake(round((left + right) / 2 - width / 2), round(line - LBHTHeight / 2), round(width), LBHTHeight);
        parent = view;
    } else if (top && navBar.window) {
        frame = LBHTSlot(navBar, fitting);
        parent = navBar;
    }
    if (CGRectIsNull(frame)) {
        if (side || (top && navBar.window)) {
            LBHTStandDown(home, @"X's row kept (no room for the glass bar)");
        } else {
            // A screen is pushed over Home: the top bar is that screen's. The row's band stays as it was.
            if (bar.superview == navBar) bar.hidden = YES;
            LBHTShowTitle(navBar, YES);
        }
        busy = NO;
        return;
    }
    if (bar.superview != parent) [parent addSubview:bar];
    else if (parent.subviews.lastObject != bar) [parent bringSubviewToFront:bar];
    bar.hidden = NO;
    bar.alpha = 1;
    if (!CGRectEqualToRect(bar.frame, frame)) bar.frame = frame;
    LBHTMaskOut(home, whole ? row : common);
    LBHTShowTitle(navBar, side);
    LBHTSetReclaim(home, !side && whole ? row.bounds.size.height : 0);
    LBHTLogState(home, [NSString stringWithFormat:@"%@ as glass %@ at %@ (read from %@ in %@, %@)",
                        [titles componentsJoinedByString:@" | "], side ? @"over the feed" : @"in the top bar",
                        NSStringFromCGRect(frame), NSStringFromClass(items.firstObject.view.class),
                        NSStringFromClass(common.class), whole ? @"the whole row" : @"part of the row"]);
    busy = NO;
}

// Home is about to be covered (a push) or left: the top bar goes to the next screen, without Home's glass bar, and
// with its own title.
static void LBHTLeave(UIViewController *home) {
    LBHomeTabsBar *bar = objc_getAssociatedObject(home, kLBHTBar);
    UINavigationBar *navBar = home.navigationController.navigationBar;
    LBHTShowTitle(navBar, YES);
    if (!bar || bar.superview != navBar || bar.hidden) return;
    [UIView animateWithDuration:0.2 animations:^{ bar.alpha = 0; } completion:^(BOOL finished) {
        if (bar.alpha == 0) bar.hidden = YES;
    }];
}

static UIViewController *LBHTHomeOf(UIView *row) {
    Class home = objc_getClass("_TtC32TwitterHomeFeatureImplementation35HomeTimelineContainerViewController");
    UIResponder *r = row.superview.nextResponder;
    return home && [r isKindOfClass:home] ? (UIViewController *)r : nil;
}

%group HomeTabs
%hook _TtC32TwitterHomeFeatureImplementation35HomeTimelineContainerViewController
- (void)viewDidLayoutSubviews {
    %orig;
    LBSyncHomeTabs(self);
}
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    LBSyncHomeTabs(self);
}
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    LBSyncHomeTabs(self);
}
- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    LBHTLeave(self);
}
%end

// The row lays out as its timelines change (a list pinned or unpinned) and as X restyles it.
%hook _TtC11XNavigation18AccessoryStackView
- (void)layoutSubviews {
    %orig;
    UIViewController *home = LBHTHomeOf(self);
    if (home) LBSyncHomeTabs(home);
}
%end
%end

%ctor {
    if (objc_getClass("_TtC32TwitterHomeFeatureImplementation35HomeTimelineContainerViewController") &&
        objc_getClass("_TtC11XNavigation18AccessoryStackView")) %init(HomeTabs);
}
