import * as THREE from 'three';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';
import { Reflector } from 'three/addons/objects/Reflector.js';
import { createStorageModel, clamp } from './model.mjs';

export function createStorageView(host, onFailure) {
  const renderer=new THREE.WebGLRenderer({alpha:true,antialias:true,powerPreference:'low-power'});
  const canvas=renderer.domElement;
  canvas.setAttribute('aria-hidden','true');canvas.className='storage-canvas';
  host.append(canvas);
  renderer.setClearColor(0x080c10,0);
  renderer.outputColorSpace=THREE.SRGBColorSpace;
  renderer.toneMapping=THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure=1.25;
  renderer.shadowMap.enabled=true;
  renderer.shadowMap.type=THREE.PCFSoftShadowMap;
  let shaderFailed=false;
  renderer.debug.onShaderError=()=>{shaderFailed=true;onFailure();};
  const scene=new THREE.Scene();
  const camera=new THREE.PerspectiveCamera(34,1,.1,80);
  const pmrem=new THREE.PMREMGenerator(renderer),room=new RoomEnvironment();
  const environment=pmrem.fromScene(room,.04);
  scene.environment=environment.texture;
  room.dispose();pmrem.dispose();
  const model=createStorageModel();scene.add(model.group);
  const key=new THREE.DirectionalLight(0xe4efff,4.0);key.position.set(-3,6,5);key.castShadow=true;
  key.shadow.mapSize.set(1024,1024);key.shadow.camera.left=-5;key.shadow.camera.right=5;key.shadow.camera.top=6;key.shadow.camera.bottom=-4;key.shadow.normalBias=.018;key.shadow.bias=-.0003;scene.add(key);
  const rim=new THREE.DirectionalLight(0x73baff,2.8);rim.position.set(4,2,-3);scene.add(rim);
  const fill=new THREE.DirectionalLight(0xffffff,.9);fill.position.set(3,4,6);scene.add(fill);
  scene.add(new THREE.HemisphereLight(0xc8ddf7,0x080b12,.65));
  const floorGeometry=new THREE.PlaneGeometry(200,200);
  const floorMaterial=new THREE.ShadowMaterial({opacity:.34});
  const floor=new THREE.Mesh(floorGeometry,floorMaterial);floor.rotation.x=-Math.PI/2;floor.position.y=-1.85;floor.receiveShadow=true;scene.add(floor);
  const reflectionGeometry=new THREE.PlaneGeometry(12,10);
  const reflectionShader={...Reflector.ReflectorShader,
    vertexShader:Reflector.ReflectorShader.vertexShader.replace('varying vec4 vUv;','varying vec4 vUv; varying vec2 vFloorUv;').replace('vUv = textureMatrix','vFloorUv=uv; vUv = textureMatrix'),
    fragmentShader:`uniform vec3 color; uniform sampler2D tDiffuse; varying vec4 vUv; varying vec2 vFloorUv;
      void main(){vec2 uv=vUv.xy/vUv.w;vec2 blur=vec2(.0025,.0035);
      vec3 reflected=texture2D(tDiffuse,uv).rgb*.24;
      reflected+=texture2D(tDiffuse,uv+blur).rgb*.19;
      reflected+=texture2D(tDiffuse,uv-blur).rgb*.19;
      reflected+=texture2D(tDiffuse,uv+vec2(blur.x,-blur.y)).rgb*.19;
      reflected+=texture2D(tDiffuse,uv+vec2(-blur.x,blur.y)).rgb*.19;
      float fade=exp(-dot((vFloorUv-.5)*vec2(3.5,3.),(vFloorUv-.5)*vec2(3.5,3.)));
      gl_FragColor=vec4(reflected*.28,fade*.48);
      #include <tonemapping_fragment>
      #include <colorspace_fragment>
      }`};
  const reflection=new Reflector(reflectionGeometry,{textureWidth:512,textureHeight:512,multisample:0,clipBias:.003,shader:reflectionShader});
  reflection.rotation.x=-Math.PI/2;reflection.position.y=-1.87;reflection.material.transparent=true;reflection.material.depthWrite=false;scene.add(reflection);
  const glowMaterial=new THREE.ShaderMaterial({transparent:true,depthWrite:false,uniforms:{},
    vertexShader:`varying vec2 vUv; void main(){vUv=uv;gl_Position=projectionMatrix*modelViewMatrix*vec4(position,1.0);}`,
    fragmentShader:`varying vec2 vUv; void main(){vec2 p=(vUv-.5)*2.;float a=exp(-dot(p,p)*5.)*.14;gl_FragColor=vec4(.04,.33,.65,a);}`});
  const glowGeometry=new THREE.PlaneGeometry(6,4);
  const glow=new THREE.Mesh(glowGeometry,glowMaterial);glow.rotation.x=-Math.PI/2;glow.position.set(0,-1.84,.2);scene.add(glow);
  let width=1,height=1,lost=false;
  function resize(){
    const rect=host.getBoundingClientRect();width=Math.max(1,rect.width);height=Math.max(1,rect.height);
    const dpr=Math.min(window.devicePixelRatio||1,width<600?1.4:1.65);
    renderer.setPixelRatio(dpr);renderer.setSize(width,height,false);model.setDpr(dpr);camera.aspect=width/height;camera.updateProjectionMatrix();
  }
  function render(progress,pointer={x:0,y:0}) {
    if(lost||shaderFailed)return false;
    model.update(progress);
    const open=clamp(progress*3),clear=clamp(progress*3-2);
    // Keep the original volume large; widen only to accommodate the reviewed group.
    const spread=Math.sin(open*Math.PI/2)*(1-clear);
    const distance=9.8+spread*1.7-clear*.9;
    const portraitScale=Math.max(1,1.15/camera.aspect);
    camera.position.set((4.4+pointer.x*.22)*portraitScale,(3.0-pointer.y*.13)*portraitScale,distance*portraitScale);
    camera.lookAt(.9*spread,.23-.35*clear,0);
    model.group.rotation.y=-.17+progress*.12+pointer.x*.025;
    renderer.render(scene,camera);return !shaderFailed;
  }
  function contextLost(event){event.preventDefault();lost=true;onFailure();}
  canvas.addEventListener('webglcontextlost',contextLost);
  // A restored context gets a fresh view through the controller.
  function contextRestored(){lost=false;host.dispatchEvent(new Event('storage-context-restored'));}
  canvas.addEventListener('webglcontextrestored',contextRestored);
  function dispose(){
    canvas.removeEventListener('webglcontextlost',contextLost);canvas.removeEventListener('webglcontextrestored',contextRestored);
    model.dispose();floorGeometry.dispose();floorMaterial.dispose();reflection.dispose();reflectionGeometry.dispose();glowGeometry.dispose();glowMaterial.dispose();environment.dispose();renderer.dispose();canvas.remove();
  }
  resize();
  return {resize,render,dispose,model};
}
