#import "YCPNative.h"
#import "YCPResponsiveLayout.h"
#import <objc/message.h>
#import <objc/runtime.h>

static const void *YCPWatchOriginalsKey = &YCPWatchOriginalsKey;

static IMP YCPWatchOriginal(id object, SEL selector) {
    for (Class cls = object_getClass(object); cls; cls = class_getSuperclass(cls)) {
        NSDictionary *methods = objc_getAssociatedObject(cls, YCPWatchOriginalsKey);
        NSValue *value = methods[NSStringFromSelector(selector)];
        if (value) return value.pointerValue;
    }
    return NULL;
}

// Native fullscreen transitions briefly detach the watch hierarchy. Remember
// its display without retaining the window, so a nil view.window cannot make
// the exit animation switch back to phone geometry. A different attached
// window or a disconnected car immediately stops the override.
@interface YCPWatchDisplayReference : NSObject
@property(nonatomic, weak) UIWindow *window;
@end
@implementation YCPWatchDisplayReference
@end

static const void *YCPWatchDisplayKey = &YCPWatchDisplayKey;
static BOOL YCPWatchViewBelongsToCar(UIView *view) {
    UIWindow *car = YCPSurface.shared.activeWindow;
    if (!car || !view) return NO;
    YCPWatchDisplayReference *reference = objc_getAssociatedObject(view, YCPWatchDisplayKey);
    if (view.window == car) {
        if (!reference) {
            reference = [YCPWatchDisplayReference new];
            objc_setAssociatedObject(view, YCPWatchDisplayKey, reference, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        reference.window = car;
        return YES;
    }
    if (view.window) {
        reference.window = nil;
        return NO;
    }
    return reference.window == car;
}

static BOOL YCPCarWideWatchView(UIView *view) {
    UIWindow *car = YCPSurface.shared.activeWindow;
    return car && YCPWatchViewBelongsToCar(view) && YCPShouldUseWideWatch(YCPSurface.shared.contentBounds.size);
}

static UIView *YCPWatchLayer(id object) {
    SEL getter = NSSelectorFromString(@"watchLayerView");
    id view = [object respondsToSelector:getter] ? ((id (*)(id, SEL))objc_msgSend)(object, getter) : nil;
    return [view isKindOfClass:UIView.class] ? view : nil;
}

static BOOL YCPResolvingFullscreenWindow;

static UIWindow *YCPFullscreenMainWindow(id object, SEL selector) {
    UIWindow *car = YCPSurface.shared.activeWindow;
    if (YCPResolvingFullscreenWindow && car) return car;
    IMP original = YCPWatchOriginal(object, selector);
    return ((id (*)(id, SEL))original)(object, selector);
}

static BOOL YCPWatchFullscreenAllowed(UIViewController *controller, SEL selector) {
    IMP original = YCPWatchOriginal(controller, selector);
    UIWindow *car = YCPSurface.shared.activeWindow;
    BOOL previous = YCPResolvingFullscreenWindow;
    // Preserve every native transition predicate. Only its global-window lookup
    // should resolve to the display actually containing the watch interface.
    YCPResolvingFullscreenWindow = NSThread.isMainThread && car && YCPWatchViewBelongsToCar(controller.viewIfLoaded);
    if (YCPResolvingFullscreenWindow) YCPWatchViewBelongsToCar(YCPWatchLayer(controller));
    @try {
        return ((BOOL (*)(id, SEL))original)(controller, selector);
    } @finally {
        YCPResolvingFullscreenWindow = previous;
    }
}

static BOOL YCPWatchFullscreenGeometry(UIViewController *controller, SEL selector, NSInteger behavior) {
    if (YCPWatchViewBelongsToCar(controller.viewIfLoaded))
        return NO; // External display fullscreen is not a phone rotation request.
    IMP original = YCPWatchOriginal(controller, selector);
    return ((BOOL (*)(id, SEL, NSInteger))original)(controller, selector, behavior);
}

static BOOL YCPWatchLayoutFlag(id object, SEL selector) {
    UIView *view = YCPWatchLayer(object);
    UIWindow *car = YCPSurface.shared.activeWindow;
    if (car && YCPWatchViewBelongsToCar(view)) {
        CGSize size = YCPSurface.shared.contentBounds.size;
        if (selector == NSSelectorFromString(@"isLargeWideLayout")) return YCPShouldUseWideWatch(size);
        if (selector == NSSelectorFromString(@"isLandscape")) return size.width > size.height;
        return size.width >= 600;
    }
    IMP original = YCPWatchOriginal(object, selector);
    return original ? ((BOOL (*)(id, SEL))original)(object, selector) : NO;
}

static NSInteger YCPWatchOrientation(id object, SEL selector) {
    UIView *view = YCPWatchLayer(object);
    if (YCPWatchViewBelongsToCar(view)) {
        CGSize size = YCPSurface.shared.contentBounds.size;
        return size.width > size.height ? UIInterfaceOrientationLandscapeLeft : UIInterfaceOrientationPortrait;
    }
    IMP original = YCPWatchOriginal(object, selector);
    return original ? ((NSInteger (*)(id, SEL))original)(object, selector) : UIInterfaceOrientationUnknown;
}

static BOOL YCPWideWatchDelegate(id object, SEL selector, UIView *watch) {
    if (YCPWatchViewBelongsToCar(watch)) return YCPShouldUseWideWatch(YCPSurface.shared.contentBounds.size);
    IMP original = YCPWatchOriginal(object, selector);
    return original ? ((BOOL (*)(id, SEL, id))original)(object, selector, watch) : NO;
}

static CGFloat YCPWatchTopInset(id object, SEL selector) {
    UIView *view = [object isKindOfClass:UIViewController.class] ? ((UIViewController *)object).viewIfLoaded : nil;
    if (YCPCarWideWatchView(view)) return YCPSurface.shared.activeWindow.safeAreaInsets.top;
    IMP original = YCPWatchOriginal(object, selector);
    return original ? ((CGFloat (*)(id, SEL))original)(object, selector) : 0;
}

static UIEdgeInsets YCPNativeWindowInsets(UIView *view, SEL selector) {
    IMP original = YCPWatchOriginal(view, selector);
    UIEdgeInsets insets = original ? ((UIEdgeInsets (*)(id, SEL))original)(view, selector) : UIEdgeInsetsZero;
    UIWindow *car = YCPSurface.shared.activeWindow;
    // YouTube's category can use the phone window's cached status-bar height,
    // independently of the watch controller's statusBarHeight property.
    if (car && view.window == car) insets.top = car.safeAreaInsets.top;
    return insets;
}

static CGRect YCPMiniPlayerFrame(id object, SEL selector) {
    IMP original = YCPWatchOriginal(object, selector);
    CGRect frame = original ? ((CGRect (*)(id, SEL))original)(object, selector) : CGRectZero;
    if (!YCPSurface.shared.activeWindow) return frame;
    return YCPFitMiniPlayer(frame, YCPSurface.shared.contentBounds, YCPSurface.shared.miniPlayerSafeInsets);
}

// Keep the first below-player cell clear of the player's scrubber/clipping edge.
// Use the actual collection viewport, not phone dimensions or a scroll reset.
static UIEdgeInsets YCPWatchSectionInsets(UIViewController *controller, SEL selector, UICollectionView *collection, UICollectionViewLayout *layout, NSInteger section) {
    IMP original = YCPWatchOriginal(controller, selector);
    UIEdgeInsets insets = original ? ((UIEdgeInsets (*)(id, SEL, id, id, NSInteger))original)(controller, selector, collection, layout, section) : UIEdgeInsetsZero;
    UIWindow *car = YCPSurface.shared.activeWindow;
    if (section != 0 || !YCPCarWideWatchView(controller.viewIfLoaded) || collection.window != car) return insets;
    CGRect viewport = [collection convertRect:collection.bounds toView:car];
    // The metadata column is below the player, on the leading side. The queue
    // starts at the top on the trailing side and must retain its native insets.
    if (CGRectGetMinY(viewport) > car.safeAreaInsets.top + 44
        && CGRectGetMinX(viewport) < CGRectGetMidX(car.bounds)
        && CGRectGetWidth(viewport) < CGRectGetWidth(car.bounds) * 0.8)
        insets.top = MAX(12, insets.top);
    return insets;
}

static BOOL YCPSplitMetadataFix(id object, SEL selector) {
    if (YCPSurface.shared.activeWindow) return YES;
    IMP original = YCPWatchOriginal(object, selector);
    return original ? ((BOOL (*)(id, SEL))original)(object, selector) : NO;
}

static const void *YCPSeekThumbTransformKey = &YCPSeekThumbTransformKey;

static BOOL YCPSeekbarInCar(UIView *view) {
    UIWindow *car = YCPSurface.shared.activeWindow;
    return car && view.window == car;
}

static CGFloat YCPSeekbarScale(UIView *view) {
    CGPoint start = [view convertPoint:CGPointZero toView:view.window];
    CGPoint end = [view convertPoint:CGPointMake(0, 1) toView:view.window];
    CGFloat scale = hypot(end.x - start.x, end.y - start.y);
    return isfinite(scale) && scale > 0.01 ? scale : 1;
}

static CGRect YCPSeekbarFrame(UIView *view, SEL selector) {
    IMP original = YCPWatchOriginal(view, selector);
    CGRect frame = ((CGRect (*)(id, SEL))original)(view, selector);
    if (!YCPSeekbarInCar(view) || CGRectIsEmpty(frame)) return frame;
    CGFloat height = MAX(frame.size.height, 6.0 / YCPSeekbarScale(view));
    frame.origin.y = CGRectGetMidY(frame) - height * 0.5;
    frame.size.height = height;
    return frame;
}

static BOOL YCPSeekbarPointInside(UIView *view, SEL selector, CGPoint point, UIEvent *event) {
    IMP original = YCPWatchOriginal(view, selector);
    if (((BOOL (*)(id, SEL, CGPoint, id))original)(view, selector, point, event)) return YES;
    if (!YCPSeekbarInCar(view) || view.hidden || view.alpha < 0.01 || !view.userInteractionEnabled) return NO;
    CGFloat extra = MAX(0, (44.0 / YCPSeekbarScale(view) - view.bounds.size.height) * 0.5);
    return CGRectContainsPoint(CGRectInset(view.bounds, 0, -extra), point);
}

static void YCPSeekThumbLayout(UIView *view, SEL selector) {
    IMP original = YCPWatchOriginal(view, selector);
    ((void (*)(id, SEL))original)(view, selector);
    NSValue *saved = objc_getAssociatedObject(view, YCPSeekThumbTransformKey);
    if (!YCPSeekbarInCar(view)) {
        if (saved) {
            view.transform = saved.CGAffineTransformValue;
            objc_setAssociatedObject(view, YCPSeekThumbTransformKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        return;
    }
    if (!saved) {
        saved = [NSValue valueWithCGAffineTransform:view.transform];
        objc_setAssociatedObject(view, YCPSeekThumbTransformKey, saved, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    // Measure ancestors, excluding our own transform, so repeated layouts do
    // not alternate between enlarged and normal sizes.
    CGFloat scale = view.superview ? YCPSeekbarScale(view.superview) : 1;
    CGFloat diameter = MAX(view.bounds.size.width, view.bounds.size.height);
    if (diameter <= 0) return;
    CGFloat growth = MAX(1.35, 14.0 / (diameter * scale));
    CGAffineTransform transform = CGAffineTransformScale(saved.CGAffineTransformValue, growth, growth);
    if (!CGAffineTransformEqualToTransform(view.transform, transform)) view.transform = transform;
}

static void YCPPatchWatch(Class cls, SEL selector, IMP replacement) {
    Method method = class_getInstanceMethod(cls, selector);
    if (!method || method_getImplementation(method) == replacement) return;
    NSMutableDictionary *methods = [objc_getAssociatedObject(cls, YCPWatchOriginalsKey) mutableCopy] ?: [NSMutableDictionary new];
    methods[NSStringFromSelector(selector)] = [NSValue valueWithPointer:method_getImplementation(method)];
    objc_setAssociatedObject(cls, YCPWatchOriginalsKey, methods, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!class_addMethod(cls, selector, replacement, method_getTypeEncoding(method)))
        class_replaceMethod(cls, selector, replacement, method_getTypeEncoding(method));
}

void YCPInstallWatchLayoutHooks(void) {
    Class bar = NSClassFromString(@"YTModularPlayerBarView");
    if (bar) YCPPatchWatch(bar, NSSelectorFromString(@"barFrame"), (IMP)YCPSeekbarFrame);
    for (NSString *name in @[@"YTInlineScrubGestureView", @"YTInlinePlayerBarContainerView"]) {
        Class gesture = NSClassFromString(name);
        if (gesture) YCPPatchWatch(gesture, @selector(pointInside:withEvent:), (IMP)YCPSeekbarPointInside);
    }
    Class thumb = NSClassFromString(@"YTPlayerBarScrubberDotView");
    if (thumb) YCPPatchWatch(thumb, @selector(layoutSubviews), (IMP)YCPSeekThumbLayout);
    YCPPatchWatch(UIView.class, NSSelectorFromString(@"yt_safeAreaInsetsForWindow"), (IMP)YCPNativeWindowInsets);
    YCPPatchWatch(UIView.class, NSSelectorFromString(@"yt_safeAreaInsetsForBrowse"), (IMP)YCPNativeWindowInsets);
    // 21.42.4 implements this ObjC protocol in a Swift class with a mangled name.
    // Discover that implementation instead of depending on the Swift module name.
    Protocol *protocol = objc_getProtocol("YTWatchLayoutController");
    unsigned int count = 0;
    Class *classes = objc_copyClassList(&count);
    for (unsigned int index = 0; index < count; index++) {
        Class cls = classes[index];
        // Enable the native fix for metadata measured in a split watch column.
        SEL metadataFix = NSSelectorFromString(@"enableIosSplitMetadataViewFix");
        if (class_getInstanceMethod(cls, metadataFix))
            YCPPatchWatch(cls, metadataFix, (IMP)YCPSplitMetadataFix);
        if (!protocol || !class_conformsToProtocol(cls, protocol)
            || !class_getInstanceMethod(cls, NSSelectorFromString(@"watchLayerView"))) continue;
        for (NSString *name in @[@"isLargeLayout", @"isLargeWideLayout", @"isLandscape"])
            YCPPatchWatch(cls, NSSelectorFromString(name), (IMP)YCPWatchLayoutFlag);
        YCPPatchWatch(cls, NSSelectorFromString(@"interfaceOrientation"), (IMP)YCPWatchOrientation);
    }
    free(classes);
    Class results = NSClassFromString(@"YTWatchNextResultsViewController");
    if (results) YCPPatchWatch(results, NSSelectorFromString(@"collectionView:layout:insetForSectionAtIndex:"), (IMP)YCPWatchSectionInsets);
    Class mini = NSClassFromString(@"YTWatchMiniplayerLayoutOutput");
    if (mini) YCPPatchWatch(mini, NSSelectorFromString(@"miniplayerFrame"), (IMP)YCPMiniPlayerFrame);
    Class windows = NSClassFromString(@"YTMainWindowUtils");
    if (windows) YCPPatchWatch(object_getClass(windows), NSSelectorFromString(@"mainWindow"), (IMP)YCPFullscreenMainWindow);
    Class layer = NSClassFromString(@"YTWatchLayerViewController");
    if (layer) {
        YCPPatchWatch(layer, NSSelectorFromString(@"canPresentFullScreen"), (IMP)YCPWatchFullscreenAllowed);
        YCPPatchWatch(layer, NSSelectorFromString(@"canDismissFullScreen"), (IMP)YCPWatchFullscreenAllowed);
        YCPPatchWatch(layer, NSSelectorFromString(@"shouldRequestGeometryUpdateForFullscreenButtonBehavior:"), (IMP)YCPWatchFullscreenGeometry);
        YCPPatchWatch(layer, NSSelectorFromString(@"statusBarHeight"), (IMP)YCPWatchTopInset);
        YCPPatchWatch(layer, NSSelectorFromString(@"headerHeight"), (IMP)YCPWatchTopInset);
    }
    Class watch = NSClassFromString(@"YTWatchViewController");
    if (watch) YCPPatchWatch(watch, NSSelectorFromString(@"isWideLayoutForWatchView:"), (IMP)YCPWideWatchDelegate);
}
