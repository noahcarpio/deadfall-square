import { defaultQuality, type QualityLevel } from '../config/quality';
import { clamp } from './math';
import { Storage } from './Storage';

export interface SettingsData {
  masterVolume: number;
  musicVolume: number;
  sfxVolume: number;
  sensitivity: number;
  quality: QualityLevel;
  showFps: boolean;
  screenShake: boolean;
  damageNumbers: boolean;
}

const KEY = 'deadfall.settings.v1';

export function defaultSettings(): SettingsData {
  return {
    masterVolume: 0.8,
    musicVolume: 0.5,
    sfxVolume: 0.8,
    sensitivity: 1,
    quality: defaultQuality(),
    showFps: false,
    screenShake: true,
    damageNumbers: true,
  };
}

/** Validates untrusted (stored) settings, falling back to defaults per field. */
export function sanitizeSettings(raw: Partial<SettingsData> | null | undefined): SettingsData {
  const d = defaultSettings();
  if (!raw || typeof raw !== 'object') return d;
  const num = (v: unknown, def: number, min: number, max: number): number =>
    typeof v === 'number' && Number.isFinite(v) ? clamp(v, min, max) : def;
  const bool = (v: unknown, def: boolean): boolean => (typeof v === 'boolean' ? v : def);
  return {
    masterVolume: num(raw.masterVolume, d.masterVolume, 0, 1),
    musicVolume: num(raw.musicVolume, d.musicVolume, 0, 1),
    sfxVolume: num(raw.sfxVolume, d.sfxVolume, 0, 1),
    sensitivity: num(raw.sensitivity, d.sensitivity, 0.2, 3),
    quality: raw.quality === 'low' || raw.quality === 'medium' || raw.quality === 'high' ? raw.quality : d.quality,
    showFps: bool(raw.showFps, d.showFps),
    screenShake: bool(raw.screenShake, d.screenShake),
    damageNumbers: bool(raw.damageNumbers, d.damageNumbers),
  };
}

/** Persistent user settings with change notification. */
export class Settings {
  data: SettingsData;
  private readonly listeners = new Set<(s: SettingsData) => void>();

  constructor() {
    this.data = sanitizeSettings(Storage.get<Partial<SettingsData> | null>(KEY, null));
  }

  update(patch: Partial<SettingsData>): void {
    this.data = sanitizeSettings({ ...this.data, ...patch });
    Storage.set(KEY, this.data);
    for (const l of this.listeners) l(this.data);
  }

  onChange(fn: (s: SettingsData) => void): void {
    this.listeners.add(fn);
  }
}
