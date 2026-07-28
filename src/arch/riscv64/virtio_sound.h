#pragma once

// VirtIO-sound — the first audio driver in this codebase. Same MMIO
// virtqueue scaffold as virtio_net.c/virtio_gpu.c, but with FOUR fixed
// queues (spec-mandated order, not renegotiable): 0=controlq,
// 1=eventq, 2=txq, 3=rxq. Only control+tx are ever actively used here
// (playback-only, no capture, no jack/channel-map introspection) -
// eventq/rxq are still allocated and marked ready (legal to leave
// idle - no buffers ever posted to them) since there's no way to
// verify from spec text alone whether a given backend tolerates an
// entirely unconfigured queue at DRIVER_OK time.
//
// virtio_sound_beep() synthesizes a plain square-wave tone (no libm/
// lookup table needed) and streams it out synchronously in page-sized
// chunks via the control-queue PCM lifecycle (SET_PARAMS -> PREPARE ->
// START -> tx chunks -> STOP -> RELEASE). Requires the device to
// support S16 samples at 44100 or 48000 Hz - if not, fails cleanly
// rather than guessing at an unsupported format.

int virtio_sound_init(void);
int virtio_sound_ready(void);

// beep(freq_hz, duration_ms) -> 0 ok / -1 err (no device, freq out of
// range, or device doesn't support S16 @ 44100/48000 Hz). Blocks for
// roughly duration_ms while the tone plays (synchronous, like every
// other blocking I/O call in this codebase - see tcp_send()'s own
// retry loop for the same style).
int virtio_sound_beep(unsigned int freq_hz, unsigned int duration_ms);
