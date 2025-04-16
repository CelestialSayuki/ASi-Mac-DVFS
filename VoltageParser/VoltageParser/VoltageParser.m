//
//  VoltageParser.m
//  VoltageParser
//
//  Created by Celestial紗雪 on 2025/4/15.
//

#import "VoltageParser.h"
#import <sys/sysctl.h>
#import <IOKit/IOKitLib.h>

// External references for IOReport methods
typedef struct IOReportSubscriptionRef* IOReportSubscriptionRef;

extern IOReportSubscriptionRef IOReportCreateSubscription(void*, /* NULL */
                                                         CFMutableDictionaryRef desiredChannels,
                                                         CFMutableDictionaryRef* subbedChannels,
                                                         uint64_t channel_id,/* 0 */
                                                         CFTypeRef /* nil */ );

extern CFDictionaryRef IOReportCreateSamples(IOReportSubscriptionRef subscription,
                                             CFMutableDictionaryRef subbedChannels,
                                             CFTypeRef /* nil */);

extern CFDictionaryRef IOReportCreateSamplesDelta(CFDictionaryRef previousSample,
                                                  CFDictionaryRef currentSample,
                                                  CFTypeRef /* nil */ );

extern CFMutableDictionaryRef IOReportCopyChannelsInGroup(NSString* channel,
                                                           NSString* /* nil */,
                                                           uint64_t /* 0 */,
                                                           uint64_t /* 0 */,
                                                           uint64_t /* 0 */);

extern void IOReportMergeChannels(CFMutableDictionaryRef firstChannel,
                                 CFMutableDictionaryRef secondChannel,
                                 CFTypeRef /* nil */);

extern void IOReportIterate(CFDictionaryRef samples, int(^)(CFDictionaryRef channel));

extern NSString* IOReportChannelGetChannelName(CFDictionaryRef);
extern NSString* IOReportChannelGetGroup(CFDictionaryRef);
extern NSString* IOReportChannelGetSubGroup(CFDictionaryRef);

extern int IOReportStateGetCount(CFDictionaryRef);
extern uint64_t IOReportStateGetResidency(CFDictionaryRef, int);
extern NSString* IOReportStateGetNameForIndex(CFDictionaryRef, int);
extern uint64_t IOReportArrayGetValueAtIndex(CFDictionaryRef, int);
extern long IOReportSimpleGetIntegerValue(CFDictionaryRef, int);

#define TOOL_VERSION "v1"

#define METRIC_ACTIVE   "%active"
#define METRIC_IDLE     "%idle"
#define METRIC_FREQ     "freq"
#define METRIC_DVFS     "dvfs"
#define METRIC_DVFSVOLTS "dvfs_volts"
#define METRIC_VOLTS    "volts"
#define METRIC_CORES    "per-core stats on supported units"

#define UNIT_ECPU       "ecpu"
#define UNIT_PCPU       "pcpu"
#define UNIT_GPU        "gpu"
#define UNIT_ANE        "ane"

#define METRIC_COUNT 7
#define UNITS_COUNT 4

#define VOLTAGE_STATES_ECPU CFSTR("voltage-states1-sram")
#define VOLTAGE_STATES_PCPU CFSTR("voltage-states5-sram")
#define VOLTAGE_STATES_ANE CFSTR("voltage-states8")
#define VOLTAGE_STATES_GPU CFSTR("voltage-states9")

typedef struct param_set {
    const char* name;
    const char* description;
} param_set;

static const NSArray* performanceCounterKeys = @[ @"ECPU", @"PCPU", /* pleb chips (M1, M2, M3, M3 Pro) */
                                                  @"ECPU0", @"PCPU0", @"PCPU1", /* Max Chips */
                                                  @"EACC_CPU", @"PACC0_CPU", @"PACC1_CPU" /* Ultra Chips */];

static NSString* P_STATE     = @"P";
static NSString* V_STATE     = @"V";
static NSString* IDLE_STATE = @"IDLE";
static NSString* OFF_STATE   = @"OFF";

NSString* getPlatformName(void) {
     io_registry_entry_t entry;
     io_iterator_t  iter;

     CFMutableDictionaryRef servicedict;
     CFMutableDictionaryRef service;

     if (!(service = IOServiceMatching("IOPlatformExpertDevice"))) return nil;
     if (!(IOServiceGetMatchingServices(kIOMasterPortDefault, service, &iter) == kIOReturnSuccess)) return nil;

     NSString* platfromName = nil;

     while ((entry = IOIteratorNext(iter)) != IO_OBJECT_NULL) {
         if ((IORegistryEntryCreateCFProperties(entry, &servicedict, kCFAllocatorDefault, 0) != kIOReturnSuccess)) {
             IOObjectRelease(entry); // Release entry on failure
             continue;
         }

         const void* data = CFDictionaryGetValue(servicedict, @"platform-name");

         if (data != nil && CFGetTypeID(data) == CFDataGetTypeID()) {
             NSData* formattedData = (NSData*)CFBridgingRelease(CFDataCreateCopy(kCFAllocatorDefault, (CFDataRef)data));
             const unsigned char* databytes = [formattedData bytes];
             platfromName = [[NSString alloc] initWithBytes:databytes length:formattedData.length encoding:NSASCIIStringEncoding];
             platfromName = [platfromName capitalizedString];

         }
         CFRelease(servicedict);
         IOObjectRelease(entry);
         if (platfromName) break;
     }
     IOObjectRelease(iter);

     return platfromName;
}


