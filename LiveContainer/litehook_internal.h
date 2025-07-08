//
//  litehook_internal.h
//  LiveContainer
//
//  Created by Duy Tran on 8/7/25.
//

#include "../litehook/src/litehook.h"

typedef struct {
    const mach_header_u *sourceHeader;
    void *replacee;
    void *replacement;
    bool (*exceptionFilter)(const mach_header_u *header);
} global_rebind;

extern uint32_t gRebindCount;
extern global_rebind *gRebinds;
