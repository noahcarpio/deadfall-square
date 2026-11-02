import '@fontsource/bebas-neue/latin-400.css';
import './ui/styles.css';
import { installTestHook } from './debug/TestHook';
import { Game } from './game/Game';

function boot(): void {
  const container = document.getElementById('app');
  if (!container) throw new Error('#app container missing');
  let game: Game;
  try {
    game = new Game(container);
  } catch (err) {
    console.error(err);
    const msg = document.createElement('div');
    msg.className = 'fatal';
    msg.textContent = 'Deadfall Square needs WebGL. Please use a modern browser with hardware acceleration enabled.';
    container.appendChild(msg);
    return;
  }
  if (new URLSearchParams(window.location.search).has('test')) installTestHook(game);
  game.start();
  document.getElementById('boot')?.remove();
}

boot();
