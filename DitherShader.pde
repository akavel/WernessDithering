/**********************************************************
 * This is a quick test app that demonstrates the shaders.*
 **********************************************************/

// The three shaders that are needed
PShader dither;
PShader outShader;
PShader inShader;

// Information for shared images
String name = "test2.jpg";
PImage backgroundImage;
PGraphics cube;

void setup() {
  // Initialize the canvases
  size(600, 287, P2D);
  colorMode(RGB, 1.0);
  backgroundImage = loadImage(name);
  cube = createGraphics(width, height, P3D);

  // Initialize the shaders
  initAtkinson();
  initInShader();
  initOutShader();

  // Don't limit the framerate
  frameRate(1000);
}

// A few quick key commands
void keyPressed() {
  switch(key) {
    case '1': initAtkinson(); break;  // Use the Atkinson shader
    case '2': initMyDither(); break;  // Use the smoother shader
    case '3': initDirDither(); break; // Use the directional shader
    case 's': frameRate(24); break;   // Slow it down so you can see each frame
    case 'f': frameRate(1000); break; // Speed it back up to unlimited framerate
  }
}

// draw the spinning cube to be overlayed
void drawCube() {
  cube.noSmooth();
  cube.beginDraw();
  cube.lights();
  cube.clear();
  cube.noStroke();
  cube.translate(width/2, height/2);
  cube.rotateX(PI*frameCount/100.0);
  cube.rotateY(PI*frameCount/600.0);
  cube.box(120);
  cube.endDraw();
}

// draw everything
void draw() {
  // draw the background and cube
  drawCube();
  image(backgroundImage, (frameCount)%width, 0);
  image(backgroundImage, (frameCount)%width-width, 0);
  image(cube, 0, 0);

  // Do the shader work needed to filter the frame:
  // 1. Run the input shader to initialize as the frames as needed
  filter(inShader);
  // 2. Repeatedly apply the dithering shader to perform the error diffusion.  
  //    There are 9 phases where px and py run over a 3x3 grid.
  //    The choice of t running up to 36 is a bit arbitrary.  There is a bit
  //    of a trade-off here.  The fewer the faster, and also more importantly 
  //    the less that the shimmering spreads.  The more iterations, the more
  //    accurately it can represent shades very close to black and white.
  //
  // In a real implementation, this should be done with a pingpong shading
  // technique rendering back and forth between a pair of buffers.  This version
  // in fact moves the image from the CPU memory to GPU memory, applies the shader
  // and the copies it back.  Repeating that 36 times per frame.  This slows it down
  // a fair bit!
  for (int t = 0; t < 36; t++) {
    dither.set("px", t%3);
    dither.set("py", (t/3)%3);
    filter(dither);
  }
  // 3. Get rid of the temporary data used by the dithering shader.
  filter(outShader);

  // write the framerate to the image
  fill(0);
  textSize(24);
  text(frameRate, 5, 32);
}

/**********************************************************
 * This loads the version of the shader needed to imitate *
 * that Atkinson style.  This version is somewhat         *
 * optimized so it runs a tiny bit faster.  The kernal    *
 * array is the one that is used. A bit of anatomy:       *
 *   Red: input image                                     *
 * Green: diffused error (up to sign)                     *
 *  Blue: sign of diffused error and the output           *
 *
 * In general, to imitate any of the classical error      *
 * diffusion dithering methods.  You can set the kernel   *
 * to match the diffusion matrix, and then mirror it so   *
 * that it is symmetrical.
 **********************************************************/

void initAtkinson() {
  String[] vertSource = {
    "#version 410", 

    "uniform mat4 transform;", 

    "in vec4 vertex;", 
    "in vec2 texCoord;", 

    "out vec2 vertTexCoord;", 

    "void main() {", 
      "vertTexCoord = vec2(texCoord.x, 1.0 - texCoord.y);", 
      "gl_Position = transform * vertex;", 
    "}"
  };
  String[] fragSource = {
    "#version 410", 

    "const float kernel[25] = float[](0.0/12, 0.0/12, 1.0/12, 0.0/12, 0.0/12,", 
                                     "0.0/12, 1.0/12, 1.0/12, 1.0/12, 0.0/12,", 
                                     "1.0/12, 1.0/12, 0.0/12, 1.0/12, 1.0/12,", 
                                     "0.0/12, 1.0/12, 1.0/12, 1.0/12, 0.0/12,", 
                                     "0.0/12, 0.0/12, 1.0/12, 0.0/12, 0.0/12);", 

    "uniform sampler2D texture;", 
    "uniform vec2 texOffset;", 

    "uniform int px;", 
    "uniform int py;", 

    "in vec2 vertTexCoord;", 
    "in vec4 gl_FragCoord;", 

    "out vec4 fragColor;", 

    "float err(float i, float j) {", 
      "vec4 temp = texture(texture, vertTexCoord + vec2(i*texOffset.x, j*texOffset.y));", 
      "return temp.y*(1.0-temp.z) - temp.y*temp.z;", 
    "}", 

    "void main() {", 
      "vec4 cur = texture(texture, vertTexCoord);", 
      "float sum = cur.x + (2*err(-1.5,0) + 2*err(1.5,0) + 2*err(0,-1.5) + 2*err(0,1.5) + err(-1,-1) + err(1,-1) + err(-1,1) + err(1,1))/12;", 
      "int fx = int(gl_FragCoord.x);", 
      "int fy = int(gl_FragCoord.y);", 
      "vec4 new = ((sum > 0.5))?vec4(cur.x,1.0-sum,1.0,1.0):vec4(cur.x,sum-0.0,0.0,1.0);", 
      "fragColor = ((fx % 3 == px)&&(fy % 3 == py))?new:cur;", 
    "}", 
  };
  dither = new PShader(this, vertSource, fragSource);
}

