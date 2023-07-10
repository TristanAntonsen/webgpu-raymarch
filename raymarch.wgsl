@group(0) @binding(0) var<uniform> rez: vec2f;
@group(0) @binding(1) var<uniform> time: f32;
@group(0) @binding(2) var<uniform> mouse: vec2f;

struct VertexInput {
    @location(0) pos: vec2f,
};

struct VertexOutput {
    @builtin(position) pos: vec4f,
};

// Ray marching constants
const MAX_STEPS = 1000;
const SURF_DIST = 0.001;
const MAX_DIST = 100.0;
const PI = 3.14159265359;

////////////////////////////////////////////////////////////////
// PBR Helper functions

fn DistributionGGX(N: vec3f, H: vec3f, roughness: f32) -> f32
{
    let a      = roughness*roughness;
    let a2     = a*a;
    let NdotH  = max(dot(N, H), 0.0);
    let NdotH2 = NdotH*NdotH;
	
    let num   = a2;
    var denom = (NdotH2 * (a2 - 1.0) + 1.0);
    denom = PI * denom * denom;
	
    return num / denom;
}

fn GeometrySchlickGGX(NdotV: f32, roughness: f32) -> f32
{
    let r = (roughness + 1.0);
    let k = (r*r) / 8.0;

    let num   = NdotV;
    let denom = NdotV * (1.0 - k) + k;
	
    return num / denom;
}

fn GeometrySmith(N: vec3f, V: vec3f, L: vec3f, roughness: f32) -> f32
{
    let NdotV = max(dot(N, V), 0.0);
    let NdotL = max(dot(N, L), 0.0);
    let ggx2  = GeometrySchlickGGX(NdotV, roughness);
    let ggx1  = GeometrySchlickGGX(NdotL, roughness);
	
    return ggx1 * ggx2;
}

