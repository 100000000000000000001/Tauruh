#import "Core/SGCore.h"
#import "HeadGestures.h"

%ctor {
    if (SGFlag(SGKeyHeadGestures, NO)) SGSetHeadGesturesEnabled(YES);
}
