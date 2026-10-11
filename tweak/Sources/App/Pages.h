#import <UIKit/UIKit.h>

@class SGModSection;

// Redesigned UI, the one switch between the two looks, and what its ⓘ reads out.
void SGSetRedesignedUI(BOOL on);
extern NSString *const SGRedesignedUIInfo;

SGModSection *SGAppearanceSection(void);   // the Appearance card at the top of Mod Settings
UIViewController *SGPlayerSettingsPage(void);
UIViewController *SGLyricsSettingsPage(void);  // its sources in either look, and the redesign's display
UIViewController *SGNavbarPage(void);       // the tab editor of whichever look is stored
