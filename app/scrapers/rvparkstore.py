"""
RVParkStore.com — dedicated marketplace for RV park sales.
"""
import logging
import re

from app.scrapers.base import BaseScraper

logger = logging.getLogger(__name__)

BASE = 'https://www.rvparkstore.com'
SEARCH_URL = f'{BASE}/listings/'


class RVParkStoreScraper(BaseScraper):
    name = 'rvparkstore'
    display_name = 'RVParkStore'

    def scrape(self):
        results = []
        page = 1
        while len(results) < self.max_listings:
            url = SEARCH_URL if page == 1 else f'{SEARCH_URL}?paged={page}'
            try:
                s = self.soup(url)
            except Exception as exc:
                logger.warning(f"[rvparkstore] page {page}: {exc}")
                break

            cards = (
                s.select('div.property-listing')
                or s.select('div.listing-item')
                or s.select('article.listing')
                or s.select('div[class*="listing"]')
            )
            if not cards:
                # try generic article/div fallback
                cards = s.select('article')

            if not cards:
                logger.info(f"[rvparkstore] no cards on page {page}")
                break

            before = len(results)
            for card in cards:
                listing = self._parse(card)
                if listing:
                    results.append(listing)
                if len(results) >= self.max_listings:
                    break

            if len(results) == before:
                break  # no new items, stop

            if not s.select_one('a.next, a[rel="next"], .pagination .next a'):
                break
            page += 1

        return results

    def _parse(self, card):
        try:
            anchor = (
                card.select_one('h2 a, h3 a, .listing-title a, .property-title a')
                or card.select_one('a[href]')
            )
            title = anchor.get_text(strip=True) if anchor else ''
            url = anchor['href'] if anchor else ''
            if url and not url.startswith('http'):
                url = BASE + url

            price_el = card.select_one('.price, [class*="price"]')
            price_text = price_el.get_text(strip=True) if price_el else ''
            price, price_text = self.clean_price(price_text)

            loc_el = card.select_one('.location, [class*="location"], .city-state')
            location = loc_el.get_text(strip=True) if loc_el else ''
            city, state = self.extract_city_state(location)

            text = card.get_text(' ')
            lot_count = None
            m = re.search(r'(\d+)\s*(?:site|space|lot|pad|unit)s?', text, re.I)
            if m:
                lot_count = int(m.group(1))

            acreage = None
            m2 = re.search(r'([\d.]+)\s*acres?', text, re.I)
            if m2:
                acreage = float(m2.group(1))

            desc_el = card.select_one('p, .description, [class*="desc"]')
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
                'property_type': 'rv_park',
                'source_id': url.rstrip('/').split('/')[-1],
            }
        except Exception as exc:
            logger.debug(f"[rvparkstore] parse error: {exc}")
            return None
