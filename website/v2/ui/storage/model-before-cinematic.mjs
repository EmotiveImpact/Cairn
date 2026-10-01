import * as THREE from 'three';

export const clamp = x => Math.max(0, Math.min(1, x));
const smooth = x => { x = clamp(x); return x*x*(3-2*x); };
const mix = (a,b,t) => a+(b-a)*t;

// Each wafer retains its identity when the timeline is reversed.
export const layers = [
  ...Array.from({length:6},(_,i)=>({kind:'base',index:i})),
  ...Array.from({length:3},(_,i)=>({kind:'work',index:i})),
  ...Array.from({length:8},(_,i)=>({kind:'review',index:i})),
  ...Array.from({length:8},(_,i)=>({kind:'upper',index:i})),
  {kind:'cap',index:0}
];

export function layerPose(layer, progress) {
  const p=clamp(progress)*3, open=smooth(p), protect=smooth(p-1), clear=smooth(p-2);
  const i=layer.index;
  let x=0,y=0,z=0,scale=1;
  if(layer.kind==='base') y=-1.7+i*.135;
  if(layer.kind==='work') y=mix(-.79+i*.20,-.68+i*.77,open);
  if(layer.kind==='review') {
    x=3.2*open+.2*protect+3.4*clear;
    y=-.08+i*.135+.08*open+.25*clear;
    z=-.45*open-2*clear;
    scale=1-clear;
  }
  if(layer.kind==='upper') {
    y=1.04+i*.135+.44*open+.20*protect+2.3*clear;
    x=.10*protect;
    z=-.5*clear;
    scale=1-clear;
  }
  if(layer.kind==='cap') y=mix(2.2+.44*open+.20*protect,1.43,clear);
  return {x,y,z,scale,visible:scale>.005};
}

function perimeter(w,d,r,y) {
  const pts=[];
  for(let c=0;c<4;c++) {
    const a=c*Math.PI/2;
    const cx=(c===0||c===3?1:-1)*(w/2-r);
    const cz=(c<2?1:-1)*(d/2-r);
    for(let k=0;k<=16;k++) {
      const t=a+k/16*Math.PI/2;
      pts.push(new THREE.Vector3(cx+Math.cos(t)*r,y,cz+Math.sin(t)*r));
    }
  }
  // Build the rounded rectangle clockwise, including straight edges.
  return new THREE.BufferGeometry().setFromPoints(pts);
}

function roundedPlate(width,depth,thickness,radius) {
  const shape=new THREE.Shape(),x=-width/2,z=-depth/2,r=radius;
  shape.moveTo(x+r,z);shape.lineTo(x+width-r,z);shape.absarc(x+width-r,z+r,r,-Math.PI/2,0,false);
  shape.lineTo(x+width,z+depth-r);shape.absarc(x+width-r,z+depth-r,r,0,Math.PI/2,false);
  shape.lineTo(x+r,z+depth);shape.absarc(x+r,z+depth-r,r,Math.PI/2,Math.PI,false);
  shape.lineTo(x,z+r);shape.absarc(x+r,z+r,r,Math.PI,Math.PI*1.5,false);
  const bevel=.018,body=thickness-bevel*2;
  const geometry=new THREE.ExtrudeGeometry(shape,{depth:body,steps:1,curveSegments:12,bevelEnabled:true,bevelThickness:bevel,bevelSize:bevel,bevelSegments:3});
  geometry.rotateX(-Math.PI/2);geometry.translate(0,-body/2,0);
  return geometry;
}

