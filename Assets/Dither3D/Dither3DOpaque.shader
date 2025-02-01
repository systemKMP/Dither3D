/*
 * Copyright (c) 2025 Rune Skovbo Johansen
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

Shader "Dither 3D/Opaque"
{
    Properties
    {
        _Color ("Color", Color) = (1,1,1,1)
        _MainTex ("Albedo", 2D) = "white" {}
        _BumpMap ("Normal Map", 2D) = "bump" {}
        _EmissionMap ("Emission", 2D) = "white" {}
        _EmissionColor ("Emission Color", Color) = (0,0,0,0)
        _Glossiness ("Smoothness", Range(0,1)) = 0.5
        _Metallic ("Metallic", Range(0,1)) = 0.0

        [Header(Dither Input Brightness)]
        _InputExposure ("Exposure", Range(0,5)) = 1
        _InputOffset ("Offset", Range(-1,1)) = 0

        [Header(Dither Settings)]
        _DitherTex ("Dither 3D Texture", 3D) = "white" {}
        _NoiseTex ("Noise 3D Texture", 3D) = "white" {}

        _Density ("Pattern density", Range(0.01,5)) = 1.0
        
        _Scale ("Dot Scale", Range(2,10)) = 5.0
        _SizeVariability ("Dot Size Variability", Range(0,1)) = 0
        _Contrast ("Dot Contrast", Range(0,2)) = 1
        _StretchSmoothness ("Stretch Smoothness", Range(0,2)) = 1
    }
    SubShader
    {
        Tags
        {
            "RenderType"="Opaque"
        }
        LOD 200

        CGPROGRAM
        // Physically based Standard lighting model, and enable shadows on all light types
        #pragma surface surf Standard fullforwardshadows vertex:vert finalcolor:mycolor

        #pragma target 3.5
        #pragma multi_compile_fog
        #pragma shader_feature RADIAL_COMPENSATION
        #pragma shader_feature QUANTIZE_LAYERS
        #pragma shader_feature DEBUG_FRACTAL

        #include "Dither3DInclude.cginc"

        sampler2D _MainTex;
        sampler2D _BumpMap;
        sampler2D _EmissionMap;
        sampler3D _NoiseTex;

        struct Input
        {
            float2 uv_MainTex;
            float2 uv_BumpMap;
            float2 uv_EmissionMap;
            float2 uv_DitherTex;
            float4 screenPos;
            float3 worldPos;
            UNITY_FOG_COORDS(4)
        };

        half _Glossiness;
        half _Metallic;
        fixed4 _Color;
        fixed4 _EmissionColor;
        
        half _Density;

        void vert(inout appdata_full v, out Input o)
        {
            UNITY_INITIALIZE_OUTPUT(Input, o);
            float3 clipPos = UnityObjectToClipPos(v.vertex);
            o.worldPos = mul(unity_ObjectToWorld, v.vertex);
            UNITY_TRANSFER_FOG(o, clipPos);
        }

        void surf(Input IN, inout SurfaceOutputStandard o)
        {
            fixed4 c = tex2D(_MainTex, IN.uv_MainTex) * _Color;
            o.Albedo = c.rgb;
            o.Normal = UnpackNormal(tex2D(_BumpMap, IN.uv_BumpMap));
            o.Emission = tex2D(_EmissionMap, IN.uv_EmissionMap) * _EmissionColor;

            o.Metallic = _Metallic;
            o.Smoothness = _Glossiness;
            o.Alpha = c.a;
        }

        float2 rot(float2 coord, float angle)
        {
            return float2(sin(angle) * coord.x + cos(angle) * coord.y, cos(angle) * coord.x - sin(angle) * coord.y);
        }

        float noise(float3 pos)
        {
            float3 offsetCoords = pos;
            offsetCoords.xy = rot(offsetCoords.xy, 0.24575f);
            offsetCoords.yz = rot(offsetCoords.yz, 0.71346f);
            offsetCoords.zx = rot(offsetCoords.zx, 1.93317f);

            float3 lookupOffset = tex3D(_NoiseTex, offsetCoords);

            return tex3D(_NoiseTex, pos + lookupOffset).r;
        }


        float4 Get3DNoiseDither(float3 p, float brightness, float distance)
        {
            float scaler = log2(distance);

            float f1 = floor(scaler);
            float f2 = f1 + 1;

            float frac;
            if (scaler >= 0)
            {
                frac = scaler % 1.0f;
            }
            else
            {
                frac = 1.0f - -scaler % 1.0f;
            }

            float n1 = noise(p / pow(2, f1));
            float n2 = noise(p / pow(2, f2));

            brightness = pow(brightness, _InputExposure) + _InputOffset;

            float n = (n1 * (1.0 - frac) + n2 * frac) < brightness ? 1 : 0;

            return float4(_Color.xyz * n, _Color.a);
        }

        //https://www.chilliant.com/rgb2hsv.html
        float Epsilon = 1e-10;

        float3 RGBtoHCV(in float3 RGB)
        {
            // Based on work by Sam Hocevar and Emil Persson
            float4 P = (RGB.g < RGB.b) ? float4(RGB.bg, -1.0, 2.0 / 3.0) : float4(RGB.gb, 0.0, -1.0 / 3.0);
            float4 Q = (RGB.r < P.x) ? float4(P.xyw, RGB.r) : float4(RGB.r, P.yzx);
            float C = Q.x - min(Q.w, Q.y);
            float H = abs((Q.w - Q.y) / (6 * C + Epsilon) + Q.z);
            return float3(H, C, Q.x);
        }

        float3 RGBtoHSV(in float3 RGB)
        {
            float3 HCV = RGBtoHCV(RGB);
            float S = HCV.y / (HCV.z + Epsilon);
            return float3(HCV.x, S, HCV.z);
        }

        half Brightness(in float3 color)
        {
            return RGBtoHSV(color).z;
        }

        void mycolor(Input IN, SurfaceOutputStandard o, inout fixed4 color)
        {
            UNITY_APPLY_FOG(IN.fogCoord, color);

            color.a = 1.0f;
            float distance = length(IN.worldPos - _WorldSpaceCameraPos);

            // color = GetDither3D(IN.uv_DitherTex, IN.screenPos, GetGrayscale(color));
            color = Get3DNoiseDither(IN.worldPos, Brightness(color), distance / _Density);
        }
        ENDCG
    }
    FallBack "Diffuse"
}