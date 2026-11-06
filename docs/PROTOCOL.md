# Kodmoz Screen tel protokolü (v1)

Bu belge Mac sunucusu (`StreamServer.swift`) ile Android istemcisi
(`StreamClient.kt`) arasındaki ikili protokolü tanımlar. Tüm çok baytlı
tamsayılar **big-endian**'dır.

- Taşıma: TCP, varsayılan port **9280**.
- Tek istemci; yeni bağlantı eskisini kapatır.
- Bonjour servis türü: `_kodmoz-screen._tcp`.

## 1. El sıkışma

İstemci bağlandıktan hemen sonra:

| Alan | Boyut | Değer |
|---|---:|---|
| Sihirli sayı | 8 | `KODMOZSC` (ASCII) |
| Sürüm | 1 | `1` |
| Ayrılmış | 3 | `0` |
| JSON uzunluğu | 4 | `uint32` |
| JSON | değişken | UTF-8 |

İstemci JSON'u:

```json
{
  "protocol": 1,
  "device": "SM-X710",
  "code": "4821",
  "width": 2560,
  "height": 1600,
  "fps": 60
}
```

`code`, Mac'te eşleşme kodu açıksa zorunludur. `width`/`height`/`fps`
bilgilendirme amaçlıdır; çözünürlüğü Mac belirler.

Sunucu yanıtı aynı 16 baytlık başlıkla başlar, ardından JSON gelir:

```json
{
  "protocol": 1,
  "ok": true,
  "width": 2560,
  "height": 1600,
  "fps": 60,
  "bitrate": 20000000,
  "codec": "avc",
  "sps": "AAAAASdNADOr...",
  "pps": "AAAAASjOPIA=",
  "display": "Kodmoz Screen",
  "scale": 2,
  "server": "1.0.0"
}
```

- `sps` / `pps`: **Annex-B başlangıç kodu (`00 00 00 01`) dahil** NAL
  birimlerinin base64 hâli. Android bunları `csd-0` / `csd-1` olarak kullanır.
- `scale`: nokta→piksel ölçeği (Retina için 2).
- Sunucu, istemci bağlandığında bir anahtar kare zorlar. Yanıt, o kare hazır
  olmadan gönderilmez. Bu nedenle istemci yanıtı 10 saniye içinde alamazsa
  bağlantıyı kapatmalıdır.

Hata durumunda sunucu, el sıkışma JSON'u yerine normal bir çerçeve (tür 6)
gönderip bağlantıyı kapatır:

```json
{ "message": "Eşleşme kodu hatalı...", "code": "badCode" }
```

Olası `code` değerleri: `badMagic`, `badVersion`, `badJSON`, `badHello`,
`badCode`, `timeout`, `noVideo`.

## 2. Çerçeveler

El sıkışmadan sonra her iki yön de 8 baytlık başlık + yük kullanır:

| Alan | Boyut | Açıklama |
|---|---:|---|
| Tür | 1 | Aşağıdaki tablo |
| Bayraklar | 1 | Mesaja özel |
| Ayrılmış | 2 | `0` |
| Yük uzunluğu | 4 | `uint32`, en fazla 8 MiB |

| Tür | Ad | Yön | Yük |
|---:|---|---|---|
| 1 | Video | Mac → tablet | H.264 Annex-B erişim birimi |
| 2 | Girdi | tablet → Mac | Aşağıdaki girdi olayı |
| 3 | Ping | tablet → Mac | 8 bayt `int64` zaman damgası (ns) |
| 4 | Pong | Mac → tablet | Ping yükünün aynısı |
| 5 | İstatistik | Mac → tablet | JSON |
| 6 | Hata | Mac → tablet | `{message, code}` JSON |
| 7 | Kapanış | iki yön | boş |

### Video bayrakları

| Bit | Ad | Anlam |
|---:|---|---|
| 0 | `KEYFRAME` | Yük bir IDR anahtar karesi |
| 1 | `CONFIG` | Yükün başında SPS/PPS NAL'ları var |

Video yükü Annex-B'dir: her NAL `00 00 00 01` ile başlar. Anahtar karelerde
SPS ve PPS, IDR'den önce tekrar gönderilir; böylece istemci akışa herhangi bir
noktada katılabilir. Kare hızı hedefi 60 fps, anahtar kare aralığı 2 saniyedir.
ScreenCaptureKit yalnızca değişimde kare ürettiği için hareketsiz masaüstünde
kare hızı düşer.

### İstatistik (tür 5)

```json
{ "fps": 59.8, "mbps": 14.2, "width": 2560, "height": 1600 }
```

Sunucu her saniye gönderir; aynı zamanda canlılık sinyalidir.

## 3. Girdi olayları (tür 2)

İlk bayt olay türüdür.

### 3.1 Hareket — `0`

| Alan | Boyut | Açıklama |
|---|---:|---|
| Tür | 1 | `0` |
| x | 2 | `uint16`, 0…65535 normalize |
| y | 2 | `uint16`, 0…65535 normalize |

x/y, sanal ekranın sol üst köşesine göre normalize edilmiştir; Mac bunu
`CGDisplayBounds` ile gerçek noktaya çevirir.

### 3.2 Düğme — `1`

| Alan | Boyut | Açıklama |
|---|---:|---|
| Tür | 1 | `1` |
| x | 2 | `uint16` |
| y | 2 | `uint16` |
| Düğme | 1 | `0` sol, `1` sağ, `2` orta |
| Basılı | 1 | `1` bas, `0` bırak |
| Tık sayısı | 1 | `1` tek, `2` çift |
| Ayrılmış | 1 | `0` |

### 3.3 Kaydırma — `2`

| Alan | Boyut | Açıklama |
|---|---:|---|
| Tür | 1 | `2` |
| dx | 2 | `int16`, piksel |
| dy | 2 | `int16`, piksel |

Mac tarafı doğal kaydırma ayarını uygular.

### 3.4 Tuş — `3`

| Alan | Boyut | Açıklama |
|---|---:|---|
| Tür | 1 | `3` |
| Android tuş kodu | 2 | `uint16` (`KeyEvent.KEYCODE_*`) |
| Basılı | 1 | `1` / `0` |
| Meta | 1 | bit 0 Shift, 1 Ctrl, 2 Alt, 3 Command |

Mac yalnızca tanıdığı kodları eşler (Enter, Tab, Esc, Backspace, yön tuşları,
Caps Lock). Diğer karakterler için metin olayı kullanılır.

### 3.5 Metin — `4`

| Alan | Boyut | Açıklama |
|---|---:|---|
| Tür | 1 | `4` |
| UTF-8 metin | değişken | Unicode |

Mac, metni `CGEvent.keyboardSetUnicodeString` ile etkin pencereye yazar.

## 4. Yeniden bağlanma ve çözünürlük değişimi

- Bağlantı koparsa istemci 0,5 s'den başlayıp 8 s'ye kadar artan gecikmeyle
  yeniden dener.
- Hatalı eşleşme kodunda (`badCode`) otomatik deneme yapılmaz; kullanıcı kodu
  düzeltmelidir.
- Mac'te çözünürlük değişirse sunucu hattı yeniden başlatır ve istemciyi
  düşürür; istemci yeni el sıkışmayla yeni boyutu ve SPS/PPS'i alır.
- TCP geri baskısı: 6 MB'tan fazla gönderim birikirse anahtar olmayan kareler
  atlanır. Anahtar kareler her zaman gönderilir.
