"""
BizBuySell scraper — targets RV park and mobile-home-park category pages.
Falls back to the Apify actor when APIFY_API_KEY is configured.
"""
import logging
import re

from app.scrapers.base import BaseScraper

logger = logging.getLogger(__name__)

CATEGORY_URLS = [
    ('rv_park',        'https://www.bizbuysell.com/campgrounds-rv-parks-for-sale/'),
    ('mobile_home_park', 'https://www.bizbuysell.com/mobile-home-parks-for-sale/'),
]


class BizBuySellScraper(BaseScraper):
    name = 'bizbuysell'
    display_name = 'BizBuySell'

    def scrape(self):
        apify_key = self.config.get('APIFY_API_KEY', '')
        if apify_key:
            return self._scrape_via_apify(apify_key)
        return self._scrape_direct()

    # ── direct HTML scraping ────────────────────────────────────────────────

    def _scrape_direct(self):
        results = []
        for prop_type, base_url in CATEGORY_URLS:
            page = 1
            while len(results) < self.max_listings:
                url = base_url if page == 1 else f"{base_url}?page={page}"
                try:
                    s = self.soup(url)
                except Exception as exc:
                    logger.warning(f"[bizbuysell] page {page} failed: {exc}")
                    break

                cards = (
                    s.select('div.listing-item')
                    or s.select('div[class*="listing"]')
                    or s.select('article')
                )
                if not cards:
                    logger.info(f"[bizbuysell] no cards found on page {page}, stopping")
                    break

                for card in cards:
                    listing = self._parse_card(card, prop_type)
                    if listing:
                        results.append(listing)
                    if len(results) >= self.max_listings:
                        break

                # next page?
                if not s.select_one('a[rel="next"], a.next, li.next a'):
                    break
                page += 1

        return results

    def _parse_card(self, card, prop_type):
        try:
            # title / URL
            anchor = card.select_one('a[href*="/Business-Opportunity/"], a[href*="/business/"], h3 a, h2 a, .listing-name a')
            if not anchor:
                anchor = card.select_one('a')
            title = anchor.get_text(strip=True) if anchor else card.get_text(strip=True)[:80]
            url = anchor.get('href', '') if anchor else ''
            if url and not url.startswith('http'):
                url = 'https://www.bizbuysell.com' + url

            # price
            price_el = card.select_one('.price, [class*="price"], [class*="Price"]')
            price_text = price_el.get_text(strip=True) if price_el else ''
            price, price_text = self.clean_price(price_text)

            # location
            loc_el = card.select_one('.location, [class*="location"], [class*="Location"]')
            location = loc_el.get_text(strip=True) if loc_el else ''
            city, state = self.extract_city_state(location)

            # description snippet
            desc_el = card.select_one('.description, p, [class*="desc"]')
            description = desc_el.get_text(strip=True)[:500] if desc_el else ''

            # extract lot count from text
            lot_count = None
            full_text = card.get_text(' ')
            m = re.search(r'(\d+)\s*(?:lot|site|space|pad|unit)s?', full_text, re.I)
            if m:
                lot_count = int(m.group(1))

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
                'source': self.name,
                'url': url,
                'property_type': prop_type,
                'source_id': url.split('/')[-2] if url else '',
            }
        except Exception as exc:
            logger.debug(f"[bizbuysell] card parse error: {exc}")
            return None

    # ── Apify fallback ──────────────────────────────────────────────────────

    def _scrape_via_apify(self, api_key):
        try:
            from apify_client import ApifyClient
        except ImportError:
            logger.error("[bizbuysell] apify_client not installed")
            return self._scrape_direct()

        results = []
        client = ApifyClient(api_key)

        for prop_type, base_url in CATEGORY_URLS:
            try:
                run = client.actor('dtrungtin/bizbuysell-scraper').call(
                    run_input={
                        'startUrls': [base_url],
                        'maxItems': self.max_listings,
                        'includeRawHTML': False,
                    }
                )
                if not run:
                    continue
                items = client.dataset(run['defaultDatasetId']).list_items().items
                for item in items:
                    price, price_text = self.clean_price(item.get('price') or item.get('PRICE'))
                    location = item.get('location') or item.get('LOCATION', '')
                    city, state = self.extract_city_state(location)
                    results.append({
                        'title': item.get('title') or item.get('TITLE', 'Untitled'),
                        'price': price,
                        'price_text': price_text,
                        'location': location,
                        'city': city,
                        'state': state,
                        'description': item.get('description') or item.get('INDUSTRY DETAILS', '')[:500],
                        'source': self.name,
                        'url': item.get('url') or item.get('URL', ''),
                        'property_type': prop_type,
                        'source_id': item.get('id', ''),
                    })
            except Exception as exc:
                logger.error(f"[bizbuysell] Apify run failed: {exc}")

        return results
