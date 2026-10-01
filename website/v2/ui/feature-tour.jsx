import React from 'react';
import {Tabs} from 'radix-ui';

const examples = [
  [['Xcode build data','Review requirements'],['Simulator support','Review requirements'],['Generated project folders','Check rebuildability']],
  [['Node & npm','Package caches'],['Python','Tool caches'],['Rust','Build & package data']],
  [['Large files','Review individually'],['Duplicate files','Compare copies'],['App data','Review individually']],
  [['Browser data','Temporary files'],['Creative tools','Temporary files'],['Saved work','Keep distinct from cache']],
  [['Model downloads','Review storage'],['AI app caches','Review requirements'],['Known coding sessions','Protected']],
  [['Eligible export copies','Verify the copy'],['Supported encrypted drive','Originals retained'],['Low-space alerts','Optional notifications']],
];

export function FeatureTour({features}) {
  return <Tabs.Root defaultValue="0" orientation="vertical" className="feature-tour">
    <div className="feature-tour-art">
      {features.map((feature,i)=><Tabs.Content key={i} value={String(i)} className="feature-tour-panel">
        <div className="feature-tour-window">
          <div className="feature-tour-chrome"><span className="feature-tour-mark" dangerouslySetInnerHTML={{__html:feature.icon}}/><span>Cairn</span><span className="feature-tour-example">Illustrative view</span></div>
          <div className="feature-tour-window-body"><p className="feature-tour-eyebrow">{i===5?'Storage & alerts':'A closer look'}</p><h3>{feature.title}</h3>
            <div className="feature-tour-rows">{examples[i].map(([label,note])=><div key={label}><span>{label}</span><small className={note==='Protected'?'is-protected':''}>{note}</small></div>)}</div>
            <p className="feature-tour-window-note">{i===5?'Check the outcome. Keep your originals.':'Review the details before deciding what goes.'}</p>
          </div>
        </div>
        <p className="feature-tour-disclaimer">Illustrative categories. Availability depends on what Cairn finds on your Mac.</p>
      </Tabs.Content>)}
    </div>
    <Tabs.List className="feature-tour-options" aria-label="Explore Cairn features">
      {features.map((feature,i)=><Tabs.Trigger key={i} value={String(i)} className="feature-tour-option">
        <span className="feature-tour-option-heading"><span className="feature-tour-mark" dangerouslySetInnerHTML={{__html:feature.icon}}/><span>{feature.title}</span><span className="feature-tour-indicator" aria-hidden="true">+</span></span>
        <span className="feature-tour-description">{feature.description}</span>
      </Tabs.Trigger>)}
    </Tabs.List>
  </Tabs.Root>;
}
