(() => {
  const workflow = document.querySelector('.workflow');
  if (workflow) {
    const tablist = workflow.querySelector('.workflow-tabs');
    const tabs = [...tablist.querySelectorAll('[data-step]')];
    const panels = [...workflow.querySelectorAll('[data-panel]')];
    const knownSteps = new Set(tabs.map((tab) => tab.dataset.step));
    const stepFromHash = () => {
      const value = window.location.hash.slice(1);
      return value === 'step-changes' ? 'changes' : value;
    };

    function activateStep(key, { focus = false, updateURL = false } = {}) {
      if (!knownSteps.has(key)) return;
      panels.forEach((panel) => { panel.hidden = panel.dataset.panel !== key; });
      tabs.forEach((tab) => {
        const selected = tab.dataset.step === key;
        tab.setAttribute('aria-selected', String(selected));
        tab.tabIndex = selected ? 0 : -1;
        if (selected && focus) tab.focus({ preventScroll: true });
      });
      if (updateURL && window.location.hash !== `#${key}`) {
        try { window.history.replaceState(null, '', `#${key}`); }
        catch { window.location.hash = key; }
      }
    }

    workflow.dataset.enhanced = 'true';
    tablist.hidden = false;
    activateStep(knownSteps.has(stepFromHash()) ? stepFromHash() : 'changes');

    tabs.forEach((tab, index) => {
      tab.addEventListener('click', () => activateStep(tab.dataset.step, { updateURL: true }));
      tab.addEventListener('keydown', (event) => {
        let nextIndex;
        if (event.key === 'ArrowRight') nextIndex = (index + 1) % tabs.length;
        else if (event.key === 'ArrowLeft') nextIndex = (index - 1 + tabs.length) % tabs.length;
        else if (event.key === 'Home') nextIndex = 0;
        else if (event.key === 'End') nextIndex = tabs.length - 1;
        else return;
        event.preventDefault();
        activateStep(tabs[nextIndex].dataset.step, { focus: true, updateURL: true });
      });
    });

    function followWorkflowHash() {
      const key = stepFromHash();
      if (!knownSteps.has(key)) return;
      activateStep(key);
      workflow.scrollIntoView({ block: 'start', behavior: 'auto' });
    }
    window.addEventListener('hashchange', followWorkflowHash);
    if (knownSteps.has(stepFromHash())) window.requestAnimationFrame(followWorkflowHash);
  }

  const dialog = document.querySelector('.app-preview');
  if (!dialog || typeof dialog.showModal !== 'function') return;
  const image = dialog.querySelector('.preview-image');
  const canvas = dialog.querySelector('.preview-image-wrap');
  const title = dialog.querySelector('#preview-title');
  const zoom = dialog.querySelector('.preview-zoom');
  const original = dialog.querySelector('.preview-original');
  const hint = dialog.querySelector('.preview-hint');
  const choices = [...dialog.querySelectorAll('[data-screen]')];

  function resetScroll() { canvas.scrollTo({ left: 0, top: 0, behavior: 'instant' }); }
  function setZoom(enabled) {
    canvas.classList.toggle('is-zoomed', enabled);
    zoom.setAttribute('aria-pressed', String(enabled));
    zoom.textContent = enabled ? 'Fit to window' : 'Actual size';
    hint.textContent = enabled ? 'Scroll across the image to inspect the details.' : 'Choose Actual size to read the details.';
    resetScroll();
  }
  function selectScreen(key) {
    const choice = choices.find((button) => button.dataset.screen === key);
    if (!choice) return false;
    image.src = choice.dataset.src;
    image.alt = choice.dataset.alt;
    original.href = choice.dataset.src;
    title.textContent = choice.textContent;
    choices.forEach((button) => button.setAttribute('aria-pressed', String(button === choice)));
    resetScroll();
    return true;
  }

  document.querySelectorAll('[data-preview]').forEach((link) => {
    link.addEventListener('click', (event) => {
      if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
      if (!selectScreen(link.dataset.preview)) return;
      event.preventDefault();
      setZoom(false);
      if (!dialog.open) dialog.showModal();
      document.body.classList.add('preview-open');
    });
  });
  choices.forEach((button) => button.addEventListener('click', () => selectScreen(button.dataset.screen)));
  zoom.addEventListener('click', () => {
    const enabled = zoom.getAttribute('aria-pressed') !== 'true';
    setZoom(enabled);
    if (enabled) canvas.focus({ preventScroll: true });
  });
  dialog.querySelector('.preview-close').addEventListener('click', () => dialog.close());
  dialog.addEventListener('close', () => {
    document.body.classList.remove('preview-open');
    setZoom(false);
  });
  dialog.addEventListener('click', (event) => {
    if (event.target !== dialog) return;
    const bounds = dialog.getBoundingClientRect();
    if (event.clientX < bounds.left || event.clientX > bounds.right ||
        event.clientY < bounds.top || event.clientY > bounds.bottom) dialog.close();
  });
})();
