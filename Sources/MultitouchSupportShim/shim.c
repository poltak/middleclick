#include "MultitouchSupportShim.h"

_Static_assert(sizeof(MTTouch) == 96, "Unexpected MTTouch size");
_Static_assert(offsetof(MTTouch, timestamp) == 8, "Unexpected timestamp offset");
_Static_assert(offsetof(MTTouch, fingerID) == 24, "Unexpected fingerID offset");
_Static_assert(offsetof(MTTouch, normalizedVector) == 32, "Unexpected normalizedVector offset");
_Static_assert(offsetof(MTTouch, zTotal) == 48, "Unexpected zTotal offset");
_Static_assert(offsetof(MTTouch, absoluteVector) == 68, "Unexpected absoluteVector offset");
_Static_assert(offsetof(MTTouch, zDensity) == 92, "Unexpected zDensity offset");
