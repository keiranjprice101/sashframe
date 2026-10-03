import type { Weather } from './types';

/**
 * Coordinates for Local Forecast, UK
 * Latitude: 51.453° N, Longitude: -0.902° W
 */
export const DEFAULT_WEATHER_COORDS = {
  latitude: 51.453,
  longitude: -0.902,
  name: 'Local Forecast'
};

/**
 * WMO Weather interpretation codes (WW)
 */
export function getWeatherConditionFromCode(code: number): string {
  switch (code) {
    case 0:
      return 'Clear';
    case 1:
      return 'Mainly Clear';
    case 2:
      return 'Partly Cloudy';
    case 3:
      return 'Overcast';
    case 45:
    case 48:
      return 'Fog';
    case 51:
      return 'Light Drizzle';
    case 53:
      return 'Drizzle';
    case 55:
      return 'Heavy Drizzle';
    case 56:
    case 57:
      return 'Freezing Drizzle';
    case 61:
      return 'Light Rain';
    case 63:
      return 'Rain';
    case 65:
      return 'Heavy Rain';
    case 66:
    case 67:
      return 'Freezing Rain';
    case 71:
      return 'Light Snow';
    case 73:
      return 'Snow';
    case 75:
      return 'Heavy Snow';
    case 77:
      return 'Snow Grains';
    case 80:
      return 'Light Showers';
    case 81:
      return 'Showers';
    case 82:
      return 'Heavy Showers';
    case 85:
    case 86:
      return 'Snow Showers';
    case 95:
      return 'Thunderstorm';
    case 96:
    case 99:
      return 'Thunderstorm with Hail';
    default:
      return 'Partly Cloudy';
  }
}

/**
 * Fetch real-time weather from Open-Meteo for Local Forecast, UK.
 * Fully authless, zero API key required, CORS-enabled.
 */
export async function fetchLocalWeather(): Promise<Weather> {
  const url = `https://api.open-meteo.com/v1/forecast?latitude=${DEFAULT_WEATHER_COORDS.latitude}&longitude=${DEFAULT_WEATHER_COORDS.longitude}&current=temperature_2m,weather_code&daily=temperature_2m_max,temperature_2m_min&timezone=Europe%2FLondon`;

  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), 8000);

  try {
    const res = await fetch(url, { signal: controller.signal });
    clearTimeout(timeoutId);

    if (!res.ok) {
      throw new Error(`Open-Meteo responded with status ${res.status}`);
    }

    const data = await res.json();
    const currentTemp = Math.round(data.current?.temperature_2m ?? 15);
    const code = Number(data.current?.weather_code ?? 2);
    const condition = getWeatherConditionFromCode(code);
    const high = data.daily?.temperature_2m_max?.[0] != null 
      ? Math.round(data.daily.temperature_2m_max[0]) 
      : undefined;
    const low = data.daily?.temperature_2m_min?.[0] != null 
      ? Math.round(data.daily.temperature_2m_min[0]) 
      : undefined;

    return {
      temperature: currentTemp,
      unit: '°C',
      condition,
      high,
      low
    };
  } catch (err) {
    clearTimeout(timeoutId);
    throw err;
  }
}
