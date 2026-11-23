#import <UIKit/UIKit.h>
#import <CarPlay/CarPlay.h>

NS_ASSUME_NONNULL_BEGIN
void YCPLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
BOOL YCPIsCarRole(UISceneSessionRole role);
void YCPInstallWatchLayoutHooks(void);
void YCPInstallHeaderLayoutHooks(void);
void YCPRefreshHeaderScrollObservers(void);
BOOL YCPShouldOverrideBrowseGrid(id candidate, UIWindow * _Nullable car);
void YCPBootstrapNativeScene(UIWindowScene *scene, UISceneSession *session, UISceneConnectionOptions *options);

@interface YCPSurface : NSObject
+ (instancetype)shared;
@property(nonatomic, readonly, nullable) UIWindow *activeWindow;
@property(nonatomic, readonly) CGRect contentBounds;
@property(nonatomic, readonly) UIEdgeInsets miniPlayerSafeInsets;
- (void)connectTemplate:(CPInterfaceController *)controller window:(nullable CPWindow *)window;
- (void)disconnectTemplate;
- (void)connectWindow:(UIWindow *)window;
- (void)disconnectWindow:(UIWindow *)window;
- (void)reconcile;
- (void)textInputBecameActive:(UIView *)view;
- (BOOL)ownsNativeController:(UIViewController *)controller;
- (void)sourceWindowMovedToPhone:(UIWindow *)window;
@end

@interface YCPTemplateDelegate : UIResponder <CPTemplateApplicationSceneDelegate>
@end
@interface YCPWindowDelegate : UIResponder <UIWindowSceneDelegate>
@property(nonatomic, strong, nullable) UIWindow *window;
@end
NS_ASSUME_NONNULL_END