char* getSocName(void) {
    size_t len = 0;
    if (sysctlbyname("machdep.cpu.brand_string", NULL, &len, NULL, 0) == -1) {
        perror("sysctlbyname size failed");
        return NULL;
    }

    char* cpubrand = malloc(len);
    if (!cpubrand) {
        perror("malloc failed");
        return NULL;
    }

    if (sysctlbyname("machdep.cpu.brand_string", cpubrand, &len, NULL, 0) == -1) {
        perror("sysctlbyname value failed");
        free(cpubrand);
        return NULL;
    }
    return cpubrand;
}


static void getDfvs(io_registry_entry_t entry, CFStringRef string, NSMutableArray* dvfs, BOOL isLegacy) {
    CFTypeRef dataRef = IORegistryEntryCreateCFProperty(entry, string, kCFAllocatorDefault, kNilOptions);

    if (dataRef != nil && CFGetTypeID(dataRef) == CFDataGetTypeID()) {
        NSData* formattedData = (NSData*)CFBridgingRelease(dataRef);
        const unsigned char* databytes = [formattedData bytes];
        NSUInteger dataLength = [formattedData length];
        double divisor = isLegacy ? 1e-6 : 1e-3;

        if (dataLength % 8 == 0 && dataLength >= 8) {
            for (NSUInteger ii = 0; ii < dataLength; ii += 8) {
                if (ii + 8 > dataLength) break;

                uint32_t freqRaw;
                uint32_t voltRaw;
                memcpy(&freqRaw, databytes + ii, sizeof(uint32_t));
                memcpy(&voltRaw, databytes + ii + 4, sizeof(uint32_t));

                double freqValue = (double)freqRaw * divisor;

                NSNumber* mvolt = nil;

                // Check for the specific "invalid" voltage value
                if (voltRaw != 0xFFFFFFFF) {
                     mvolt = [NSNumber numberWithUnsignedInt:voltRaw];
                 } else {
                     mvolt = @0;
                 }

                if (freqValue > 0) {
                    NSNumber* freq = [NSNumber numberWithDouble:freqValue];
                    if (mvolt != nil) {
                        [dvfs addObject: @[freq, mvolt]];
                    }
                }
            }
        }
    } else if (dataRef != nil) {
        CFRelease(dataRef);
    }
}


static void makeDvfsTables(NSMutableArray* ecpu_table, NSMutableArray* pcpu_table, NSMutableArray* gpu_table, NSMutableArray* ane_table, BOOL isLegacy) {
    io_iterator_t iter = IO_OBJECT_NULL;
    io_registry_entry_t entry = IO_OBJECT_NULL;
    CFMutableDictionaryRef service = IOServiceMatching("AppleARMIODevice");

    if (!service) {
        fprintf(stderr, "Error: IOServiceMatching failed for AppleARMIODevice.\n");
        return;
    }

    kern_return_t kr = IOServiceGetMatchingServices(kIOMasterPortDefault, service, &iter);

    if (kr != KERN_SUCCESS || iter == IO_OBJECT_NULL) {
        fprintf(stderr, "Error: No matching services found for AppleARMIODevice. kr=0x%x\n", kr);
        if (iter != IO_OBJECT_NULL) IOObjectRelease(iter);
        return;
    }

    BOOL foundDevice = NO;
    while ((entry = IOIteratorNext(iter)) != IO_OBJECT_NULL) {
        CFTypeRef propertyCheck = IORegistryEntryCreateCFProperty(entry, VOLTAGE_STATES_ECPU, kCFAllocatorDefault, kNilOptions);
        if (propertyCheck != nil) {
             CFRelease(propertyCheck);

             getDfvs(entry, VOLTAGE_STATES_ECPU, ecpu_table, isLegacy);
             getDfvs(entry, VOLTAGE_STATES_PCPU, pcpu_table, isLegacy);
             getDfvs(entry, VOLTAGE_STATES_GPU, gpu_table, YES);
             getDfvs(entry, VOLTAGE_STATES_ANE, ane_table, YES);

             foundDevice = YES;
             IOObjectRelease(entry);
             break;
         }

         IOObjectRelease(entry);
     }

    IOObjectRelease(iter);

    if (!foundDevice) {
        fprintf(stderr, "Warning: Could not find AppleARMIODevice with voltage state properties.\n");
    }
}

