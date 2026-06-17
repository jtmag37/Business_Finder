import os
from dotenv import load_dotenv

load_dotenv()

class Config:
    SECRET_KEY = os.getenv('SECRET_KEY', 'dev-key-change-me-in-production')
    SQLALCHEMY_DATABASE_URI = os.getenv('DATABASE_URL', 'sqlite:///rv_parks.db')
    SQLALCHEMY_TRACK_MODIFICATIONS = False

    APIFY_API_KEY = os.getenv('APIFY_API_KEY', '')
    GROQ_API_KEY = os.getenv('GROQ_API_KEY', '')

    EMAIL_USERNAME = os.getenv('EMAIL_USERNAME', '')
    EMAIL_PASSWORD = os.getenv('EMAIL_PASSWORD', '')
    NOTIFICATION_EMAIL = os.getenv('NOTIFICATION_EMAIL', '')

    SCRAPE_INTERVAL_HOURS = int(os.getenv('SCRAPE_INTERVAL_HOURS', 6))
    MAX_LISTINGS_PER_SOURCE = int(os.getenv('MAX_LISTINGS_PER_SOURCE', 50))
    REQUEST_DELAY = float(os.getenv('REQUEST_DELAY', 2.5))

    APP_USERNAME = os.getenv('APP_USERNAME', '')
    APP_PASSWORD = os.getenv('APP_PASSWORD', '')
