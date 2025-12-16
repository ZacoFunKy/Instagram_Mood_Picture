
import logging
import os
import sys
from logging.handlers import RotatingFileHandler

# Constants
LOG_DIR = "logs"
LOG_FILE_NAME = "app.log"
LOG_FORMAT = "[%(asctime)s] | %(levelname)-8s | %(name)-15s | %(message)s"
DATE_FORMAT = "%Y-%m-%d %H:%M:%S"

def setup_logger(name: str = "MoodPredictor") -> logging.Logger:
    """
    Configures and returns a standardized logger.
    
    Features:
    - Console Output (StreamHandler)
    - File Output with Rotation (Rewritten on new runs or rotated)
    - Standardized Formatting
    
    Args:
        name: Name of the logger module
        
    Returns:
        Configured Logger instance
    """
    logger = logging.getLogger(name)
    logger.setLevel(logging.INFO)
    
    # Avoid duplicate handlers if setup is called multiple times
    if logger.handlers:
        return logger

    # Ensure log directory exists
    if not os.path.exists(LOG_DIR):
        os.makedirs(LOG_DIR)
        
    log_path = os.path.join(LOG_DIR, LOG_FILE_NAME)

    # Formatter
    formatter = logging.Formatter(LOG_FORMAT, datefmt=DATE_FORMAT)

    # 1. Console Handler
    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setFormatter(formatter)
    console_handler.setLevel(logging.INFO)
    logger.addHandler(console_handler)

    # 2. File Handler (Write mode 'w' to overwrite/rotate each run essentially, 
    # or 'a' for append. User requested "clean log of current execution". 
    # 'w' mode is best for "overwrite on new execution" behavior if we want strict cleanliness,
    # but RotatingFileHandler usually appends. 
    # Let's use FileHandler with mode='w' to strictly clear old logs on startup 
    # OR use RotatingFileHandler to keep history but limited.
    # User said: "Le fichier doit être écrasé ou roté à chaque nouvelle exécution".
    # I will stick to RotatingFileHandler with a small backup count, but trigger a rollover?
    # Actually, simplest for "clean log" is FileHandler(mode='w').
    
    file_handler = logging.FileHandler(log_path, mode='w', encoding='utf-8')
    file_handler.setFormatter(formatter)
    file_handler.setLevel(logging.INFO)
    logger.addHandler(file_handler)

    return logger

# Singleton-like accessor
def get_logger(name: str) -> logging.Logger:
    return setup_logger(name)
