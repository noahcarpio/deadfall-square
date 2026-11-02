import { clamp } from '../core/math';
import { Music, type MusicMood } from './Music';
import { SFX_RECIPES, type SfxName, type SynthContext } from './Sfx';

export interface SfxOptions {
  x?: number;
  z?: number;
  volume?: number;
  pitch?: number;
}

/** Minimum seconds between two plays of the same sound (prevents machine-gun stacking). */
const THROTTLE: Partial<Record<SfxName, number>> = {
  hit: 0.035,
  zombieDeath: 0.05,
  groan: 0.4,
  zombieAttack: 0.12,
  playerHurt: 0.15,
  coin: 0.05,
  acidSplash: 0.08,
  structureHit: 0.1,
  turret: 0.05,
  footstep: 0.12,
  explosion: 0.04,
};

const MAX_VOICES = 40;

/**
 * Web Audio graph: master -> compressor -> destination, with separate SFX and
 * music buses. Everything is synthesised at runtime (no audio files). The
 * context is created lazily on the first user gesture, as browsers require.
 */
export class AudioEngine {
  private ctx: AudioContext | null = null;
  private master!: GainNode;
  private sfxBus!: GainNode;
  private musicBus!: GainNode;
  private noise!: AudioBuffer;
  private music: Music | null = null;
  private readonly lastPlayed = new Map<SfxName, number>();
  private voices = 0;
  private flameGain: GainNode | null = null;
  private flameSource: AudioBufferSourceNode | null = null;
  listenerX = 0;
  listenerZ = 0;
  private volumes = { master: 0.8, music: 0.5, sfx: 0.8 };
  private pendingMood: MusicMood = 'menu';

  get ready(): boolean {
    return this.ctx !== null && this.ctx.state === 'running';
  }

  /** Must be called from a user-gesture handler. Safe to call repeatedly. */
  unlock(): void {
    if (!this.ctx) {
      const Ctor = window.AudioContext ?? (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
      if (!Ctor) return;
      try {
        this.ctx = new Ctor();
      } catch {
        return;
      }
      const ctx = this.ctx;
      const comp = ctx.createDynamicsCompressor();
      comp.threshold.value = -14;
      comp.knee.value = 12;
      comp.ratio.value = 4;
      comp.attack.value = 0.003;
      comp.release.value = 0.2;
      comp.connect(ctx.destination);
      this.master = ctx.createGain();
      this.master.connect(comp);
      this.sfxBus = ctx.createGain();
      this.sfxBus.connect(this.master);
      this.musicBus = ctx.createGain();
      this.musicBus.connect(this.master);
      this.noise = makeNoiseBuffer(ctx);
      this.applyVolumes();
      this.music = new Music(ctx, this.musicBus, this.noise);
      this.music.setMood(this.pendingMood);
      this.music.start();
    }
    if (this.ctx.state === 'suspended') void this.ctx.resume().catch(() => undefined);
  }

  setVolumes(master: number, music: number, sfx: number): void {
    this.volumes = { master, music, sfx };
    this.applyVolumes();
  }

  private applyVolumes(): void {
    if (!this.ctx) return;
    const t = this.ctx.currentTime;
    this.master.gain.setTargetAtTime(this.volumes.master, t, 0.05);
    this.sfxBus.gain.setTargetAtTime(this.volumes.sfx, t, 0.05);
    this.musicBus.gain.setTargetAtTime(this.volumes.music * 0.55, t, 0.05);
  }

  setMusicMood(mood: MusicMood): void {
    this.pendingMood = mood;
    this.music?.setMood(mood);
  }

  /** Mutes/unmutes all output (pause menu keeps music quietly). */
  setPaused(paused: boolean): void {
    if (!this.ctx) return;
    this.sfxBus.gain.setTargetAtTime(paused ? 0 : this.volumes.sfx, this.ctx.currentTime, 0.05);
    if (paused) this.setFlame(false);
  }

  setListener(x: number, z: number): void {
    this.listenerX = x;
    this.listenerZ = z;
  }

  sfx(name: SfxName, opts: SfxOptions = {}): void {
    const ctx = this.ctx;
    if (!ctx || ctx.state !== 'running') return;
    if (this.voices >= MAX_VOICES) return;
    const now = ctx.currentTime;
    const throttle = THROTTLE[name];
    if (throttle !== undefined) {
      const last = this.lastPlayed.get(name) ?? -1;
      if (now - last < throttle) return;
    }
    this.lastPlayed.set(name, now);

    let volume = opts.volume ?? 1;
    let pan = 0;
    if (opts.x !== undefined && opts.z !== undefined) {
      const dx = opts.x - this.listenerX;
      const dz = opts.z - this.listenerZ;
      const dist = Math.hypot(dx, dz);
      volume *= clamp(1.15 - dist / 34, 0.06, 1);
      pan = clamp(dx / 22, -0.85, 0.85);
    }
    if (volume < 0.02) return;

    const out = ctx.createGain();
    out.gain.value = volume;
    const panner = ctx.createStereoPanner();
    panner.pan.value = pan;
    out.connect(panner);
    panner.connect(this.sfxBus);

    const synth: SynthContext = { ctx, out, noise: this.noise, t: now, pitch: opts.pitch ?? 1 };
    const duration = SFX_RECIPES[name](synth);
    this.voices++;
    window.setTimeout(() => {
      this.voices--;
      out.disconnect();
      panner.disconnect();
    }, (duration + 0.2) * 1000);
  }

  /** Continuous flamethrower roar while the trigger is held. */
  setFlame(on: boolean): void {
    const ctx = this.ctx;
    if (!ctx) return;
    if (on && !this.flameSource) {
      const src = ctx.createBufferSource();
      src.buffer = this.noise;
      src.loop = true;
      const lp = ctx.createBiquadFilter();
      lp.type = 'lowpass';
      lp.frequency.value = 900;
      const bp = ctx.createBiquadFilter();
      bp.type = 'peaking';
      bp.frequency.value = 300;
      bp.gain.value = 8;
      const g = ctx.createGain();
      g.gain.value = 0;
      g.gain.setTargetAtTime(0.55, ctx.currentTime, 0.04);
      src.connect(lp).connect(bp).connect(g).connect(this.sfxBus);
      src.start();
      this.flameSource = src;
      this.flameGain = g;
    } else if (!on && this.flameSource && this.flameGain) {
      const src = this.flameSource;
      this.flameGain.gain.setTargetAtTime(0, ctx.currentTime, 0.06);
      window.setTimeout(() => {
        try {
          src.stop();
        } catch {
          /* already stopped */
        }
        src.disconnect();
      }, 400);
      this.flameSource = null;
      this.flameGain = null;
    }
  }

  /** Music intensity follows the game state. */
  setIntensity(level: number): void {
    this.music?.setIntensity(level);
  }
}

function makeNoiseBuffer(ctx: AudioContext): AudioBuffer {
  const len = ctx.sampleRate * 2;
  const buf = ctx.createBuffer(1, len, ctx.sampleRate);
  const data = buf.getChannelData(0);
  for (let i = 0; i < len; i++) data[i] = Math.random() * 2 - 1;
  return buf;
}
