"""
MobileHomeParkStore.com — dedicated marketplace for MHP sales.
"""
import logging
import re

from app.scrapers.base import BaseScraper

logger = logging.getLogger(__name__)

BASE = 'https://www.mobilehomeparkstore.com'
SEARCH_URL = f'{BASE}/mobile-home-parks-for-sale/'


class MobileHomeParkStoreScraper(BaseScraper):
    name = 'mobilehomeparkstore'
    display_name = 'MobileHomeParkStore'

    def scrape(self):
        results = []
        page = 1
        while len(results) < self.max_listings:
            url = SEARCH_URL if page == 1 else f'{SEARCH_URL}?page={page}'
            try:
                s = self.soup(url)
            except Exception as exc:
                logger.warning(f"[mhpstore] page {page}: {exc}")
                break

            cards = (
                s.select('div.property-item')
                or s.select('div.listing-item')
                or s.select('div[class*="listing"]')
                or s.select('article')
            )
            if not cards:
                break

            before = len(results)
            for card in cards:
                item = self._parse(card)
                if item:
                    results.append(item)
                if len(results) >= self.max_listings:
                    break

            if len(results) == before:
                break

            if not s.select_one('a.next, a[rel="next"], .pagination .next'):
                break
            page += 1

        return results

    def _parse(self, card):
        try:
            anchor = card.select_one('h2 a, h3 a, .listing-title a') or card.select_one('a[href]')
            title = anchor.get_text(strip=True) if anchor else ''
            url = anchor['href'] if anchor else ''
            if url and not url.startswith('http'):
                url = BASE + url

            price_el = card.select_one('.price, [class*="price"]')
            price_text = price_el.get_text(strip=True) if price_el else ''
            price, price_text = self.clean_price(price_text)

            loc_el = card.select_one('.location, [class*="location"]')
            location = loc_el.get_text(strip=True) if loc_el else ''
            city, state = self.extract_city_state(location)

            text = card.get_text(' ')
            lot_count = None
            m = re.search(r'(\d+)\s*(?:lot|space|site|pad|home)s?', text, re.I)
            if m:
                lot_count = int(m.group(1))

            acreage = None
            m2 = re.search(r'([\d.]+)\s*acres?', text, re.I)
            if m2:
                acreage = float(m2.group(1))

            cap_rate = None
            m3 = re.search(r'cap\s*rate[:\s]*([\d.]+)\s*%', text, re.I)
            if m3:
                cap_rate = float(m3.group(1))

            desc_el = card.select_one('p, .description')
            description = desc_el.get_text(strip=True)[:500] if desc_el else ''

            if not title:
                return None

            return {
                'title': title,
                'price': price,
                'price_text': price_text,
                'location': location,
                'city': city,
                'state': state,
                'description': description,
                'lot_count': lot_count,
                'acreage': acreage,
                'cap_rate': cap_rate,
                'source': self.name,
                'url': url,
                'property_type': 'mobile_home_park',
                'source_id': url.rstrip('/').split('/')[-1],
            }
        except Exception as exc:
            logger.debug(f"[mhpstore] parse error: {exc}")
            return None
