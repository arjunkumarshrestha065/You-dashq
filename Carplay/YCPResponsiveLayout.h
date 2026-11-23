#import <UIKit/UIKit.h>

// Pure geometry shared by native layout hooks and the resize regression suite.
BOOL YCPShouldUseWideWatch(CGSize size);
CGRect YCPFitMiniPlayer(CGRect requested, CGRect contentBounds, UIEdgeInsets safeInsets);

// Native content lays out in logical points, then fits the actual car viewport.
CGFloat YCPContentScaleForSize(CGSize viewport);
@interface YCPScaledContentView : UIView
@property(nonatomic, readonly) UIView *canvas;
@property(nonatomic, readonly) CGFloat contentScale;
@end
