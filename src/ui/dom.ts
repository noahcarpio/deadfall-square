type Child = Node | string | null | undefined | false;

export interface ElementProps {
  class?: string;
  text?: string;
  html?: never;
  attrs?: Record<string, string>;
  style?: Partial<CSSStyleDeclaration>;
  on?: Partial<{ [K in keyof HTMLElementEventMap]: (e: HTMLElementEventMap[K]) => void }>;
}

/** Tiny hyperscript helper for building DOM without innerHTML. */
export function h<K extends keyof HTMLElementTagNameMap>(tag: K, props: ElementProps = {}, children: Child[] = []): HTMLElementTagNameMap[K] {
  const el = document.createElement(tag);
  if (props.class) el.className = props.class;
  if (props.text !== undefined) el.textContent = props.text;
  if (props.attrs) for (const [k, v] of Object.entries(props.attrs)) el.setAttribute(k, v);
  if (props.style) Object.assign(el.style, props.style);
  if (props.on) {
    for (const [k, fn] of Object.entries(props.on)) {
      if (fn) el.addEventListener(k, fn as EventListener);
    }
  }
  for (const c of children) {
    if (c === null || c === undefined || c === false) continue;
    el.appendChild(typeof c === 'string' ? document.createTextNode(c) : c);
  }
  return el;
}

export function clear(el: HTMLElement): void {
  while (el.firstChild) el.removeChild(el.firstChild);
}

/** Sets text only when it changed (avoids layout thrash in per-frame HUD updates). */
export function setText(el: HTMLElement, text: string): void {
  if (el.textContent !== text) el.textContent = text;
}

export function setWidth(el: HTMLElement, fraction: number): void {
  const v = `${(Math.max(0, Math.min(1, fraction)) * 100).toFixed(1)}%`;
  if (el.style.width !== v) el.style.width = v;
}

export function toggle(el: HTMLElement, cls: string, on: boolean): void {
  if (el.classList.contains(cls) !== on) el.classList.toggle(cls, on);
}
