#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <execinfo.h>
#import <signal.h>
#import <fcntl.h>
#import <unistd.h>
#import <dlfcn.h>

// When this build was made: every crash record carries it, so the layout copy can tell a crash from an earlier
// build (kept until the next crash) from one in this build.
static const char LBBuild[] = __DATE__ " " __TIME__;

extern NSString *LBCPanelStatus;   // Columns.x
NSString *LBFoldDescription(UIWindow *w);   // Tweak.x: the fold regions iOS reports

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
    [out appendFormat:@"Explore panel: %@\n", LBCPanelStatus];
    [out appendFormat:@"fold: %@\n", LBFoldDescription(w)];
    if (w.windowScene.screen)
        [out appendFormat:@"on screen: %@ of %@\n", NSStringFromCGRect([w convertRect:w.bounds toCoordinateSpace:w.windowScene.screen.coordinateSpace]),
                          NSStringFromCGSize(w.windowScene.screen.bounds.size)];
    NSString *crash = [NSUserDefaults.standardUserDefaults stringForKey:@"liquidbird_last_crash"];
    BOOL thisBuild = [crash containsString:[NSString stringWithFormat:@"build %s,", LBBuild]];
    [out appendFormat:@"last crash%@: %@\n\n", !crash ? @"" : thisBuild ? @" (this build)" : @" (an earlier build, none in this one)",
                      crash ?: @"none recorded"];
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

// The last crash, for the layout copy: an uncaught exception's reason and where it was thrown, or the signal and
// the stack, kept in the defaults (no tweet text: symbols and offsets only). The handlers before LiquidBird's
// (Crashlytics) still run.
static NSUncaughtExceptionHandler *LBPreviousExceptionHandler;
static int LBCrashFile = -1;

static void LBRecordException(NSException *e) {
    NSArray<NSString *> *stack = [e.callStackSymbols subarrayWithRange:NSMakeRange(0, MIN((NSUInteger)24, e.callStackSymbols.count))];
    NSString *line = [NSString stringWithFormat:@"%@ build %s, %@: %@\n%@", NSDate.date, LBBuild, e.name, e.reason,
                      [stack componentsJoinedByString:@"\n"]];
    [NSUserDefaults.standardUserDefaults setObject:line forKey:@"liquidbird_last_crash"];
    [NSUserDefaults.standardUserDefaults synchronize];
    if (LBPreviousExceptionHandler) LBPreviousExceptionHandler(e);
}

static struct sigaction LBPreviousSignal[32];

static void LBRecordSignal(int sig, siginfo_t *info, void *context) {
    if (LBCrashFile >= 0) {
        char head[96];
        int n = snprintf(head, sizeof head, "build %s, signal %d at %p\n", LBBuild, sig, info ? info->si_addr : NULL);
        if (n > 0) write(LBCrashFile, head, (size_t)n);
        void *frames[32];
        int count = backtrace(frames, 32);
        backtrace_symbols_fd(frames, count, LBCrashFile);
        fsync(LBCrashFile);
    }
    struct sigaction previous = LBPreviousSignal[sig];
    if (previous.sa_flags & SA_SIGINFO && previous.sa_sigaction) previous.sa_sigaction(sig, info, context);
    else if (previous.sa_handler && previous.sa_handler != SIG_IGN && previous.sa_handler != SIG_DFL) previous.sa_handler(sig);
    signal(sig, SIG_DFL);
    raise(sig);
}

static NSString *LBSignalLogPath(void) {
    return [NSTemporaryDirectory() stringByAppendingPathComponent:@"liquidbird-crash.txt"];
}

