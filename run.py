"""
Root entry point for the Mood Predictor application.
Bootstraps the src package and runs the main orchestrator.
"""

import sys
import os

# Ensure the project root is in python path
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from src.main import main

if __name__ == "__main__":
    main()
