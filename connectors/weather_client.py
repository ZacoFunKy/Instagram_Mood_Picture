import requests
import logging

# Bordeaux Coordinates
LAT = 44.8404
LON = -0.5805

logger = logging.getLogger(__name__)

def get_bordeaux_weather() -> str:
    """
    Fetches the daily weather forecast for Bordeaux using Open-Meteo API.
    Returns a human-readable summary string.
    """
    url = "https://api.open-meteo.com/v1/forecast"
    params = {
        "latitude": LAT,
        "longitude": LON,
        "daily": "weather_code,temperature_2m_max,temperature_2m_min",
        "timezone": "Europe/Paris",
        "forecast_days": 1
    }

    try:
        response = requests.get(url, params=params, timeout=10)
        response.raise_for_status()
        data = response.json()
        
        daily = data.get("daily", {})
        if not daily:
             return "Weather data unavailable."

        # Parse data
        max_temp = daily.get("temperature_2m_max", ["?"])[0]
        min_temp = daily.get("temperature_2m_min", ["?"])[0]
        code = daily.get("weather_code", [0])[0]
        
        # WMO Weather interpretation
        # 0: Clear, 1-3: Cloudy, 45-48: Fog, 51-55: Drizzle, 61-65: Rain, 71-77: Snow, 95-99: Thunderstorm
        condition = "Unknown"
        if code == 0: condition = "Ensoleillé ☀️"
        elif code in [1, 2, 3]: condition = "Nuageux/Éclaircies ⛅"
        elif code in [45, 48]: condition = "Brumeux 🌫️"
        elif code in [51, 53, 55]: condition = "Bruine 🌧️"
        elif code in [61, 63, 65]: condition = "Pluvieux ☔"
        elif code in [71, 73, 75, 77]: condition = "Neige ❄️"
        elif code >= 80 and code <= 82: condition = "Averses 🌦️"
        elif code >= 95: condition = "Orageux ⛈️"
        
        summary = f"Météo Bordeaux: {condition}, Min {min_temp}°C, Max {max_temp}°C."
        logger.info(summary)
        return summary

    except Exception as e:
        logger.error(f"Failed to fetch weather: {e}")
        return "Weather unavailable (Error)."
