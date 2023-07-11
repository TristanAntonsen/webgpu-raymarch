
@group(0) @binding(0) var<uniform> rez: vec2f;
@group(0) @binding(1) var<uniform> time: f32;
@group(0) @binding(2) var<uniform> mouse: vec2f;


struct VertexInput {
    @location(0) pos: vec2f,
};
struct VertexOutput {
    @builtin(position) pos: vec4f,
};

@vertex
fn vertexMain(input: VertexInput) ->
    VertexOutput {
    var output: VertexOutput;
    output.pos = vec4f(input.pos, 0, 1);
    return output;
}

fn add_two(i: i32, b: f32) -> i32 {
  return i + 2;  // A formal parameter is available for use in the body.
}

fn sdCircle(p: vec2f, c: vec2f, r: f32) -> f32 {

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


fn opSubtraction(d1: f32, d2: f32) -> f32 {
    //NOTE: Flipped order because it makes more sense to me
    return max(-d2, d1);
}

fn getDist(p: vec2f) -> f32 {
    let m = mouse / rez;
    var c1 = sdCircle(p, vec2f(0.0),0.25);
    var b1 = sdRoundedBox(p, vec2f(0.375), vec4f(0.1, 0.0, 0.0, 0.1));
    let s1 = opSubtraction(b1, c1);
    var c2 = sdCircle(p, m * 2.0, 0.15);
    let d = opSmoothUnion(s1, c2, 0.05);
    let t = sin(0.05 * time) * 0.02;
    return d + t;
}

// COORDINATE SYSTEM
// X = [-1,+1], Right is positive
// Y = [-1,+1], Down is positive

fn getNormal(p: vec2f) -> vec2f {
    let epsilon = 0.0001;
    let dx = vec2(epsilon, 0.);
    let dy = vec2(0., epsilon);

    let ddx = getDist(p + dx) - getDist(p - dx);
    let ddy = getDist(p + dy) - getDist(p - dy);
    
    return normalize(vec2f(ddx, ddy));
}

@fragment
fn fragmentMain(@builtin(position) pos: vec4<f32>) -> @location(0) vec4f {
    // Setting up uv coordinates
    let uv = 2.0 * (vec2(pos.x, pos.y) - 0.5 * rez.xy) / min(rez.x, rez.y);
    let d = getDist(uv);
    
    let col0 = vec4f(0.1, 0.1, 0.1, 0.0);
    let col1 = vec4f(1.0);
    let col2 = vec4f(0.85, 0.85, 0.85, 1.0);
    
    let f = 200.0; // Ripple frequency
    let fac = 0.5 * cos(f * d) + 0.5; // creating ripples & shifting from 0 to 1
    // let fac = 0.1 * sin(f * d * 0.5) + 1.;

    let n = getNormal(uv);
    let col3 = vec4f(n, 1.0, 1.0);
    let prettyColor: vec4f = mix(col1, col3, fac); 
    // let prettyColor = fac * vec4(n.x, n.y, 1.0, 1.0);
    // var prettyColor = vec4(n.x, n.y, 1.0, 1.0);
    let blend = 250.0;
    var fragColor = mix(col0, prettyColor, smoothstep(0.0,1.0, blend * d) );
    // var fragColor = vec4f(uv, 0.0, 1.0);
    return fragColor;
} 