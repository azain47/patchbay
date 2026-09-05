#ifndef PATCHBAY_DSP_CONFIG_H
#define PATCHBAY_DSP_CONFIG_H

#include <stdint.h>

#define PB_MAX_MODULES 16
#define PB_MAX_PARAMS 12
#define PB_MAX_BIQUADS 128

typedef struct {
    double b0, b1, b2, a1, a2;
} PBBiquad;

typedef struct {
    uint32_t kind;
    uint32_t enabled;
    uint32_t biquadStart;
    uint32_t biquadCount;
    float params[PB_MAX_PARAMS];
} PBModule;

typedef struct {
    uint64_t generation;
    uint64_t layoutGeneration;
    float sampleRate;
    uint32_t bypass;
    uint32_t moduleCount;
    uint32_t biquadCount;
    PBModule modules[PB_MAX_MODULES];
    PBBiquad biquads[PB_MAX_BIQUADS];
} PBDSPConfig;

typedef struct PBDSPConfigStore PBDSPConfigStore;

PBDSPConfigStore *PBDSPConfigStoreCreate(void);
void PBDSPConfigStoreDestroy(PBDSPConfigStore *store);
/// Publishes a snapshot. Retires snapshots older than two seconds; the realtime
/// reader never holds a pointer across callbacks, so that grace window is safe.
void PBDSPConfigStorePublish(PBDSPConfigStore *store, const PBDSPConfig *config);
const PBDSPConfig *PBDSPConfigStoreLoad(const PBDSPConfigStore *store);

#endif