export function createStorageModel() {
  const group=new THREE.Group(), uniforms={scan:{value:-2},strength:{value:0},progress:{value:0}};
  const geometry=roundedPlate(3.05,2.1,.112,.28);
  const glassGeometry=roundedPlate(3.0,2.05,.18,.28);
  const metal=new THREE.MeshPhysicalMaterial({color:0x515b68,metalness:.96,roughness:.28,clearcoat:.4,clearcoatRoughness:.19,envMapIntensity:2.25});
  metal.onBeforeCompile=shader=>{
    shader.uniforms.uScan=uniforms.scan;
    shader.uniforms.uScanStrength=uniforms.strength;
    shader.vertexShader=shader.vertexShader.replace('#include <common>','#include <common>\nvarying vec3 vStorageWorld;');
    shader.vertexShader=shader.vertexShader.replace('#include <worldpos_vertex>','#include <worldpos_vertex>\nvStorageWorld=(modelMatrix*vec4(transformed,1.0)).xyz;');
    shader.fragmentShader=shader.fragmentShader.replace('#include <common>','#include <common>\nvarying vec3 vStorageWorld;\nuniform float uScan;\nuniform float uScanStrength;');
    shader.fragmentShader=shader.fragmentShader.replace('#include <roughnessmap_fragment>',`#include <roughnessmap_fragment>
      float grain=fract(sin(dot(vStorageWorld.xz,vec2(127.1,311.7)))*43758.5453);
      roughnessFactor=clamp(roughnessFactor+(grain-.5)*.055,.08,1.0);`);
    shader.fragmentShader=shader.fragmentShader.replace('#include <emissivemap_fragment>',`#include <emissivemap_fragment>
      float scan=exp(-pow((vStorageWorld.y-uScan)*32.0,2.0))*uScanStrength;
      totalEmissiveRadiance+=vec3(.12,.65,1.3)*scan;`);
  };
  metal.customProgramCacheKey=()=> 'cairn-storage-scan-v1';
  const glass=new THREE.MeshPhysicalMaterial({color:0x54aaff,metalness:.03,roughness:.07,transmission:.72,thickness:.60,ior:1.46,attenuationColor:0x1268c4,attenuationDistance:1.2,clearcoat:1,clearcoatRoughness:.06,envMapIntensity:2.8,emissive:0x005fbe,emissiveIntensity:.27});
  const edgeMaterial=new THREE.LineBasicMaterial({color:0x8397ad,transparent:true,opacity:.28});
  const blueEdgeMaterial=new THREE.LineBasicMaterial({color:0x8adaff,transparent:true,opacity:.85});
  const edgeGeometry=perimeter(3.05,2.1,.28,.045);
  const glassEdgeGeometry=perimeter(3.0,2.05,.28,.081);
  const pieces=layers.map(layer=>{
    const holder=new THREE.Group();
    const mesh=new THREE.Mesh(layer.kind==='work'?glassGeometry:geometry,layer.kind==='work'?glass:metal);
    mesh.castShadow=true;mesh.receiveShadow=true;
    const edge=new THREE.LineLoop(layer.kind==='work'?glassEdgeGeometry:edgeGeometry,layer.kind==='work'?blueEdgeMaterial:edgeMaterial);
    holder.add(mesh,edge);group.add(holder);
    holder.userData.layer=layer;
    return holder;
  });

  // Fine connections are anchored to the retained glass layers at every stage.
  const points=[],strands=100,segments=64;
  for(let line=0;line<strands;line++) {
    const angle=line*2.399963, radius=.12+(line%17)/17*1.03;
    for(let s=0;s<segments;s++) for(const t of [s/segments,(s+1)/segments]) {
      const twist=angle+Math.sin(t*Math.PI)*.7+Math.sin(t*Math.PI*3+angle)*.11;
      points.push(Math.cos(twist)*radius*(.37+.63*Math.abs(2*t-1)),t,Math.sin(twist)*radius*.65);
    }
  }
  const fiberGeometry=new THREE.BufferGeometry();
  fiberGeometry.setAttribute('position',new THREE.Float32BufferAttribute(points,3));
  const fiberUniforms={uLow:{value:-.79},uHigh:{value:-.39},uProgress:uniforms.progress};
  const fiberMaterial=new THREE.ShaderMaterial({transparent:true,depthWrite:false,blending:THREE.AdditiveBlending,uniforms:fiberUniforms,
    vertexShader:`uniform float uLow; uniform float uHigh; varying float vAlong; varying float vSeed;
      void main(){vAlong=position.y;vSeed=position.x;vec3 p=position;p.y=mix(uLow,uHigh,position.y);gl_Position=projectionMatrix*modelViewMatrix*vec4(p,1.0);}`,
    fragmentShader:`uniform float uProgress; varying float vAlong; varying float vSeed;
      void main(){float pulse=pow(.5+.5*sin(vAlong*22.0+vSeed*8.0-uProgress*16.0),12.0);
      gl_FragColor=vec4(vec3(.21,.62,1.0)+pulse*vec3(.35,.35,.35),.30+pulse*.60);
      #include <colorspace_fragment>
      }`
  });
  const fibers=new THREE.LineSegments(fiberGeometry,fiberMaterial);fibers.frustumCulled=false;group.add(fibers);

  const dustGeometry=new THREE.BufferGeometry();
  const specks=[];
  for(let i=0;i<160;i++) specks.push(Math.sin(i*37.11)*1.30,(i%3),Math.cos(i*23.7)*.85);
  dustGeometry.setAttribute('position',new THREE.Float32BufferAttribute(specks,3));
  const dustMaterial=new THREE.ShaderMaterial({transparent:true,depthWrite:false,blending:THREE.AdditiveBlending,
    uniforms:{uOpen:{value:0},uDpr:{value:1}},
    vertexShader:`uniform float uOpen; uniform float uDpr; void main(){vec3 p=position;p.y=mix(-.79+position.y*.20,-.68+position.y*.77,uOpen)+.008;vec4 mv=modelViewMatrix*vec4(p,1.0);gl_PointSize=clamp(16.0/-mv.z,1.0,2.4)*uDpr;gl_Position=projectionMatrix*mv;}`,
    fragmentShader:`void main(){float a=1.0-smoothstep(.10,.5,length(gl_PointCoord-.5));gl_FragColor=vec4(.3,.72,1.,a*.7);}`});
  const dust=new THREE.Points(dustGeometry,dustMaterial);dust.frustumCulled=false;group.add(dust);

  function update(progress) {
    progress=clamp(progress);
    pieces.forEach((piece,i)=>{
      const pose=layerPose(layers[i],progress);
      piece.position.set(pose.x,pose.y,pose.z);piece.scale.setScalar(Math.max(.001,pose.scale));piece.visible=pose.visible;
    });
    const open=smooth(progress*3);
    fiberUniforms.uLow.value=mix(-.79,-.68,open);
    fiberUniforms.uHigh.value=mix(-.39,.86,open);
    uniforms.progress.value=progress;
    uniforms.scan.value=mix(2.2,-1.8,clamp(progress*4));
    uniforms.strength.value=1-smooth(progress*3);
    dustMaterial.uniforms.uOpen.value=open;
  }
  function dispose(){geometry.dispose();glassGeometry.dispose();metal.dispose();glass.dispose();edgeGeometry.dispose();glassEdgeGeometry.dispose();edgeMaterial.dispose();blueEdgeMaterial.dispose();fiberGeometry.dispose();fiberMaterial.dispose();dustGeometry.dispose();dustMaterial.dispose();}
  update(0);
  return {group,update,dispose,pieces,uniforms,setDpr:dpr=>{dustMaterial.uniforms.uDpr.value=dpr;}};
}
