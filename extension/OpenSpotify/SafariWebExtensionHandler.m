#import <Foundation/Foundation.h>
#import <SafariServices/SafariServices.h>

// All routing stays in the web extension. No native messaging or network access is needed.
@interface TaurusSafariWebExtensionHandler : NSObject <NSExtensionRequestHandling>
@end
@implementation TaurusSafariWebExtensionHandler
- (void)beginRequestWithExtensionContext:(NSExtensionContext *)context {
    [context completeRequestReturningItems:@[] completionHandler:nil];
}
@end
