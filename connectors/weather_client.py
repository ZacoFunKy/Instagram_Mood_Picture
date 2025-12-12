"""
Weather forecast module for Bordeaux using Open-Meteo API.

Provides human-readable weather summaries with WMO weather code interpretation.
This module runs at 3am UTC, returning a forecast for the upcoming day (not real-time).
"""

import logging
from enum import IntEnum
from typing import Optional, Tuple
from dataclasses import dataclass

import requests


# ============================================================================
# CONSTANTS & CONFIGURATION
# ============================================================================

# Bordeaux Coordinates (France)
BORDEAUX_LATITUDE = 44.8404
BORDEAUX_LONGITUDE = -0.5805
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
    # Clear sky
    CLEAR = 0

    # Mainly clear, partly cloudy, and overcast
    MAINLY_CLEAR = 1
    PARTLY_CLOUDY = 2
    OVERCAST = 3

    # Fog and depositing rime fog
    FOG = 45
    DEPOSITING_RIME_FOG = 48

    # Drizzle
    LIGHT_DRIZZLE = 51
    MODERATE_DRIZZLE = 53
    DENSE_DRIZZLE = 55

    # Freezing Drizzle
    LIGHT_FREEZING_DRIZZLE = 56
    DENSE_FREEZING_DRIZZLE = 57

    # Rain
    LIGHT_RAIN = 61
    MODERATE_RAIN = 63
    HEAVY_RAIN = 65

    # Freezing Rain
    LIGHT_FREEZING_RAIN = 66
    HEAVY_FREEZING_RAIN = 67

    # Snow
    LIGHT_SNOW = 71
    MODERATE_SNOW = 73
    HEAVY_SNOW = 75
    SNOW_GRAINS = 77

    # Rain showers
    LIGHT_RAIN_SHOWERS = 80
    MODERATE_RAIN_SHOWERS = 81
    VIOLENT_RAIN_SHOWERS = 82

    # Snow showers
    LIGHT_SNOW_SHOWERS = 85
    HEAVY_SNOW_SHOWERS = 86

    # Thunderstorm
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
    condition: str          # Description (e.g., "Ensoleille (Sunny)")
    condition_code: WeatherCondition  # Classification
    min_temp: float         # Minimum temperature in Celsius
    max_temp: float         # Maximum temperature in Celsius
    wmo_code: int          # Raw WMO code

    def __str__(self) -> str:
        """Returns human-readable summary."""
        return f"Meteo Bordeaux: {self.condition}, Min {self.min_temp}C, Max {self.max_temp}C."

    def to_tuple(self) -> Tuple[str, dict]:
        """Returns summary string and metadata dict."""
        metadata = {
            "condition": self.condition,
            "condition_code": self.condition_code.value,
            "temp_min": self.min_temp,
            "temp_max": self.max_temp,
            "wmo_code": self.wmo_code
        }
        return str(self), metadata


# ============================================================================
# WMO CODE INTERPRETER
# ============================================================================

class WMOInterpreter:
    """Interprets WMO weather codes to human-readable descriptions."""

    # Mapping: WMO code ranges to descriptions and classifications
    CODE_MAPPINGS = {
        # Single code
        0: ("Ensoleille (Sunny)", WeatherCondition.SUNNY),

        # Cloudy range (1-3)
        1: ("Nuageux (Mainly Clear)", WeatherCondition.CLOUDY),
        2: ("Nuageux (Partly Cloudy)", WeatherCondition.CLOUDY),
        3: ("Nuageux (Overcast)", WeatherCondition.CLOUDY),

        # Fog (45-48)
        45: ("Brumeux (Fog)", WeatherCondition.FOG),
        48: ("Brumeux (Rime Fog)", WeatherCondition.FOG),

        # Drizzle (51-57)
        51: ("Bruine (Light Drizzle)", WeatherCondition.DRIZZLE),
        53: ("Bruine (Moderate Drizzle)", WeatherCondition.DRIZZLE),
        55: ("Bruine (Dense Drizzle)", WeatherCondition.DRIZZLE),
        56: ("Bruine gelée (Freezing Drizzle)", WeatherCondition.DRIZZLE),
        57: ("Bruine gelée (Heavy Freezing Drizzle)", WeatherCondition.DRIZZLE),

        # Rain (61-67)
        61: ("Pluvieux (Light Rain)", WeatherCondition.RAINY),
        63: ("Pluvieux (Moderate Rain)", WeatherCondition.RAINY),
        65: ("Pluvieux (Heavy Rain)", WeatherCondition.RAINY),
        66: ("Pluie gelée (Light Freezing Rain)", WeatherCondition.RAINY),
        67: ("Pluie gelée (Heavy Freezing Rain)", WeatherCondition.RAINY),

        # Snow (71-77)
        71: ("Neige (Light Snow)", WeatherCondition.SNOW),
        73: ("Neige (Moderate Snow)", WeatherCondition.SNOW),
        75: ("Neige (Heavy Snow)", WeatherCondition.SNOW),
        77: ("Grêle de neige (Snow Grains)", WeatherCondition.SNOW),

        # Showers (80-86)
        80: ("Averses (Light Showers)", WeatherCondition.SHOWERS),
        81: ("Averses (Moderate Showers)", WeatherCondition.SHOWERS),
        82: ("Averses violentes (Violent Showers)", WeatherCondition.SHOWERS),
        85: ("Averses de neige (Light Snow Showers)", WeatherCondition.SNOW),
        86: ("Averses de neige (Heavy Snow Showers)", WeatherCondition.SNOW),

        # Thunderstorm (95-99)
        95: ("Orageux (Thunderstorm)", WeatherCondition.THUNDERSTORM),
        96: ("Orageux (Thunderstorm with Light Hail)", WeatherCondition.THUNDERSTORM),
        99: ("Orageux (Thunderstorm with Heavy Hail)", WeatherCondition.THUNDERSTORM),
    }

    @classmethod
    def interpret(cls, wmo_code: int) -> Tuple[str, WeatherCondition]:
        """
        Interprets a WMO weather code.

        Args:
            wmo_code: WMO weather code (0-99)

        Returns:
            Tuple of (description, condition_code)

        Raises:
            ValueError: If WMO code is invalid
        """
        if wmo_code not in cls.CODE_MAPPINGS:
            logger.warning(f"Unknown WMO code: {wmo_code}, defaulting to 'Unknown'")
            return "Unknown", WeatherCondition.CLOUDY

        return cls.CODE_MAPPINGS[wmo_code]


