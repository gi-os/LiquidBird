#import <UIKit/UIKit.h>
#import <objc/runtime.h>

extern NSString *LBCPanelStatus;   // Columns.x

// A layout dump for working on LiquidBird without FLEX: press and hold anywhere with three fingers and
// the window's view and view controller hierarchies are copied to the pasteboard, for Giovanni to paste
// to Claude. Class names, frames, hidden/alpha, accessibility identifiers and control labels only; cells
// are listed by class without their contents, so no tweet text is copied.

// The layout changes LiquidBird made lately (Tiling.x, Columns.x), newest last, with how long before the
// copy: what it did when something jumped.
static NSMutableArray<NSArray *> *LBLogLines(void) {
    static NSMutableArray *lines;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ lines = [NSMutableArray array]; });
    return lines;
}

void LBLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
void LBLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *line = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSMutableArray *lines = LBLogLines();
    [lines addObject:@[@(CFAbsoluteTimeGetCurrent()), line]];
    if (lines.count > 120) [lines removeObjectAtIndex:0];
}

static NSString *LBPad(NSInteger depth) {
    return [@"" stringByPaddingToLength:(NSUInteger)depth * 2 withString:@" " startingAtIndex:0];
}

static void LBDumpView(UIView *v, NSInteger depth, NSMutableString *out, NSInteger *lines) {
    if (*lines >= 1500) return;
    (*lines)++;
    [out appendFormat:@"%@%@ %@", LBPad(depth), NSStringFromClass(v.class), NSStringFromCGRect(v.frame)];
    if (v.hidden) [out appendString:@" hidden"];
    if (v.alpha < 0.99) [out appendFormat:@" a=%.2f", v.alpha];
    if (v.accessibilityIdentifier.length) [out appendFormat:@" id=%@", v.accessibilityIdentifier];
    if ([v isKindOfClass:UIScrollView.class]) {
        UIScrollView *sv = (UIScrollView *)v;
        [out appendFormat:@" offset=%@ inset=%@ adjusted=%@", NSStringFromCGPoint(sv.contentOffset),
                          NSStringFromUIEdgeInsets(sv.contentInset), NSStringFromUIEdgeInsets(sv.adjustedContentInset)];
    }
    if ([v.nextResponder isKindOfClass:UIViewController.class])
        [out appendFormat:@" safe=%@", NSStringFromUIEdgeInsets(v.safeAreaInsets)];
    // Labels name X's tabs and buttons; a cell's would be its tweet, so cells' are left out.
    BOOL cell = [v isKindOfClass:UITableViewCell.class] || [v isKindOfClass:UICollectionViewCell.class];
    if (!cell && ([v isKindOfClass:UIControl.class] || v.isAccessibilityElement) && v.accessibilityLabel.length)
        [out appendFormat:@" label=%@", [v.accessibilityLabel substringToIndex:MIN(v.accessibilityLabel.length, (NSUInteger)40)]];
    [out appendString:@"\n"];
    // Cells are listed without their contents (tweets), except X's paging cells, which hold whole timelines.
    if (depth >= 45 || (cell && [NSStringFromClass(v.class) rangeOfString:@"PagingCell"].location == NSNotFound)) return;
    for (UIView *s in v.subviews) LBDumpView(s, depth + 1, out, lines);
}

static void LBDumpViewController(UIViewController *vc, NSInteger depth, NSMutableString *out) {
    UIView *v = vc.viewIfLoaded;
    [out appendFormat:@"%@%@ view=%@ %@ additionalSafe=%@\n", LBPad(depth), NSStringFromClass(vc.class),
                      v ? NSStringFromClass(v.class) : @"-", v ? NSStringFromCGRect(v.frame) : @"",
                      NSStringFromUIEdgeInsets(vc.additionalSafeAreaInsets)];
    for (UIViewController *c in vc.childViewControllers) LBDumpViewController(c, depth + 1, out);
    UIViewController *p = vc.presentedViewController;
    if (p && p.presentingViewController == vc) {
        [out appendFormat:@"%@presents (style %ld, captures status bar %d, prefers it hidden %d):\n", LBPad(depth + 1),
                          (long)p.modalPresentationStyle, p.modalPresentationCapturesStatusBarAppearance, p.prefersStatusBarHidden];
        LBDumpViewController(p, depth + 2, out);
    }
}

@interface LBDumper : NSObject
+ (instancetype)shared;
- (void)pressed:(UILongPressGestureRecognizer *)g;
@end

