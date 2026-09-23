//
//  Kalfa-Bridging-Header.h
//
//  Private/undocumented C declarations Kalfa relies on.
//
//  Two groups:
//    1. IOAVService  — the Apple Silicon path for DDC/CI I2C traffic. There is no
//       public replacement; IOFramebuffer's I2C interface only exists on Intel.
//    2. CGSConfigureDisplayMode — SkyLight's mode setter, used only as a fallback
//       when CGConfigureDisplayWithDisplayMode refuses a mode that clearly exists.
//
//  Everything else in Kalfa uses public CoreGraphics / IOKit API.
//

#ifndef Kalfa_Bridging_Header_h
#define Kalfa_Bridging_Header_h

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <IOKit/IOKitLib.h>

#pragma mark - IOAVService (Apple Silicon DDC/CI)

typedef void *IOAVServiceRef;

/// Wraps a DCPAVServiceProxy IORegistry node so I2C can be spoken over it.
extern IOAVServiceRef IOAVServiceCreateWithService(CFAllocatorRef allocator,
                                                   io_service_t service);

extern IOReturn IOAVServiceReadI2C(IOAVServiceRef service,
                                   uint32_t chipAddress,
                                   uint32_t offset,
                                   void *outputBuffer,
                                   uint32_t outputBufferSize);

extern IOReturn IOAVServiceWriteI2C(IOAVServiceRef service,
                                    uint32_t chipAddress,
                                    uint32_t dataAddress,
                                    void *inputBuffer,
                                    uint32_t inputBufferSize);

#pragma mark - SkyLight display modes

/// Sets a display mode by raw IODisplayModeID — the only way to select a mode
/// CoreGraphics refuses to list.
///
/// The first parameter is a live `CGDisplayConfigRef` from
/// `CGBeginDisplayConfiguration`, NOT a CGS connection ID. Passing a connection
/// ID here segfaults inside SkyLight, which dereferences it as the config object.
extern CGError CGSConfigureDisplayMode(CGDisplayConfigRef config,
                                       CGDirectDisplayID display,
                                       int32_t modeNumber);

/// Number of modes in SkyLight's own list, which is a superset of the one
/// CGDisplayCopyAllDisplayModes returns. On a clamshell MacBook the difference
/// includes the HiDPI modes, so this is not an optimisation — it is the only
/// route to a Retina desktop with the lid shut.
extern CGError CGSGetNumberOfDisplayModes(CGDirectDisplayID display,
                                          int32_t *count);

/// Fills a CGSDisplayModeDescription for one mode. `length` must be the exact
/// struct size (0xD4 on macOS 11 through 26) or the call fails.
extern CGError CGSGetDisplayModeDescriptionOfLength(CGDirectDisplayID display,
                                                    int32_t index,
                                                    void *description,
                                                    int32_t length);

#endif /* Kalfa_Bridging_Header_h */
