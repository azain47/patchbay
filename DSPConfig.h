#ifndef PATCHBAY_DSP_CONFIG_H
#define PATCHBAY_DSP_CONFIG_H

#include <stdbool.h>
#include <stdint.h>

#define PB_MAX_BANDS 12
#define PB_MAX_MODULES 8

typedef enum : uint32_t {
    PBModulePreamp = 1,
    PBModuleEqualizer = 2,
    PBModuleBalance = 3,
    PBModuleLimiter = 4,
} PBModuleKind;

typedef struct {
    double b0;
    double b1;
    double b2;
    double a1;
    double a2;
    uint32_t enabled;
} PBBiquadCoefficients;

typedef struct {
    uint64_t generation;
    float preampLinear;
    float leftGain;
    float rightGain;
    float limiterThreshold;
    uint32_t moduleCount;
    uint32_t bandCount;
    uint32_t modules[PB_MAX_MODULES];
    PBBiquadCoefficients bands[PB_MAX_BANDS];
} PBDSPConfig;

typedef struct PBDSPConfigStore PBDSPConfigStore;

PBDSPConfigStore *PBDSPConfigStoreCreate(void);
void PBDSPConfigStoreDestroy(PBDSPConfigStore *store);
void PBDSPConfigStorePublish(PBDSPConfigStore *store, const PBDSPConfig *config);
const PBDSPConfig *PBDSPConfigStoreLoad(const PBDSPConfigStore *store);

void PBDSPConfigInit(PBDSPConfig *config, uint64_t generation);
void PBDSPConfigSetModule(PBDSPConfig *config, uint32_t index, uint32_t module);
void PBDSPConfigSetBand(PBDSPConfig *config, uint32_t index, PBBiquadCoefficients coefficients);
uint32_t PBDSPConfigModule(const PBDSPConfig *config, uint32_t index);
const PBBiquadCoefficients *PBDSPConfigBand(const PBDSPConfig *config, uint32_t index);

#endif