static void LBWatchCrashes(void) {
    // A signal last time left its stack in the file: kept as the last crash, and the file emptied.
    NSString *path = LBSignalLogPath();
    NSString *signalled = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    if (signalled.length) {
        NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
        [NSUserDefaults.standardUserDefaults setObject:[NSString stringWithFormat:@"%@ %@", attributes.fileModificationDate, signalled]
                                                forKey:@"liquidbird_last_crash"];
    }
    LBCrashFile = open(path.fileSystemRepresentation, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    LBPreviousExceptionHandler = NSGetUncaughtExceptionHandler();
    NSSetUncaughtExceptionHandler(LBRecordException);
    for (int sig = 1; sig < 32; sig++) {
        if (sig != SIGSEGV && sig != SIGBUS && sig != SIGILL && sig != SIGTRAP && sig != SIGFPE) continue;
        struct sigaction action = {0};
        action.sa_sigaction = LBRecordSignal;
        action.sa_flags = SA_SIGINFO | SA_ONSTACK;
        sigemptyset(&action.sa_mask);
        sigaction(sig, &action, &LBPreviousSignal[sig]);
    }
}

// MARK: - Jumps in the Home timeline

// For the layout copy: where the Home timeline moved without the finger asking. A jump of its scroll position, or a
// scroll something asked for, is logged with the code that asked (image+offset, which scripts/objc_find.py places in
// a method); posts that moved on screen with no scroll at all (a post above them changing height) are logged with how
// far. Offsets and sizes only, no post text.
@interface TFNTableView : UITableView
@end

// Whether a class descends from another, without messaging it (which would initialise X's class at load).
static BOOL LBDescends(Class c, Class base) {
    for (; c; c = class_getSuperclass(c)) if (c == base) return YES;
    return NO;
}

static NSString *LBCallers(NSUInteger skip, NSUInteger count) {
    NSArray<NSNumber *> *addresses = NSThread.callStackReturnAddresses;
    NSMutableArray *parts = [NSMutableArray array];
    for (NSUInteger i = skip; i < addresses.count && parts.count < count; i++) {
        Dl_info info;
        uintptr_t pc = (uintptr_t)addresses[i].unsignedLongValue;
        if (!dladdr((void *)pc, &info) || !info.dli_fname) continue;
        NSString *image = @(info.dli_fname).lastPathComponent;
        if ([image hasPrefix:@"libobjc"]) continue;
        [parts addObject:[NSString stringWithFormat:@"%@+0x%lx", image, (unsigned long)(pc - (uintptr_t)info.dli_fbase)]];
    }
    return [parts componentsJoinedByString:@" < "];
}

static BOOL LBIsHomeTimeline(UIScrollView *s) { return [s.accessibilityIdentifier isEqualToString:@"THFHomeTimelineItems Table"]; }
static NSString *LBFinger(UIScrollView *s) {
    return s.isTracking ? @" under the finger" : s.isDecelerating ? @" mid-fling" : @"";
}
static BOOL LBScrollAsked;   // inside setContentOffset:animated:, which logs it

// The topmost post on screen and where it was: if it moved by more than the scroll did, the posts jumped.
static void LBWatchTopPost(UITableView *table) {
    static __weak UITableViewCell *cell;
    static NSString *post;
    static CGFloat y, offset;
    CGFloat top = table.contentOffset.y + table.adjustedContentInset.top;
    UITableViewCell *first = nil;
    for (UITableViewCell *c in table.visibleCells)
        if (!c.hidden && CGRectGetMaxY(c.frame) > top) { first = c; break; }
    NSString *identifier = first.accessibilityIdentifier;
    if (first && first == cell && identifier && [identifier isEqualToString:post]) {
        CGFloat moved = (first.frame.origin.y - y) - (table.contentOffset.y - offset);
        if (fabs(moved) >= 80)
            LBLog(@"Home timeline: the posts on screen moved %.0f %@ with no scroll%@ (content %.0f)", fabs(moved),
                  moved > 0 ? @"down" : @"up", LBFinger(table), table.contentSize.height);
    }
    cell = first;
    post = identifier;
    y = first.frame.origin.y;
    offset = table.contentOffset.y;
}

%group TimelineJumps
%hook TFNTableView
- (void)setContentOffset:(CGPoint)target {
    CGFloat from = self.contentOffset.y;
    %orig;
    if (!LBScrollAsked && fabs(target.y - from) >= 200 && LBIsHomeTimeline(self))
        LBLog(@"Home timeline jumped %.0f -> %.0f%@ (content %.0f): %@", from, target.y, LBFinger(self), self.contentSize.height,
              LBCallers(1, 6));
}
- (void)setContentOffset:(CGPoint)target animated:(BOOL)animated {
    CGFloat from = self.contentOffset.y;
    if (fabs(target.y - from) >= 100 && LBIsHomeTimeline(self))
        LBLog(@"Home timeline scrolled%@ %.0f -> %.0f%@: %@", animated ? @" (animated)" : @"", from, target.y, LBFinger(self),
              LBCallers(1, 6));
    BOOL was = LBScrollAsked;
    LBScrollAsked = YES;
    %orig;
    LBScrollAsked = was;
}
- (void)layoutSubviews {
    %orig;
    if (LBIsHomeTimeline(self)) LBWatchTopPost(self);
}
%end
%end

%ctor {
    LBWatchCrashes();
    %init;
    if (LBDescends(objc_getClass("TFNTableView"), objc_getClass("UITableView"))) %init(TimelineJumps);
    if (objc_getClass("T1StatusViewTruncationTokenAreaTapEventHandler") && objc_getClass("T1StandardStatusInlineExpansionHelper"))
        %init(ShowMore);
}
