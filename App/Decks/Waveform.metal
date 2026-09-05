#include <metal_stdlib>
using namespace metal;

// Le stesse terne di WaveformPalette.swift. Se si cambiano lì vanno cambiate anche qui: il
// fragment shader mescola i colori per conto suo e non può leggere le costanti Swift.
constant float3 kLowColor = float3(0.16, 0.47, 0.98);
constant float3 kMidColor = float3(0.22, 0.80, 0.42);
constant float3 kHighColor = float3(0.98, 0.65, 0.16);
constant float3 kBackground = float3(0.07, 0.07, 0.09);
constant float3 kCenterLine = float3(0.20, 0.20, 0.23);
// Guadagni di presentazione delle bande: stesso valore di WaveformPalette.bandGain, e stesso
// motivo — senza, ogni waveform risulterebbe blu dall'inizio alla fine.
constant float3 kBandGain = float3(1.0, 3.0, 12.0);

/// Un bin della cache dei peaks, nello stesso ordine di campi di `WaveformRenderer.Bin`.
struct WaveformBin {
    float minimum;
    float maximum;
    float low;
    float mid;
    float high;
};

/// Tutte le posizioni sono espresse in **bin**, non in frame: un brano lungo arriva a 15 milioni
/// di frame, oltre la precisione di un `float`, mentre in bin sono al massimo qualche centinaio
/// di migliaia e la precisione resta abbondantemente sotto il sample.
struct WaveformUniforms {
    float startBin;
    float binsPerPixel;
    float pixelWidth;
    float pixelHeight;
    float amplitudeScale;
    uint binCount;
    uint markerCount;
};

/// Un marker di cue: `.x` è la posizione in bin, `.yzw` il colore.
///
/// Un `float4` invece di una struct con un `float3`: in Metal `float3` si allinea a 16 byte,
/// quindi `{float, float3}` diventerebbe 32 byte con un buco in mezzo, e il layout andrebbe
/// tenuto d'accordo a mano con Swift. Un `float4` è 16 byte da entrambe le parti e non c'è
/// niente da ricordare.
///
/// I marker si disegnano qui e non come overlay SwiftUI perché mentre il deck suona la waveform
/// scorre a 60 fps mentre la UI si aggiorna a 20: un overlay resterebbe indietro di qualche pixel
/// e sembrerebbe scollato. Calcolati dalle stesse uniform, sono inchiodati alla waveform per
/// costruzione.
struct WaveformMarker {
    float4 binAndColor;
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex VertexOut waveformVertex(uint vertexID [[vertex_id]]) {
    const float2 corners[4] = {
        float2(-1.0, -1.0), float2(1.0, -1.0), float2(-1.0, 1.0), float2(1.0, 1.0)
    };
    float2 corner = corners[vertexID];

    VertexOut out;
    out.position = float4(corner, 0.0, 1.0);
    out.uv = float2((corner.x + 1.0) * 0.5, (1.0 - corner.y) * 0.5);
    return out;
}

float3 bandColor(float low, float mid, float high) {
    float3 weighted = float3(low, mid, high) * kBandGain;
    float total = weighted.x + weighted.y + weighted.z;
    if (total < 1e-6) {
        return float3(0.35);
    }
    float3 mixed = kLowColor * (weighted.x / total)
                 + kMidColor * (weighted.y / total)
                 + kHighColor * (weighted.z / total);
    float peak = max(mixed.r, max(mixed.g, mixed.b));
    if (peak > 1e-6) {
        mixed *= 0.98 / peak;
    }
    return mixed;
}

/// Bandierina in cima al marker, in **pixel del drawable**: su uno schermo Retina sono 6 punti
/// di altezza e 4,5 di larghezza. È ciò che fa trovare un cue quando la waveform sotto è piena di
/// roba, e la linea da sola si perde.
constant float kMarkerFlagHeight = 12.0;
constant float kMarkerFlagHalfWidth = 4.5;

fragment float4 waveformFragment(VertexOut in [[stage_in]],
                                 const device WaveformBin *bins [[buffer(0)]],
                                 constant WaveformUniforms &uniforms [[buffer(1)]],
                                 const device WaveformMarker *markers [[buffer(2)]]) {
    float columnStart = uniforms.startBin + in.uv.x * uniforms.pixelWidth * uniforms.binsPerPixel;
    float columnEnd = columnStart + uniforms.binsPerPixel;

    int first = int(floor(columnStart));
    int last = max(first, int(ceil(columnEnd)) - 1);
    // I livelli distano 4× l'uno dall'altro, quindi in una colonna non cadono mai più di quattro
    // bin: il limite è solo una rete di sicurezza contro un ciclo lungo per errore di calcolo.
    last = min(last, first + 7);

    float minimum = 0.0;
    float maximum = 0.0;
    float low = 0.0;
    float mid = 0.0;
    float high = 0.0;
    bool covered = false;

    for (int index = first; index <= last; ++index) {
        if (index < 0 || index >= int(uniforms.binCount)) {
            continue;
        }
        WaveformBin bin = bins[index];
        minimum = min(minimum, bin.minimum);
        maximum = max(maximum, bin.maximum);
        low = max(low, bin.low);
        mid = max(mid, bin.mid);
        high = max(high, bin.high);
        covered = true;
    }

    // Fuori dalla traccia resta solo lo sfondo, così si vede dove il brano comincia e finisce.
    float3 color = kBackground;

    if (covered) {
        float y = 1.0 - in.uv.y * 2.0;
        float aa = max(fwidth(y), 1e-4);
        float top = max(maximum * uniforms.amplitudeScale, aa);
        float bottom = min(minimum * uniforms.amplitudeScale, -aa);

        float inside = smoothstep(-aa, aa, y - bottom) * smoothstep(-aa, aa, top - y);
        color = mix(kBackground, bandColor(low, mid, high), inside);

        float center = 1.0 - smoothstep(0.0, aa, abs(y));
        color = mix(color, kCenterLine, center * (1.0 - inside));
    }

    // I marker passano sopra la waveform, per tutta l'altezza. La testina invece è un overlay
    // SwiftUI e finisce comunque sopra a questi.
    //
    // Si disegnano nell'ordine in cui arrivano, quindi l'ultimo vince dove due si sovrappongono:
    // il cue di lavoro sta in fondo alla lista proprio per questo.
    float pixelX = in.uv.x * uniforms.pixelWidth;
    float pixelY = in.uv.y * uniforms.pixelHeight;
    float binsPerPixel = max(uniforms.binsPerPixel, 1e-6);

    for (uint index = 0; index < uniforms.markerCount; ++index) {
        float4 marker = markers[index].binAndColor;
        float markerX = (marker.x - uniforms.startBin) / binsPerPixel;
        float distance = fabs(pixelX - markerX);

        float line = 1.0 - smoothstep(1.0, 2.0, distance);
        float flag = (pixelY < kMarkerFlagHeight)
            ? 1.0 - smoothstep(kMarkerFlagHalfWidth, kMarkerFlagHalfWidth + 1.0, distance)
            : 0.0;
        color = mix(color, marker.yzw, max(line, flag));
    }

    return float4(color, 1.0);
}
