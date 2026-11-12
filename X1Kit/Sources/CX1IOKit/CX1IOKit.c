// SPDX-License-Identifier: MIT
#include "CX1IOKit.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/scsi/SCSITaskLib.h>

struct cx1_device {
    io_service_t service;
    IOCFPlugInInterface **plugin;
    SCSITaskDeviceInterface **interface;
};

static void copy_property(io_service_t service, const char *key, char *dst, size_t size) {
    dst[0] = 0;
    CFStringRef cfKey = CFStringCreateWithCString(NULL, key, kCFStringEncodingUTF8);
    CFTypeRef value = IORegistryEntrySearchCFProperty(service, kIOServicePlane, cfKey, NULL,
                          kIORegistryIterateRecursively | kIORegistryIterateParents);
    CFRelease(cfKey);
    if (!value) return;
    if (CFGetTypeID(value) == CFStringGetTypeID())
        CFStringGetCString((CFStringRef)value, dst, (CFIndex)size, kCFStringEncodingUTF8);
    CFRelease(value);
}

static int is_supported_vendor(const char *vendor) {
    return strcasestr(vendor, "imacon") != NULL || strcasestr(vendor, "hasselbl") != NULL;
}

int32_t cx1_open(cx1_device **out_device, char *description, size_t description_size) {
    *out_device = NULL;
    if (description && description_size) description[0] = 0;

    CFMutableDictionaryRef matching = CFDictionaryCreateMutable(NULL, 0,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFMutableDictionaryRef property = CFDictionaryCreateMutable(NULL, 0,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFDictionarySetValue(property, CFSTR(kIOPropertySCSITaskDeviceCategory),
                         CFSTR(kIOPropertySCSITaskUserClientDevice));
    CFDictionarySetValue(matching, CFSTR(kIOPropertyMatchKey), property);
    CFRelease(property);

    io_iterator_t iterator = IO_OBJECT_NULL;
    kern_return_t kr = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator);
    if (kr != KERN_SUCCESS) return kr;

    IOReturn result = kIOReturnNotFound;
    io_service_t service;
    while ((service = IOIteratorNext(iterator))) {
        char vendor[64], product[64];
        copy_property(service, "Vendor Identification", vendor, sizeof vendor);
        copy_property(service, "Product Identification", product, sizeof product);
        if (!is_supported_vendor(vendor)) { IOObjectRelease(service); continue; }

        IOCFPlugInInterface **plugin = NULL;
        SInt32 score = 0;
        result = IOCreatePlugInInterfaceForService(service, kIOSCSITaskDeviceUserClientTypeID,
                                                   kIOCFPlugInInterfaceID, &plugin, &score);
        if (result != kIOReturnSuccess || !plugin) {
            if (result == kIOReturnSuccess) result = kIOReturnError;
            IOObjectRelease(service);
            continue;
        }

        SCSITaskDeviceInterface **interface = NULL;
        HRESULT hr = (*plugin)->QueryInterface(plugin, CFUUIDGetUUIDBytes(kIOSCSITaskDeviceInterfaceID),
                                               (LPVOID *)&interface);
        if (hr != S_OK || !interface) {
            result = kIOReturnError;
            IODestroyPlugInInterface(plugin);
            IOObjectRelease(service);
            continue;
        }

        result = (*interface)->ObtainExclusiveAccess(interface);
        if (result != kIOReturnSuccess) {
            (*interface)->Release(interface);
            IODestroyPlugInInterface(plugin);
            IOObjectRelease(service);
            continue;
        }

        cx1_device *device = calloc(1, sizeof *device);
        if (!device) {
            (*interface)->ReleaseExclusiveAccess(interface);
            (*interface)->Release(interface);
            IODestroyPlugInInterface(plugin);
            IOObjectRelease(service);
            result = kIOReturnNoMemory;
            break;
        }
        device->service = service;
        device->plugin = plugin;
        device->interface = interface;
        if (description && description_size)
            snprintf(description, description_size, "%s %s", vendor, product);
        *out_device = device;
        break;
    }
    IOObjectRelease(iterator);
    return result;
}

int32_t cx1_execute(cx1_device *device,
                    const uint8_t *cdb, uint8_t cdb_length,
                    uint8_t *buffer, uint32_t buffer_length, int32_t direction,
                    uint32_t timeout_ms,
                    uint8_t *status, uint64_t *transferred,
                    uint8_t *sense, uint32_t sense_size) {
    *status = kSCSITaskStatus_No_Status;
    *transferred = 0;
    if (!device || !device->interface) return kIOReturnNotOpen;

    SCSITaskDeviceInterface **interface = device->interface;
    SCSITaskInterface **task = (*interface)->CreateSCSITask(interface);
    if (!task) return kIOReturnNoResources;

    SCSI_Sense_Data sense_data;
    memset(&sense_data, 0, sizeof sense_data);
    SCSITaskStatus task_status = kSCSITaskStatus_No_Status;
    UInt64 count = 0;

    IOReturn result = (*task)->SetCommandDescriptorBlock(task, (UInt8 *)cdb, cdb_length);
    if (result == kIOReturnSuccess) {
        if (direction == CX1_DIRECTION_NONE || buffer_length == 0 || !buffer) {
            result = (*task)->SetScatterGatherEntries(task, NULL, 0, 0, kSCSIDataTransfer_NoDataTransfer);
        } else {
            IOVirtualRange range = { (IOVirtualAddress)buffer, (IOByteCount)buffer_length };
            UInt8 transfer = direction == CX1_DIRECTION_TO_DEVICE
                ? kSCSIDataTransfer_FromInitiatorToTarget
                : kSCSIDataTransfer_FromTargetToInitiator;
            result = (*task)->SetScatterGatherEntries(task, &range, 1, buffer_length, transfer);
        }
    }
    if (result == kIOReturnSuccess) {
        (*task)->SetTimeoutDuration(task, timeout_ms);
        result = (*task)->ExecuteTaskSync(task, &sense_data, &task_status, &count);
    }

    *status = (uint8_t)task_status;
    *transferred = count;
    if (sense && sense_size) {
        size_t n = sense_size < sizeof sense_data ? sense_size : sizeof sense_data;
        memcpy(sense, &sense_data, n);
    }
    (*task)->Release(task);
    return result;
}

void cx1_close(cx1_device *device) {
    if (!device) return;
    if (device->interface) {
        (*device->interface)->ReleaseExclusiveAccess(device->interface);
        (*device->interface)->Release(device->interface);
    }
    if (device->plugin) IODestroyPlugInInterface(device->plugin);  // closes the connection
    if (device->service) IOObjectRelease(device->service);
    free(device);
}
