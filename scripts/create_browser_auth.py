"""
YouTube Music browser authentication setup script.

Guides user through YouTube Music header extraction and generates
browser_auth.json file for ytmusicapi library.
"""

import sys
import os
import re
import logging
from typing import List, Optional

from ytmusicapi import setup

logger = logging.getLogger(__name__)

# ============================================================================
# CONSTANTS
# ============================================================================

AUTH_FILE_NAME = "browser_auth_new.json"
INSTRUCTION_TEXT = """
╔══════════════════════════════════════════════════════════════════════════╗
║  CREATION: YouTube Music Browser Authentication File                    ║
╚══════════════════════════════════════════════════════════════════════════╝

📋 INSTRUCTIONS:

1. Open https://music.youtube.com in Chrome/Firefox
2. Ensure you're logged in with your YouTube account
3. Open DevTools (F12)
4. Go to Network tab
5. Filter by "browse"
6. Refresh (F5)
7. Click any "browse" request
8. Copy ALL Request Headers (from first line to last)

Example format:
:authority: music.youtube.com
:method: POST
:path: /youtubei/v1/browse
accept: */*
authorization: SAPISIDHASH ...
cookie: VISITOR_INFO1_LIVE=...; PREF=...
...

"""

CURL_REGEX = r"-H\s+'([^:]+):\s*(.*)'|curl\s+|User-Agent|Authorization"


# ============================================================================
# EXCEPTIONS
# ============================================================================

class AuthSetupError(Exception):
    """Raised when authentication setup fails."""
    pass


# ============================================================================
# HEADER PARSING
# ============================================================================

class HeaderExtractor:
    """Extracts headers from raw text input."""

    @staticmethod
    def extract_from_raw(text: str) -> str:
        """
        Extracts headers from raw text.

        Args:
            text: Raw header text from DevTools

        Returns:
            Cleaned header text

        Raises:
            AuthSetupError: If no valid headers found
        """
        if not text.strip():
            raise AuthSetupError("No headers provided")

        # Check if input is cURL format
        if text.strip().lower().startswith("curl"):
            return HeaderExtractor._extract_from_curl(text)

        # Otherwise treat as raw headers
        return text

    @staticmethod
    def _extract_from_curl(curl_command: str) -> str:
        """
        Extracts headers from cURL command.

        Args:
            curl_command: cURL command string

        Returns:
            Formatted header text

        Example:
            >>> curl = 'curl -H "Authorization: ..." -b "cookie: ..."'
            >>> headers = HeaderExtractor._extract_from_curl(curl)
        """
        lines = curl_command.splitlines()
        headers = []
        cookie_val = None

        for line in lines:
            # Match -H 'header: value' format
            header_match = re.search(r"-H\s+'([^:]+):\s*(.*)'", line)
            if header_match:
                key = header_match.group(1).strip()
                val = header_match.group(2).strip()
                headers.append(f"{key}: {val}")

            # Match -b 'cookie: value' format
            cookie_match = re.search(r"-b\s+'(.+?)'", line)
            if cookie_match:
                cookie_val = cookie_match.group(1).strip()

        # Add cookie header if found
        if cookie_val:
            headers.append(f"cookie: {cookie_val}")

        if not headers:
            raise AuthSetupError("No headers found in cURL command")

        return "\n".join(headers)


# ============================================================================
# INPUT COLLECTION
# ============================================================================

class HeaderInputCollector:
    """Collects header input from user."""

    @staticmethod
    def collect_from_stdin() -> str:
        """
        Collects multi-line header input from stdin.

        User presses ENTER twice to finish input.

        Returns:
            Collected header text

        Raises:
            AuthSetupError: If no input provided
        """
        print(INSTRUCTION_TEXT)
        print("Paste Request Headers or cURL command below, then press ENTER twice:\n")
        print("=" * 78)

        lines = []
        empty_count = 0

        try:
            while True:
                line = input()

                if not line.strip():
                    empty_count += 1
                    if empty_count >= 2:
                        break
                else:
                    empty_count = 0
                    lines.append(line)

        except EOFError:
            pass

        text = "\n".join(lines)

        if not text.strip():
            raise AuthSetupError("No headers provided")

        return text


# ============================================================================
# AUTHENTICATION FILE GENERATION
# ============================================================================

class AuthFileGenerator:
    """Generates browser_auth.json file."""

    def __init__(self, output_dir: Optional[str] = None):
        """
        Initialize generator.

        Args:
            output_dir: Directory to save auth file (defaults to project root)
        """
        if output_dir:
            self.output_dir = output_dir
        else:
            # Use project root (parent of scripts/)
            self.output_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

    def generate(self, headers_text: str) -> str:
        """
        Generates browser_auth.json file.

        Args:
            headers_text: Raw header text

        Returns:
            Path to generated file

        Raises:
            AuthSetupError: If generation fails
        """
        try:
            output_path = os.path.join(self.output_dir, AUTH_FILE_NAME)

            logger.info("📝 Creating authentication file...")

            # ytmusicapi.setup() handles the conversion
            setup(filepath=output_path, headers_raw=headers_text)

            logger.info(f"✅ File created: {output_path}")
            return output_path

        except Exception as e:
            logger.error(f"Generation failed: {e}")
            raise AuthSetupError(f"Could not generate auth file: {e}") from e


# ============================================================================
# ORCHESTRATION
# ============================================================================

class BrowserAuthSetup:
    """Orchestrates browser authentication setup process."""

    def __init__(self, output_dir: Optional[str] = None):
        """Initialize setup."""
        self.extractor = HeaderExtractor()
        self.collector = HeaderInputCollector()
        self.generator = AuthFileGenerator(output_dir)

    def run(self) -> str:
        """
        Runs complete setup process.

        Returns:
            Path to generated auth file

        Raises:
            AuthSetupError: If any step fails
        """
        # Collect input
        raw_input = self.collector.collect_from_stdin()

        # Extract headers
        headers_text = self.extractor.extract_from_raw(raw_input)

        # Generate file
        output_path = self.generator.generate(headers_text)

        print("\n" + "=" * 78)
        print("\n✅ YouTube Music authentication setup complete!\n")
        print(f"Generated file: {output_path}\n")
        print("Next steps:")
        print("  1. Verify the file exists")
        print("  2. Test with: python .\\scripts\\test_full_auth.py")
        print()

        return output_path


# ============================================================================
# PUBLIC API
# ============================================================================

def setup_browser_auth(output_dir: Optional[str] = None) -> None:
    """
    Creates YouTube Music browser authentication file.

    Guides user through header extraction and generates browser_auth_new.json.

    Args:
        output_dir: Optional output directory (defaults to project root)

    Example:
        >>> from scripts.create_browser_auth_refactored import setup_browser_auth
        >>> setup_browser_auth()
    """
    try:
        setup = BrowserAuthSetup(output_dir)
        setup.run()
    except AuthSetupError as e:
        logger.error(f"Setup failed: {e}")
        sys.exit(1)
    except Exception as e:
        logger.error(f"Unexpected error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    logging.basicConfig(
        level=logging.INFO,
        format='%(message)s'
    )
    setup_browser_auth()
