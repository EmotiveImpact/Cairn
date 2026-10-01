import React,{useEffect,useState} from 'react';
import {createPortal} from 'react-dom';
import {Accordion} from 'radix-ui';

const steps=[
 {key:'overview',title:'See where your space goes',description:'Start with available space and its recent history. Find your next step without searching through every folder.',name:'Overview',alt:'Cairn Overview showing available space and its recent history'},
 {key:'developer',title:'Review before you remove',description:'Build output, package caches and developer tools. Inspect exact paths, sizes and requirements before you act. Known working locations stay protected.',name:'Developer Cleanup',alt:'Cairn Developer Cleanup showing cleanup candidates and review requirements'},
 {key:'activity',title:'See what happened',description:'Review recorded actions and the recovery options available for each one. Check the outcome before getting back to your build.',name:'Activity & Recovery',alt:'Cairn Activity and Recovery showing the record of cleanup actions'},
];

export function ProductTour({controls,visual}) {
 const [active,setActive]=useState('overview');
 useEffect(()=>{
  const section=document.querySelector('#inside-cairn');
  const compact=window.matchMedia('(max-width: 760px), (max-height: 760px)');
  const reduced=window.matchMedia('(prefers-reduced-motion: reduce)');
  let frame=0;
  const enabled=()=>!compact.matches&&!reduced.matches;
  const header=()=>document.querySelector('.site-header')?.getBoundingClientRect().height||76;
  const range=()=>Math.max(1,section.offsetHeight-(window.innerHeight-header()));
  const read=()=>{
   frame=0;
   if(!enabled())return;
   const progress=Math.max(0,Math.min(1,(header()-section.getBoundingClientRect().top)/range()));
   setActive(steps[Math.min(2,Math.floor(progress*3))].key);
   section.style.setProperty('--tour-progress',String(progress));
  };
  const schedule=()=>{if(!frame)frame=requestAnimationFrame(read);};
  const preference=()=>{section.classList.toggle('tour-ready',enabled());schedule();};
  window.addEventListener('scroll',schedule,{passive:true});
  window.addEventListener('resize',preference,{passive:true});
  compact.addEventListener('change',preference);
  reduced.addEventListener('change',preference);
  preference();
  return()=>{cancelAnimationFrame(frame);section.classList.remove('tour-ready');window.removeEventListener('scroll',schedule);window.removeEventListener('resize',preference);compact.removeEventListener('change',preference);reduced.removeEventListener('change',preference);};
 },[]);
 const select=value=>{
  if(!value)return;
  setActive(value);
  const section=document.querySelector('#inside-cairn');
  if(!section.classList.contains('tour-ready'))return;
  const index=steps.findIndex(step=>step.key===value);
  const header=document.querySelector('.site-header')?.getBoundingClientRect().height||76;
  const travel=Math.max(1,section.offsetHeight-(window.innerHeight-header));
  window.scrollTo({top:window.scrollY+section.getBoundingClientRect().top-header+travel*((index+.5)/3),behavior:'smooth'});
 };
 return <>
  {createPortal(<Accordion.Root type="single" value={active} onValueChange={select} className="product-tour-steps">
    {steps.map((step,index)=><Accordion.Item key={step.key} value={step.key} className="product-tour-step">
      <Accordion.Header><Accordion.Trigger className="product-tour-trigger"><span className="product-tour-number" aria-hidden="true">{index+1}</span><span>{step.title}</span><span className="product-tour-chevron" aria-hidden="true"/></Accordion.Trigger></Accordion.Header>
      <Accordion.Content className="product-tour-description"><p>{step.description}</p><a className="text-link" href={`assets/app-${step.key}-current.png`} data-preview={step.key} aria-haspopup="dialog">Explore {step.name}</a></Accordion.Content>
    </Accordion.Item>)}
  </Accordion.Root>,controls)}
  {createPortal(<figure>
    {steps.map(step=><a key={step.key} className="product-tour-screen" hidden={active!==step.key} href={`assets/app-${step.key}-current.png`} data-preview={step.key} aria-haspopup="dialog" aria-label={`Open the full Cairn ${step.name} preview`}>
      <img src={`assets/app-${step.key}-current.png`} width="1120" height="740" alt={step.alt} loading="lazy" decoding="async"/>
    </a>)}
    <figcaption><span>{steps.find(step=>step.key===active).name}</span><span>Native app preview · Sample data</span></figcaption>
  </figure>,visual)}
 </>;
}
