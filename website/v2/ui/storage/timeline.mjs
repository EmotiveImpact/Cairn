const clamp = value => Math.max(0, Math.min(1, value));

// Scroll keeps moving through these plateaus; the composition stays still.
export const chapterStops = [0, .35, .65, 1];
export const holds = [[0, .12], [.28, .42], [.58, .72], [.88, 1]];

export function storyAt(scrollProgress) {
  const p = clamp(scrollProgress);
  for (let i = 0; i < holds.length; i++) {
    const [start, end] = holds[i];
    if (p >= start && p <= end) return {pose: i / 3, chapter: i, holding: true};
    const next = holds[i + 1];
    if (next && p > end && p < next[0]) {
      const t = (p - end) / (next[0] - end);
      // Geometry and camera supply their own easing, so this mapping stays linear.
      return {pose: (i + t) / 3, chapter: t < .5 ? i : i + 1, holding: false};
    }
  }
}
