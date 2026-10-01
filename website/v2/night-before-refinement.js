(() => {
  const dialog = document.querySelector('.app-preview');
  if (!dialog || typeof dialog.showModal !== 'function') return;

  const image = dialog.querySelector('.preview-image');
  const title = dialog.querySelector('#preview-title');
  const choices = [...dialog.querySelectorAll('[data-screen]')];

  function selectScreen(key) {
    const choice = choices.find((button) => button.dataset.screen === key);
    if (!choice) return false;
    image.src = choice.dataset.src;
    image.alt = choice.dataset.alt;
    title.textContent = choice.textContent;
    choices.forEach((button) => {
      button.setAttribute('aria-pressed', String(button === choice));
    });
    return true;
  }

  document.querySelectorAll('[data-preview]').forEach((link) => {
    link.addEventListener('click', (event) => {
      if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
      if (!selectScreen(link.dataset.preview)) return;
      event.preventDefault();
      dialog.showModal();
      document.body.classList.add('preview-open');
    });
  });

  choices.forEach((button) => {
    button.addEventListener('click', () => selectScreen(button.dataset.screen));
  });
  dialog.querySelector('.preview-close').addEventListener('click', () => dialog.close());
  dialog.addEventListener('close', () => document.body.classList.remove('preview-open'));
  dialog.addEventListener('click', (event) => {
    if (event.target !== dialog) return;
    const bounds = dialog.getBoundingClientRect();
    if (event.clientX < bounds.left || event.clientX > bounds.right ||
        event.clientY < bounds.top || event.clientY > bounds.bottom) dialog.close();
  });
})();
