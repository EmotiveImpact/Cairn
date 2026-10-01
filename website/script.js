const screens = {
  overview: {
    src: "assets/app-overview.png",
    alt: "Cairn Overview preview showing available space, recent storage history, and a file review prompt",
    caption: "Overview shows available space, recent history, and a next step grounded in measured findings."
  },
  storage: {
    src: "assets/app-storage.png",
    alt: "Cairn Storage preview showing internal and external drives, protected locations, and a verified copy option for finished exports",
    caption: "Storage distinguishes supported export copies from protected source and session locations."
  }
};

const preview = document.querySelector("#app-preview");
const caption = document.querySelector("#preview-caption");
const tabs = [...document.querySelectorAll(".preview-tab")];

for (const tab of tabs) {
  tab.addEventListener("click", () => {
    const screen = screens[tab.dataset.screen];
    if (!screen) return;
    preview.src = screen.src;
    preview.alt = screen.alt;
    caption.textContent = screen.caption;
    for (const other of tabs) {
      const active = other === tab;
      other.classList.toggle("is-active", active);
      other.setAttribute("aria-pressed", String(active));
    }
  });
}
