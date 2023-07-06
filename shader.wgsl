
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

@fragment
fn fragmentMain(@builtin(position) pos: vec4<f32>) -> @location(0) vec4f {
    let uv = (vec2(pos.x, pos.y) / rez - 0.5) * 2.0; // normalizing
    let color = uv; // resolution;
    return vec4f(color, 0.0, 1.0);
}