NSMutableDictionary* filterChannelAndConstructCollection(BOOL isLegacy) { // Removed unused 'channel' parameter
    NSMutableArray* ecpuDvfs = [[NSMutableArray alloc] init];
    NSMutableArray* pcpuDvfs = [[NSMutableArray alloc] init];
    NSMutableArray* gpuDvfs = [[NSMutableArray alloc] init];
    NSMutableArray* aneDvfs = [[NSMutableArray alloc] init];

    makeDvfsTables(ecpuDvfs, pcpuDvfs, gpuDvfs, aneDvfs, isLegacy);

    NSMutableDictionary* dvfsCollection = [[NSMutableDictionary alloc] init];

    if ([ecpuDvfs count] > 0) {
        [ecpuDvfs sortUsingComparator:^NSComparisonResult(id obj1, id obj2) {
            NSNumber *freq1 = [(NSArray *)obj1 objectAtIndex:0];
            NSNumber *freq2 = [(NSArray *)obj2 objectAtIndex:0];
            return [freq1 compare:freq2];
        }];
        [dvfsCollection setValue:ecpuDvfs forKey:@"E-core"];
    }
    if ([pcpuDvfs count] > 0) {
        [pcpuDvfs sortUsingComparator:^NSComparisonResult(id obj1, id obj2) {
            NSNumber *freq1 = [(NSArray *)obj1 objectAtIndex:0];
            NSNumber *freq2 = [(NSArray *)obj2 objectAtIndex:0];
            return [freq1 compare:freq2];
        }];
        [dvfsCollection setValue:pcpuDvfs forKey:@"P-core"];
    }
    if ([gpuDvfs count] > 0) {
        [gpuDvfs sortUsingComparator:^NSComparisonResult(id obj1, id obj2) {
            NSNumber *freq1 = [(NSArray *)obj1 objectAtIndex:0];
            NSNumber *freq2 = [(NSArray *)obj2 objectAtIndex:0];
            return [freq1 compare:freq2];
        }];
        [dvfsCollection setValue:gpuDvfs forKey:@"GPU"];
    }
    if ([aneDvfs count] > 0) {
        [aneDvfs sortUsingComparator:^NSComparisonResult(id obj1, id obj2) {
            NSNumber *freq1 = [(NSArray *)obj1 objectAtIndex:0];
            NSNumber *freq2 = [(NSArray *)obj2 objectAtIndex:0];
            return [freq1 compare:freq2];
        }];
        [dvfsCollection setValue:aneDvfs forKey:@"ANE"];
    }

    return dvfsCollection;
}

// --- Class Method Implementation ---
@implementation VoltageParser

+ (NSString *)getVoltageDataString {
    NSMutableString* output = [NSMutableString string];

    [output appendString:NSLocalizedString(@"parser.toolTitle", @"Tool title header")];
    [output appendString:@"\n"];

    char* socNameC = getSocName();
    NSString* platformName = getPlatformName();
    NSString* socName = NSLocalizedString(@"parser.unknownSoC", @"Fallback SoC name");
    if (socNameC) {
        socName = [NSString stringWithUTF8String:socNameC];
        free(socNameC);
    }

    BOOL isLegacy = NO;
    if ([socName containsString:@"M1"] || [socName containsString:@"M2"] || [socName containsString:@"M3"]) {
        isLegacy = YES;
    }

    NSDictionary* dvfsTable = filterChannelAndConstructCollection(isLegacy);

    NSString *localizedPlatformName = platformName ?: NSLocalizedString(@"parser.unknownPlatform", @"Fallback platform name");
    NSString *cpuInfoFormat = NSLocalizedString(@"parser.cpuModelFormat", @"CPU model format string: %@ = SoC, %@ = Platform");
    [output appendFormat:cpuInfoFormat, socName, localizedPlatformName];
    [output appendString:@"\n\n"];

    [output appendString:NSLocalizedString(@"parser.voltageDataHeader", @"Voltage data section header")];
    [output appendString:@"\n"];

    void (^appendVoltageData)(NSString*, NSArray*) = ^(NSString* localizedCoreTypeLabel, NSArray* coreData) {
        if (coreData && coreData.count > 0) {
            [output appendFormat:@"%@\n", localizedCoreTypeLabel];
            for (NSArray* state in coreData) {
                if (state.count >= 2) {
                    NSNumber* freq = state[0];
                    NSNumber* voltage = state[1];
                    if ([voltage floatValue] > 0) {
                        NSString *format = NSLocalizedString(@"parser.stateFormatMHz_mV", @"Format for frequency and voltage");
                        [output appendFormat:format, [freq floatValue], [voltage floatValue]];
                    } else {
                        NSString *format = NSLocalizedString(@"parser.stateFormatMHz_unsupported", @"Format for frequency when voltage is unsupported");
                        [output appendFormat:format, [freq floatValue]];
                    }
                    [output appendString:@"\n"];
                }
            }
             [output appendString:@"\n"];
        }
    };

    appendVoltageData(NSLocalizedString(@"parser.coreTypeECore", @"E-core label"), dvfsTable[@"E-core"]);
    appendVoltageData(NSLocalizedString(@"parser.coreTypePCore", @"P-core label"), dvfsTable[@"P-core"]);
    appendVoltageData(NSLocalizedString(@"parser.coreTypeGPU", @"GPU label"), dvfsTable[@"GPU"]);
    appendVoltageData(NSLocalizedString(@"parser.coreTypeANE", @"ANE label"), dvfsTable[@"ANE"]);

    return [output copy];
}

@end