/**********************************************************
 * The more general version of the shader that actually   *
 * uses the kernel matrix.  In this case the kernel is a  *
 * Gaussian blur with standard deviation of 1 pixel.  In  *
 * general, the tighter the diffusion in a direction the  *
 * finer the texture.                                     *
 **********************************************************/

void initMyDither() {
  String[] vertSource = {
    "#version 410", 

    "uniform mat4 transform;", 

    "in vec4 vertex;", 
    "in vec2 texCoord;", 

    "out vec2 vertTexCoord;", 

    "void main() {", 
      "vertTexCoord = vec2(texCoord.x, 1.0 - texCoord.y);", 
      "gl_Position = transform * vertex;", 
    "}"
  };
  String[] fragSource = {
    "#version 410", 

    "const float kernel[25] = float[]( 1.0/232,  4.0/232,  7.0/232,  4.0/232,  1.0/232,", 
                                     " 4.0/232, 16.0/232, 26.0/232, 16.0/232,  4.0/232,", 
                                     " 7.0/232, 26.0/232,  0.0/232, 26.0/232,  7.0/232,", 
                                     " 4.0/232, 16.0/232, 26.0/232, 16.0/232,  4.0/232,", 
                                     " 1.0/232,  4.0/232,  7.0/232,  4.0/232,  1.0/232);", 

    "uniform sampler2D texture;", 
    "uniform vec2 texOffset;", 

    "uniform int px;", 
    "uniform int py;", 

    "in vec2 vertTexCoord;", 
    "in vec4 gl_FragCoord;", 

    "out vec4 fragColor;", 

    "float err(int i, int j) {", 
      "vec4 temp = texture(texture, vertTexCoord + vec2(i*texOffset.x, j*texOffset.y));", 
      "return temp.y*(1.0-temp.z) - temp.y*temp.z;", 
    "}", 

    "void main() {", 
      "vec4 cur = texture(texture, vertTexCoord);", 
      "float sum = cur.x + kernel[ 0]*err(-2,-2) + kernel[ 1]*err(-1,-2) + kernel[ 2]*err( 0,-2) + kernel[ 3]*err( 1,-2) + kernel[ 4]*err( 2,-2) +", 
                          "kernel[ 5]*err(-2,-1) + kernel[ 6]*err(-1,-1) + kernel[ 7]*err( 0,-1) + kernel[ 8]*err( 1,-1) + kernel[ 9]*err( 2,-1) +", 
                          "kernel[10]*err(-2, 0) + kernel[11]*err(-1, 0) + kernel[12]*err( 0, 0) + kernel[13]*err( 1, 0) + kernel[14]*err( 2, 0) +", 
                          "kernel[15]*err(-2, 1) + kernel[16]*err(-1, 1) + kernel[17]*err( 0, 1) + kernel[18]*err( 1, 1) + kernel[19]*err( 2, 1) +", 
                          "kernel[20]*err(-2, 2) + kernel[21]*err(-1, 2) + kernel[22]*err( 0, 2) + kernel[23]*err( 1, 2) + kernel[24]*err( 2, 2);", 
      "int fx = int(gl_FragCoord.x);", 
      "int fy = int(gl_FragCoord.y);", 
      "vec4 new = ((sum > 0.5))?vec4(cur.x,1.0-sum,1.0,1.0):vec4(cur.x,sum-0.0,0.0,1.0);", 
      "fragColor = ((fx % 3 == px)&&(fy % 3 == py))?new:cur;", 
    "}", 
  };
  dither = new PShader(this, vertSource, fragSource);
}

/**********************************************************
 * The exact same shader as above, but with a wider blur  *
 * in the vertical axis leading to the hatching style.    *
 **********************************************************/

