#include <libkern/libkern.h>
#include <mach/mach_types.h>
extern "C" {
static kern_return_t ps_kmod_start(kmod_info_t *ki, void *d) { return KERN_SUCCESS; }
static kern_return_t ps_kmod_stop (kmod_info_t *ki, void *d) { return KERN_SUCCESS; }
KMOD_EXPLICIT_DECL(local.predatorsense.PredatorSenseEC, "1.0.0", ps_kmod_start, ps_kmod_stop)
}
