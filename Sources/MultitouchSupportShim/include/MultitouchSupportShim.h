#ifndef MULTITOUCH_SUPPORT_SHIM_H
#define MULTITOUCH_SUPPORT_SHIM_H

#include <CoreFoundation/CoreFoundation.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef const void *MTDeviceRef;

typedef struct {
    float x;
    float y;
} MTPoint;

typedef struct {
    MTPoint position;
    MTPoint velocity;
} MTVector;

typedef uint32_t MTTouchState;
enum {
    MTTouchStateNotTracking = 0,
    MTTouchStateStartInRange = 1,
    MTTouchStateHoverInRange = 2,
    MTTouchStateMakeTouch = 3,
    MTTouchStateTouching = 4,
    MTTouchStateBreakTouch = 5,
    MTTouchStateLingerInRange = 6,
    MTTouchStateOutOfRange = 7,
};

typedef struct {
    int32_t frame;
    double timestamp;
    int32_t pathIndex;
    MTTouchState state;
    int32_t fingerID;
    int32_t handID;
    MTVector normalizedVector;
    float zTotal;
    int32_t field9;
    float angle;
    float majorAxis;
    float minorAxis;
    MTVector absoluteVector;
    int32_t field14;
    int32_t field15;
    float zDensity;
} MTTouch;

typedef void (*MTFrameCallbackFunction)(
    MTDeviceRef device,
    MTTouch touches[],
    size_t numTouches,
    double timestamp,
    size_t frame
);

CFArrayRef MTDeviceCreateList(void);
void MTRegisterContactFrameCallback(MTDeviceRef device, MTFrameCallbackFunction callback);
void MTUnregisterContactFrameCallback(MTDeviceRef device, MTFrameCallbackFunction callback);
int32_t MTDeviceStart(MTDeviceRef device, int32_t mode);
int32_t MTDeviceStop(MTDeviceRef device);

#endif
