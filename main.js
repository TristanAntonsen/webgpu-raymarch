let m = document.querySelector("canvas");


async function main() {
  const shaderText = await fetch('./shader.wgsl')
    .then(result => result.text());

  // Getting the canvas & setting the resolution
  let canvas = document.querySelector("canvas");

  const X_RES = 720;
  const Y_RES = 720;

  canvas.width = X_RES;
  canvas.height = Y_RES;

  // Adding mouse functions
  let MOUSE_X = 0.0;
  let MOUSE_Y = 0.0;

  let mousePressed = false;

  function updateMouse(e) {
    let domain = canvas.getBoundingClientRect();
    if (mousePressed) {
      MOUSE_Y = (e.clientY - domain.top) - X_RES / 2;
      MOUSE_X = (e.clientX - domain.left) - Y_RES / 2;
      console.log("MOUSE:", MOUSE_X / X_RES, MOUSE_Y / Y_RES)
      console.log(mouseUniformArray)
    }
  }
  
  canvas.addEventListener("mousemove", updateMouse);
  canvas.addEventListener("mousedown", (event) => { mousePressed = true });
  canvas.addEventListener("mouseup", (event) => { mousePressed = false });

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
  const rezUniformArray = new Float32Array([X_RES, Y_RES]);
  const rezBuffer = device.createBuffer({
    label: "Resolution Uniform",
    size: rezUniformArray.byteLength,
    usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
  });

  // Create a uniform buffer that tracks the time.
  const timeUniformArray = new Float32Array([0.0]);
  const timeBuffer = device.createBuffer({
    label: "Time Uniform",
    size: timeUniformArray.byteLength,
    usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
  });

  // Create a uniform buffer that tracks the mouse position.
  const mouseUniformArray = new Float32Array([MOUSE_X, MOUSE_Y]);
  const mouseBuffer = device.createBuffer({
    label: "Mouse Uniform",
    size: mouseUniformArray.byteLength,
    usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
  });

  // Creating the shaders (they get passed in as strings)
  const cellShaderModule = device.createShaderModule({
    label: 'Cell shader',
    code: shaderText
  });


  const bindGroupLayout = device.createBindGroupLayout({
    entries: [
      { binding: 0, visibility: GPUShaderStage.FRAGMENT, buffer: { type: "uniform" } },
      { binding: 1, visibility: GPUShaderStage.FRAGMENT, buffer: { type: "uniform" } },
      { binding: 2, visibility: GPUShaderStage.FRAGMENT, buffer: { type: "uniform" } },
    ]
  })


  const pipelineLayout = device.createPipelineLayout({
    bindGroupLayouts: [
      bindGroupLayout, // @group(0)
    ]
  });

  // Creating the render pipeline (conttrols how geometry is drawn, which shaders are used, etc.)
  const cellPipeline = device.createRenderPipeline({
    label: "Cell pipeline",
    layout: pipelineLayout,
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
    entries: [
      { binding: 0, resource: { buffer: rezBuffer } },
      { binding: 1, resource: { buffer: timeBuffer } },
      { binding: 2, resource: { buffer: mouseBuffer } },
    ],
  });

  const draw = () => {
    const run = () => {

      // Increment time
      timeUniformArray[0] += 1.0;

      mouseUniformArray[0] = MOUSE_X;
      mouseUniformArray[1] = MOUSE_Y;

      // Copying the vertices into the buffer's memory
      device.queue.writeBuffer(vertexBuffer, /*bufferOffset=*/0, vertices);
      device.queue.writeBuffer(rezBuffer, 0, rezUniformArray);
      device.queue.writeBuffer(timeBuffer, 0, timeUniformArray);
      device.queue.writeBuffer(mouseBuffer, 0, mouseUniformArray);




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
    run();
    run();
    requestAnimationFrame(draw);
    // setTimeout(draw, 100.0);
  }
  draw();
}
main() 