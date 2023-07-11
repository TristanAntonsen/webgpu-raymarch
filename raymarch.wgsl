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
const MAX_STEPS = 5000;
const SURF_DIST = 0.001;
const MAX_DIST = 100.0;
const PI = 3.141592653592;
const TAU = 6.283185307185;

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

fn Rot(a: f32) -> mat2x2f {
    let s = sin(a);
    let c = cos(a);
    return mat2x2f(c, -s, s, c);
}


fn rotX(p: vec3f, a: f32) -> vec3f {
    let s = sin(a);
    let c = cos(a);
    let m = mat3x3f(
        1., 0., 0.,
        0., c, -s,
        0., s, c,
        );
    return m * p;
}

fn rotY(p: vec3f, a: f32) -> vec3f {
    let s = sin(a);
    let c = cos(a);
    let m = mat3x3f(
        c, 0., s,
        0., 1., 0.,
        -s, 0., c,
        );
    return m * p;
}

fn rotZ(p: vec3f, a: f32) -> vec3f {
    let s = sin(a);
    let c = cos(a);
    let m = mat3x3f(
        c, -s, 0.,
        s,  c, 0.,
        0., 0., 1.
        );
        
    return m * p;
}


fn sdPlane( p: vec3f, n: vec3f, h: f32 ) -> f32
{
  return dot(p,normalize(n)) + h;
}

fn sdSphere(p: vec3f, c: vec3f, r: f32) -> f32 {

    return length(p-c) - r;
}

fn sdRoundBox( po: vec3f, c: vec3f, b: vec3f, r: f32 ) -> f32
{
    let p = po - c;
    let q = abs(p) - b;
    return length(max(q,vec3f(0.0))) + min(max(q.x,max(q.y,q.z)),0.0) - r;
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

fn orbitControls(po: vec3f) -> vec3f {

    let m = (vec2f(mouse.x, mouse.y) / rez) + 0.5;
    var p = po;

    p = rotY(po, -m.x*TAU);
    // p = rotZ(p, m.y*PI);
    p = rotX(p, -m.y*PI);
    
    return p;
}

fn getDist(po: vec3f) -> f32 {
    let p = orbitControls(po);
    let noise = gradientNoise(p * 50.) * 0.005;
    var c = sdRoundBox(p, vec3f(0.0), vec3f(0.375), 0.075);
    var s = sdSphere(p, vec3f(0.0), 0.55);
    var s2 = sdSphere(p, vec3f(0.0), 0.25) + noise;
    var d = opSmoothSubtraction(c, s, 0.02);
    d = opUnion(d, s2);

    return d;
}

fn sphereCube(p: vec3f) -> f32 {
    var s = sdSphere(p, vec3f(0.2, -0.2, 0.2), 0.35);
    var c = sdRoundBox(p, vec3f(-0.2, 0.2, -0.2), vec3f(0.25), 0.075);
    var d = opSmoothUnion(s, c, 0.2);
    return d;
}

fn head(p: vec3f) -> f32 {
    let r = 0.6;
    var s = sdSphere(p, vec3f(0.0, 0.0, 0.0), r);

    var s2 = sdSphere(vec3f(p.x * 1.8, p.yz), vec3f(0.0, 0.0, 0.6), r * 1.90);
    s2 = opSubtraction(s2, sdPlane(p, vec3f(0., 1.0, 0.), 0.0));
    s2 = opSubtraction(s2, sdPlane(p, vec3f(0., -0.5, -1.), 0.3));
    var d = opSmoothUnion(s, s2, 0.05);

    let off = 0.45;
    d = opSubtraction(d, sdPlane(p, vec3f(1., 0., 0.), off));
    d = opSubtraction(d, sdPlane(p, vec3f(-1., 0., 0.), off));
    d = opSubtraction(d, sdPlane(p, vec3f(0., -1., 0.), 0.8));
    d = opSubtraction(d, sdPlane(p, vec3f(-1., -1., 0.), 0.7));
    d = opSubtraction(d, sdPlane(p, vec3f(1., -1., 0.), 0.7));

    return d;
}

fn rippleSphere(p: vec3f) -> f32 {
    let n = gradientNoise(100.0 * p + 0.01);
    let s = sdSphere(p, vec3f(0.), 0.625) + 0.0025 * sin(150.0 * p.x);
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

fn rayDirection(p: vec2f, ro: vec3f, rt: vec3f) -> vec3f {

    // screen orientation
    let vup = vec3f(0., 1.0, 0.0);
    let aspectRatio = rez.y / rez.x;

    let vw = normalize(ro - rt);
    let vu = normalize(cross(vup, vw));
    let vv = cross(vw, vu);
    let theta = radians(30.); // half FOV
    let viewport_height = 2. * tan(theta);
    let viewport_width = aspectRatio * viewport_height;
    let horizontal = -viewport_width * vu;
    let vertical = viewport_height * vv;
    let focus_dist = length(ro - rt);
    let center = ro - vw * focus_dist;

    let rd = center + p.x * horizontal + p.y * vertical - ro;

    return normalize(rd);
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

    let rt = vec3f(0., 0., 0.);
    var ro = vec3f(0., 0., -5.0);

    let rd = rayDirection(uv, ro, rt);
    let d = rayMarch(ro, rd);

    let baseLightPower = 18.0;

    // Background
    var v = length(uv) * .75;
    var fragColor = vec4f(mix(0.1, 0.2, smoothstep(0.0, 1.0, uv.y)));
	fragColor += mix(vec4f(0.6), vec4f(0.0, 0.0, 0.0, 1.0), v);
    // fragColor *= 1.0 / (length(uv));

    const numLights = 4;
    const lights = array<vec3f, numLights>(
        vec3f(4.0, -2.0, -4.0),
        vec3f(-1, -.25, 1.),
        vec3f(0., -10.0, 0.),
        vec3f(0., 20.0, 0.)
    );
    const lightPowers = array<f32, numLights>( 4.0, 1.0, 2.0, 1.0 );
    const lightColors = array<vec3f, numLights>(
        vec3f(1.0, 0.9, 0.9),
        vec3f(1.0),
        vec3f(0.9, 0.9, 1.0),
        vec3f(1.0),
    );

    if (d <= 100.0) {
        let p = ro + rd * d;
        let N = getNormal(p);

        // PBR Shading
        // material parameters
        let albedo = vec3f(1.0);
        let roughness = 0.15;
        let metallic = 0.0;
        var F0 = vec3(0.04);
        F0 = mix(F0, albedo, metallic);

        // reflectance equation
        // radiance
        let V = -rd;

        var Lo = vec3f(0.);
        // calculate per-light radiance
        //WGSL
        var i = 0;
        var lightPos: vec3f;
        loop {
            if i >= numLights { break; }
            lightPos = lights[i];
            let L = normalize(lightPos - p);
            let H = normalize(V + L);
            let distance    = length(lightPos - p);
            let attenuation = 1.0 / (distance * distance);
            let radiance    = lightColors[i] * attenuation;        
            
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
            Lo += (kD * albedo / PI + specular) * radiance * NdotL * baseLightPower * lightPowers[i]; 
            i++;
        }
        let ambient = vec3f(0.01) * albedo;
        var color = ambient + Lo;
        
        color = color / (color + vec3f(1.0));
        color = pow(color, vec3f(1.0/2.2));  
    
        fragColor = vec4(color, 1.0);
        
    }

    return fragColor;
} 