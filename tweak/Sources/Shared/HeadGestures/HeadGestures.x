// Starts the AirPods gesture engine at launch when its switch is on. The switch itself starts and
// stops the listening live from the settings page; nothing here runs at launch for anyone who has
// never turned it on.
#import "Core/SGCore.h"
#import "HeadGestures.h"

%ctor {
    if (SGFlag(SGKeyHeadGestures, NO)) SGSetHeadGesturesEnabled(YES);
}