@implementation LBDumper
+ (instancetype)shared {
    static LBDumper *d;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ d = [LBDumper new]; });
    return d;
}

- (void)pressed:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    UIWindow *w = (UIWindow *)g.view;
    UIWindowScene *scene = w.windowScene;
    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"LiquidBird layout dump, iOS %@, idiom %ld, scale %.0f\n", UIDevice.currentDevice.systemVersion,
                      (long)UIDevice.currentDevice.userInterfaceIdiom, w.traitCollection.displayScale];
    [out appendFormat:@"window %@ safeArea %@ sizeClass h%ld v%ld\n", NSStringFromCGRect(w.bounds),
                      NSStringFromUIEdgeInsets(w.safeAreaInsets), (long)w.traitCollection.horizontalSizeClass,
                      (long)w.traitCollection.verticalSizeClass];
    [out appendFormat:@"statusBar %@%@\n", NSStringFromCGRect(scene.statusBarManager.statusBarFrame),
                      scene.statusBarManager.isStatusBarHidden ? @" hidden" : @""];
    // Which window decides the status bar: the topmost, through its root's say.
    for (UIWindow *win in scene.windows)
        [out appendFormat:@"  %@ level %.0f%@%@ %@ root %@ prefersHidden %d\n", NSStringFromClass(win.class), win.windowLevel,
                          win.hidden ? @" hidden" : @"", win.isKeyWindow ? @" key" : @"", NSStringFromCGRect(win.frame),
                          NSStringFromClass(win.rootViewController.class), win.rootViewController.prefersStatusBarHidden];
    [out appendFormat:@"Explore panel: %@\n\n", LBCPanelStatus];
    [out appendString:@"== LiquidBird's layout changes (seconds before this copy)\n"];
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    for (NSArray *entry in LBLogLines())
        [out appendFormat:@"%7.2f  %@\n", now - [entry.firstObject doubleValue], entry.lastObject];
    [out appendString:@"\n== view controllers\n"];
    if (w.rootViewController) LBDumpViewController(w.rootViewController, 0, out);
    [out appendString:@"\n== views\n"];
    NSInteger lines = 0;
    LBDumpView(w, 0, out, &lines);
    UIPasteboard.generalPasteboard.string = out;

    UIViewController *top = w.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Layout copied"
                                                               message:@"Paste it to Claude."
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [top presentViewController:a animated:YES completion:nil];
}
@end

static const void *kLBDumpGesture = &kLBDumpGesture;

%hook UIWindow
- (void)becomeKeyWindow {
    %orig;
    if (objc_getAssociatedObject(self, kLBDumpGesture)) return;
    UILongPressGestureRecognizer *g = [[UILongPressGestureRecognizer alloc] initWithTarget:[LBDumper shared]
                                                                                    action:@selector(pressed:)];
    g.numberOfTouchesRequired = 3;
    g.minimumPressDuration = 1.0;
    g.cancelsTouchesInView = NO;
    [self addGestureRecognizer:g];
    objc_setAssociatedObject(self, kLBDumpGesture, g, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
%end

// Marks X's "Show more" on a long post in the log, so what moved after it shows.
@interface T1StatusViewTruncationTokenAreaTapEventHandler : NSObject @end
@interface T1StandardStatusInlineExpansionHelper : NSObject @end

%group ShowMore
%hook T1StatusViewTruncationTokenAreaTapEventHandler
- (void)handleStatusViewEvent:(id)event controller:(id)controller scribeContext:(id)context {
    LBLog(@"Show more tapped (in %@)", NSStringFromClass([controller class]));
    %orig;
}
%end

// Whether X expanded it in place (YES), or fell back to a reload (NO; no row, it isn't on screen).
%hook T1StandardStatusInlineExpansionHelper
- (BOOL)setExpanded:(BOOL)expanded forViewModel:(id)model atIndexPath:(NSIndexPath *)path inController:(id)controller
   animationEnabled:(BOOL)animated {
    BOOL done = %orig;
    LBLog(@"Show more %@ row %@ animated %d: %@", expanded ? @"expand" : @"collapse", path ? @(path.row) : @"none", animated,
          done ? @"in place" : @"left to a reload");
    return done;
}
%end
%end

%ctor {
    %init;
    if (objc_getClass("T1StatusViewTruncationTokenAreaTapEventHandler") && objc_getClass("T1StandardStatusInlineExpansionHelper"))
        %init(ShowMore);
}
