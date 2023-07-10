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

fn gridLines(uv: vec2f, width: f32, spacing: f32) -> f32 {
    let gS = 0.2;
    let lines = mix(0.75, 1.0, min(step(width, fract(uv.x/spacing + width / 2.0)), step(width, fract(uv.y/spacing + width / 2.0))));
    return lines;
}

@fragment
fn fragmentMain(@builtin(position) pos: vec4<f32>) -> @location(0) vec4f {
    // Setting up uv coordinates
    let uv = (vec2(pos.x, pos.y) / rez - 0.5) * 2.0; // normalizing
    
    let lMaj = gridLines(uv, 0.04, 0.15);
    let lMin = gridLines(uv, 0.04, 0.15 / 5.0);
    let lines = min(lMaj, lMin);
    let fragColor = vec4f(vec3f(lines), 1.0);

    return fragColor;
} 