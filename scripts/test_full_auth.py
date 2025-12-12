"""
YouTube Music authentication verification script.

Verifies that ytmusicapi browser authentication is working correctly
by attempting to retrieve recent history.
"""

import sys
import os
import logging
from typing import List, Dict, Any, Optional

logger = logging.getLogger(__name__)

# Add parent directory to path to import connectors
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from connectors.yt_music import get_full_history

# ============================================================================
# CONSTANTS
# ============================================================================

HISTORY_LIMIT = 30
OUTPUT_WIDTH = 70


# ============================================================================
# EXCEPTIONS
# ============================================================================

class AuthTestError(Exception):
    """Raised when authentication test fails."""
    pass


# ============================================================================
# HISTORY FORMATTER
# ============================================================================

class HistoryFormatter:
    """Formats history data for display."""

    @staticmethod
    def format_item(item: Dict[str, Any], index: int) -> str:
        """
        Formats a single history item.

        Args:
            item: History item dict
            index: Item number (1-based)

        Returns:
            Formatted string
        """
        title = item.get('title', 'N/A')
        artists = ", ".join(item.get('artists', []))
        played = item.get('played', '')

        lines = [f"{index:2d}. {artists} - {title}"]
        if played:
            lines.append(f"    ({played})")

        return "\n".join(lines)

    @staticmethod
    def format_results(history: List[Dict[str, Any]], limit: int = HISTORY_LIMIT) -> str:
        """
        Formats complete history results.

        Args:
            history: Full history list
            limit: Maximum items to display

        Returns:
            Formatted output string
        """
        output_lines = [
            "✅ SUCCESS! Retrieved history from YouTube Music\n",
            f"Recent plays (showing {min(len(history), limit)} of {len(history)}):",
            "=" * OUTPUT_WIDTH
        ]

        for i, item in enumerate(history[:limit], 1):
            output_lines.append(HistoryFormatter.format_item(item, i))

        output_lines.append("=" * OUTPUT_WIDTH)
        output_lines.append("")
        output_lines.append("✅ YTMUSICAPI BROWSER AUTHENTICATION WORKING!")

        return "\n".join(output_lines)


# ============================================================================
# AUTHENTICATION TESTER
# ============================================================================

class AuthenticationTester:
    """Tests YouTube Music authentication."""

    @staticmethod
    def test_history_retrieval(limit: int = HISTORY_LIMIT) -> List[Dict[str, Any]]:
        """
        Tests authentication by retrieving history.

        Args:
            limit: Number of history items to retrieve

        Returns:
            History items list

        Raises:
            AuthTestError: If retrieval fails

        Example:
            >>> tester = AuthenticationTester()
            >>> history = tester.test_history_retrieval(limit=30)
        """
        try:
            logger.info("Testing YouTube Music authentication...\n")

            history = get_full_history(limit=limit)

            if not history:
                raise AuthTestError("No history items returned")

            return history

        except FileNotFoundError as e:
            raise AuthTestError(
                f"Authentication file not found: {e}\n\n"
                f"Run 'python scripts\\create_browser_auth.py' to generate browser_auth_new.json"
            ) from e

        except Exception as e:
            raise AuthTestError(f"History retrieval failed: {e}") from e

    @staticmethod
    def print_results(history: List[Dict[str, Any]]) -> None:
        """
        Prints formatted test results.

        Args:
            history: History items list
        """
        output = HistoryFormatter.format_results(history)
        print(output)


# ============================================================================
# PUBLIC API
# ============================================================================

def test_youtube_music_auth() -> bool:
    """
    Tests YouTube Music authentication and history retrieval.

    Attempts to retrieve recent history from YouTube Music to verify
    that browser authentication (browser_auth.json) is working.

    Returns:
        True if authentication successful, False otherwise

    Example:
        >>> from scripts.test_full_auth_refactored import test_youtube_music_auth
        >>> success = test_youtube_music_auth()
    """
    try:
        tester = AuthenticationTester()
        history = tester.test_history_retrieval(limit=HISTORY_LIMIT)
        tester.print_results(history)
        return True

    except AuthTestError as e:
        logger.error(f"❌ Authentication test failed:")
        logger.error(f"\n{e}\n")
        return False

    except Exception as e:
        logger.error(f"❌ Unexpected error:")
        logger.error(f"\n{repr(e)}\n")
        import traceback
        traceback.print_exc()
        return False


if __name__ == "__main__":
    logging.basicConfig(
        level=logging.INFO,
        format='%(message)s'
    )

    success = test_youtube_music_auth()
    sys.exit(0 if success else 1)
