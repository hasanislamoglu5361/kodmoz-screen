#import "include/CVirtualDisplay.h"

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/message.h>
#import <objc/runtime.h>

// CGVirtualDisplay ailesi macOS'ta yıllardır var ama başlıklarda yayınlanmıyor.
// Sınıfları çalışma zamanında arıyoruz: Apple bir gün kaldırırsa uygulama
// başlangıçta çökmez, çağıran taraf NULL görüp aynalama moduna geçer.

struct KodmozVirtualDisplayHandle {
    void *display;
};

typedef id (*KodmozMsgSendId)(id, SEL);
typedef id (*KodmozMsgSendIdId)(id, SEL, id);
typedef id (*KodmozMsgSendIdULLD)(id, SEL, NSUInteger, NSUInteger, CGFloat);
typedef BOOL (*KodmozMsgSendBoolId)(id, SEL, id);
typedef void (*KodmozMsgSendVoidQueue)(id, SEL, dispatch_queue_t);

KodmozVirtualDisplayHandle *KodmozVirtualDisplayCreate(
    const char *name,
    uint32_t widthPixels,
    uint32_t heightPixels,
    double refreshRate,
    uint32_t hiDPI,
    uint32_t *outDisplayID)
{
    if (outDisplayID) *outDisplayID = 0;
    if (!name || widthPixels < 640 || heightPixels < 480) return NULL;

    Class descriptorClass = NSClassFromString(@"CGVirtualDisplayDescriptor");
    Class displayClass = NSClassFromString(@"CGVirtualDisplay");
    Class settingsClass = NSClassFromString(@"CGVirtualDisplaySettings");
    Class modeClass = NSClassFromString(@"CGVirtualDisplayMode");
    if (!descriptorClass || !displayClass || !settingsClass || !modeClass) {
        NSLog(@"[KodmozScreen] CGVirtualDisplay sınıfları bulunamadı");
        return NULL;
    }

    @try {
        id descriptor = ((KodmozMsgSendId)objc_msgSend)(descriptorClass, sel_registerName("new"));
        if (!descriptor) return NULL;

        [descriptor setValue:[NSString stringWithUTF8String:name] forKey:@"name"];
        // DeskPad gibi geniş bir üst sınır veriyoruz; macOS kendi mod
        // listesini bu sınıra göre üretiyor.
        [descriptor setValue:@(MAX(widthPixels, 3840u)) forKey:@"maxPixelsWide"];
        [descriptor setValue:@(MAX(heightPixels, 2400u)) forKey:@"maxPixelsHigh"];
        [descriptor setValue:@(0x4B534352) forKey:@"productID"];
        [descriptor setValue:@(0x4B4D5A) forKey:@"vendorID"];
        [descriptor setValue:@(1) forKey:@"serialNum"];

        // Fiziksel boyut: ~250 ppi varsayımı. macOS bunu yalnızca ekranın
        // "inç" bilgisini göstermek için kullanır.
        const double mmPerInch = 25.4;
        const double assumedPPI = 250.0;
        double mmWide = (double)widthPixels / assumedPPI * mmPerInch;
        double mmHigh = (double)heightPixels / assumedPPI * mmPerInch;
        [descriptor setValue:[NSValue valueWithSize:NSMakeSize(mmWide, mmHigh)]
                      forKey:@"sizeInMillimeters"];

        // DeskPad ve benzeri uygulamalar ana kuyruğu kullanıyor; pencere
        // sunucusuyla eşleşme bu kuyruk üzerinden yürüyor.
        dispatch_queue_t queue = dispatch_get_main_queue();
        if ([descriptor respondsToSelector:sel_registerName("setDispatchQueue:")]) {
            ((KodmozMsgSendVoidQueue)objc_msgSend)(
                descriptor, sel_registerName("setDispatchQueue:"), queue);
        } else {
            [descriptor setValue:queue forKey:@"queue"];
        }

        id allocated = ((KodmozMsgSendId)objc_msgSend)(displayClass, sel_registerName("alloc"));
        id display = ((KodmozMsgSendIdId)objc_msgSend)(
            allocated, sel_registerName("initWithDescriptor:"), descriptor);
        if (!display) return NULL;

        id settings = ((KodmozMsgSendId)objc_msgSend)(settingsClass, sel_registerName("new"));
        if (!settings) return NULL;
        [settings setValue:@(hiDPI ? 1 : 0) forKey:@"hiDPI"];

        // Tek mod verildiğinde macOS 26 ekranı pencere sunucusuna kaydetmiyor;
        // DeskPad'in kullandığı gibi standart bir mod listesi veriyoruz.
        NSMutableArray *modes = [NSMutableArray array];
        NSArray<NSArray<NSNumber *> *> *standardModes = @[
            @[@(1280), @(720)],
            @[@(1280), @(800)],
            @[@(1366), @(768)],
            @[@(1600), @(900)],
            @[@(1920), @(1080)],
            @[@(1920), @(1200)],
            @[@(2560), @(1440)],
            @[@(2560), @(1600)],
            @[@(2960), @(1848)],
            @[@(3840), @(2160)],
        ];
        for (NSArray<NSNumber *> *entry in standardModes) {
            NSUInteger w = entry[0].unsignedIntegerValue;
            NSUInteger h = entry[1].unsignedIntegerValue;
            id allocatedMode = ((KodmozMsgSendId)objc_msgSend)(modeClass, sel_registerName("alloc"));
            id standardMode = ((KodmozMsgSendIdULLD)objc_msgSend)(
                allocatedMode,
                sel_registerName("initWithWidth:height:refreshRate:"),
                w, h, (CGFloat)refreshRate);
            if (standardMode) [modes addObject:standardMode];
        }
        // İstenen çözünürlük listede yoksa ekle.
        BOOL requestedAlreadyPresent = NO;
        for (id candidate in modes) {
            if ([[candidate valueForKey:@"width"] unsignedIntegerValue] == widthPixels &&
                [[candidate valueForKey:@"height"] unsignedIntegerValue] == heightPixels) {
                requestedAlreadyPresent = YES;
                break;
            }
        }
        if (!requestedAlreadyPresent) {
            id allocatedMode = ((KodmozMsgSendId)objc_msgSend)(modeClass, sel_registerName("alloc"));
            id requestedMode = ((KodmozMsgSendIdULLD)objc_msgSend)(
                allocatedMode,
                sel_registerName("initWithWidth:height:refreshRate:"),
                (NSUInteger)widthPixels,
                (NSUInteger)heightPixels,
                (CGFloat)refreshRate);
            if (requestedMode) [modes addObject:requestedMode];
        }

        id selectedMode = modes.firstObject;
        for (id candidate in modes) {
            if ([[candidate valueForKey:@"width"] unsignedIntegerValue] == widthPixels &&
                [[candidate valueForKey:@"height"] unsignedIntegerValue] == heightPixels) {
                selectedMode = candidate;
                break;
            }
        }

        [settings setValue:modes forKey:@"modes"];

        NSLog(@"[KodmozScreen] ayarlar: hiDPI=%@, istenen=%ux%u, mod sayısı=%@",
              [settings valueForKey:@"hiDPI"], widthPixels, heightPixels,
              @([[settings valueForKey:@"modes"] count]));

        BOOL applied = ((KodmozMsgSendBoolId)objc_msgSend)(
            display, sel_registerName("applySettings:"), settings);
        NSLog(@"[KodmozScreen] applySettings: %d, ekran modları: %@",
              applied, [display valueForKey:@"modes"]);
        if (!applied) {
            NSLog(@"[KodmozScreen] applySettings: başarısız");
            return NULL;
        }

        unsigned int displayID = [[display valueForKey:@"displayID"] unsignedIntValue];
        if (displayID == kCGNullDirectDisplay) {
            NSLog(@"[KodmozScreen] geçersiz displayID");
            return NULL;
        }

        KodmozVirtualDisplayHandle *handle = calloc(1, sizeof(KodmozVirtualDisplayHandle));
        if (!handle) return NULL;
        handle->display = (__bridge_retained void *)display;
        if (outDisplayID) *outDisplayID = displayID;

        NSLog(@"[KodmozScreen] sanal ekran hazır: id=%u, %ux%u, hiDPI=%u",
              displayID, widthPixels, heightPixels, hiDPI);
        return handle;
    }
    @catch (NSException *exception) {
        NSLog(@"[KodmozScreen] sanal ekran hatası: %@", exception);
        return NULL;
    }
}

void KodmozVirtualDisplayDestroy(KodmozVirtualDisplayHandle *handle)
{
    if (!handle) return;
    if (handle->display) {
        id display = (__bridge_transfer id)handle->display;
        (void)display; // ARC kapsam dışına çıkınca bırakır.
        handle->display = NULL;
    }
    free(handle);
}