fn fresnelSchlick(cosTheta: f32, F0: vec3f) -> vec3f
{
    return F0 + (1.0 - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
} 

////////////////////////////////////////////////////////////////

fn simpleHash( p0: vec3f ) -> vec3f
// Adapted from iq: https://www.shadertoy.com/view/Xsl3Dl
{
	var p = vec3( dot(p0,vec3(127.1,311.7, 74.7)),
			  dot(p0,vec3(269.5,183.3,246.1)),
			  dot(p0,vec3(113.5,271.9,124.6)));

	return -1.0 + 2.0*fract(sin(p)*43758.5453123);
}

fn gradientNoise( p : vec3f ) -> f32
// Adapted from iq: https://www.shadertoy.com/view/Xsl3Dl
{
    var i = floor( p );
    var f = fract( p );
    // cubic interpolant
    var u = f*f*(3.0-2.0*f);

    return mix( mix( mix( dot( simpleHash( i + vec3(0.0,0.0,0.0) ), f - vec3(0.0,0.0,0.0) ), 
                          dot( simpleHash( i + vec3(1.0,0.0,0.0) ), f - vec3(1.0,0.0,0.0) ), u.x),
                     mix( dot( simpleHash( i + vec3(0.0,1.0,0.0) ), f - vec3(0.0,1.0,0.0) ), 
                          dot( simpleHash( i + vec3(1.0,1.0,0.0) ), f - vec3(1.0,1.0,0.0) ), u.x), u.y),
                mix( mix( dot( simpleHash( i + vec3(0.0,0.0,1.0) ), f - vec3(0.0,0.0,1.0) ), 
                          dot( simpleHash( i + vec3(1.0,0.0,1.0) ), f - vec3(1.0,0.0,1.0) ), u.x),
                     mix( dot( simpleHash( i + vec3(0.0,1.0,1.0) ), f - vec3(0.0,1.0,1.0) ), 
                          dot( simpleHash( i + vec3(1.0,1.0,1.0) ), f - vec3(1.0,1.0,1.0) ), u.x), u.y), u.z );
}

fn sdSphere(p: vec3f, c: vec3f, r: f32) -> f32 {

    return length(p-c) - r;
}

fn sdRoundedBox(p: vec2f, b: vec2f, r: vec4f) -> f32 {
    var rad = vec4f(0.0);
    rad = select(r, vec4f(r.z, r.w, r.z, r.w), p.x>0.0);
    rad.x = select(rad.y, rad.x, p.y>0.0);
    var q = abs(p)-b+rad.x;

    return min(max(q.x,q.y),0.0) + length(max(q,vec2f(0.0))) - rad.x;
}


fn opSmoothUnion(d1: f32, d2: f32, k: f32) -> f32 {
    let h = clamp( 0.5 + 0.5*(d2-d1)/k, 0.0, 1.0 );
    return mix( d2, d1, h ) - k*h*(1.0-h);
}
fn opSmoothSubtraction(d1: f32, d2: f32, k: f32) -> f32 {
    let h = clamp( 0.5 - 0.5*(d2+d1)/k, 0.0, 1.0 );
    return mix( d1, -d2, h ) + k*h*(1.0-h);
}

fn opUnion(d1: f32, d2: f32 ) -> f32 { return min(d1,d2); }

fn opSubtraction(d1: f32, d2: f32) -> f32 {
    //NOTE: Flipped order because it makes more sense to me
    return max(-d2, d1);
}
fn opIntersection(d1: f32, d2: f32) -> f32 {
    return max(d1, d2);
}

fn getDist(p: vec3f) -> f32 {
    let r = 0.3;
    var d = sdSphere(p, vec3f(-0.375, -0.375, 0.0), r);
    d = opUnion(d, sdSphere(p, vec3f(0.375, -0.375, 0.0), r)) + 0.0025 * sin(200.0 * p.x);
    d = opUnion(d, sdSphere(p, vec3f(-0.375, 0.375, 0.0), r));
    d = opUnion(d, sdSphere(p, vec3f(0.375, 0.375, 0.0), r));
    d = opSmoothSubtraction(d, sdSphere(p, vec3f(2.0 * mouse / rez, 0.0), 0.15), 0.15);
    d = opUnion(d, sdSphere(p, vec3f(2.0 * mouse / rez, 0.0), 0.15));

    return d;
}

fn rippleSphere(p: vec3f) -> f32 {
    let n = gradientNoise(100.0 * p + 0.01);
    let s = sdSphere(p, vec3f(0.), 0.5) + 0.0025 * sin(200.0 * p.x);
    let s2 = sdSphere(p, vec3f(0.375, -0.375, -0.375), 0.375);
    let d = opSmoothSubtraction(s, s2, 0.025);
    // return s + 0.001 * n;
    return d;
}

// COORDINATE SYSTEM
// X = [-1,+1], Right is positive
// Y = [-1,+1], Down is positive

fn getNormal(p: vec3f) -> vec3f {
    let epsilon = 0.0001;
    let dx = vec3(epsilon, 0., 0.0);
    let dy = vec3(0., epsilon, 0.0);
    let dz = vec3(0., 0.0, epsilon);

    let ddx = getDist(p + dx) - getDist(p - dx);
    let ddy = getDist(p + dy) - getDist(p - dy);
    let ddz = getDist(p + dz) - getDist(p - dz);
    
    return normalize(vec3f(ddx, ddy, ddz));
}

fn rayDirection(p: vec2f, ro: vec3f) -> vec3f {

    // let rd = normalize(llc + p.x * horizontal + p.y * vertical - ro);
    let rd = normalize(vec3f(p, 0.0)-ro);
    return rd;
}

fn rayMarch(ro: vec3f, rd: vec3f) -> f32 {
    var d = 0.0;

    var i: i32 = 0;
    loop {
        if i >= MAX_STEPS { break; }
        let p = ro + rd * d;
        let ds = getDist(p);
        d += ds;
        if d >= MAX_DIST || ds < SURF_DIST {
            break;
        }
        i++;
    }
    return d;

}

@vertex
fn vertexMain(input: VertexInput) ->
    VertexOutput {
    var output: VertexOutput;
    output.pos = vec4f(input.pos, 0, 1);
    return output;
}

@fragment
fn fragmentMain(@builtin(position) pos: vec4<f32>) -> @location(0) vec4f {
    // Setting up uv coordinates
    let uv = (vec2(pos.x, pos.y) / rez - 0.5) * 2.0; // normalizing

    let ro = vec3f(0., 0., -2.0);
    let rd = rayDirection(uv, ro);
    let d = rayMarch(ro, rd);

    var lx = 1.0 * sin(0.025 * time);
    var lz = 1.0 * cos(0.025 * time);

    // let lightPos = vec3f(1,-1, -2);
    let lightPos = vec3f(lx,-1, lz);
    // let lightPos = vec3f(2.0 * mouse / rez, 0.0);
    let lightColor = vec3f(1.0);
    let lightPower = 4.0;
    var fragColor = vec4f(0.);

    if (d <= 100.0) {
        let p = ro + rd * d;
        let N = getNormal(p);

        // PBR Shading
        // material parameters
        let albedo = vec3f(1.0, 0.0, 0.0);
        let roughness = 0.4;
        let metallic = 0.0;
        var F0 = vec3(0.04);
        F0 = mix(F0, albedo, metallic);


        // reflectance equation
        // radiance
        let V = -rd;

        var Lo = vec3f(0.);
        // calculate per-light radiance
        let L = normalize(lightPos - p);
        let H = normalize(V + L);
        let distance    = length(lightPos - p);
        let attenuation = 1.0 / (distance * distance);
        let radiance    = lightColor * attenuation;        
        
        // cook-torrance brdf
        let NDF = DistributionGGX(N, H, roughness);        
        let G   = GeometrySmith(N, V, L, roughness);      
        let F    = fresnelSchlick(max(dot(H, V), 0.0), F0);       
        
        let kS = F;
        var kD = vec3f(1.0) - kS;
        kD *= 1.0 - metallic;	  
        
        let numerator   = NDF * G * F;
        let denominator = 4.0 * max(dot(N, V), 0.0) * max(dot(N, L), 0.0) + 0.0001;
        let specular    = numerator / denominator;  
            
        // add to outgoing radiance Lo
        let NdotL = max(dot(N, L), 0.0);                
        Lo += (kD * albedo / PI + specular) * radiance * NdotL * lightPower; 
        
        let ambient = vec3f(0.0025) * albedo;
        var color = ambient + Lo;
        
        color = color / (color + vec3f(1.0));
        color = pow(color, vec3f(1.0/2.2));  
    
        fragColor = vec4(color, 1.0);
        
    }

    return fragColor;
} 