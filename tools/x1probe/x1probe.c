/*
 * X1-Scan-ARM : sonde v3, lecture seule.
 * Rejoue les commandes de LECTURE que FlexColor 4.8.13 envoie au X1 à
 * l'initialisation (capture lldb du 2026-11-12), avec les mêmes CDB.
 * Liste blanche stricte : seuls les opcodes 0x12, 0x00, 0x03, 0x5A, 0x4D,
 * 0xEE et 0xD3, et uniquement dans le sens scanner -> Mac.
 * La commande 0xD2 (sans données, effet inconnu) n'est PAS envoyée.
 *
 * Compilation : clang -o x1probe x1probe.c -framework IOKit -framework CoreFoundation
 * Usage       : ./x1probe | tee x1probe.txt
 * SPDX-License-Identifier: MIT
 */
#include <stdio.h>
#include <string.h>
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/scsi/SCSITaskLib.h>

static void getStr(io_service_t s, const char *key, char *dst, size_t n) {
    dst[0] = 0;
    CFStringRef k = CFStringCreateWithCString(NULL, key, kCFStringEncodingUTF8);
    CFTypeRef v = IORegistryEntrySearchCFProperty(s, kIOServicePlane, k, NULL,
                    kIORegistryIterateRecursively | kIORegistryIterateParents);
    CFRelease(k);
    if (!v) return;
    if (CFGetTypeID(v) == CFStringGetTypeID())
        CFStringGetCString((CFStringRef)v, dst, n, kCFStringEncodingUTF8);
    CFRelease(v);
}

static void hexdump(const uint8_t *b, int n) {
    for (int i = 0; i < n; i += 16) {
        printf("    %04x  ", i);
        for (int j = 0; j < 16; j++) (i+j < n) ? printf("%02x ", b[i+j]) : printf("   ");
        printf(" ");
        for (int j = 0; j < 16 && i+j < n; j++) putchar(b[i+j] >= 32 && b[i+j] < 127 ? b[i+j] : '.');
        printf("\n");
    }
}

static int allowed(UInt8 op) {
    return op == 0x12 || op == 0x00 || op == 0x03 || op == 0x5A ||
           op == 0x4D || op == 0xEE || op == 0xD3;
}

/* Envoie une commande de lecture. quiet=1 : une seule ligne (pour les registres). */
static int run(SCSITaskDeviceInterface **dev, const char *name,
               const UInt8 *cdbIn, UInt8 cdbLen, uint8_t *buf, int bufLen, int quiet) {
    UInt8 cdb[16]; memcpy(cdb, cdbIn, cdbLen);
    if (!allowed(cdb[0])) { printf("  %s : opcode 0x%02x refusé par la liste blanche\n", name, cdb[0]); return -1; }
    memset(buf, 0, bufLen > 0 ? bufLen : 0);
    SCSITaskInterface **task = (*dev)->CreateSCSITask(dev);
    if (!task) { printf("  %s : CreateSCSITask a échoué\n", name); return -1; }
    SCSI_Sense_Data sense; memset(&sense, 0, sizeof sense);
    SCSITaskStatus st = kSCSITaskStatus_No_Status;
    UInt64 got = 0;
    IOVirtualRange r = { (IOVirtualAddress)buf, (IOByteCount)bufLen };
    (*task)->SetCommandDescriptorBlock(task, cdb, cdbLen);
    if (bufLen > 0)
        (*task)->SetScatterGatherEntries(task, &r, 1, bufLen, kSCSIDataTransfer_FromTargetToInitiator);
    else
        (*task)->SetScatterGatherEntries(task, NULL, 0, 0, kSCSIDataTransfer_NoDataTransfer);
    (*task)->SetTimeoutDuration(task, 10000);
    IOReturn kr = (*task)->ExecuteTaskSync(task, &sense, &st, &got);
    if (quiet && kr == kIOReturnSuccess && st == kSCSITaskStatus_GOOD && got == 1) {
        printf("  %s = 0x%02x (%u)\n", name, buf[0], buf[0]);
    } else {
        printf("  %s : IOReturn=0x%08x statut=0x%02x octets=%llu   CDB:", name, kr, st,
               (unsigned long long)got);
        for (int i = 0; i < cdbLen; i++) printf(" %02x", cdb[i]);
        printf("\n");
        if (st == kSCSITaskStatus_CHECK_CONDITION)
            printf("    sense : clé=0x%x ASC=0x%02x ASCQ=0x%02x\n", sense.SENSE_KEY & 0x0F,
                   sense.ADDITIONAL_SENSE_CODE, sense.ADDITIONAL_SENSE_CODE_QUALIFIER);
        if (got > 0) hexdump(buf, (int)got);
    }
    (*task)->Release(task);
    return (kr == kIOReturnSuccess && st == kSCSITaskStatus_GOOD) ? 0 : -1;
}