# ============================================================================
# API INTERACTION
# ============================================================================

class WeatherAPIClient:
    """Handles Open-Meteo API interactions."""

    def __init__(self, latitude: float = BORDEAUX_LATITUDE,
                 longitude: float = BORDEAUX_LONGITUDE,
                 timezone: str = TIMEZONE,
                 timeout: int = REQUEST_TIMEOUT):
        """
        Initialize weather API client.

        Args:
            latitude: Location latitude
            longitude: Location longitude
            timezone: Timezone name
            timeout: Request timeout in seconds
        """
        self.latitude = latitude
        self.longitude = longitude
        self.timezone = timezone
        self.timeout = timeout

    def fetch_daily_forecast(self) -> Optional[WeatherData]:
        """
        Fetches daily weather forecast from Open-Meteo API.

        The script runs at 3am, so this returns the forecast for the upcoming day
        (not real-time current conditions).

        Returns:
            WeatherData object if successful, None on error

        Raises:
            requests.exceptions.RequestException: On network errors
        """
        params = {
            "latitude": self.latitude,
            "longitude": self.longitude,
            "daily": "weather_code,temperature_2m_max,temperature_2m_min",
            "timezone": self.timezone,
            "forecast_days": 1
        }

        try:
            response = requests.get(
                API_URL,
                params=params,
                timeout=self.timeout
            )
            response.raise_for_status()
            data = response.json()

            return self._parse_forecast(data)

        except requests.exceptions.Timeout:
            logger.error(f"Weather API timeout after {self.timeout}s")
            return None
        except requests.exceptions.ConnectionError as e:
            logger.error(f"Weather API connection error: {e}")
            return None
        except requests.exceptions.HTTPError as e:
            logger.error(f"Weather API HTTP error: {e}")
            return None
        except Exception as e:
            logger.error(f"Unexpected error fetching weather: {e}")
            return None

    def _parse_forecast(self, api_data: dict) -> Optional[WeatherData]:
        """
        Parses Open-Meteo API response.

        Args:
            api_data: JSON response from API

        Returns:
            WeatherData object, None if parsing fails

        Raises:
            ValueError: If response format is unexpected
        """
        try:
            daily = api_data.get("daily", {})
            if not daily:
                logger.warning("No daily forecast in API response")
                return None

            # Extract values (array index 0 for single-day forecast)
            max_temps = daily.get("temperature_2m_max", [None])
            min_temps = daily.get("temperature_2m_min", [None])
            weather_codes = daily.get("weather_code", [None])

            max_temp = max_temps[0] if max_temps[0] is not None else "?"
            min_temp = min_temps[0] if min_temps[0] is not None else "?"
            wmo_code = weather_codes[0] if weather_codes[0] is not None else 0

            # Interpret WMO code
            description, condition = WMOInterpreter.interpret(int(wmo_code))

            return WeatherData(
                condition=description,
                condition_code=condition,
                min_temp=float(min_temp) if min_temp != "?" else 0,
                max_temp=float(max_temp) if max_temp != "?" else 0,
                wmo_code=int(wmo_code)
            )

        except (KeyError, IndexError, ValueError) as e:
            logger.error(f"Failed to parse forecast data: {e}")
            return None


# ============================================================================
# PUBLIC API
# ============================================================================

def get_bordeaux_weather() -> str:
    """
    Fetches daily weather forecast for Bordeaux.

    This function provides a human-readable weather summary for the upcoming day.
    Since the main script runs at 3am UTC, this returns the daytime forecast
    (not real-time conditions).

    Returns:
        Human-readable weather summary string

    Example:
        >>> summary = get_bordeaux_weather()
        >>> print(summary)
        "Meteo Bordeaux: Nuageux (Cloudy), Min 9.1C, Max 14.8C."

    Note:
        Returns a fallback message if API is unavailable.
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


def get_bordeaux_weather_detailed() -> Optional[Tuple[str, dict]]:
    """
    Fetches detailed weather forecast for Bordeaux with metadata.

    Returns both human-readable summary and structured metadata.

    Returns:
        Tuple of (summary_string, metadata_dict) or None if failed

    Example:
        >>> result = get_bordeaux_weather_detailed()
        >>> if result:
        ...     summary, metadata = result
        ...     print(f"Condition code: {metadata['condition_code']}")
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
