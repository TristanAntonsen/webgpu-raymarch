
@group(0) @binding(0) var<uniform> rez: vec2f;


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

fn sdCircle(p: vec2f, r: f32) -> f32 {
    return length(p) - r;
}

fn getDist(p: vec2f) -> f32 {
    let d = sdCircle(p, 0.5);
    return d;
}

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
    let uv = (vec2(pos.x, pos.y) / rez - 0.5) * 2.0; // normalizing

    let d = getDist(uv);

    let col0 = vec4f(0.2, 0.2, 0.2, 0.0);
    let col1 = vec4f(1.0);
    let col2 = vec4f(0.9, 0.9, 0.9, 1.0);
    
    let f = 200.0; // Ripple frequency
    // let fac = 0.5 * sin(f * d) + 0.5; // creating ripples & shifting from 0 to 1
    let fac = 0.1 * sin(f * d * 0.5) + 1.;


    let n = getNormal(uv);
    let col3 = vec4f(n, 1.0, 1.0);
    let prettyColor: vec4f = mix(col1, col3, fac); 
    // let prettyColor = fac * vec4(n.x, n.y, 1.0, 1.0);

    let blend = 100.0;
    let fragColor = mix(col0, prettyColor, smoothstep(0.0,1.0, blend * d) );
    // let fragColor = vec4f(uv, 0.0, 1.0);
    return fragColor;
} 