static void probe(SCSITaskDeviceInterface **dev) {
    uint8_t buf[256];
    char name[64];

    printf("\n== Commandes standard\n");
    { UInt8 c[6] = {0x12,0,0,0,0x60,0}; run(dev, "INQUIRY", c, 6, buf, 96, 0); }
    { UInt8 c[6] = {0x00,0,0,0,0,0};    run(dev, "TEST UNIT READY", c, 6, buf, 0, 0); }
    { UInt8 c[6] = {0x03,0,0,0,18,0};   run(dev, "REQUEST SENSE", c, 6, buf, 18, 0); }

    printf("\n== MODE SENSE(10) pages vendeur (CDB identiques à FlexColor)\n");
    struct { UInt8 page; UInt8 len; } pages[] = {
        {0x26, 56}, {0x27, 20}, {0x25, 24}, {0x21, 100}, {0x29, 14}, {0x23, 60}
    };
    for (unsigned i = 0; i < sizeof pages / sizeof pages[0]; i++) {
        UInt8 c[10] = {0x5A, 0, pages[i].page, 0x01, 0, 0, 0, 0, pages[i].len, 0};
        snprintf(name, sizeof name, "MODE SENSE page 0x%02x", pages[i].page);
        run(dev, name, c, 10, buf, pages[i].len, 0);
    }

    printf("\n== LOG SENSE(10) page 0x30\n");
    { UInt8 c[10] = {0x4D,0,0x30,0,0,0,0,0,0x34,0}; run(dev, "LOG SENSE page 0x30", c, 10, buf, 52, 0); }

    printf("\n== Registres 0xEE (banque 1, adresses 0x04 à 0x19)\n");
    for (UInt8 a = 0x04; a <= 0x19; a++) {
        UInt8 c[10] = {0xEE,0,0,0,0x01,a,0,0,0x01,0};
        snprintf(name, sizeof name, "registre 1.%02x", a);
        run(dev, name, c, 10, buf, 1, 1);
    }

    printf("\n== Bouton de scan 0xD3\n");
    { UInt8 c[6] = {0xD3,0,0,0,0x02,0}; run(dev, "BOUTON", c, 6, buf, 2, 0); }
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    CFMutableDictionaryRef m = CFDictionaryCreateMutable(NULL, 0,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFMutableDictionaryRef sub = CFDictionaryCreateMutable(NULL, 0,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFDictionarySetValue(sub, CFSTR(kIOPropertySCSITaskDeviceCategory),
                              CFSTR(kIOPropertySCSITaskUserClientDevice));
    CFDictionarySetValue(m, CFSTR(kIOPropertyMatchKey), sub);
    CFRelease(sub);

    io_iterator_t it;
    if (IOServiceGetMatchingServices(MACH_PORT_NULL, m, &it) != KERN_SUCCESS) {
        printf("Recherche IOKit impossible.\n"); return 1;
    }
    int found = 0;
    io_service_t s;
    while ((s = IOIteratorNext(it))) {
        char ven[64], prod[64];
        getStr(s, "Vendor Identification", ven, sizeof ven);
        getStr(s, "Product Identification", prod, sizeof prod);
        if (!(strcasestr(ven, "imacon") || strcasestr(ven, "hasselbl"))) { IOObjectRelease(s); continue; }
        found++;
        printf("Périphérique : '%s' '%s'\n", ven, prod);

        IOCFPlugInInterface **plug = NULL; SInt32 score = 0;
        IOReturn kr = IOCreatePlugInInterfaceForService(s, kIOSCSITaskDeviceUserClientTypeID,
                          kIOCFPlugInInterfaceID, &plug, &score);
        if (kr != kIOReturnSuccess || !plug) {
            printf("  Ouverture impossible (0x%08x). FlexColor ou une autre sonde est-il ouvert ?\n", kr);
            IOObjectRelease(s); continue;
        }
        SCSITaskDeviceInterface **dev = NULL;
        (*plug)->QueryInterface(plug, CFUUIDGetUUIDBytes(kIOSCSITaskDeviceInterfaceID), (LPVOID *)&dev);
        if (dev) {
            if ((*dev)->ObtainExclusiveAccess(dev) == kIOReturnSuccess) {
                probe(dev);
                (*dev)->ReleaseExclusiveAccess(dev);
            } else printf("  Accès exclusif refusé.\n");
            (*dev)->Release(dev);
        } else printf("  QueryInterface a échoué\n");
        IODestroyPlugInInterface(plug);   /* en dernier : ferme la connexion */
        IOObjectRelease(s);
    }
    IOObjectRelease(it);
    if (!found) printf("Aucun scanner Imacon/Hasselblad trouvé.\n");
    return 0;
}
