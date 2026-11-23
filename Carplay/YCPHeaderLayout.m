#import "YCPNative.h"
#import <objc/runtime.h>
#import <objc/message.h>

static IMP YCPHeaderOriginalMove, YCPHeaderOriginalScroll, YCPHeaderOriginalSticky;
static IMP YCPHeaderOriginalBackground, YCPHeaderOriginalTint, YCPHeaderSuperTint;
static const void *YCPHeaderDesiredScroll = &YCPHeaderDesiredScroll;
static const void *YCPHeaderDesiredSticky = &YCPHeaderDesiredSticky;

static BOOL YCPScrollingHeaderInCar(UIView *header) {
    UIWindow *car = YCPSurface.shared.activeWindow;
    if (!car || header.window != car) return NO;
    for (UIResponder *responder = header; responder; responder = responder.nextResponder) {
        NSString *name = NSStringFromClass(responder.class);
        for (NSString *excluded in @[@"Search", @"Watch", @"Player", @"Engagement"])
            if ([name containsString:excluded]) return NO;
    }
    return YES;
}

static const void *YCPHeaderApplyingColorKey = &YCPHeaderApplyingColorKey;
static void YCPApplyHeaderColor(UIView *header) {
    if (!YCPScrollingHeaderInCar(header) || !YCPHeaderSuperTint || objc_getAssociatedObject(header, YCPHeaderApplyingColorKey)) return;
    objc_setAssociatedObject(header, YCPHeaderApplyingColorKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIColor *color = [UIColor colorWithWhite:15.0 / 255.0 alpha:1];
    // YouTube's override can clear the tint for translucent styles. Use the
    // navigation bar's own setter after that override, without recoloring icons.
    ((void (*)(id, SEL, id))YCPHeaderSuperTint)(header, NSSelectorFromString(@"setBarTintColor:"), color);
    header.backgroundColor = color;
    objc_setAssociatedObject(header, YCPHeaderApplyingColorKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static void YCPHeaderBackground(UIView *header, SEL selector) {
    ((void (*)(id, SEL))YCPHeaderOriginalBackground)(header, selector);
    YCPApplyHeaderColor(header);
}
static void YCPHeaderTint(UIView *header, SEL selector, UIColor *color) {
    ((void (*)(id, SEL, id))YCPHeaderOriginalTint)(header, selector, color);
    YCPApplyHeaderColor(header);
}

static NSHashTable<UIView *> *YCPObservedHeaders;
static const void *YCPHeaderObservationKey = &YCPHeaderObservationKey;
static void *YCPHeaderOffsetContext = &YCPHeaderOffsetContext;

@interface YCPHeaderScrollObservation : NSObject
@property(nonatomic, weak) UIView *header;
@property(nonatomic, weak) UIScrollView *scroll;
@property(nonatomic) BOOL updating;
@end
@implementation YCPHeaderScrollObservation
- (void)dealloc {
    if (self.scroll) [self.scroll removeObserver:self forKeyPath:@"contentOffset" context:YCPHeaderOffsetContext];
}
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context != YCPHeaderOffsetContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    UIView *header = self.header;
    UIScrollView *scroll = self.scroll;
    if (self.updating || !YCPScrollingHeaderInCar(header) || scroll.window != header.window) return;
    CGFloat top = -scroll.adjustedContentInset.top;
    CGFloat bottom = MAX(top, scroll.contentSize.height - scroll.bounds.size.height + scroll.adjustedContentInset.bottom);
    CGPoint old = [change[NSKeyValueChangeOldKey] CGPointValue];
    CGPoint current = [change[NSKeyValueChangeNewKey] CGPointValue];
    CGFloat delta = MIN(bottom, MAX(top, current.y)) - MIN(bottom, MAX(top, old.y));
    if (current.y <= top + 1) delta = -1000; // Always reveal at the top, including scroll-to-top.
    if (fabs(delta) < 0.25 || !isfinite(delta)) return;
    SEL move = NSSelectorFromString(@"scrollNavHeaderViewWithOffset:");
    if (![header respondsToSelector:move]) return;
    self.updating = YES;
    ((void (*)(id, SEL, CGFloat))objc_msgSend)(header, move, delta);
    [header.superview setNeedsLayout];
    self.updating = NO;
}
@end

static UIView *YCPHeaderComboContainer(UIView *header) {
    for (UIView *parent = header.superview; parent; parent = parent.superview)
        if ([NSStringFromClass(parent.class) containsString:@"HeaderContentComboView"]) return parent;
    return header.superview;
}

void YCPRefreshHeaderScrollObservers(void) {
    for (UIView *header in YCPObservedHeaders.allObjects) {
        if (!YCPScrollingHeaderInCar(header)) {
            objc_setAssociatedObject(header, YCPHeaderObservationKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            continue;
        }
        UIView *container = YCPHeaderComboContainer(header);
        YCPHeaderScrollObservation *existing = objc_getAssociatedObject(header, YCPHeaderObservationKey);
        if (existing.scroll.window == header.window && [existing.scroll isDescendantOfView:container]) continue;
        UIScrollView *best = nil;
        CGFloat largest = 0;
        NSMutableArray *pending = [NSMutableArray arrayWithArray:container.subviews ?: @[]];
        while (pending.count) {
            UIView *view = pending.lastObject; [pending removeLastObject];
            if (view == header) continue;
            if ([view isKindOfClass:UIScrollView.class]) {
                UIScrollView *scroll = (id)view;
                BOOL vertical = scroll.alwaysBounceVertical || scroll.contentSize.height > scroll.bounds.size.height + 1;
                CGFloat area = scroll.bounds.size.width * scroll.bounds.size.height;
                if (vertical && scroll.bounds.size.height >= 120 && scroll.bounds.size.width >= container.bounds.size.width * 0.65 && area > largest) {
                    best = scroll; largest = area;
                }
            }
            [pending addObjectsFromArray:view.subviews];
        }
        if (!best) continue;
        YCPHeaderScrollObservation *observer = [YCPHeaderScrollObservation new];
        observer.header = header; observer.scroll = best;
        [best addObserver:observer forKeyPath:@"contentOffset" options:NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew context:YCPHeaderOffsetContext];
        objc_setAssociatedObject(header, YCPHeaderObservationKey, observer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void YCPHeaderScrollEnabled(UIView *header, SEL selector, BOOL enabled) {
    objc_setAssociatedObject(header, YCPHeaderDesiredScroll, @(enabled), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    ((void (*)(id, SEL, BOOL))YCPHeaderOriginalScroll)(header, selector, YCPScrollingHeaderInCar(header) ? YES : enabled);
}
static void YCPHeaderStickyEnabled(UIView *header, SEL selector, BOOL enabled) {
    objc_setAssociatedObject(header, YCPHeaderDesiredSticky, @(enabled), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    ((void (*)(id, SEL, BOOL))YCPHeaderOriginalSticky)(header, selector, YCPScrollingHeaderInCar(header) ? NO : enabled);
}
static void YCPHeaderMovedToWindow(UIView *header, SEL selector) {
    ((void (*)(id, SEL))YCPHeaderOriginalMove)(header, selector);
    BOOL car = YCPScrollingHeaderInCar(header);
    NSNumber *scroll = objc_getAssociatedObject(header, YCPHeaderDesiredScroll);
    NSNumber *sticky = objc_getAssociatedObject(header, YCPHeaderDesiredSticky);
    // Keep native controls, geometry and resize animations; retain the app's scroll delegate.
    if (car || scroll) ((void (*)(id, SEL, BOOL))YCPHeaderOriginalScroll)(header, NSSelectorFromString(@"setHeaderScrollEnabled:"), car ? YES : scroll.boolValue);
    if (car || sticky) ((void (*)(id, SEL, BOOL))YCPHeaderOriginalSticky)(header, NSSelectorFromString(@"setStickyNavHeaderEnabled:"), car ? NO : sticky.boolValue);
    if (!YCPObservedHeaders) YCPObservedHeaders = [NSHashTable weakObjectsHashTable];
    [YCPObservedHeaders addObject:header];
    SEL reset = NSSelectorFromString(@"resetHeaderParamsForStatusBarUpdate");
    if ([header respondsToSelector:reset]) ((void (*)(id, SEL))objc_msgSend)(header, reset);
    SEL background = NSSelectorFromString(@"updateBackgroundColor");
    if ([header respondsToSelector:background]) ((void (*)(id, SEL))objc_msgSend)(header, background);
    YCPRefreshHeaderScrollObservers();
}
static IMP YCPHeaderReplace(Class cls, SEL selector, IMP replacement) {
    Method method = class_getInstanceMethod(cls, selector);
    if (!method) return NULL;
    IMP original = method_getImplementation(method);
    if (!class_addMethod(cls, selector, replacement, method_getTypeEncoding(method)))
        class_replaceMethod(cls, selector, replacement, method_getTypeEncoding(method));
    return original;
}
void YCPInstallHeaderLayoutHooks(void) {
    if (YCPHeaderOriginalMove) return;
    Class header = NSClassFromString(@"YTHeaderView");
    if (!header || !class_getInstanceMethod(header, NSSelectorFromString(@"setHeaderScrollEnabled:"))
        || !class_getInstanceMethod(header, NSSelectorFromString(@"setStickyNavHeaderEnabled:"))) return;
    SEL tint = NSSelectorFromString(@"setBarTintColor:");
    Method superTint = class_getInstanceMethod(class_getSuperclass(header), tint);
    if (superTint && class_getInstanceMethod(header, NSSelectorFromString(@"updateBackgroundColor"))) {
        YCPHeaderSuperTint = method_getImplementation(superTint);
        YCPHeaderOriginalTint = YCPHeaderReplace(header, tint, (IMP)YCPHeaderTint);
        YCPHeaderOriginalBackground = YCPHeaderReplace(header, NSSelectorFromString(@"updateBackgroundColor"), (IMP)YCPHeaderBackground);
    }
    YCPHeaderOriginalScroll = YCPHeaderReplace(header, NSSelectorFromString(@"setHeaderScrollEnabled:"), (IMP)YCPHeaderScrollEnabled);
    YCPHeaderOriginalSticky = YCPHeaderReplace(header, NSSelectorFromString(@"setStickyNavHeaderEnabled:"), (IMP)YCPHeaderStickyEnabled);
    YCPHeaderOriginalMove = YCPHeaderReplace(header, @selector(didMoveToWindow), (IMP)YCPHeaderMovedToWindow);
}
