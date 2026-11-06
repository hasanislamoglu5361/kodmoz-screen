#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Elle tutulan sanal ekran nesnesi.
typedef struct KodmozVirtualDisplayHandle KodmozVirtualDisplayHandle;

/// macOS'un özel CGVirtualDisplay API'si ile sanal bir ekran oluşturur.
///
/// - Parameters:
///   - name:      Sistem Ayarları > Ekranlar listesinde görünen ad.
///   - widthPixels/heightPixels: Ekranın piksel çözünürlüğü.
///   - refreshRate: Yenileme hızı (genelde 60).
///   - hiDPI: 1 ise arayüz piksellerin yarısı kadar nokta kullanır (Retina).
///   - outDisplayID: Oluşturulan CGDirectDisplayID.
/// - Returns: Başarısızsa NULL (API yoksa veya ekran oluşmazsa).
KodmozVirtualDisplayHandle *KodmozVirtualDisplayCreate(
    const char *name,
    uint32_t widthPixels,
    uint32_t heightPixels,
    double refreshRate,
    uint32_t hiDPI,
    uint32_t *outDisplayID);

/// Sanal ekranı serbest bırakır; ekran sistemden kalkar.
void KodmozVirtualDisplayDestroy(KodmozVirtualDisplayHandle *handle);

#ifdef __cplusplus
}
#endif
