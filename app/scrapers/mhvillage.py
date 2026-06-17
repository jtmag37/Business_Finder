"""
MHVillage.com — manufactured-home community listings for sale.
"""
import logging
import re

from app.scrapers.base import BaseScraper

logger = logging.getLogger(__name__)

BASE = 'https://www.mhvillage.com'
SEARCH_URL = f'{BASE}/MHParksForSale/'


class MHVillageScraper(BaseScraper):
    name = 'mhvillage'
    display_name = 'MHVillage'

    def scrape(self):
        results = []
        page = 1
        while len(results) < self.max_listings:
            url = SEARCH_URL if page == 1 else f'{SEARCH_URL}?p={page}'
            try:
                s = self.soup(url)
            except Exception as exc:
                logger.warning(f"[mhvillage] page {page}: {exc}")
                break

            cards = (
                s.select('div.park-listing')
                or s.select('div.listing-card')
                or s.select('div[class*="park"]')
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

            nxt = s.select_one('a[rel="next"], a.next, .pagination a[aria-label="Next"]')
            if not nxt:
                break
            page += 1

        return results

    def _parse(self, card):
        try:
            anchor = card.select_one('h2 a, h3 a, .park-name a, a.park-link') or card.select_one('a[href]')
            title = anchor.get_text(strip=True) if anchor else ''
            url = anchor['href'] if anchor else ''
            if url and not url.startswith('http'):
                url = BASE + url

            price_el = card.select_one('[class*="price"], [class*="Price"]')
            price_text = price_el.get_text(strip=True) if price_el else ''
            price, price_text = self.clean_price(price_text)

            loc_el = card.select_one('[class*="location"], [class*="city"], address')
            location = loc_el.get_text(strip=True) if loc_el else ''
            city, state = self.extract_city_state(location)

            text = card.get_text(' ')
            lot_count = None
            m = re.search(r'(\d+)\s*(?:home\s*site|lot|space|site)s?', text, re.I)
            if m:
                lot_count = int(m.group(1))

            acreage = None
            m2 = re.search(r'([\d.]+)\s*acres?', text, re.I)
            if m2:
                acreage = float(m2.group(1))

            desc_el = card.select_one('p.description, p')
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
                'source': self.name,
                'url': url,
                'property_type': 'mobile_home_park',
                'source_id': url.rstrip('/').split('/')[-1],
            }
        except Exception as exc:
            logger.debug(f"[mhvillage] parse error: {exc}")
            return None
