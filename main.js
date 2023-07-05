console.log("Pushing pixels...")
// https://codelabs.developers.google.com/your-first-webgpu-app

const canvas = document.querySelector("canvas");

// Setting up the GPU Pipeline

// Checking to make sure browser supports WebGPU
if (!navigator.gpu) {
    throw new Error("WebGPU not supported on this browser.");
}

// WebGPU's representation of the available gpu hardware
const adapter = await navigator.gpu.requestAdapter(); // returns a promise, so use await
if (!adapter) {
    throw new Error("No appropriate GPUAdapter found.");
}

// The main interface through which most interaction with the GPU happens
const device = await adapter.requestDevice();

// Configuring the canvas
const context = canvas.getContext("webgpu");
const canvasFormat = navigator.gpu.getPreferredCanvasFormat();
context.configure({
    device: device,
    format: canvasFormat,
});

// Creating the quad
const HALF_WIDTH = 1.0;
const vertices = new Float32Array([
    //   X,    Y,
    -HALF_WIDTH, -HALF_WIDTH, // Triangle 1 (Blue)
    HALF_WIDTH, -HALF_WIDTH,
    HALF_WIDTH, HALF_WIDTH,

    -HALF_WIDTH, -HALF_WIDTH, // Triangle 2 (Red)
    HALF_WIDTH, HALF_WIDTH,
    -HALF_WIDTH, HALF_WIDTH,
]);

// Creating the buffer
const vertexBuffer = device.createBuffer({
    label: "Cell vertices",
    size: vertices.byteLength,
    usage: GPUBufferUsage.VERTEX | GPUBufferUsage.COPY_DST,
});

// Copying the vertices into the buffer's memory
device.queue.writeBuffer(vertexBuffer, /*bufferOffset=*/0, vertices);

// Defining the vertex data structure
const vertexBufferLayout = {
    arrayStride: 8,
    attributes: [{
        format: "float32x2",
        offset: 0,
        shaderLocation: 0, // Position, see vertex shader
    }],
};

// Creating the shaders (they get passed in as strings)
const cellShaderModule = device.createShaderModule({
  label: 'Cell shader',
  code: `
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
      let uv = (vec2(pos.x, pos.y) / 512.0 - 0.5) * 2.0;
      let color = uv; // resolution;
      let l = length(color);
      if l < 0.5 {
        return vec4(0.0, 0.0, 1.0, 0.0);
      } else {
        return vec4f(l, 1.0, 0.0, 1.0);
      }
    }
  `
});

// Creating the render pipeline (conttrols how geometry is drawn, which shaders are used, etc.)
const cellPipeline = device.createRenderPipeline({
  label: "Cell pipeline",
  layout: "auto",
  vertex: {
    module: cellShaderModule,
    entryPoint: "vertexMain",
    buffers: [vertexBufferLayout]
  },
  fragment: {
    module: cellShaderModule,
    entryPoint: "fragmentMain",
    targets: [{
      format: canvasFormat
    }]
  }
});

// Provides an interface for recording GPU commands
const encoder = device.createCommandEncoder();

const pass = encoder.beginRenderPass({
    colorAttachments: [{
        view: context.getCurrentTexture().createView(),
        loadOp: "clear",
        clearValue: { r: 0, g: 0, b: 0.4, a: 1 }, // New line
        storeOp: "store",
    }]
});

pass.setPipeline(cellPipeline);
pass.setVertexBuffer(0, vertexBuffer);

// pass.setBindGroup(0, bindGroup); // setting bind group

pass.draw(vertices.length / 2); // 6 vertices

// Ending the render pass
pass.end()

// Finish the command buffer and immediately submit it.
device.queue.submit([encoder.finish()]);