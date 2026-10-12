#pragma once
#include <math.h>

#define SGSingMinimumVocalLevel 0.2f
static inline float SGSingClampLevel(float value) {
    return isfinite(value) ? fmaxf(SGSingMinimumVocalLevel, fminf(1, value)) : 1;
}
static inline float SGSingLevelFromPosition(float position) {
    return SGSingMinimumVocalLevel + (1 - SGSingMinimumVocalLevel) * fmaxf(0, fminf(1, position));
}
static inline float SGSingPositionFromLevel(float level) {
    return (SGSingClampLevel(level) - SGSingMinimumVocalLevel) / (1 - SGSingMinimumVocalLevel);
}
