"""
Crexi.com — commercial real estate platform. Queries their public search
endpoint for mobile home parks and RV parks.
"""
import logging

from app.scrapers.base import BaseScraper

logger = logging.getLogger(__name__)

API_URL = 'https://www.crexi.com/api/search/properties'

QUERY_PARAMS = [
    ('mobile_home_park', {
        'propertyTypes': 'MobileHomePark',
        'transactionType': 'Sale',
        'pageSize': 50,
        'page': 1,
    }),
    ('rv_park', {
        'propertyTypes': 'RVPark',
        'transactionType': 'Sale',
        'pageSize': 50,
        'page': 1,
    }),
]


class CrexiScraper(BaseScraper):
    name = 'crexi'
    display_name = 'Crexi'

    def scrape(self):
        results = []
        for prop_type, base_params in QUERY_PARAMS:
            page = 1
            while len(results) < self.max_listings:
                params = {**base_params, 'page': page}
                try:
                    resp = self.get(API_URL, params=params,
                                    headers={'Accept': 'application/json',
                                             'X-Requested-With': 'XMLHttpRequest'})
                    data = resp.json()
                except Exception as exc:
                    logger.warning(f"[crexi] {prop_type} page {page}: {exc}")
                    break

                items = (
                    data.get('data', {}).get('properties', [])
                    or data.get('results', [])
                    or data.get('properties', [])
                    or []
                )
                if not items:
                    break

                for item in items:
                    parsed = self._normalize(item, prop_type)
                    if parsed:
                        results.append(parsed)
                    if len(results) >= self.max_listings:
                        break

                total = data.get('total') or data.get('totalCount') or 0
                if page * base_params['pageSize'] >= total:
                    break
                page += 1

        return results

    def _normalize(self, item, prop_type):
        try:
            title = item.get('name') or item.get('address') or item.get('title', '')
            url_slug = item.get('slug') or item.get('id') or ''
            url = f'https://www.crexi.com/properties/{url_slug}' if url_slug else ''

            price, price_text = self.clean_price(str(item.get('price') or item.get('askingPrice') or ''))
            location = item.get('address') or item.get('location') or ''
            city = item.get('city') or ''
            state = item.get('state') or item.get('stateCode') or self.extract_state(location)

            return {
                'title': title,
                'price': price,
                'price_text': price_text,
                'location': f"{city}, {state}" if city and state else location,
                'city': city,
                'state': state,
                'description': item.get('description', '')[:500],
                'lot_count': self.clean_int(item.get('units') or item.get('lots')),
                'acreage': self.clean_float(item.get('acres') or item.get('lotSize')),
                'cap_rate': self.clean_float(item.get('capRate')),
                'gross_revenue': self.clean_float(item.get('grossRevenue')),
                'net_income': self.clean_float(item.get('noi') or item.get('netIncome')),
                'source': self.name,
                'url': url,
                'property_type': prop_type,
                'source_id': str(item.get('id') or url_slug),
                'broker_name': item.get('brokerName') or '',
                'broker_phone': item.get('brokerPhone') or '',
                'broker_email': item.get('brokerEmail') or '',
            }
        except Exception as exc:
            logger.debug(f"[crexi] normalize error: {exc}")
            return None
