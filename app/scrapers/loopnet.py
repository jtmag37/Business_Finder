"""
LoopNet scraper — searches for Mobile Home Park & RV Park property types.
LoopNet serves pages with server-side rendering for the initial result list,
though some data lives in JSON embedded in <script> tags.
"""
import json
import logging
import re

from app.scrapers.base import BaseScraper

logger = logging.getLogger(__name__)

SEARCH_URLS = [
    ('mobile_home_park',
     'https://www.loopnet.com/search/mobile-home-parks/usa/for-sale/'),
    ('rv_park',
     'https://www.loopnet.com/search/rv-parks/usa/for-sale/'),
]


class LoopNetScraper(BaseScraper):
    name = 'loopnet'
    display_name = 'LoopNet'

    def scrape(self):
        results = []
        for prop_type, url in SEARCH_URLS:
            try:
                items = self._scrape_url(url, prop_type)
                results.extend(items)
            except Exception as exc:
                logger.warning(f"[loopnet] {prop_type}: {exc}")
            if len(results) >= self.max_listings:
                break
        return results[:self.max_listings]

    def _scrape_url(self, url, prop_type):
        results = []
        page = 1
        while len(results) < self.max_listings // 2:
            paged = url if page == 1 else f"{url}?page={page}"
            try:
                s = self.soup(paged)
            except Exception as exc:
                logger.warning(f"[loopnet] page {page}: {exc}")
                break

            # try embedded JSON first (LoopNet embeds __NEXT_DATA__ or window.__STATE__)
            json_items = self._extract_json_listings(s, prop_type)
            if json_items:
                results.extend(json_items)
            else:
                # fall back to HTML card parsing
                html_items = self._parse_cards(s, prop_type)
                if not html_items:
                    break
                results.extend(html_items)

            if not s.select_one('a[aria-label="Next page"], a.next-page'):
                break
            page += 1

        return results

    def _extract_json_listings(self, soup, prop_type):
        results = []
        for script in soup.select('script[type="application/json"], script#__NEXT_DATA__'):
            try:
                data = json.loads(script.string or '{}')
                listings = (
                    data.get('props', {}).get('pageProps', {}).get('searchResults', {}).get('listingResults', [])
                    or data.get('listings', [])
                    or data.get('results', [])
                )
                for item in listings:
                    parsed = self._normalize_json_item(item, prop_type)
                    if parsed:
                        results.append(parsed)
            except (json.JSONDecodeError, AttributeError):
                continue
        return results

    def _normalize_json_item(self, item, prop_type):
        try:
            title = item.get('propertyName') or item.get('title') or item.get('address', '')
            url_path = item.get('listingUrl') or item.get('url') or ''
            url = url_path if url_path.startswith('http') else f'https://www.loopnet.com{url_path}'

            price_raw = item.get('price') or item.get('salePrice') or ''
            price, price_text = self.clean_price(str(price_raw))

            location = item.get('location') or item.get('address') or ''
            city = item.get('city') or ''
            state = item.get('state') or item.get('stateCode') or self.extract_state(location)

            return {
                'title': title,
                'price': price,
                'price_text': price_text,
                'location': location,
                'city': city,
                'state': state,
                'description': item.get('description', '')[:500],
                'acreage': self.clean_float(item.get('lotSize') or item.get('acres')),
                'source': self.name,
                'url': url,
                'property_type': prop_type,
                'source_id': str(item.get('listingId') or item.get('id', '')),
                'cap_rate': self.clean_float(item.get('capRate')),
            }
        except Exception:
            return None

    def _parse_cards(self, soup, prop_type):
        results = []
        cards = (
            soup.select('li.placard')
            or soup.select('article[class*="property"]')
            or soup.select('div[class*="listing-item"]')
        )
        for card in cards:
            try:
                anchor = card.select_one('a[href*="/Listing/"]') or card.select_one('a[href]')
                title_el = card.select_one('p.property-address, h3, h2, [class*="address"]')
                title = title_el.get_text(strip=True) if title_el else (anchor.get_text(strip=True) if anchor else '')
                url = anchor['href'] if anchor else ''
                if url and not url.startswith('http'):
                    url = 'https://www.loopnet.com' + url

                price_el = card.select_one('[class*="price"], [class*="Price"]')
                price_text = price_el.get_text(strip=True) if price_el else ''
                price, price_text = self.clean_price(price_text)

                loc_el = card.select_one('[class*="location"], [class*="city"]')
                location = loc_el.get_text(strip=True) if loc_el else ''
                city, state = self.extract_city_state(location)

                text = card.get_text(' ')
                m = re.search(r'(\d+)\s*(?:site|space|lot|pad|unit)s?', text, re.I)
                lot_count = int(m.group(1)) if m else None

                if not title:
                    continue
                results.append({
                    'title': title,
                    'price': price,
                    'price_text': price_text,
                    'location': location,
                    'city': city,
                    'state': state,
                    'lot_count': lot_count,
                    'source': self.name,
                    'url': url,
                    'property_type': prop_type,
                    'source_id': url.split('/')[-1] if url else '',
                })
            except Exception as exc:
                logger.debug(f"[loopnet] card error: {exc}")
        return results
