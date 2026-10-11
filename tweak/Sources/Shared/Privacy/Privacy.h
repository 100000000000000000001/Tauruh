#import <UIKit/UIKit.h>

#define SGKeyBlockTelemetry @"spotifyglass.blockTelemetry"

NSArray<NSString *> *SGBlockedLabels(void);
NSUInteger SGBlockedCount(NSString *label);
void SGResetBlocked(void);

@class SGModSection;
// The telemetry switch and what it has stopped, on the Premium, ads & privacy page.
SGModSection *SGPrivacySection(void);
SGModSection *SGPrivacyCountersSection(void);
