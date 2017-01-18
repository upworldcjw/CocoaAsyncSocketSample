#import <UIKit/UIKit.h>
#import "GCDAsyncSocket.h"
@class IPhoneConnectTestViewController;
@class GCDAsyncSocket;


@interface IPhoneConnectTestAppDelegate : NSObject <UIApplicationDelegate,GCDAsyncSocketDelegate>
{
	GCDAsyncSocket *asyncSocket;
	
	UIWindow *window;
	IPhoneConnectTestViewController *viewController;
}
@property (nonatomic, strong) NSMutableData *cacheData;
@property (nonatomic, retain) IBOutlet UIWindow *window;
@property (nonatomic, retain) IBOutlet IPhoneConnectTestViewController *viewController;

@end