void initDirDither() {
  String[] vertSource = {
    "#version 410", 

    "uniform mat4 transform;", 

    "in vec4 vertex;", 
    "in vec2 texCoord;", 

    "out vec2 vertTexCoord;", 

    "void main() {", 
    "vertTexCoord = vec2(texCoord.x, 1.0 - texCoord.y);", 
    "gl_Position = transform * vertex;", 
    "}"
  };
  String[] fragSource = {
    "#version 410", 

    "const float kernel[25] = float[]( 1.0/74,  4.0/74,  6.0/74,  4.0/74,  1.0/74,", 
                                     " 1.0/74,  4.0/74,  6.0/74,  4.0/74,  1.0/74,", 
                                     " 1.0/74,  4.0/74,  0.0/74,  4.0/74,  1.0/74,", 
                                     " 1.0/74,  4.0/74,  6.0/74,  4.0/74,  1.0/74,", 
                                     " 1.0/74,  4.0/74,  6.0/74,  4.0/74,  1.0/74);", 

    "uniform sampler2D texture;", 
    "uniform vec2 texOffset;", 

    "uniform int px;", 
    "uniform int py;", 

    "in vec2 vertTexCoord;", 
    "in vec4 gl_FragCoord;", 

    "out vec4 fragColor;", 

    "float err(int i, int j) {", 
    "vec4 temp = texture(texture, vertTexCoord + vec2(i*texOffset.x, j*texOffset.y));", 
    "return temp.y*(1.0-temp.z) - temp.y*temp.z;", 
    "}", 

    "void main() {", 
      "vec4 cur = texture(texture, vertTexCoord);", 
      "float sum = cur.x + kernel[ 0]*err(-2,-2) + kernel[ 1]*err(-1,-2) + kernel[ 2]*err( 0,-2) + kernel[ 3]*err( 1,-2) + kernel[ 4]*err( 2,-2) +", 
                          "kernel[ 5]*err(-2,-1) + kernel[ 6]*err(-1,-1) + kernel[ 7]*err( 0,-1) + kernel[ 8]*err( 1,-1) + kernel[ 9]*err( 2,-1) +", 
                          "kernel[10]*err(-2, 0) + kernel[11]*err(-1, 0) + kernel[12]*err( 0, 0) + kernel[13]*err( 1, 0) + kernel[14]*err( 2, 0) +", 
                          "kernel[15]*err(-2, 1) + kernel[16]*err(-1, 1) + kernel[17]*err( 0, 1) + kernel[18]*err( 1, 1) + kernel[19]*err( 2, 1) +", 
                          "kernel[20]*err(-2, 2) + kernel[21]*err(-1, 2) + kernel[22]*err( 0, 2) + kernel[23]*err( 1, 2) + kernel[24]*err( 2, 2);", 
      "int fx = int(gl_FragCoord.x);", 
      "int fy = int(gl_FragCoord.y);", 
      "vec4 new = ((sum > 0.5))?vec4(cur.x,1.0-sum,1.0,1.0):vec4(cur.x,sum-0.0,0.0,1.0);", 
      "fragColor = ((fx % 3 == px)&&(fy % 3 == py))?new:cur;", 
    "}", 
  };
  dither = new PShader(this, vertSource, fragSource);
}

/**********************************************************
 * Output shader.  Just takes the green channel as the    *
 * dithered output.                                       *
 **********************************************************/

void initOutShader() {
  String[] vertSource = {
    "#version 410", 

    "uniform mat4 transform;", 

    "in vec4 vertex;", 
    "in vec2 texCoord;", 

    "out vec2 vertTexCoord;", 

    "void main() {", 
      "vertTexCoord = vec2(texCoord.x, 1.0 - texCoord.y);", 
      "gl_Position = transform * vertex;", 
    "}"
  };
  String[] fragSource = {
    "#version 410", 

    "uniform sampler2D texture;", 
    "uniform vec2 texOffset;", 

    "in vec2 vertTexCoord;", 

    "out vec4 fragColor;", 

    "void main() {", 
      "vec4 cur = texture(texture, vertTexCoord);", 

      "fragColor = vec4(cur.z,cur.z,cur.z,1.0);", 
    "}", 
  };
  outShader = new PShader(this, vertSource, fragSource);
}

/**********************************************************
 * The shader to initialize.  Red channel contains the    *
 * input image.  Blue and Green are white noise.  The     *
 * same source of noise should be reused for each frame   *
 * if you want to have any coherence between frames.      *
 **********************************************************/

void initInShader() {
  String[] vertSource = {
    "#version 410", 

    "uniform mat4 transform;", 

    "in vec4 vertex;", 
    "in vec2 texCoord;", 

    "out vec2 vertTexCoord;", 

    "void main() {", 
      "vertTexCoord = vec2(texCoord.x, 1.0 - texCoord.y);", 
      "gl_Position = transform * vertex;", 
    "}"
  };
  String[] fragSource = {
    "#version 410", 

    "uniform sampler2D texture;", 
    "uniform sampler2D noise;", 
    "uniform vec2 texOffset;", 

    "in vec2 vertTexCoord;", 

    "out vec4 fragColor;", 

    "void main() {", 
      "vec4 cur = texture(texture, vertTexCoord);", 
      "vec4 noi = texture(noise, vertTexCoord);", 
  
      "fragColor = vec4(cur.x,noi.y,noi.z,1.0);", 
    "}", 
  };
  inShader = new PShader(this, vertSource, fragSource);

  PImage noise = new PImage(width, height);
  noise.loadPixels();
  for (int i = 0; i < width; i++) {
    for (int j = 0; j < height; j++) {
      noise.pixels[i+width*j] = color(0.0, random(1.0), random(1.0));
    }
  }
  noise.updatePixels();

  inShader.set("noise", noise);
}