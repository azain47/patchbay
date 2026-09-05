#include "DSPConfig.h"

#include <mach/mach_time.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

typedef struct PBConfigNode {
    PBDSPConfig config;
    uint64_t publishedAt;
    struct PBConfigNode *next;
} PBConfigNode;

struct PBDSPConfigStore {
    _Atomic(PBConfigNode *) current;
    PBConfigNode *retired;  // newest first; only touched by the publishing thread
};

static uint64_t nanosPerTick(void) {
    static mach_timebase_info_data_t info;
    if (info.denom == 0) mach_timebase_info(&info);
    return info.numer / info.denom;
}

PBDSPConfigStore *PBDSPConfigStoreCreate(void) {
    PBDSPConfigStore *store = calloc(1, sizeof(PBDSPConfigStore));
    if (store == NULL) return NULL;
    atomic_init(&store->current, NULL);
    return store;
}

void PBDSPConfigStoreDestroy(PBDSPConfigStore *store) {
    if (store == NULL) return;
    PBConfigNode *node = store->retired;
    while (node != NULL) {
        PBConfigNode *next = node->next;
        free(node);
        node = next;
    }
    free(store);
}

void PBDSPConfigStorePublish(PBDSPConfigStore *store, const PBDSPConfig *config) {
    if (store == NULL || config == NULL) return;
    PBConfigNode *node = malloc(sizeof(PBConfigNode));
    if (node == NULL) return;
    memcpy(&node->config, config, sizeof(PBDSPConfig));
    node->publishedAt = mach_absolute_time();
    node->next = store->retired;
    store->retired = node;
    atomic_store_explicit(&store->current, node, memory_order_release);

    // Free everything older than the grace window, keeping the current node.
    const uint64_t graceTicks = 2000000000ULL / nanosPerTick();
    PBConfigNode *keep = node;
    PBConfigNode *cursor = node->next;
    while (cursor != NULL) {
        PBConfigNode *next = cursor->next;
        if (node->publishedAt - cursor->publishedAt > graceTicks) {
            keep->next = NULL;
            while (cursor != NULL) {
                PBConfigNode *n = cursor->next;
                free(cursor);
                cursor = n;
            }
            break;
        }
        keep = cursor;
        cursor = next;
    }
}

const PBDSPConfig *PBDSPConfigStoreLoad(const PBDSPConfigStore *store) {
    if (store == NULL) return NULL;
    PBConfigNode *node = atomic_load_explicit(&store->current, memory_order_acquire);
    return node == NULL ? NULL : &node->config;
}
