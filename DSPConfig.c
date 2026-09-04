#include "DSPConfig.h"

#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

typedef struct PBConfigNode {
    PBDSPConfig config;
    struct PBConfigNode *next;
} PBConfigNode;

struct PBDSPConfigStore {
    _Atomic(PBConfigNode *) current;
    PBConfigNode *allocated;
};

PBDSPConfigStore *PBDSPConfigStoreCreate(void) {
    PBDSPConfigStore *store = calloc(1, sizeof(PBDSPConfigStore));
    if (store == NULL) return NULL;
    atomic_init(&store->current, NULL);
    return store;
}

void PBDSPConfigStoreDestroy(PBDSPConfigStore *store) {
    if (store == NULL) return;
    PBConfigNode *node = store->allocated;
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
    node->next = store->allocated;
    store->allocated = node;
    atomic_store_explicit(&store->current, node, memory_order_release);
}

const PBDSPConfig *PBDSPConfigStoreLoad(const PBDSPConfigStore *store) {
    if (store == NULL) return NULL;
    PBConfigNode *node = atomic_load_explicit(&store->current, memory_order_acquire);
    return node == NULL ? NULL : &node->config;
}

void PBDSPConfigInit(PBDSPConfig *config, uint64_t generation) {
    if (config == NULL) return;
    memset(config, 0, sizeof(PBDSPConfig));
    config->generation = generation;
    config->preampLinear = 1.0f;
    config->leftGain = 1.0f;
    config->rightGain = 1.0f;
    config->limiterThreshold = 0.9440609f;
}

void PBDSPConfigSetModule(PBDSPConfig *config, uint32_t index, uint32_t module) {
    if (config == NULL || index >= PB_MAX_MODULES) return;
    config->modules[index] = module;
}

void PBDSPConfigSetBand(PBDSPConfig *config, uint32_t index, PBBiquadCoefficients coefficients) {
    if (config == NULL || index >= PB_MAX_BANDS) return;
    config->bands[index] = coefficients;
}

uint32_t PBDSPConfigModule(const PBDSPConfig *config, uint32_t index) {
    if (config == NULL || index >= config->moduleCount || index >= PB_MAX_MODULES) return 0;
    return config->modules[index];
}

const PBBiquadCoefficients *PBDSPConfigBand(const PBDSPConfig *config, uint32_t index) {
    if (config == NULL || index >= config->bandCount || index >= PB_MAX_BANDS) return NULL;
    return &config->bands[index];
}
