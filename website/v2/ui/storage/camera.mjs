const clamp=n=>Math.max(0,Math.min(1,n));
const keys=[
  {eye:[4.4,3.0,9.8],target:[0,.23,0],rotation:-.17},
  {eye:[4.6,2.8,11.9],target:[.9,.23,0],rotation:-.06},
  {eye:[2.6,1.1,6.8],target:[0,.12,0],rotation:.08},
  {eye:[3.9,2.6,8.9],target:[0,-.12,0],rotation:-.07}
];

// The protection chapter intentionally becomes a close study of the retained core.
export function cameraPose(progress,aspect=1.3,pointer={x:0,y:0}){
  const p=clamp(progress)*3,index=Math.min(2,Math.floor(p)),u=p-index,t=u*u*(3-2*u);
  const a=keys[index],b=keys[index+1],scale=Math.max(1,1.15/aspect);
  const interpolate=(a,b)=>a+(b-a)*t;
  return {eye:a.eye.map((v,i)=>(interpolate(v,b.eye[i])+(i===0?pointer.x*.16:i===1?-pointer.y*.10:0))*scale),
    target:a.target.map((v,i)=>interpolate(v,b.target[i])),rotation:interpolate(a.rotation,b.rotation)+pointer.x*.025,
    focus:Math.max(0,1-Math.abs(p-2))};
}
