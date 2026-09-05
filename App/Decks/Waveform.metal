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
    /// Durata di una battuta, in bin. Zero quando la traccia non ha ancora una griglia.
    float beatBins;
    /// Posizione del primo downbeat, in bin.
    float gridOffsetBins;
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

// La griglia ha **una corsia sua in cima**, e la forma d'onda si stringe sotto per farle posto.
//
// La prima versione disegnava i trattini sopra la waveform, ed è stata provata su un brano vero:
// quando la griglia è giusta i trattini cadono esattamente sull'attacco della cassa, che è dipinto
// quasi bianco e alto quanto tutta la vista — e ci spariscono dentro. Il risultato era una griglia
// che si vedeva solo dove non serviva, sopra il silenzio, e diventava invisibile proprio nei
// passaggi pieni dove si va a controllare se il pezzo è a tempo.
//
// Nella corsia lo sfondo è sempre scuro, quindi i trattini si leggono sempre. Sopra la waveform
// resta una linea di misura tenue, che serve a seguire l'occhio senza coprire niente.
constant float3 kBarLineColor = float3(1.0, 1.0, 1.0);
constant float3 kBeatLineColor = float3(0.72, 0.75, 0.82);
constant float3 kGridLaneBackground = float3(0.12, 0.12, 0.15);
/// Altezza della corsia, in pixel del drawable: su uno schermo Retina sono 7 punti.
constant float kGridLaneHeight = 14.0;
/// Quanto della corsia occupa un trattino di battuta, misurato dal basso: l'uno della misura la
/// riempie tutta, gli altri quarti no, ed è così che si distinguono a colpo d'occhio.
constant float kBeatTickFraction = 0.55;
/// Opacità della linea di misura che continua sotto, dentro la waveform.
constant float kBarGuideOpacity = 0.22;
/// Sotto questa distanza in pixel due linee si impastano e la griglia diventa una campitura: le
/// battute spariscono per prime, poi le misure. È lo stesso comportamento della griglia di
/// rekordbox quando si allarga la vista.
constant float kMinimumLineSpacing = 5.0;

/// Distanza in pixel dalla linea di griglia più vicina, e a che battuta appartiene.
struct GridHit {
    float distance;
    int beat;
};

GridHit nearestGridLine(float pixelBin, float beatBins, float binsPerPixel) {
    float beat = pixelBin / beatBins;
    float nearest = round(beat);
    GridHit hit;
    hit.distance = fabs(beat - nearest) * beatBins / binsPerPixel;
    hit.beat = int(nearest);
    return hit;
}

fragment float4 waveformFragment(VertexOut in [[stage_in]],
                                 const device WaveformBin *bins [[buffer(0)]],
                                 constant WaveformUniforms &uniforms [[buffer(1)]],
                                 const device WaveformMarker *markers [[buffer(2)]]) {
    float columnStart = uniforms.startBin + in.uv.x * uniforms.pixelWidth * uniforms.binsPerPixel;
    float columnEnd = columnStart + uniforms.binsPerPixel;

    // Senza griglia non c'è corsia e la forma d'onda si prende tutta l'altezza, come prima.
    float laneHeight = (uniforms.beatBins > 0.0) ? kGridLaneHeight : 0.0;
    float waveHeight = max(uniforms.pixelHeight - laneHeight, 1.0);
    float waveCenter = laneHeight + waveHeight * 0.5;

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
        // Coordinata verticale della forma d'onda: +1 in cima, −1 in fondo, dentro la sola parte
        // che le resta sotto la corsia della griglia.
        float y = (waveCenter - in.uv.y * uniforms.pixelHeight) / (waveHeight * 0.5);
        float aa = max(fwidth(y), 1e-4);
        float top = max(maximum * uniforms.amplitudeScale, aa);
        float bottom = min(minimum * uniforms.amplitudeScale, -aa);

        float inside = smoothstep(-aa, aa, y - bottom) * smoothstep(-aa, aa, top - y);
        color = mix(kBackground, bandColor(low, mid, high), inside);

        float center = 1.0 - smoothstep(0.0, aa, abs(y));
        color = mix(color, kCenterLine, center * (1.0 - inside));
    }

    float pixelX = in.uv.x * uniforms.pixelWidth;
    float pixelY = in.uv.y * uniforms.pixelHeight;
    float binsPerPixel = max(uniforms.binsPerPixel, 1e-6);

    // La corsia della griglia, e la linea di misura che prosegue tenue sotto.
    if (uniforms.beatBins > 0.0) {
        if (pixelY < laneHeight) {
            color = kGridLaneBackground;
        }

        float beatSpacing = uniforms.beatBins / binsPerPixel;
        float barSpacing = beatSpacing * 4.0;
        float pixelBin = columnStart - uniforms.gridOffsetBins;
        GridHit hit = nearestGridLine(pixelBin, uniforms.beatBins, binsPerPixel);
        // Il resto va preso positivo: prima del primo downbeat gli indici di battuta sono
        // negativi, e in C il resto di un negativo è negativo.
        int inBar = ((hit.beat % 4) + 4) % 4;
        bool isBar = inBar == 0;

        bool visible = isBar ? (barSpacing >= kMinimumLineSpacing)
                             : (beatSpacing >= kMinimumLineSpacing);
        if (visible) {
            float line = 1.0 - smoothstep(0.5, 1.5, hit.distance);

            if (pixelY < laneHeight) {
                float top = isBar ? 0.0 : laneHeight * (1.0 - kBeatTickFraction);
                float inside = pixelY >= top ? 1.0 : 0.0;
                float3 tint = isBar ? kBarLineColor : kBeatLineColor;
                color = mix(color, tint, line * inside);
            } else if (isBar) {
                color = mix(color, kBarLineColor, line * kBarGuideOpacity);
            }
        }
    }

    // I marker passano sopra la waveform, per tutta l'altezza. La testina invece è un overlay
    // SwiftUI e finisce comunque sopra a questi.
    //
    // Si disegnano nell'ordine in cui arrivano, quindi l'ultimo vince dove due si sovrappongono:
    // il cue di lavoro sta in fondo alla lista proprio per questo.
    for (uint index = 0; index < uniforms.markerCount; ++index) {
        float4 marker = markers[index].binAndColor;
        float markerX = (marker.x - uniforms.startBin) / binsPerPixel;
        float distance = fabs(pixelX - markerX);

        float line = 1.0 - smoothstep(1.0, 2.0, distance);
        // La bandierina scende sotto la corsia della griglia, altrimenti le si sovrapporrebbe.
        float flag = (pixelY >= laneHeight && pixelY < laneHeight + kMarkerFlagHeight)
            ? 1.0 - smoothstep(kMarkerFlagHalfWidth, kMarkerFlagHalfWidth + 1.0, distance)
            : 0.0;
        color = mix(color, marker.yzw, max(line, flag));
    }

    return float4(color, 1.0);
}
