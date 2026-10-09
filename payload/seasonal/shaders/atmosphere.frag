#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float intensity;
    float speed;
    float direction;
    float warmth;
    float mode;
    float energy;
    float cornerRadius;
    vec2 extent;
    vec4 coldColor;
    vec4 warmColor;
    float time;
};
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
    vec2 i = floor(p), f = fract(p); f = f*f*(3.0 - 2.0*f);
    return mix(mix(hash(i), hash(i+vec2(1,0)), f.x), mix(hash(i+vec2(0,1)), hash(i+vec2(1,1)), f.x), f.y);
}
float mist(vec2 p) {
    return noise(p)*0.57 + noise(p*2.07+vec2(3.2,7.8))*0.28 + noise(p*4.11)*0.15;
}
void main() {
    vec2 uv = qt_TexCoord0;
    vec2 drift = vec2(sin(time), cos(time)) * speed * 1.5;
    vec2 p = uv * vec2(clamp(extent.x/max(extent.y, 1.0), 1.0, 12.0)*2.0, 2.8);
    float n = 0.0, folded = 0.0;
    if (mode < 1.5 || (mode >= 5.5 && mode < 6.5)) {
        n = mist(p + drift);
        folded = mist(p + vec2(n * 1.6, -n) - drift*0.4);
    }
    float alpha;
    vec3 light;
    if (mode < 0.5) {
        float side = direction > 0.0 ? uv.x : 1.0 - uv.x;
        float edge = (1.0 - smoothstep(0.05, 0.72, side)) * sin(uv.y * 3.141593);
        alpha = smoothstep(0.22, 0.8, folded) * edge * intensity;
        light = mix(coldColor.rgb, warmColor.rgb, warmth + n*0.12);
    } else if (mode < 1.5) {
        float source = exp(-pow((uv.x - 0.40) * 4.4, 2.0)) * 0.65
                     + exp(-pow((uv.x - 0.63) * 6.5, 2.0)) * 0.45;
        float rise = pow(uv.y, 2.8);
        float flicker = 0.88 + 0.07*sin(time*19.0) + 0.05*sin(time*31.0+1.4);
        float glow = source * rise * flicker;
        float vapor = smoothstep(0.38, 0.8, folded) * source * pow(uv.y, 1.3) * (1.0 - uv.y) * 1.6;
        alpha = (glow + vapor * 0.5) * intensity;
        light = mix(coldColor.rgb, warmColor.rgb, clamp(warmth * rise + glow * 0.4, 0.0, 1.0));
    } else if (mode < 2.5) {
        // Conductive filaments trace the edge, leaving control labels clear.
        vec2 px = uv * extent;
        float edge = min(min(px.x, extent.x-px.x), min(px.y, extent.y-px.y));
        float flow = sin(uv.x*9.0 + uv.y*7.0 - time*24.0);
        float turbulence = noise(vec2(uv.x*38.0,uv.y*31.0)+vec2(sin(time*8.0),cos(time*6.0))*2.0);
        float strand = exp(-pow((edge - 3.0 - turbulence*3.0) / 1.0, 2.0));
        float bloom = exp(-edge*0.14) * 0.15;
        alpha = (strand * (0.4+0.6*pow(max(flow,0.0),3.0)) + bloom) * intensity * (0.65+energy*0.35);
        light = mix(warmColor.rgb, coldColor.rgb, 0.5+flow*0.22);
    } else if (mode < 3.5) {
        // Three counterflowing filaments outside the album surface.
        vec2 q = (uv-0.5)*2.0;
        float radius = length(q), angle = atan(q.y,q.x);
        float ripple = sin(angle*5.0-time*14.0)*0.008 + sin(angle*9.0+time*8.0)*0.006;
        float ring = exp(-pow((radius-0.93-ripple-energy*0.018)/0.018,2.0));
        float outer = exp(-pow((radius-0.93)/0.07,2.0))*0.23;
        float arc = pow(0.5+0.5*sin(angle*3.0-time*12.0),2.0);
        alpha = (ring*(0.35+arc*0.65)+outer) * intensity;
        light = mix(warmColor.rgb,coldColor.rgb,arc*0.45);
    } else if (mode < 4.5) {
        float side = exp(-uv.x*18.0) + exp(-(1.0-uv.x)*18.0);
        float arc = sin(uv.y*17.0-time*19.0+noise(uv*9.0)*2.0);
        float thread = exp(-pow((abs(arc)-0.82)*12.0,2.0));
        alpha = side * (0.07+thread*0.28) * intensity * (0.6+energy*0.4);
        light = mix(coldColor.rgb,warmColor.rgb,warmth);
    } else if (mode < 5.5) {
        float sweep = (sin(time*6.0)+1.0)*0.85;
        float reflection = exp(-pow((uv.x+uv.y*0.40-sweep)*12.0,2.0));
        alpha = reflection * intensity * 0.35;
        light = mix(coldColor.rgb,warmColor.rgb,uv.y*warmth);
    } else if (mode < 6.5) {
        float band = pow(uv.y,7.0);
        float wave = 0.55+0.45*sin(uv.x*19.0-time*18.0+folded*3.0);
        alpha = band * wave * intensity * (0.6+energy*0.4);
        light = mix(warmColor.rgb,coldColor.rgb,(1.0-uv.y)*0.4);
    } else if (mode < 7.5) {
        vec2 q = (uv-0.5)*2.0;
        float radius = length(q), angle = atan(q.y,q.x);
        float wave = 0.5+0.5*sin(radius*42.0-time*26.0);
        float band = smoothstep(0.63,0.70,radius) * (1.0-smoothstep(0.95,1.0,radius));
        float orbit = pow(0.5+0.5*sin(angle*(energy>0.7 ? 2.0 : 3.0)-time*12.0),4.0);
        alpha = band * (pow(wave,12.0)*0.65 + orbit*0.25) * intensity;
        light = mix(coldColor.rgb,warmColor.rgb,warmth);
    } else if (mode < 8.5) {
        float sweep = energy * 1.9 - 0.45;
        float band = exp(-pow((uv.x + uv.y*0.35 - sweep) * 15.0, 2.0));
        float fade = sin(clamp(energy,0.0,1.0) * 3.141593);
        alpha = band * fade * intensity;
        light = mix(coldColor.rgb,warmColor.rgb,0.22);
    } else if (mode < 9.5) {
        // A luminous tear and three folded, tapering ribbons; no ghost icon.
        float center = 0.5 + sin(uv.x*9.0-energy*8.0)*(1.0-uv.x)*0.09;
        float width = 0.018 + uv.x*uv.x*0.075;
        float ribbon = exp(-pow((uv.y-center)/width,2.0)) * smoothstep(0.02,0.62,uv.x) * (1.0-smoothstep(0.72,0.85,uv.x));
        float fold = exp(-pow((uv.y-center-0.075*sin(uv.x*12.0+energy*6.0))/(width*0.65),2.0)) * 0.28;
        vec2 q=(uv-vec2(0.70,0.5))/vec2(0.11,0.15);
        float head=exp(-dot(q,q)*1.8);
        float haze=exp(-dot(q,q)*0.45)*0.16;
        alpha = (head+ribbon*0.44+fold*smoothstep(0.05,0.60,uv.x)*(1.0-smoothstep(0.65,0.85,uv.x))+haze)*intensity;
        light = mix(coldColor.rgb,vec3(0.96,0.97,1.0),head*0.90);
    } else {
        // A tapered flame, blue at the wick, ivory within, ember at its edges.
        // Several unequal frequencies prevent a uniform pulse or a rigid teardrop.
        float flicker = sin(time*117.0)*0.038 + sin(time*191.0+1.2)*0.025;
        float lean = sin(time*69.0)*0.075 + sin(time*143.0)*0.035;
        float h = clamp((0.93-uv.y)/0.82, 0.0, 1.0);
        float center = 0.5 + lean*h*h + sin(h*9.0-time*107.0)*h*0.035;
        float radius = (0.10+flicker*0.4) * pow(max(sin(h*3.141593),0.0),0.78) * (1.2-h*0.45);
        float distance = abs(uv.x-center);
        float flame = 1.0-smoothstep(radius*0.65, radius+0.016, distance);
        flame *= smoothstep(0.0,0.065,h)*(1.0-smoothstep(0.87+flicker,1.0,h));
        float core = exp(-pow(distance/max(radius*0.48,0.005),2.0))*(1.0-smoothstep(0.2,0.8,h));
        float bloom = exp(-pow((uv.x-center)*7.0,2.0)-pow((uv.y-0.62)*2.6,2.0))*0.18;
        light = mix(vec3(0.98,0.36,0.08),vec3(1.0,0.89,0.56),core);
        light = mix(light,vec3(0.48,0.63,0.94), (1.0-smoothstep(0.03,0.15,h))*flame*0.45);
        alpha = (flame*0.92+bloom)*intensity;
    }
    // Round rectangle SDF, without a texture, blur, or offscreen source capture.
    vec2 halfSize = extent * 0.5;
    float r = min(cornerRadius, min(halfSize.x, halfSize.y));
    vec2 q = abs(uv * extent - halfSize) - halfSize + vec2(r);
    float dist = length(max(q, vec2(0))) + min(max(q.x,q.y), 0.0) - r;
    alpha *= 1.0 - smoothstep(-1.0, 0.0, dist);
    alpha *= qt_Opacity;
    fragColor = vec4(light * alpha, alpha);
}
