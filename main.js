require.config({ paths: { 'vs': 'https://cdnjs.cloudflare.com/ajax/libs/monaco-editor/0.26.1/min/vs' } });

require(['vs/editor/editor.main'], function () {
  var editor = monaco.editor.create(document.getElementById('container'), {
    value: [
      '@group(0) @binding(0) var<uniform> rez: vec2f;',
      '',
      'struct VertexInput {',
      '    @location(0) pos: vec2f,',
      '};',
      '',
      'struct VertexOutput {',
      '    @builtin(position) pos: vec4f,',
      '};',
      ,
      '@vertex',
      'fn vertexMain(input: VertexInput) ->',
      '    VertexOutput {',
      '    var output: VertexOutput;',
      '    output.pos = vec4f(input.pos, 0, 1);',
      '    return output;',
      '}',
      '',
      '@fragment',
      'fn fragmentMain(@builtin(position) pos: vec4<f32>) -> @location(0) vec4f {',
      '    // Setting up uv coordinates',
      '    let uv = (vec2(pos.x, pos.y) / rez - 0.5) * 2.0; // normalizing',
      ''    ,
      '    let fragColor = vec4f(uv, 0.0, 1.0);',
      '',
      '    return fragColor;',
      '}'].join('\n'),
    // language: 'javascript',
    scrollbar: {
      vertical: 'auto',
    },
    theme: "vs-dark",
    automaticLayout: true, minimap: { enabled: false }
  });

  let bindRun = editor.addCommand(monaco.KeyMod.CtrlCmd | monaco.KeyCode.Enter, function () {
    let shaderText = editor.getValue();
    // console.log(editor.getValue())
    run(shaderText);
  })
});

async function run(shaderText) {
  // Loading shader from .wgsl file
  // const shaderText = await fetch('./simple.wgsl')
  //   .then(result => result.text());

  // Rendering texture to the canvas
  render(shaderText)
}

// Getting the canvas & setting the resolution
let canvas = document.querySelector("canvas");

const X_RES = 512;
const Y_RES = 512;

canvas.width = X_RES;
canvas.height = Y_RES;

// Most of this setup is pulled from Google's webgpu-for-beginners tutorial setup (Conway's Game of Life)
async function render(shaderText) {

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

  // Creating the quad for rendering the texture
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

  // Create a uniform buffer that describes the grid.
  const uniformArray = new Float32Array([X_RES, Y_RES]);
  const uniformBuffer = device.createBuffer({
    label: "Grid Uniforms",
    size: uniformArray.byteLength,
    usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
  });
  device.queue.writeBuffer(uniformBuffer, 0, uniformArray);



  // Creating the shaders (they get passed in as strings)
  const cellShaderModule = device.createShaderModule({
    label: 'Cell shader',
    code: shaderText
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

  const bindGroup = device.createBindGroup({
    label: "Cell renderer bind group",
    layout: cellPipeline.getBindGroupLayout(0),
    entries: [{
      binding: 0,
      resource: { buffer: uniformBuffer }
    }],
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

  pass.setBindGroup(0, bindGroup); // New line!

  pass.draw(vertices.length / 2); // 6 vertices

  // Ending the render pass
  pass.end()

  // Finish the command buffer and immediately submit it.
  device.queue.submit([encoder.finish()]);
}

// run()