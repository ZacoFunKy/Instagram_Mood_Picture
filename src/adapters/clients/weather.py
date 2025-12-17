"""
Weather forecast module for Bordeaux using Open-Meteo API.

Provides human-readable weather summaries with WMO weather code interpretation.
This module runs at 3am UTC, returning a forecast for the upcoming day (not real-time).
It attempts to use the User's last known location from the database, falling back to Bordeaux.
"""

import logging
import os
from enum import IntEnum
from typing import Optional, Tuple, Dict, Any
from dataclasses import dataclass

import requests
import pymongo
from dotenv import load_dotenv
from geopy.geocoders import Nominatim

# Load Env for DB
load_dotenv(dotenv_path="assets/.env")

# ============================================================================
# CONSTANTS & CONFIGURATION
# ============================================================================

# Bordeaux Coordinates (France) - DEFAULT
DEFAULT_LATITUDE = 44.8404
DEFAULT_LONGITUDE = -0.5805
TIMEZONE = "Europe/Paris"

# Open-Meteo API
API_URL = "https://api.open-meteo.com/v1/forecast"
REQUEST_TIMEOUT = 10

logger = logging.getLogger(__name__)


# ============================================================================
# ENUMS - WMO WEATHER CODES
# ============================================================================

class WMOWeatherCode(IntEnum):
    """
    WMO Weather Codes (0-99) for weather code interpretation.
    Reference: https://open-meteo.com/en/docs#weather_code
    """
    CLEAR = 0
    MAINLY_CLEAR = 1
    PARTLY_CLOUDY = 2
    OVERCAST = 3
    FOG = 45
    DEPOSITING_RIME_FOG = 48
    LIGHT_DRIZZLE = 51
    MODERATE_DRIZZLE = 53
    DENSE_DRIZZLE = 55
    LIGHT_FREEZING_DRIZZLE = 56
    DENSE_FREEZING_DRIZZLE = 57
    LIGHT_RAIN = 61
    MODERATE_RAIN = 63
    HEAVY_RAIN = 65
    LIGHT_FREEZING_RAIN = 66
    HEAVY_FREEZING_RAIN = 67
    LIGHT_SNOW = 71
    MODERATE_SNOW = 73
    HEAVY_SNOW = 75
    SNOW_GRAINS = 77
    LIGHT_RAIN_SHOWERS = 80
    MODERATE_RAIN_SHOWERS = 81
    VIOLENT_RAIN_SHOWERS = 82
    LIGHT_SNOW_SHOWERS = 85
    HEAVY_SNOW_SHOWERS = 86
    THUNDERSTORM = 95
    THUNDERSTORM_WITH_LIGHT_HAIL = 96
    THUNDERSTORM_WITH_HEAVY_HAIL = 99


class WeatherCondition(IntEnum):
    """Human-readable weather condition classifications."""
    SUNNY = 0
    CLOUDY = 1
    FOG = 2
    DRIZZLE = 3
    RAINY = 4
    SNOW = 5
    SHOWERS = 6
    THUNDERSTORM = 7


# ============================================================================
# DATA CLASSES
# ============================================================================

@dataclass
class WeatherData:
    """Encapsulates weather forecast data."""
    condition: str          # Description
    condition_code: WeatherCondition
    min_temp: float         # Minimum temperature in Celsius
    max_temp: float         # Maximum temperature in Celsius
    wmo_code: int           # Raw WMO code
    location_name: str      # City name

    def __str__(self) -> str:
        """Returns human-readable summary."""
        return f"Meteo {self.location_name}: {self.condition}, Min {self.min_temp}C, Max {self.max_temp}C."

    def to_tuple(self) -> Tuple[str, Dict[str, Any]]:
        """Returns summary string and metadata dict."""
        metadata = {
            "condition": self.condition,
            "condition_code": self.condition_code.value,
            "temp_min": self.min_temp,
            "temp_max": self.max_temp,
            "wmo_code": self.wmo_code,
            "location": self.location_name
        }
        return str(self), metadata


# ============================================================================
# WMO CODE INTERPRETER
# ============================================================================

