"""
LandWatch.com — recreational and campground/RV park land listings.
"""
import logging
import re

from app.scrapers.base import BaseScraper

logger = logging.getLogger(__name__)

BASE = 'https://www.landwatch.com'
SEARCH_URLS = [
    ('rv_park',          f'{BASE}/rv-park-land-for-sale/'),
    ('mobile_home_park', f'{BASE}/mobile-home-park-land-for-sale/'),
    ('rv_park',          f'{BASE}/campground-land-for-sale/'),
]


class LandWatchScraper(BaseScraper):
    name = 'landwatch'
    display_name = 'LandWatch'

    def scrape(self):
        results = []
        seen_urls = set()
        for prop_type, url in SEARCH_URLS:
            if len(results) >= self.max_listings:
                break
            try:
                items = self._scrape_url(url, prop_type, seen_urls)
                results.extend(items)
            except Exception as exc:
                logger.warning(f"[landwatch] {url}: {exc}")
        return results[:self.max_listings]

    def _scrape_url(self, url, prop_type, seen_urls):
        results = []
        page = 1
        while len(results) < self.max_listings // len(SEARCH_URLS):
            paged = url if page == 1 else f"{url}?page={page}"
            try:
                s = self.soup(paged)
            except Exception as exc:
                logger.warning(f"[landwatch] page {page}: {exc}")
                break

            cards = (
                s.select('div.propCard')
                or s.select('div[class*="listing-card"]')
                or s.select('article[class*="listing"]')
                or s.select('div[class*="property-card"]')
            )
            if not cards:
                break

            before = len(results)
            for card in cards:
                item = self._parse(card, prop_type)
                if item and item['url'] not in seen_urls:
                    seen_urls.add(item['url'])
                    results.append(item)

            if len(results) == before:
                break

            if not s.select_one('a[rel="next"], a.next-page, .pagination a[aria-label="Next"]'):
                break
            page += 1

        return results

    def _parse(self, card, prop_type):
        try:
            anchor = card.select_one('h2 a, h3 a, a[class*="title"]') or card.select_one('a[href]')
            title = anchor.get_text(strip=True) if anchor else ''
            url = anchor['href'] if anchor else ''
            if url and not url.startswith('http'):
                url = BASE + url

            price_el = card.select_one('[class*="price"], [class*="Price"]')
            price_text = price_el.get_text(strip=True) if price_el else ''
            price, price_text = self.clean_price(price_text)

            loc_el = card.select_one('[class*="location"], [class*="city"], [class*="address"]')
            location = loc_el.get_text(strip=True) if loc_el else ''
            city, state = self.extract_city_state(location)

            text = card.get_text(' ')
            acreage = None
            m = re.search(r'([\d,.]+)\s*acres?', text, re.I)
            if m:
                acreage = self.clean_float(m.group(1))

            desc_el = card.select_one('p, [class*="desc"]')
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
                'acreage': acreage,
                'source': self.name,
                'url': url,
                'property_type': prop_type,
                'source_id': url.rstrip('/').split('/')[-1],
            }
        except Exception as exc:
            logger.debug(f"[landwatch] parse error: {exc}")
            return None
