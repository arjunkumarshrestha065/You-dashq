#import "YCPResponsiveLayout.h"

BOOL YCPShouldUseWideWatch(CGSize size) {
    // Leave room for a readable video/details column and a 260-point queue.
    return size.width >= 820 && size.height >= 300 && size.width > size.height;
}

CGRect YCPFitMiniPlayer(CGRect requested, CGRect contentBounds, UIEdgeInsets safeInsets) {
    CGRect safe = UIEdgeInsetsInsetRect(contentBounds, safeInsets);
    safe = CGRectInset(safe, 12, 12);
    if (safe.size.width <= 0 || safe.size.height <= 0 || CGRectIsEmpty(requested)) return requested;
    CGFloat width = MIN(320, MAX(180, safe.size.width * 0.30));
    // A 16:9 floating video, with enough surface for the native 44-point controls.
    width = MIN(width, MIN(safe.size.width, safe.size.height * 16.0 / 9.0));
    CGFloat height = width * 9.0 / 16.0;
    CGFloat x = MIN(MAX(requested.origin.x, CGRectGetMinX(safe)), CGRectGetMaxX(safe) - width);
    CGFloat y = MIN(MAX(requested.origin.y, CGRectGetMinY(safe)), CGRectGetMaxY(safe) - height);
    return CGRectMake(x, y, width, height);
}

CGFloat YCPContentScaleForSize(CGSize viewport) {
    if (viewport.width <= 0 || viewport.height <= 0) return 1;
    // Do not clamp to 0.5: small cars can have fewer than 410 usable points
    // after the system sidebar, which otherwise leaves the canvas below the
    // native wide-watch breakpoint and forces the phone's stacked player.
    return MIN(1, MIN(viewport.width / 1024.0, viewport.height / 600.0));
}

@implementation YCPScaledContentView
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _canvas = [UIView new];
        _canvas.backgroundColor = [UIColor colorWithWhite:15.0 / 255.0 alpha:1];
        [self addSubview:_canvas];
        self.clipsToBounds = YES;
    }
    return self;
}
- (CGFloat)contentScale { return YCPContentScaleForSize(self.bounds.size); }
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat scale = self.contentScale;
    CGRect bounds = CGRectMake(0, 0, self.bounds.size.width / scale, self.bounds.size.height / scale);
    CGPoint center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
    CGAffineTransform transform = CGAffineTransformMakeScale(scale, scale);
    if (!CGRectEqualToRect(self.canvas.bounds, bounds)) self.canvas.bounds = bounds;
    if (!CGPointEqualToPoint(self.canvas.center, center)) self.canvas.center = center;
    if (!CGAffineTransformEqualToTransform(self.canvas.transform, transform)) self.canvas.transform = transform;
}
@end