class WMOInterpreter:
    """Interprets WMO weather codes to human-readable descriptions."""

    CODE_MAPPINGS = {
        0: ("Ensoleillé (Sunny)", WeatherCondition.SUNNY),
        1: ("Nuageux (Mainly Clear)", WeatherCondition.CLOUDY),
        2: ("Nuageux (Partly Cloudy)", WeatherCondition.CLOUDY),
        3: ("Nuageux (Overcast)", WeatherCondition.CLOUDY),
        45: ("Brumeux (Fog)", WeatherCondition.FOG),
        48: ("Brumeux (Rime Fog)", WeatherCondition.FOG),
        51: ("Bruine (Light Drizzle)", WeatherCondition.DRIZZLE),
        53: ("Bruine (Moderate Drizzle)", WeatherCondition.DRIZZLE),
        55: ("Bruine (Dense Drizzle)", WeatherCondition.DRIZZLE),
        56: ("Bruine gelée (Freezing Drizzle)", WeatherCondition.DRIZZLE),
        57: ("Bruine gelée (Heavy Freezing Drizzle)", WeatherCondition.DRIZZLE),
        61: ("Pluvieux (Light Rain)", WeatherCondition.RAINY),
        63: ("Pluvieux (Moderate Rain)", WeatherCondition.RAINY),
        65: ("Pluvieux (Heavy Rain)", WeatherCondition.RAINY),
        66: ("Pluie gelée (Light Freezing Rain)", WeatherCondition.RAINY),
        67: ("Pluie gelée (Heavy Freezing Rain)", WeatherCondition.RAINY),
        71: ("Neige (Light Snow)", WeatherCondition.SNOW),
        73: ("Neige (Moderate Snow)", WeatherCondition.SNOW),
        75: ("Neige (Heavy Snow)", WeatherCondition.SNOW),
        77: ("Grêle de neige (Snow Grains)", WeatherCondition.SNOW),
        80: ("Averses (Light Showers)", WeatherCondition.SHOWERS),
        81: ("Averses (Moderate Showers)", WeatherCondition.SHOWERS),
        82: ("Averses violentes (Violent Showers)", WeatherCondition.SHOWERS),
        85: ("Averses de neige (Light Snow Showers)", WeatherCondition.SNOW),
        86: ("Averses de neige (Heavy Snow Showers)", WeatherCondition.SNOW),
        95: ("Orageux (Thunderstorm)", WeatherCondition.THUNDERSTORM),
        96: ("Orageux (Thunderstorm with Light Hail)", WeatherCondition.THUNDERSTORM),
        99: ("Orageux (Thunderstorm with Heavy Hail)", WeatherCondition.THUNDERSTORM),
    }

    @classmethod
    def interpret(cls, wmo_code: int) -> Tuple[str, WeatherCondition]:
        """
        Interprets a WMO weather code.

        Returns:
            Tuple of (description, condition_code).
        """
        if wmo_code not in cls.CODE_MAPPINGS:
            logger.warning(f"Unknown WMO code: {wmo_code}, defaulting to 'Unknown'")
            return "Unknown", WeatherCondition.CLOUDY

        return cls.CODE_MAPPINGS[wmo_code]


# ============================================================================
# LOCATION SERVICE
# ============================================================================

def get_target_location() -> Tuple[float, float, str]:
    """
    Determines which location to use for weather.
    Priority:
    1. Last known location from 'daily_logs' in Database (within last 5 days).
    2. Default: Bordeaux.

    Returns:
        Tuple (latitude, longitude, city_name)
    """
    mongo_uri = os.getenv("MONGO_URI")
    if not mongo_uri:
        logger.warning("MONGO_URI not set. Using Default (Bordeaux).")
        return DEFAULT_LATITUDE, DEFAULT_LONGITUDE, "Bordeaux"

    try:
        client = pymongo.MongoClient(mongo_uri)
        db = client.get_database() # Uses DB from URI
        
        # Check 'daily_logs' for recent location
        collection = db['daily_logs']
        # Find last entry with 'location' field
        last_entry = collection.find_one(
            {"location": {"$exists": True, "$ne": None}, "date": {"$exists": True}},
            sort=[("date", -1)]
        )

        if last_entry and "location" in last_entry:
             city = last_entry["location"]
             logger.info(f"Found recent location in DB: {city}")
             
             # Geocode City Name -> Lat/Lon
             geolocator = Nominatim(user_agent="mood_predictor_bot")
             location = geolocator.geocode(city)
             
             if location:
                 return location.latitude, location.longitude, city
             else:
                 logger.warning(f"Could not geocode city '{city}'. Using Default.")

    except Exception as e:
        logger.error(f"Error fetching location from DB: {e}. Using Default.")

    return DEFAULT_LATITUDE, DEFAULT_LONGITUDE, "Bordeaux"


