// SPDX-License-Identifier: MIT
//
// Minimal C access to an Imacon / Hasselblad scanner through Apple's public
// SCSITaskUserClient API. Adapted from tools/x1probe/x1probe.c.
//
// This layer does not filter commands. Callers must go through
// X1Transport.IOKitTransport, which applies the read-only policy first.

#ifndef CX1IOKIT_H
#define CX1IOKIT_H

#include <stddef.h>
#include <stdint.h>

/// Opaque handle to an opened scanner (exclusive access held until cx1_close).
typedef struct cx1_device cx1_device;

#define CX1_DIRECTION_NONE 0
#define CX1_DIRECTION_TO_DEVICE 1
#define CX1_DIRECTION_FROM_DEVICE 2

/// Finds the first device whose vendor identification contains "Imacon" or
/// "Hasselbl", opens it and obtains exclusive access.
/// Returns an IOReturn code (0 on success). `description` receives "vendor product".
int32_t cx1_open(cx1_device *_Nullable *_Nonnull out_device,
                 char *_Nullable description, size_t description_size);

/// Executes one command synchronously. Returns an IOReturn code (0 when the
/// command was delivered; check `status` for the SCSI status).
int32_t cx1_execute(cx1_device *_Nonnull device,
                    const uint8_t *_Nonnull cdb, uint8_t cdb_length,
                    uint8_t *_Nullable buffer, uint32_t buffer_length, int32_t direction,
                    uint32_t timeout_ms,
                    uint8_t *_Nonnull status, uint64_t *_Nonnull transferred,
                    uint8_t *_Nullable sense, uint32_t sense_size);

/// Releases exclusive access and closes the device.
void cx1_close(cx1_device *_Nullable device);

#endif
