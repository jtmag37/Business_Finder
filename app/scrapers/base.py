import re
import time
import logging
from abc import ABC, abstractmethod

import requests
from bs4 import BeautifulSoup

logger = logging.getLogger(__name__)

HEADERS = {
    'User-Agent': (
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
        'AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/120.0.0.0 Safari/537.36'
    ),
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.5',
    'Accept-Encoding': 'gzip, deflate, br',
    'Connection': 'keep-alive',
    'Upgrade-Insecure-Requests': '1',
    'DNT': '1',
}

US_STATES = {
    'AL','AK','AZ','AR','CA','CO','CT','DE','FL','GA','HI','ID','IL','IN',
    'IA','KS','KY','LA','ME','MD','MA','MI','MN','MS','MO','MT','NE','NV',
    'NH','NJ','NM','NY','NC','ND','OH','OK','OR','PA','RI','SC','SD','TN',
    'TX','UT','VT','VA','WA','WV','WI','WY',
}


class BaseScraper(ABC):
    name = 'base'
    display_name = 'Base Scraper'

    def __init__(self, config=None):
        self.config = config or {}
        self.session = requests.Session()
        self.session.headers.update(HEADERS)
        self.delay = float(self.config.get('REQUEST_DELAY', 2.5))
        self.max_listings = int(self.config.get('MAX_LISTINGS_PER_SOURCE', 50))

    def get(self, url, **kwargs):
        time.sleep(self.delay)
        resp = self.session.get(url, timeout=30, **kwargs)
        resp.raise_for_status()
        return resp

    def soup(self, url, **kwargs):
        resp = self.get(url, **kwargs)
        return BeautifulSoup(resp.text, 'lxml')

    @abstractmethod
    def scrape(self):
        """Return list of dicts with listing data."""

    # ── helpers ────────────────────────────────────────────────────────────

    @staticmethod
    def clean_price(text):
        if not text:
            return None, None
        raw = str(text).strip()
        digits = re.sub(r'[^\d]', '', raw.replace(',', ''))
        try:
            return float(digits), raw
        except (ValueError, TypeError):
            return None, raw

    @staticmethod
    def clean_int(text):
        if not text:
            return None
        m = re.search(r'[\d,]+', str(text))
        if m:
            try:
                return int(m.group(0).replace(',', ''))
            except ValueError:
                pass
        return None

    @staticmethod
    def clean_float(text):
        if not text:
            return None
        m = re.search(r'[\d,.]+', str(text))
        if m:
            try:
                return float(m.group(0).replace(',', ''))
            except ValueError:
                pass
        return None

    @staticmethod
    def extract_state(text):
        if not text:
            return None
        m = re.search(r'\b([A-Z]{2})\b', str(text))
        if m and m.group(1) in US_STATES:
            return m.group(1)
        return None

    @staticmethod
    def extract_city_state(location_text):
        if not location_text:
            return None, None
        parts = [p.strip() for p in str(location_text).split(',')]
        city = parts[0] if parts else None
        state = None
        for p in parts[1:]:
            abbr = p.strip().upper()[:2]
            if abbr in US_STATES:
                state = abbr
                break
        return city, state
