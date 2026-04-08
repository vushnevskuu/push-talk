import Foundation

/// Metal source compiled at runtime — SwiftPM does not compile `.metal` in executable targets.
/// Full-width flame field + `pack4` for Reduce Motion, chroma cap, intensity ceiling (design guides).
enum FlameShaderSource {
    static let metal: String = """
    #include <metal_stdlib>
    using namespace metal;

    struct FlameUniforms {
        float4 pack0;
        float4 pack1;
        float4 pack2;
        float4 pack3;
        // x: reducedMotion 0/1, y: chromaRetention, z: rgbCap, w: timeScale when reduced
        float4 pack4;
        // x: windDownPhase 0..1, y: releaseSmoke 0..1
        float4 pack5;
    };

    struct VSOut {
        float4 position [[position]];
        float2 uv;
    };

    static float hash21(float2 p) {
        float3 p3 = fract(float3(p.xyx) * 0.1031);
        p3 += dot(p3, p3.yzx + 33.33);
        return fract((p3.x + p3.y) * p3.z);
    }

    static float vnoise(float2 p) {
        float2 i = floor(p);
        float2 f = fract(p);
        float2 u = f * f * (3.0 - 2.0 * f);
        float a = hash21(i);
        float b = hash21(i + float2(1, 0));
        float c = hash21(i + float2(0, 1));
        float d = hash21(i + float2(1, 1));
        return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
    }

    static float fbm(float2 p, float midBoost) {
        float v = 0.0;
        float a = 0.5;
        float2 pp = p;
        for (int i = 0; i < 4; i++) {
            v += a * vnoise(pp);
            pp = pp * 2.03 + float2(0.15, 0.22);
            a *= 0.5;
        }
        if (midBoost > 0.45) {
            v += 0.12 * vnoise(pp * 2.7);
        }
        return v;
    }

    // Огонь: насыщенные оранжи/жёлтые; белый только узко у самых горячих кончиков — без молочной дымки.
    static float3 firePalette(float yN, float heat, float blueCore) {
        float3 deep = mix(float3(0.045, 0.034, 0.065), float3(0.11, 0.13, 0.38), blueCore);
        float3 outer = float3(0.72, 0.14, 0.035);
        float3 mid = float3(0.96, 0.42, 0.085);
        float3 core = float3(0.99, 0.86, 0.52);
        float3 hotTip = float3(1.0, 0.94, 0.72);

        float3 c = mix(deep, outer, smoothstep(0.0, 0.24, yN) * heat);
        c = mix(c, mid, smoothstep(0.10, 0.48, yN) * heat);
        float3 yellowOrange = float3(0.99, 0.76, 0.18);
        float yBand = smoothstep(0.24, 0.40, yN) * (1.0 - smoothstep(0.50, 0.68, yN));
        c = mix(c, yellowOrange, yBand * heat * 0.40);
        c = mix(c, core, smoothstep(0.36, 0.88, yN) * heat);
        float coreLift = smoothstep(0.68, 0.96, yN) * saturate(heat - 0.52) * 1.25;
        c = mix(c, hotTip, coreLift * 0.34);
        float3 smoke = float3(0.042, 0.042, 0.048);
        c = mix(c, smoke, smoothstep(0.80, 1.0, yN) * 0.18);
        return c;
    }

    vertex VSOut flameVertex(uint vid [[vertex_id]]) {
        const float2 positions[4] = {
            float2(-1.0, -1.0), float2(1.0, -1.0), float2(-1.0, 1.0), float2(1.0, 1.0)
        };
        const float2 uvs[4] = { float2(0.0, 0.0), float2(1.0, 0.0), float2(0.0, 1.0), float2(1.0, 1.0) };
        VSOut o;
        o.position = float4(positions[vid], 0.0, 1.0);
        o.uv = uvs[vid];
        return o;
    }

    fragment float4 flameFragment(VSOut in [[stage_in]], constant FlameUniforms &u [[buffer(0)]]) {
        float time = u.pack0.x;
        float level = clamp(u.pack0.y, 0.0, 1.0);
        float peak = clamp(u.pack0.z, 0.0, 1.0);
        float speak = clamp(u.pack0.w, 0.0, 1.0);

        float lowB = clamp(u.pack1.x, 0.0, 1.0);
        float midB = clamp(u.pack1.y, 0.0, 1.0);
        float highB = clamp(u.pack1.z, 0.0, 1.0);
        float hGain = max(u.pack1.w, 0.05);

        float wGain = max(u.pack2.x, 0.05);
        float turbGain = max(u.pack2.y, 0.0);
        float idleI = clamp(u.pack2.z, 0.0, 0.45);
        float glowI = max(u.pack2.w, 0.0);

        float nScale = max(u.pack3.x, 0.08);
        float nSpeed = max(u.pack3.y, 0.05);
        float vw = max(u.pack3.z, 1.0);
        float vh = max(u.pack3.w, 1.0);

        float rm = clamp(u.pack4.x, 0.0, 1.0);
        float chromaR = clamp(u.pack4.y, 0.45, 1.0);
        float rgbCap = max(u.pack4.z, 0.62);
        float timeScaleRM = clamp(u.pack4.w, 0.06, 1.0);

        float windPhase = clamp(u.pack5.x, 0.0, 1.0);
        float releaseSmoke = clamp(u.pack5.y, 0.0, 1.0);
        float flameLife = max(0.22, 1.0 - windPhase * 0.88);
        float tongueLife = flameLife * mix(0.55, 1.0, 0.35 + speak * 0.65);
        float shimmerLife = saturate(1.0 - windPhase * 0.95) * mix(0.4, 1.0, 0.3 + level * 0.7);

        float t = time * nSpeed * mix(1.0, timeScaleRM, rm);
        float detailMul = 1.0 - rm * 0.94;

        float x = clamp(in.uv.x, 0.0, 1.0);
        float y = clamp(in.uv.y, 0.0, 1.0);
        // Плоское панорамное плато по X: почти вся ширина на 1.0, без гаусса к центру; короткий мягкий спад у кромки.
        float dEdgePx = min(x, 1.0 - x);
        float edgeNorm = abs(x - 0.5) * 2.0;
        const float kPlateauTaper = 0.012;
        const float kPlateauFloor = 0.88;
        float plateauEnv = mix(kPlateauFloor, 1.0, smoothstep(0.0, kPlateauTaper, dEdgePx));
        // Слабый баррель (без сильного втягивания поля к центру).
        float barrelEdgeAtten = 1.0 - 0.42 * smoothstep(0.78, 1.0, edgeNorm);
        float xGlass = x;
        float glassBarrel = pow(xGlass - 0.5, 3.0) * 0.072 * detailMul * barrelEdgeAtten;
        float xd = clamp(xGlass + glassBarrel, 0.002, 0.998);
        float lensShearY = (x - 0.5) * 0.038 * (1.0 - y * 0.45) * detailMul;
        float ySample = clamp(y + lensShearY, 0.002, 0.998);
        float aspect = vw / max(vh, 1.0);
        float xFreq = mix(1.0, 1.45, min(aspect / 5.5, 1.0)) * wGain;

        float warp = (fbm(float2(xd * 4.8 * nScale * xFreq, ySample * 6.5 + t * 0.35), midB) - 0.5)
            * 0.047 * (0.45 + midB) * (0.35 + level * 0.85) * detailMul;
        float xw = clamp(xd + warp, 0.002, 0.998);

        float idleBreath = idleI * (0.62 + 0.38 * sin(t * 1.78));
        float Hcore = mix(0.10, 0.94, level * hGain);
        Hcore += idleBreath * (0.07 + 0.06 * (1.0 - level));
        Hcore += lowB * (0.09 + level * 0.16 + idleI * 0.08);
        Hcore = clamp(Hcore, 0.085, 1.02);

        float s1 = fbm(float2(xw * 2.7 * xFreq + 11.0, t * 0.26), midB);
        float s2 = fbm(float2(xw * 7.2 * xFreq - 3.0, t * 0.38), midB) * (0.5 + 0.5 * midB);
        float roll = sin(xw * (6.28318 * (1.1 + 1.4 * midB)) - t * (1.05 + midB * 1.6 + level * 1.1)) * 0.09 * detailMul;
        float roll2 = sin(xw * 14.5 * xFreq + t * 2.65 + s2 * 5.0) * 0.048 * (0.5 + level + midB * 0.45) * detailMul;
        float asym = (s1 - 0.5) * 0.212 * (0.45 + level * 0.95) * detailMul;

        float Hcol = Hcore * (0.64 + 0.2 * s1 + 0.16 * s2 + roll + roll2 + asym);
        Hcol = clamp(Hcol, 0.075, 1.04);

        float Hsmooth = Hcore * (0.76 + 0.14 * s1 + 0.1 * s2);
        Hcol = mix(Hcol, Hsmooth, rm * 0.9);

        // Лёгкая панорамная рябь по X (без усиления к центру — одна низкая синусоида).
        float panBand = 0.97 + 0.033 * sin(xw * 6.28318 * 2.05 + t * 0.55 + midB * 0.4);
        Hcol *= panBand;
        Hcol = clamp(Hcol, 0.07, 1.08);

        float pN1 = fbm(float2(xw * 18.0 * xFreq, t * 6.8), 0.55);
        float pN2 = fbm(float2(xw * 32.0 + 60.0, t * 8.5), 0.5);
        float pk = peak * (0.085 + 0.28 * pN1 + 0.14 * sin(xw * 26.0 + t * 12.0) + 0.09 * sin(xw * 41.0 * xFreq - t * 15.0))
            * (0.5 + 0.5 * level) * detailMul;
        pk += peak * highB * 0.1 * pN2 * detailMul;
        Hcol += pk;

        float spread = level * (0.020 + 0.055 * midB) * sin(xw * 6.28318 * 2.0 - t * (2.8 + level * 5.8)) * detailMul;
        Hcol += spread;
        Hcol = clamp(Hcol, 0.07, 1.06);

        // Горизонтальная огибающая: ~97.6% ширины на полной активности, край лишь чуть тише (~88%).
        Hcol *= plateauEnv;

        // «Плечи» и края: реальная низкая структура по всей ширине (не только bloom).
        float lowBandY = smoothstep(0.0, 0.48, y) * (1.0 - smoothstep(0.62, 1.0, y));
        float shoulder = smoothstep(0.03, 0.48, edgeNorm) * (1.0 - smoothstep(0.80, 0.995, edgeNorm));
        float shoulderFlame = shoulder * lowBandY * detailMul * (0.022 + 0.042 * level + 0.036 * midB + 0.024 * lowB)
            * max(0.0, fbm(float2(xw * 11.2 * xFreq + 0.9, y * 8.6 - t * 2.45), midB) - 0.40);
        float edgeAmt = smoothstep(0.30, 0.98, edgeNorm);
        float sideLicks = edgeAmt * lowBandY * detailMul * (0.028 + 0.048 * level + 0.042 * midB + 0.026 * lowB)
            * (0.5 * fbm(float2(xw * 15.5 * xFreq + 3.1, y * 10.5 - t * 2.75), midB)
               + 0.42 * sin(xw * 17.8 * xFreq - t * 3.35) * sin(y * 17.0 + t * 2.05));
        float sideWisps = edgeAmt * detailMul * (0.012 + 0.024 * highB + 0.016 * level)
            * sin(xw * 23.5 * xFreq + t * 4.1) * exp(-abs(y - 0.36) * 7.2);
        Hcol += shoulderFlame + sideLicks + sideWisps;
        Hcol = clamp(Hcol, 0.07, 1.12);

        float turbRoll = (0.026 + midB * turbGain * 0.48 * (0.32 + level * 0.95)) * detailMul
            * (fbm(float2(xw * 5.5 * xFreq + 1.8, y * 14.0 - t * 1.7), midB) - 0.48);
        turbRoll += midB * level * 0.04 * (fbm(float2(xw * 11.0, y * 9.0 - t * 2.2), midB) - 0.5) * detailMul;

        float turbFine = (0.010 + highB * 0.14) * detailMul
            * (fbm(float2(xw * 26.5 * xFreq, y * 30.0 + t * 4.8), highB) - 0.5);
        float flick = (0.0045 + highB * 0.06) * sin(t * 20.0 + xw * 58.0 + y * 52.0)
            * (0.5 + highB + level * 0.4) * detailMul;

        // Языки: чётче у верхней кромки, без размытия всего фронта в одну дугу.
        float topShape = smoothstep(0.10, 0.76, y);
        float topCrown = smoothstep(0.48, 0.92, y);
        float curlA = sin(xw * 22.0 * xFreq + t * 5.1 + s1 * 9.0) * cos(xw * 15.0 * xFreq - t * 3.6 + s2 * 6.0);
        float tongueCurl = curlA * (0.048 + 0.062 * level + 0.048 * midB) * detailMul * topShape * tongueLife * (1.0 + 0.22 * topCrown);
        float tongueSplit = sin(xw * 28.0 * xFreq + t * 5.8) * sin(xw * 11.5 * xFreq - t * 2.5 + midB * 3.0)
            * (0.030 + 0.050 * level) * detailMul * topShape * tongueLife * (1.0 + 0.28 * topCrown);
        float tongueMerge = fbm(float2(xw * 9.5 * xFreq, y * 13.0 - t * 3.3), midB);
        tongueMerge = (tongueMerge - 0.5) * (0.034 + 0.044 * level) * detailMul * smoothstep(0.16, 0.74, y) * tongueLife;
        float tongueCollapse = -0.024 * detailMul * topShape * (0.35 + midB) * max(0.0, sin(t * 2.4 + xw * 18.0 * xFreq)) * tongueLife;
        float tongueOpen = sin(xw * 19.0 * xFreq + t * 4.4) * (0.022 + 0.038 * level) * detailMul * smoothstep(0.32, 0.90, y) * tongueLife * (1.0 + 0.35 * topCrown);
        float tongueFine = sin(xw * 38.0 * xFreq - t * 7.4 + s1 * 12.0) * (0.0175 + 0.034 * highB + 0.025 * level)
            * detailMul * topShape * tongueLife * (1.0 + 0.50 * topCrown);
        float tongueRip = sin(xw * 46.0 * xFreq + t * 8.2) * (0.0125 + 0.0225 * level) * detailMul * topCrown * tongueLife;

        float flameTop = Hcol + turbRoll + turbFine + flick + tongueCurl + tongueSplit + tongueMerge + tongueCollapse + tongueOpen + tongueFine + tongueRip;

        float tipJag = 0.46 + 0.98 * fbm(float2(xw * 24.0 * xFreq, t * 3.8), midB);
        float tipNotch = 0.52 + 0.65 * fbm(float2(xw * 33.0 * xFreq, t * 5.5), highB);
        float tipSoft = (0.0044 + highB * 0.024 + (1.0 - level) * 0.0053) * tipJag * mix(0.58, 1.04, tipNotch);
        float dTop = y - flameTop;
        float tipSharp = 0.22 + 0.31 * fbm(float2(xw * 36.0 * xFreq, t * 5.8), highB);
        float maskTop = 1.0 - smoothstep(-tipSoft, tipSoft * tipSharp, dTop);

        float baseChunk = 0.70 + 0.30 * fbm(float2(xw * 11.0 * xFreq + 1.7, 2.8 + lowB), lowB);
        float baseDepth = smoothstep(0.0, 0.20, y) * (1.0 - smoothstep(0.36, 0.55, y));
        float baseHot = 0.92 + 0.08 * fbm(float2(xw * 15.0 * xFreq, y * 10.0 - t * 1.6), midB);
        float baseRidge = 0.932 + 0.142 * (fbm(float2(xw * 17.5 * xFreq, y * 7.5 - t * 1.1), lowB) - 0.5);
        float baseEmber = smoothstep(0.0, 0.034, y) * (0.86 + 0.14 * lowB) * mix(0.84, 0.98, baseChunk)
            * mix(0.97, 1.02, baseDepth * (0.4 + 0.6 * lowB)) * mix(0.96, 1.02, baseHot) * baseRidge;
        // Углёвое ложе почти от края до края; микроспад только у самой кромки.
        float emberSpan = mix(1.0, 0.99, smoothstep(0.985, 1.0, edgeNorm));
        baseEmber *= emberSpan;
        float mask = maskTop * baseEmber;

        float featherTop = 1.0 - smoothstep(0.785, 0.995, y);
        mask *= plateauEnv * featherTop;

        // Тонкий тёпло-серый дым; усиливается по `releaseSmoke` при затухании после хоткея.
        float smokeRise = (y - flameTop);
        float smokeZone = smoothstep(0.016, 0.050, smokeRise) * (1.0 - smoothstep(0.095, 0.20, smokeRise));
        float smokeDrift = xw * 0.08 + releaseSmoke * 0.15;
        float smokeN = fbm(float2(xw * 6.9 * xFreq + t * 0.48 + smokeDrift, smokeRise * 17.0 - t * (1.65 + releaseSmoke * 0.5)), 0.36);
        float smokeBreath = mix(0.55, 1.0, 1.0 - speak);
        float smokeAlpha = smokeZone * (0.016 + 0.022 * (1.0 - rm)) * (0.2 + level * 0.48 + peak * 0.32) * smokeBreath
            * smokeN * smokeN * plateauEnv * smoothstep(0.28, 0.72, smokeN);
        smokeAlpha *= (1.0 + releaseSmoke * 2.1);
        smokeAlpha = clamp(smokeAlpha, 0.0, 0.11);
        float3 smokeTint = mix(float3(0.44, 0.43, 0.47), float3(0.52, 0.49, 0.46), 0.35 + releaseSmoke * 0.4);

        if (mask < 0.003) {
            if (smokeAlpha < 0.0012) {
                return float4(0.0);
            }
            return float4(smokeTint * smokeAlpha, smokeAlpha);
        }

        float yNraw = y / max(Hcol, 0.085);
        float heatShimAmp = (0.42 + peak * 0.58 + level * 0.5) * 0.015 * detailMul * mix(1.0, 0.32, rm) * shimmerLife;
        float heatBand = smoothstep(flameTop - 0.088, flameTop + 0.014, y) * (1.0 - smoothstep(flameTop + 0.026, flameTop + 0.16, y));
        float yHeatDisp = heatBand * heatShimAmp * sin(xw * 44.0 * xFreq + t * 11.5);
        float xHeatDisp = heatBand * heatShimAmp * 0.55 * sin(y * 72.0 + t * 15.0 + xw * 22.0 * xFreq);
        float yN = clamp(yNraw + yHeatDisp + xHeatDisp * 0.12, 0.0, 1.35);

        float inBody = 1.0 - smoothstep(flameTop - Hcol * 0.36, flameTop + 0.006, y);
        float heat = clamp(0.26 + speak * 0.75 + level * 0.65 + lowB * (1.0 - y) * 0.24, 0.0, 1.8);
        float heatLow = fbm(float2(xw * 10.0 * xFreq, y * 5.5 + t * 0.15), midB);
        float heatHi = fbm(float2(xw * 23.0 * xFreq, y * 14.0 - t * 1.9), midB);
        float heatMicro = fbm(float2(xw * 31.0 * xFreq, y * 21.0 + t * 2.4), highB);
        heat *= 0.86 + 0.20 * heatLow * (0.45 + level) * mix(1.0, 0.52, rm);
        heat *= 0.91 + 0.17 * (heatHi - 0.5) * inBody * (0.35 + midB) * mix(1.0, 0.4, rm);
        heat *= 0.97 + 0.06 * (heatMicro - 0.5) * inBody * mix(1.0, 0.45, rm);
        heat *= mix(0.985, 1.0, smoothstep(0.0, kPlateauTaper, dEdgePx));
        heat += (0.05 + 0.07 * lowB) * smoothstep(0.35, 1.0, edgeNorm) * (1.0 - y) * mix(1.0, 0.65, rm);
        heat = min(heat, mix(1.72, 1.12, rm));

        float3 col = firePalette(yN, heat, 0.26 + idleI * 0.88);

        float interior = 1.0 - smoothstep(flameTop - Hcol * 0.33, flameTop + 0.004, y);
        float coreSpotN = fbm(float2(xw * 27.0 * xFreq + 2.0, y * 19.0 - t * 2.8), midB);
        float coreSpot = smoothstep(0.58, 0.88, coreSpotN) * interior * smoothstep(0.26, 0.86, yN) * (0.3 + 0.7 * saturate(heat - 0.38));
        col = mix(col, float3(0.99, 0.90, 0.58), coreSpot * 0.22 * mix(1.0, 0.42, rm));
        float emberVar = smoothstep(0.0, 0.40, y) * (1.0 - smoothstep(0.48, 0.72, y));
        float emberDark = smoothstep(0.55, 0.88, fbm(float2(xw * 21.0 * xFreq, y * 8.0 - t * 1.3), midB)) * interior * emberVar;
        col = mix(col, float3(0.48, 0.10, 0.028), emberDark * 0.065 * mix(1.0, 0.5, rm));

        float coreGlow = interior * (0.24 + peak * 0.28 + level * 0.30 + lowB * 0.14);
        col += float3(0.20, 0.17, 0.14) * coreGlow * glowI * mix(1.0, 0.52, rm);
        float vein = fbm(float2(xw * 19.0 * xFreq, y * 11.0 - t * 2.2), midB);
        float veinMix = smoothstep(0.32, 0.58, vein) * interior * (0.28 + 0.42 * midB) * (1.0 - smoothstep(0.72, 1.0, yN));
        col = mix(col, float3(0.96, 0.44, 0.08), veinMix * 0.24 * mix(1.0, 0.48, rm));

        float hotSheen = interior * smoothstep(0.52, 0.94, yN) * saturate(heat - 0.50) * (0.28 + peak * 0.42);
        col = mix(col, float3(1.0, 0.92, 0.72), hotSheen * 0.22 * mix(1.0, 0.32, rm));

        float pocketN = fbm(float2(xw * 14.0 * xFreq, y * 8.5 - t * 1.9), midB);
        float darkPocket = smoothstep(0.58, 0.88, pocketN) * (1.0 - interior * 0.75) * (0.5 + midB * 0.5) * (0.55 + 0.45 * smoothstep(0.10, 0.52, yN));
        col = mix(col, float3(0.20, 0.04, 0.022), darkPocket * 0.34 * mix(1.0, 0.5, rm));

        float halo = exp(-max(0.0, dTop + 0.018) * (9.0 + (1.0 - level) * 5.5 + (1.0 - midB) * 2.0))
            * (0.075 + glowI * 0.22) * (0.22 + level * 0.45 + midB * 0.20) * mix(1.0, 0.48, rm);
        halo *= (1.0 - 0.52 * smoothstep(0.0, 0.24, y));
        halo *= (1.0 - 0.25 * smoothstep(-0.04, 0.08, dTop));
        col += float3(0.48, 0.12, 0.042) * halo;

        float edgeGlowY = smoothstep(0.0, 0.2, y) * (1.0 - smoothstep(0.45, 1.0, y));
        float edgeGlow = smoothstep(0.22, 1.0, edgeNorm) * edgeGlowY
            * (0.09 + 0.16 * lowB + 0.09 * midB) * glowI * mix(1.0, 0.68, rm);
        col += float3(0.38, 0.11, 0.035) * edgeGlow;

        float sparkCol = floor(xw * 118.0) + floor(y * 102.0) * 113.0;
        float sparkSeed = hash21(float2(sparkCol, floor(t * 3.6)));
        float sparkBirth = floor(t * 14.0 + sparkSeed * 6.0);
        float sparkLife = fract(t * 14.0 + sparkSeed * 6.0);
        float sparkRare = step(0.9984, hash21(float2(sparkCol, sparkBirth)));
        float sparkPulse = smoothstep(0.0, 0.12, sparkLife) * (1.0 - smoothstep(0.38, 0.72, sparkLife));
        float spark = sparkRare * sparkPulse * step(0.52, peak) * pow(peak, 2.2) * detailMul * (1.0 - windPhase * 0.92) * mix(1.0, 0.1, rm);
        col += float3(1.0, 0.96, 0.88) * spark * 0.85;

        float lu = dot(max(col, float3(1e-5)), float3(0.2126, 0.7152, 0.0722));
        col = mix(float3(lu), col, chromaR);
        col = min(col, float3(rgbCap));

        float alphaFire = mask * (0.24 + 0.78 * clamp(interior * 0.97 + halo * 0.62 + spark * 2.2, 0.0, 1.0));
        alphaFire = clamp(alphaFire, 0.0, 1.0);
        // Дым поверх огня: premul_out = firePremul * (1 - smokeA) + smokePremul
        float alphaOut = alphaFire + smokeAlpha * (1.0 - alphaFire);
        float3 premul = col * alphaFire * (1.0 - smokeAlpha) + smokeTint * smokeAlpha;
        return float4(premul, alphaOut);
    }
    """
}
