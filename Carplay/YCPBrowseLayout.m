#import "YCPNative.h"
#import <objc/message.h>

static id YCPBrowseProperty(id object, NSString *name) {
    SEL getter = NSSelectorFromString(name);
    return [object respondsToSelector:getter] ? ((id (*)(id, SEL))objc_msgSend)(object, getter) : nil;
}

static BOOL YCPExcludedGridContext(id object) {
    NSString *name = NSStringFromClass([object class]);
    for (NSString *word in @[@"Search", @"Watch", @"Playlist", @"Queue", @"Engagement", @"Player", @"Panel", @"Comment", @"Metadata", @"Metapanel"])
        if ([name containsString:word]) return YES;
    return NO;
}

static BOOL YCPRecognizedBrowseContext(id object) {
    NSString *name = NSStringFromClass([object class]);
    for (NSString *word in @[@"Home", @"Browse", @"Subscriptions", @"Trending"])
        if ([name containsString:word]) return YES;
    id browseID = YCPBrowseProperty(object, @"browseID");
    return [browseID isKindOfClass:NSString.class] && [browseID hasPrefix:@"FE"];
}

BOOL YCPShouldOverrideBrowseGrid(id candidate, UIWindow *car) {
    if (!candidate || !car) return NO;
    // Do not guess that an unidentifiable section is a Home card. Search
    // results use horizontal rows; watch metadata contains unrelated columns.
    NSMutableArray *pending = [NSMutableArray arrayWithObject:candidate];
    NSHashTable *seen = [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
    BOOL recognized = NO, belongsToCar = NO;
    NSUInteger inspected = 0;
    while (pending.count && inspected++ < 64) {
        id object = pending.lastObject; [pending removeLastObject];
        if ([seen containsObject:object]) continue;
        [seen addObject:object];
        if (YCPExcludedGridContext(object)) return NO;
        recognized |= YCPRecognizedBrowseContext(object);
        if ([object isKindOfClass:UIView.class]) {
            UIView *view = object;
            if (view.window && view.window != car) return NO;
            belongsToCar |= view.window == car;
            if (view.nextResponder) [pending addObject:view.nextResponder];
        } else if ([object isKindOfClass:UIViewController.class]) {
            UIViewController *controller = object;
            if (controller.viewIfLoaded) [pending addObject:controller.viewIfLoaded];
            if (controller.parentViewController) [pending addObject:controller.parentViewController];
        } else if ([object isKindOfClass:UICollectionViewLayout.class]) {
            UICollectionView *collection = ((UICollectionViewLayout *)object).collectionView;
            if (collection) [pending addObject:collection];
        }
        for (NSString *property in @[@"model", @"feedController", @"viewController", @"collectionViewController", @"parentResponder"]) {
            id value = YCPBrowseProperty(object, property);
            if (value && value != object) [pending addObject:value];
        }
    }
    return recognized && belongsToCar;
}