# ============================================================================
# API INTERACTION
# ============================================================================

class WeatherAPIClient:
    """Handles Open-Meteo API interactions."""

    def __init__(self) -> None:
        pass # Lat/Lon fetched per request now

    def fetch_daily_forecast(self) -> Optional[WeatherData]:
        """
        Fetches daily weather forecast from Open-Meteo API.
        The script runs at 3am, so this returns the forecast for the upcoming day.
        """
        
        lat, lon, city = get_target_location()
        
        params = {
            "latitude": lat,
            "longitude": lon,
            "daily": "weather_code,temperature_2m_max,temperature_2m_min",
            "timezone": TIMEZONE,
            "forecast_days": 1
        }

        try:
            response = requests.get(
                API_URL,
                params=params,
                timeout=REQUEST_TIMEOUT
            )
            response.raise_for_status()
            data = response.json()

            return self._parse_forecast(data, city)

        except Exception as e:
            logger.error(f"Unexpected error fetching weather: {e}")
            return None

    def _parse_forecast(self, api_data: Dict[str, Any], city: str) -> Optional[WeatherData]:
        """Parses Open-Meteo API response."""
        try:
            daily = api_data.get("daily", {})
            if not daily:
                logger.warning("No daily forecast in API response")
                return None

            max_temps = daily.get("temperature_2m_max", [None])
            min_temps = daily.get("temperature_2m_min", [None])
            weather_codes = daily.get("weather_code", [None])

            max_temp = max_temps[0] if max_temps and max_temps[0] is not None else "?"
            min_temp = min_temps[0] if min_temps and min_temps[0] is not None else "?"
            wmo_code = weather_codes[0] if weather_codes and weather_codes[0] is not None else 0

            description, condition = WMOInterpreter.interpret(int(wmo_code))

            return WeatherData(
                condition=description,
                condition_code=condition,
                min_temp=float(min_temp) if min_temp != "?" else 0.0,
                max_temp=float(max_temp) if max_temp != "?" else 0.0,
                wmo_code=int(wmo_code),
                location_name=city
            )

        except (KeyError, IndexError, ValueError) as e:
            logger.error(f"Failed to parse forecast data: {e}")
            return None


# ============================================================================
# PUBLIC API
# ============================================================================

def get_bordeaux_weather() -> str:
    """
    Fetches daily weather forecast (auto-location or Bordeaux).
    Returns: Human-readable weather summary string.
    """
    client = WeatherAPIClient()

    try:
        weather = client.fetch_daily_forecast()

        if weather is None:
            logger.warning("Weather forecast unavailable")
            return "Weather unavailable (Error)."

        logger.info(str(weather))
        return str(weather)

    except Exception as e:
        logger.error(f"Critical error in get_bordeaux_weather: {e}")
        return "Weather unavailable (Error)."


def get_bordeaux_weather_detailed() -> Optional[Tuple[str, Dict[str, Any]]]:
    """
    Fetches detailed weather forecast with metadata.
    Returns: Tuple of (summary_string, metadata_dict) or None.
    """
    client = WeatherAPIClient()

    try:
        weather = client.fetch_daily_forecast()

        if weather is None:
            return None

        return weather.to_tuple()

    except Exception as e:
        logger.error(f"Error in get_bordeaux_weather_detailed: {e}")
        return None
