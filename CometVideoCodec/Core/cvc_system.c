#include "cvc_engine.h"
#include <sys/sysctl.h>

void cvc_engine_init(void) {
  // In FFmpeg 7.0 there is no global init needed like av_register_all()
  // It's already fully modular and self-registering.
}

void cvc_system_optimize_threads(int *out_thread_count) {
  if (!out_thread_count)
    return;

  int num_cores = 1;
  size_t size = sizeof(num_cores);
  if (sysctlbyname("hw.logicalcpu", &num_cores, &size, NULL, 0) != 0) {
    num_cores = 1;
  }

  // Adaptive Threading Heuristic:
  // We do not want to starve the host OS or AVFoundation encoder blocks.
  int threads = num_cores - 2;
  if (threads < 1)
    threads = 1;

  // Hard cap for FFmpeg decoding. There's diminishing returns beyond 16 cores.
  if (threads > 16)
    threads = 16;

  *out_thread_count = threads;
}
